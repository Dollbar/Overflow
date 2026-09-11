# 事务、故障恢复与 Block 生命周期审计

日期：2026-09-07。状态：规范对照和计划细化，尚无模型、RTL 或协议测试。C/L/M 仍指已接入的 Common 2.0、200G DL/PL 2.0、Manageability 1.0；页码为登记 PDF 页码。本轮重点重读 C §2.7.4–2.8、§3.1.3–3.1.4.4、§6.3，以及 L §2.4.4.1.4；没有重新定义线上协议。

## 1. UART 范围决定

按用户“接口先留着，标准先不设计”的指示，本轮采用的范围是：**保留标准带内 UART 固件通道及集成接口，暂不设计其上的厂商自定义消息协议。** 不是删去标准 DL UART 传输，也不是增加外部串口引脚。

- 保留：固件 TX/RX 的不透明 DWORD 数据收发边界、缓冲/可用状态、reset 请求和完成/错误事件。信号名、握手宽度、FIFO 深度及 CSR 地址尚未冻结；不将概念接口画成已经存在的 RTL。
- 继续按标准规划：R058/R059 的 stream 合法值、传输长度、连续发送、模信用、reset 清理及重试；和 Basic/Control 消息共享调度资源时，仍满足各自适用的时限。Rate Notification 继续走 Basic 消息，不迁入 UART。
- 暂缓：厂商消息类型分配、Vendor ID 选择、诊断命令、遥测 payload、寄存器访问命令及私有安全握手。测试可传不透明数据并检查完整性/顺序，不需要先发明命令集。
- 若以后使用 Vendor Defined Packet，L §2.4.4.1.4 p38 已定义首 DWORD 的 Length/Type/Vendor ID 前缀，不重新设计它。厂商包可跨多个 UART transport message；不能把两种消息边界绑定。此处保留适配边界，不替用户申请或指定 PCI-SIG Vendor ID，也不把 UALink 保留身份用于私有命令。

机器可读状态在 [工程配置](../config/project.json) 的 `uart_firmware_interface`。标准规定的安全/管理功能仍按原计划交付；暂缓自定义 payload 不豁免这些标准要求。

## 2. 事务模型必须补足的契约

R078–R086 进入 G1 的独立事务模型，随后进入 Endpoint/Switch 接口验证：

1. **请求身份与完成**：普通命名空间中按端口跟踪 Tag，全部响应结束前不复用；Block 独立命名空间见 R093。不能只用裸 Tag、调试 SrcPhysAccID、NumBeats=0 或首个响应 beat 判断完成。响应 SrcPhysAccID 可以不准确，不能用于功能关联；安全类型绑定仍待 A06。
2. **两种读响应模式都要接收**：Multi-Beat 是按 TDM 连续升序的一组 beat；Single-Beat 可乱序 offset、带空隙并与其他事务交织，每 beat 的 NumBeats=0。LAST 是最后传出的 beat，而非“最大地址 beat”。交换侧按对应 ingress→egress 保序并单 beat 转发，不等待收集整笔读。
3. **自然 byte lane 与长度**：读请求按 4-byte 对齐，数据按地址 mod 64 放置，不能总向低位紧凑打包。例：地址 60 读 8 bytes，需两个 beat，分别使用 lanes 60–63 和 0–3；总 beat 数的模型检查要计入起始偏移。首末 DWORD 的使能规则与整 beat 的 parity 保护分开。
4. **发出、接收与前进**：Write/Atomic 先获得整 burst 信用，请求和首数据同拍；同端口下一 Write/Atomic 等该数据 burst 结束，Read 可覆盖前笔数据尾部。接收端须接受这种合法重叠；发送端是否保守调度属于性能选择，不把 MAY 升格成必须满流水。Write Response 最早在最终数据到达的下一周期，响应前进不能依赖另一请求先完成。
5. **错误响应与异常截断分开**：普通读错误仍交付全部 beat/LAST；各 beat Status 相同，DataError 可逐 beat 不同。错误数据不能改动发起端缓存状态。这不覆盖 Isolation/Drop/reset 条款明确允许或要求的 burst 截断。
6. **顺序是限定范围的顺序**：每对端、每流、VC 和 256-byte 区域分别建账。SO 不是读/写响应混成一个全局序列，也不是不同源 Accelerator 的全局顺序。相同区域的地址请求有出端口亲和要求；多 station 不能任意逐请求散列而破坏它。
7. **原子性集成边界**：协议 IP 原样交付内存操作，允许的 beat/flit 打包不等于拆成多个独立操作。目的内存的 Single-Copy atomicity、执行分解和一致性属于 D04 的集成契约，不把所有 256-byte 访问宣称为原子，也不扩大为 NPU 设计任务。

## 3. 故障作用域与信用状态不能合并

依据 C §3.1.3–3.1.4，R087–R092 纳入独立 RAS 状态模型。下面是必须区分的行为，不是全部错误矩阵。

| 事件/机制 | 作用范围 | 事务与信用处理 |
| --- | --- | --- |
| Accelerator Originator Isolation | 对应 station Originator 全端口 | 停发 Request/OrigData；未完成和新到请求本地合成 CMPTO；迟到真实响应丢弃；仍正常接收并返回信用 |
| Switch INC Originator Isolation | 超时的 egress 端口；后续超时可逐端口叠加 | 保留上述隔离机制，不能因此隔离其它 vPod；普通 transit 不强加端到端请求跟踪 |
| TL Drop | 由错误位置/类型确定的端口，其全部通道及 TL↔DL 双向 | 丢弃相应流量；仅在可行且信用信息可靠时允许回收，不能为损坏账本制造信用 |
| Link Down：Switch TL | 仅故障链路端口 | 其余端口继续工作；UPLI 通道及信用贯穿 link-down/up 保持，不用全 station UPLI reset 代替 |
| Link Down：Accelerator TL | 本 station 全端口 | TL Drop，并发本地 ISOLATE 触发 Originator Isolation；相关 UPLI 仍保持 active 和信用 |
| UPLI 控制错误 | 按可定位性和规范处置，通常更大范围 | 与普通链路断开不同；不得一概承诺仅影响一个端口，非 TL 错误通道的未完成 burst 有强制终止要求 |

Drop/Isolation 是两种独立机制，能单独存在或同时存在。实现可用独立状态位或等效编码，不限定微架构；四种组合和切换时的资源行为都须测试。显式 UPLI reset 另按 R015–R018 的同步复位和状态清理语义，不与 link-down 混为同一事件。

本地 ISOLATE 通过 Write Response 通道传递，但不是某个远端写事务的完成。它的 don't-care Tag/ID/AuthTag 不用于匹配或报认证失败，仍消耗正确的 Pool/VC 信用。工程集成须保持本地来源边界，不能让普通远端响应借此跳过认证；这不是新增线上报文或自定义错误码。

有状态请求跟踪、watchdog、dummy 完成和迟到响应丢弃必须联合验证，不能“清空队列即恢复”。同拍超时/最后响应等竞态要确定内部优先级并保持一次完成和资源守恒；该内部不重复完成不等于跨故障全局 exactly-once。管理恢复可能终止并重启受影响工作负载，不承诺透明续跑。

## 4. Block 生命周期与状态写回

R093–R100 进入 G1 架构和 G4 集成：

- 交换发起的 BlockRead/BlockWriteFull Tag 可与普通/primitive Tag 同值，必须按类别和端口区分。状态缓冲区更新也走 BlockWriteFull，不是无信用消耗的内部寄存器赋值。
- Invoke 的 OKAY Write Response 与最终完成分离：即使后续入队检查发现组非法或资源不足，失败也是通过状态缓冲区报告。驱动不能看到 OKAY 就释放输入/输出缓冲区。
- 每端口物理 Control Block Queue 总容量是实现选择；SQ ID 0–63、单次条目申请 1–128 是不同维度。总条目、outstanding Tag、status-write 保留资源和普通业务竞争需独立预算，不能用编码相乘当作规范最低容量。
- 输入/输出访问出错时停止新发，等已发访问结束，再写失败状态；INC primitive 则走 response reduction。不能保证已经写出的部分结果回滚。状态写回本身背压/失败以及端口隔离时的管理兜底仍需进一步逐条审查，不能虚构成功完成。
- DO=0 释放 SQ：停止接纳新 Invoke → 处理/终止原 Block 及已发访问 → 各 Block 状态更新 → Deallocate 状态更新完成 → 资源可重新分配。不同队列与不同端口仍须正常进展。
- **A18/R097 待澄清**：C p164 的 DO=1 明确保留条目分配，p165 通用结束流程又写成 unallocated。两页原图已核实，不是文本抽取错误。候选理解是 p165 释放结尾只适用于 DO=0，但尚不以此冻结 DO=1 的完整结束/恢复接纳流程。保留该能力和资源，单列 本地澄清问题（历史文档已清理），未向外发送。
- 状态格式按命令区分：Allocate/Deallocate 用首字节 Valid；Invoke 用 V0/V1 指示不同结果字段，可能同时有效。驱动负责发起前清有效位、正确等待状态及平台内存可见性；不能套用一个通用完成位。
- Block 地址生成包含高位掩码、offset、非 stride/stride、输入输出不同跳距及 2/4 倍输出精度。掩码对生成的访问地址生效，不仅检查描述符起点；也不能把地址掩码当作安全认证的替代品。

标准 Block 操作是 BROADCAST/REDUCE/ALL-REDUCE；AllGather/ReduceScatter/AllToAll(v) 工作负载可由其它合法通信组合构建，但不能冒称本版原生 Block 操作或借 UART 增加私有 Block opcode。

## 5. 模型、VIP 与计划验收组

以下名称是待实现工作包/场景组，不是可运行文件。依 RTL 分析流程，先建立独立事务/状态预期，再接入 RTL 与独立 scoreboard；不以 TX/RX 共享同一逻辑的往返吻合代替检查。

| 场景组 | 验收重点 | 台账 / 阶段 |
| --- | --- | --- |
| VTR01 | Tag 生存期、跨端口/类别同值、调试 SrcID 不参与功能、迟到响应 | R078/R084/R093；G1/G2/G3/G4/G5 |
| VTR02 | 两种读响应模式、offset 排列、低 offset LAST、空隙/交织、交换单 beat 转发 | R079；G1/G2/G3 |
| VTR03 | 自然 byte lane、跨 64-byte 边界、首末 byte enable、被屏蔽 byte 仍有 parity | R080；G1/G2 |
| VTR04 | 错误响应全 beat、Status/poison 分离、缓存不更新、异常截断的适用范围 | R081/R088/R089；G1/G2/G6 |
| VTR05 | Write/Atomic 数据连续性、合法 Read 重叠、最后数据后响应边界、请求阻塞下响应/信用前进 | R082/R083；G1/G2/G3 |
| VTR06 | SO/SOL/non-SO、同区域端口亲和、多源/多 station、三类流独立 | R085；G1/G2/G3/G5 |
| VTR07 | 原子操作传输不分解、目的内存模型执行与响应契约 | R086/D04；G1/G2/集成 |
| VTR08 | watchdog、Drop/Isolation 四组合、最后响应同拍竞态、本地 ISOLATE 信用与来源 | R087–R089/R091；G1/G2/G4/G6 |
| VTR09 | x1/x2/x4 多端口 link-down/up、UPLI 信用持续、其它 vPod 继续工作、显式 reset 区分 | R090；G1/G2/G3/G6 |
| VTR10 | INC 参与者失联、dummy/Mixed、部分写入、状态写回拥塞/错误与管理恢复 | R092/R094；G1/G4/G6 |
| VTR11 | SQ/条目数量边界、分配竞争、同 SQ 不同端口、DO=0 的状态更新顺序 | R095/R096；G1/G4/G6 |
| VTR12 | DO=1 资源保留与后续接纳；预期须等澄清，不生成占位 PASS | R097/A18；G0/G1/G4 |
| VTR13 | 各状态格式、旧有效位、V0/V1 竞态、软件轮询与内存可见性 | R098；G1/G4/集成 |
| VTR14 | 地址掩码、跨界与进位、输入输出/状态访问、stride 和输出放大 | R099/R100；G1/G4/G5/G7 |

验证环境需要独立的请求身份/beat 收齐 scoreboard、按流排序 oracle、按端口/VC/pool 的信用账本、RAS 事件模型、Block 队列/地址/状态内存模型，以及软件驱动参考。上述需求不替代完整数值 oracle、安全位精确 oracle 或数字 PHY 模型。

## 6. 状态、剩余审查与进入实现的条件

本批保留 R001–R077，新增 R078–R100 共 23 条记录：22 条正文判据确认，R097 因 A18 阻塞。截至本批累计 100 条、94 条正文确认、6 条阻塞；这既不是全部 SHALL 的数量，也不是测试通过率。F16 索引的主要依据纠正为 C §6.3–6.4，数值依赖另指 §6.6–6.7。 最新累计计数与开工判断见 开工审计（历史文档已清理）。

后续仍须补齐完整命令/保留编码、INC 参数位图及数值矩阵、状态写回失败闭环、安全/压缩未决项、完整错误分类、调频/控制/LLR 竞态、外部 IEEE 和管理资产。G1 应先冻结已澄清范围的角色、资源、时钟和状态契约，再实现独立模型；A18 仅阻塞相应 drain-only 流程冻结，不阻止其余已确认机制继续研究。

本轮仅修改公开计划/索引/JSON 要求和本地澄清草稿；未修改规范原件、实现 RTL/model/VIP、运行协议仿真/STA、提交或推送。文件一致性检查单列在 [审查决定](review_decisions.md)，不算协议验证证据。
