# 整段发送信用准入审查

本阶段新增 `tl_credit_admission` 与 `tl_credit_admitted_port`，修复已复现的“总容量足够、但前一事务占用部分信用时，下一头部提前进入数据序列”的实际双端停顿。完整 Endpoint/Controller 和 Switch 目标不变，尚未完成。

## 规范与实现策略

核对私有 Common 2.0 §5.1.1、§5.1.2、§5.8、§9.1：非消息半 Flit 依推导序列解释，FC 属于 Control 字段，不能把 FC 普通字段当消息插进数据序列。消息可以延迟数据序列，但这不提供另一个未经规范定义的 FC 编码。

整段准入是本地调度策略。每个新 Control 头部被发送前，计算全部 CMD 及其后续 Data 对的信用需求，BE 不另收信用；仅把共享 Data Pool 的逻辑槽 10/15 合并成物理槽 10。六位需求能表示八个四 Beat 响应的 32 个 Data 信用，比较值无损扩至 WIDTH+1 位。WIDTH 支持 8–16；7/17 实际展开拒绝。

无需提前从线上账本扣除未来 Data：在当前固定有序 tenure 中，只有同一个发送者能使用该账本，新的非尾部 Control 无法抢先消耗所保留的数据信用。实际扣费仍在原端口发送成功时进行。`o_tx_allowed` 与底层门控后的实际 `o_tx_taken` 一致；缺信用不被误报为格式错误。FC/NOP 初始化不依赖应用信用。

此理由是微架构不变量的解释，尚不是完整实际联合 RTL 的归纳证明。还要求调用者保证数据供应，并在旧尾部与新头部发生冲突时先提供合法的旧尾部/FC 组合，不能无限等待一个新头部而饿死旧尾部。当前回归使用事务之间排空 tenure 的合法打包方式；自动处理旧尾部和新头部竞争的产品 packer 尚未实现。

## 实际验证

- 旧压力配置：每槽两个 CMD、四个 Data 信用，连续两个三 Beat 事务使用同一个专用 VC。真实双端在 6,000 次测试循环后超时，两端剩余 5/5 半 Flit，FIFO 为 0/0。
- 新端口同一负载：WIDTH 8/16 × Auth 0/1 × Shared 0/1 × 数字链路延迟 1/3，共 16 配置通过；合计 6,040 次测试循环、3,840 个实际存储/消费字、2,232 次 FC、960 CMD 和 2,880 Data 信用真实归还。
- 原混合五类字段负载通过另外 16 配置；5,412 次测试循环、3,072 个实际存储/消费字、1,712 次 FC、960 CMD 和 2,016 Data 信用真实归还。
- 16,742 个组合 RTL 向量覆盖支持的字段位置、Pool/VC、共享归一化、BE、最大 32 Data 需求、信用暂缺/总容量不足、初始化未完成、复位与非 Control 阶段。
- 六种实际准入 RTL 错误各跑 WIDTH 8/16，共 12 次全部失败；真实端口旁路发送门控在 16 配置全部检出。故障覆盖漏算后续 Data、错误槽、漏合并共享池、把 VC 当 Pool、忽略余额、绕过初始化和实际发送门控。
- 独立 Python 对真实逐周期观察检查载荷发送顺序、保存释放所有权、FIFO 界限、退休/返还原子性、FC 不早于实际消费、最终信用守恒，以及头部被发送时全部需求有信用支持。压力/混合负载分别有 2,400/1,632 次待完成 Data 序列的实际发送；在本测试的有效发送机会中没有因后续信用不足停顿。统计为测试循环次数，不是全流程全部时钟沿。
- 严格 Verilator lint 两宽度零警告。Yosys 通用映射分别 67,344/72,703 cells，1,059/1,379 FF bits；所有触发器属于输入时钟上的同步复位类型。本综合顶层为发送准入端口，SRAM 通过双端测试的接收路径实例化，不在这些面积数字中。

证据在 `build/verification/tl_credit_admission/evidence.json`。最终健康双端运行目录为 `pressure_verified` 与 `mixed_verified`；初始、修订、失败运行保留。检查器核对实际编译源 SHA，正常 Python 和 `-O` 均运行，避免依赖可被优化关闭的 assert。

## 未解决的单信用场景

原每槽一个 Data 信用的多 Beat 流没有被删除或提高容量。新端口运行仍实际超时：发送/接收索引 2/2，剩余 tenure 为 0/0，FIFO 为 0/0，并持续报告 `o_capacity_shortfall`。这将问题挡在头部之前，但并没有完成超容量事务。

后续必须将需求反馈给真实 packer 和 UPLI 事务处理：规范支持的 Single Beat Read Response 不能被外推成任意 Write 拆分许可；需分别核对原事务地址、LEN、beat offset、last 和错误处理。也不能把全头部等待当作解决 Request/Response 独立性。当前参数覆盖不是所有可配置容量的持续前进性证明。

## 编码、依赖与复跑

新增 RTL 是 Verilog-2001，组合准入无新增 FF、派生时钟或复位域。`tl_full_flit.v` 仅修正模块首尾中文说明，功能语句未变。技能 artifact 验证包含新增模块与实际时钟寄存器所在的 `tl_full_flit` 依赖，零错误、12 项建议（历史头、分区标签、实例命名和参数常量风格）；完整实际层级由 Verilator/Yosys 检查。保留既有工程命名和紧凑结构，未为满足建议而引入无用寄存器或逻辑。

技能包全局自检实际失败于外部缺失的 `agents-md-generator/scripts/manage_docs.py`，不将 artifact 通过冒充全局 gate 通过。第一次 artifact 发现 wire 声明内赋值及说明格式问题，已修复并保存先前日志。

干净导出最初 `make test` 发现工具测试要求 build 目录已存在；已在 Makefile 的 test 入口创建目录，随后干净导出的 `make test` 与 `make rtl-smoke` 均以 exit 0 完成。该修复不涉及 RTL 行为。

```sh
python3 verification/tl_credit_admission/test_model.py
python3 verification/tl_credit_admission/run_rtl.py --label guard_verified
python3 verification/tl_receive_credit/run_rtl.py --kd28-root /authorized/Overflow --label pressure_legacy --traffic-pressure --single
python3 verification/tl_receive_credit/run_rtl.py --kd28-root /authorized/Overflow --label pressure_verified --traffic-pressure --admission
python3 verification/tl_receive_credit/run_rtl.py --kd28-root /authorized/Overflow --label mixed_verified --admission
python3 verification/tl_receive_credit/run_rtl.py --kd28-root /authorized/Overflow --label small_verified --data-credits 1 --single --admission
python3 verification/tl_credit_admission/run_checks.py --kd28-root /authorized/Overflow --label checks_verified
python3 verification/tl_credit_admission/run_skill_gate.py --skill-root /path/to/verilog-generator
python3 verification/tl_credit_admission/check_evidence.py
make test rtl-smoke
```

`pressure_legacy` 与 `small_verified` 命令预期非零，分别代表修复前和仍待处理的反例；其他命令要求通过。新目录拒绝覆盖已有证据。模型/RTL、故障、lint/通用综合、数字链路仿真、实际宏模型和工艺 STA 保持不同范围。当前没有工艺 STA、模拟 SerDes、完整 opcode/address/LEN 验证、完整参考归纳、跨层产品顶层或 IP 签核。
