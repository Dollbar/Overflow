# 时钟、UPLI 调频与速率适配实施计划

日期：2026-09-07。用户已批准把调频能力纳入实现目标；本文件是计划，不是已实现 RTL 或时序签核。依据 C = Common 2.0、L = 200G DL/PL 2.0 的私有原件；页码与 PDF 页序一致。配合 [交付计划](ip_delivery_plan.md)、增量缺项审查（历史文档已清理） 和 [验收台账](../specs/requirements.json) 使用。

## 1. 必须分开的时钟与控制机制

| 对象 | 正文约束或参考值 | 本工程约束 |
| --- | --- | --- |
| 本地 UPLI | C §4.2 p102：接口双方的信号同步于共同 UPLIClk；L §2.5 p41–42：默认吞吐对应 512 bits×1562.5 MHz | 同一个 UPLI 接口的双方一起遵守切钟契约，不允许只切一侧、把同步 UPLI 当成异步接口 |
| Accelerator UPLI 调频 | L §2.5.3–4 p42：允许调频，经过 156.25 MHz 参考时钟与无毛刺切换 | 用户已选择实现；PLL/时钟 MUX 单元由平台提供，RTL 实现控制、握手、状态与流量约束 |
| Switch UPLI | L §2.5.2 p41：固定 UPLI 时钟/吞吐；仍响应 Accelerator 速率通知 | 不作为本流程的调频发起角色；其发往低频 Accelerator 的有效数据必须节流 |
| DL 发射侧与接收恢复侧 | L §2.5.1 Figure 2-18 p41 分别列 Transmit CLK、Recovered CLK、UPLI CLK | 跨域存储/适配必须显式设计；UPLI 调频不得改变串行线速、使能或复位 CDR/SerDes |
| DL–PL 并行接口 | L Appendix B p98–106 为 informative；示例 512 bits、约 1.66 GHz | 接口及相位/固定响应延迟由 G1 冻结；不把 1.66 GHz 或示例 5 拍当作协议唯一实现 |
| UPLI 连接握手 | C §4.3 p103：OrigClkReq/CompClkAck、CompClkReq/OrigClkAck，共四个信号 | 用于连接建立，不是每次调频/空闲的时钟门控请求；断言后保持到 UPLIReset_N 断言 |

“时钟域分开”不强制使用相互独立的物理 PLL；可以同源派生，但必须证明改变 UPLI 不扰动 PHY 线时钟。CDR 跟踪线上码元节奏，不跟踪业务有效率。正常调频不触发 UPLI reset，也不借调频清空信用、Tag、地址压缩或安全计数器；真实故障/复位按独立恢复规则处理。

200G 的单个 x4 端口、512-bit 归一化预算：1562.5 MHz 对应 800 Gb/s，156.25 MHz 对应 80 Gb/s；降低的是接口容量，不承诺过渡期间维持满业务带宽。实际 payload 还扣除协议开销、打包空洞和背压。多个 station 增加并行端口，不把这些时钟频率乘以 station 数；100G 及各合法 PHY 组合另外登记其预算，不能照搬 200G 的所有数值。

## 2. 线上速率表示与握手

依据 L §2.4.2–§2.4.2.2 p25–27、§2.5 p41–42，新增 R046–R051。

- TL Rate Notification 属于 Basic Message，不使用 Control Message 的三段确认或 decision-pending 流程。同一 Basic mclass 本地最多一个 outstanding 请求；相反方向同时请求按独立流程处理，不能互等。
- Rate 为请求中的 [31:16] 字段，每 LSB 为 50 kHz；1562.5 MHz 编码 31250，156.25 MHz 编码 3125。ACK 中该字段保留，不能要求对端回显 Rate 来匹配 ACK。
- Rate 描述归一化吞吐：800G x4 按 512 bits，400G x2 每链路按 256 bits，200G x1 每链路按 128 bits。若本地实现宽度不同，按实际可接收吞吐换算，不直接把 RTL 时钟频率写进 Rate。不能向上夸大接收能力；离散频点和舍入/保留值处理须在 G1 列成配置契约，不能自行发明线上编码。
- 156.25 MHz 是正文要求支持的最低参考速率，不把 16-bit 编码空间当作任意频率都可用的许可。其它工作频点、PLL lock 条件、切钟延迟和最高硬件频率仍待平台确认。

本地发起的完整正常流程：

1. 将本端 Tx pacing 调整到参考速率，并继续遵守更低的对端接收上限。
2. 发出参考速率的 TL Rate Notification。
3. 等待对应 ACK；未收到不能切到参考时钟。
4. 使用无毛刺 MUX 将本地 UPLI（接口双方）切到 156.25 MHz。
5. 请求平台重新配置 UPLI PLL；等平台确认可安全使用新时钟。PLL 时限是平台输入，不伪称为 UALink 固定常量。
6. 切到新 PLL 时钟；本端 Tx pacing 仍受对端已通告的较低速率限制。
7. 发送新速率的 TL Rate Notification。
8. 等待 ACK 后才报告本次调频完成。

对端接收通知的流程：先记录速率、使必要的 Tx pacing 限制生效，再回复 ACK；正文要求收到请求后 1 μs 内发出 ACK。该时限不是本端等待 ACK 的统一超时，也不是一整个调频过程的完成时限。双方可能同时调频，状态必须分别保存本地当前时钟、本地已通告速率、对端速率和本地 pending 请求，不能共用一个“当前频率”寄存器。

## 3. 持续物理发送、FIFO 与背压

依据 L §2.3.4 p19–20、§2.5.1 p41、§2.6.6.2 p47–48、§3.2.2–3 p73–74，新增 R052–R054。

- 在适用 link-up 状态，DL/RS 继续按物理节奏提供合法 payload/NOP/规定控制码流；不能把没有 TL 数据解释成暂停 SerDes，或强迫空闲时发送全零电平。
- DL NOP、空载 payload DL flit、UART 的 No-Op Message、RS 的 Idle Control Flit 不是同一对象。尤其 packer 形成的所有 segment header 为零的 payload flit 不得自动改成 NOP；跨 flit carry-over 也必须保留。空载 payload 仍遵循 payload 序号/重放规则，NOP 不消费新序号。
- Tx pacing 控制 TL flit 被接纳到 DL Tx FIFO 的节奏，不是串行波特率控制；TL credit、UPLI credit、TL 请求/响应 packing budget 与 DL pacing 是独立的约束，任何一个通过都不能代替其他约束。
- FIFO 深度通过周期模型求界：包含切钟前已有占用、对端 pacing 生效前/后的在途数据、最大突发、CDC/打包/PLL 切换停顿以及 replay。保守估算为“已有占用 + 停顿窗口内最坏新增有效数据 − 可保证排出量 + 余量”，最终用逐事件模型/断言核对，不采用未经论证的固定深度。
- 正常合规调频须证明不溢出；异常 TL 背压的 L §2.6.6.2 恢复能力另行评估。该能力在非 chiplet 实现是建议、在指定 chiplet 场景才强制；本项目拟纳入防护，不因此引入 chiplet 产品范围。若选用，完整实现规定的丢弃/计数/重放与空载排空规则，不得 ACK 未保存的数据或把丢弃当正常 pacing。
- 不承诺无限持续背压下无损无限缓存；非法配置、永久故障和 watchdog 到期必须有有界资源及规范恢复出口。

## 4. 计时器、控制面与 STA 契约

这些是实现验收约束；不是新定义的 UALink 线上字段。

- 所有计时器登记“真实时间 / DL flit time / 接收 flit 事件 / UPLI 周期”单位，禁止统一用一个可变 UPLI 周期计数替代。速率通知的 1 μs、UART reset 的 10 ms、LLR 的 10.24 ms 默认值及 DL Fault 的可编程延时分别建模。
- 1 μs 在 156.25 MHz 下是 156.25 个周期，不可简单向上取 157 拍后声称 ≤1 μs；必须包含收消息、CDC、仲裁和发消息延迟，以独立时间基准测量。计时器可用稳定时基或经过证明的换算机制，具体平台实现待定。
- Basic/Control/UART 共享消息传输资源：既满足 UART 连续传输、40 个 No-Op reset 清理，也满足通知响应时限；建立各合法速度、宽度、folding、replay 下的最坏调度界。不得通过在 UART 消息中途插入 ACK 来伪造达标。若组合时限无法同时满足，登记冲突并阻止该配置签核，不擅自改标准。
- STA 模式矩阵至少含默认 UPLI、参考 UPLI、每个已选工作频点、Switch 固定模式与独立 PHY/恢复域；512-bit 基线默认周期 0.640 ns、参考周期 6.400 ns。最终还需平台时钟波形、抖动、不确定度、I/O min/max delay、库/角点及 SRAM/SerDes 边界。
- 在约束中区分同源 generated clock、互斥 MUX 输入和真正异步交叉；不将所有跨域一律设为 false-path，也不以 false-path 掩盖组合跨域或未同步复位。UPLIReset_N 本身依 C §4.1 保持同步断言/撤销。
- 无毛刺切钟、PLL lock/失锁、窄脉冲和停顿窗口不靠静态 setup/hold 一项证明；RTL 仿真/断言、CDC/RDC、时钟单元模型与平台 STA 分开提供证据。当前不生成平台 SDC/Tcl，不沿用其他工程工艺/1 GHz 成绩。

拟分工：`upli_rate_controller`、`dl_basic_message_controller`、`dl_tx_pacer`、跨域 FIFO/适配、`dl_packer/unpacker`、时间基准与 CSR/事件记录；这些是工作包名称，不表示对应文件已经存在。平台提供 UPLI PLL 重配/稳定状态和无毛刺时钟单元契约，模拟 SerDes/CDR 不在可综合协议核中自制。

## 5. 专项验收矩阵（全部未运行）

| 组 | 场景 | 必须观察的结果 |
| --- | --- | --- |
| VCLK01 | 默认→参考→新频率→再次通知，含最终恢复默认频率 | 两次通知/ACK 与切钟顺序正确；完成状态不提前 |
| VCLK02 | 端点直连不同频率、同时调频；端点—固定频率交换机 | 双方向独立；本端升频不突破对端接收上限；交换机不发起此调频 |
| VCLK03 | x4/2x2/4x1；多 station、非二次幂数；本地宽度换算 | Rate 归一化正确；共享 UPLI 域关联的端口全部完成适用握手后才切钟；不得仅通知一个端口就改变所有端口时钟 |
| VCLK04 | 零/满负载，FIFO 临界占用，在途 burst，clock MUX 最大停顿 | 正常调频无溢出、漏收、重复或错序；业务有效率下降不改变 SerDes 线速 |
| VCLK05 | ACK 延迟/丢失/重复、连续调频请求、reset 或失锁中断 | 未确认不得提前降频；按已冻结的超时/恢复契约停留或退出；不虚构事务号/ACK 的 Rate 回显 |
| VCLK06 | UART 最大消息、UART reset、Basic ID/Port 请求、Control 协商竞争 | mclass outstanding 限制、不可穿插规则与 1 μs 时限同时成立；正常负载不能饿死协议控制 |
| VCLK07 | pacing×TL/UPLI credit×LLR replay×Folding 的合法交叉 | 各资源账户独立；重放/空载排空可前进；错误恢复不制造错误 ACK 或副作用 |
| VCLK08 | NOP/空载 payload/跨 segment 和跨 DL flit carry-over | 解包不丢有效尾部；payload 与 NOP 序号/重放区别正确 |
| VCLK09 | 各频点、相位、时钟误差、门控/MUX/PLL 平台边界 | 同步 UPLI 契约、CDC/RDC、时间单位一致；模拟 CDR 锁定结论仅由适用 PHY 证据给出 |

测试 ID 是计划组，不等于 9 项已运行测试。功能覆盖、协议断言、性能曲线与平台签核报告分别记录；ACK 时限用独立 monitor 测实际时间，不能与 DUT 共享同一错误的周期换算。

## 6. 阶段门槛与未决输入

- G1：先做独立速率/消息调度/跨域流量模型，冻结频点与归一化、每 station 共享时钟影响域、控制请求排队、ACK 关联、异常超时、PLL/MUX 接口和 FIFO 最坏界。
- G2/G3：端点直连及端点—交换机 RTL 集成调频；小规模多 station 并发，不能仅测空闲切钟。
- G6：真实数字 PHY 数据节奏、rate matching/FEC、fold/unfold 与调频联合验证；PLL/SerDes 模型来源和证据层级登记。
- G7/G8：满速/降速/恢复曲线、覆盖审查、每发布配置的多模式多角 STA/CDC/RDC；外部模拟 PHY、工艺/器件与工具未齐备前不宣称物理连接或时序签核。

目前本文件解决的是计划缺项，不关闭 A05/A06/A09/A10/A17 等旧问题，也不声称整个协议已经完成条款提取。
