# Endpoint 在途统一同步复位集成检查

本次新增真实双 Endpoint → Switch → Endpoint 的统一同步复位回归，三个在途窗口均在默认 Data bank 深度 3 和最小深度 1 下通过。两个实际模块复位接线故障均被检查器检出。未修改生产 RTL、既有事务 TB 或 runner。

这是本地网络所有参与方一起取消在途工作的集成语义：两个 `ualink_endpoint_top(TRANSACTION_MODE=1)`、一个 `ualink_switch_top`、两个实际 `ualink_memory_vip` 和测试传输流水寄存器使用同一低有效同步复位，维持三个时钟上升沿。`epoch` 仅为测试观察标签，不是协议字段，也不参与生产 RTL。没有实现或宣称单端独立 LinkDown、跨复位事务重试、远端旧包隔离或标准 epoch 协议。

## 实际连接与独立检查

[reset_tb.sv](../verification/endpoint_transaction/reset_tb.sv) 实例化当前实际 MODE1 顶层，因果路径经过 originator、真实 TL/DL、Switch、实际 600-bit 接收队列及事务接收器、completer、内存 VIP，再通过真实响应编码和两份 Data 返回 originator。测试从不预生成 Response。运行配置为 Auth 关闭、物理 port 0、端点 ID 17/513、默认 originator/completer 容量 4、单个在途请求/端。复用既有包/VIP，编译顺序为公共 package → VIP → 生产 RTL/KD28 SRAM 模型 → TB。

每个场景在复位前后都使用相同的 11-bit Tag 1024、完整 57-bit 地址 0、Length 15、Attr FF。两个端点各预约一个请求。复位后先静默观察 100 周期，再重新发出信用初始化和应用请求；新轮次两端各完成一次，所有 originator/completer/DL unacked/scheduled 计数排空后继续观察 80 周期。

独立 scoreboard 只从接口事件建立所有权：

- 应用 ready/valid 预约、顶层 `o_source_captured[0]` 捕获和真实 `u_tx.o_header_taken[0]` 发送分别计数。发送字段从 `u_tx.o_flit` 与真实 `tl_control_decode` 输出检查，capture 不冒充 sent。
- 内存 ready/valid 检查对侧请求已实际发送、地址/长度/属性正确、槽位不存在重复占用。结果首次 valid 就要求本轮存在对应实际内存请求；结果接纳必须严格晚于该请求。
- 内存结果与每次 `complete_valid` 均比较两个冻结的完整 512-bit literal。检查器不调用 VIP 的 `memory_word`，也不读取 VIP 的 pending/due 等私有状态。
- 每次完成 valid，即使应用 ready 为 0，也要求本轮已预约/发送，且对侧内存结果握手发生在更早周期。检查 Tag、port、status、data_valid 和完整 Data；背压期间整个完成结果必须稳定。
- 每个同步复位沿后检查两端事务和 DL 计数清零、完成/内存/链路输出 valid 清零，以及 Switch 输出 valid 清零。新轮次静默期禁止旧完成、旧内存请求或旧结果出现。所有 scoreboard 槽位也在同一个复位沿取消。

VIP 最小延迟设为 40 周期，槽位调度附加最多 15 周期，100 周期静默窗口超过本场景已接纳请求的返回延迟。没有通过 VIP 私有调度状态决定复位时点或完成期望。

## 三个复位窗口与实测结果

| 窗口 | 复位前实际观察，两端分别相同 | 触发周期 | 恢复并排空周期，bank 3 / 1 |
| --- | --- | ---: | ---: |
| 1：预约、capture 后尚未 sent | reserved=1、captures=1、header_taken=0、mem_reads=0 | 30 | 357 / 357 |
| 2：内存已接纳、结果未到 | sent=1、mem_reads=1、mem_returns=0、completer_count=1 | 47 | 374 / 374 |
| 3：完成被背压 | sent=1、mem_returns=1，两端完整完成 valid 连续被背压 8 周期 | 151 | 476 / 476 |

每个正常 case 总计 4 次预约，其中旧轮次取消 2 次，新轮次完成 2 次。六个正常 case 合计 24 次预约、12 次取消、12 次新轮次完成；这里没有把取消的预约称为完成。

| 证据 label | 配置/检查 | compile / run | 判定 |
| --- | --- | --- | --- |
| `reset_final` | bank 3，三个窗口 | 各 0 / 0 | 三个 `NETWORK_RESET_PASS` |
| `reset_final_minimum` | bank 1，三个窗口 | 各 0 / 0 | 三个 `NETWORK_RESET_PASS` |
| `reset_final_memory_fault` | 窗口 2；仅端点 0 的实际 VIP 复位改接只在上电生效的 `power_rstn` | 0 / 1 | `RESET_OLD_MEMORY_RESULT side=0 epoch=1` |
| `reset_final_endpoint_fault` | 窗口 3；仅端点 0 的实际 Endpoint 复位改接 `power_rstn` | 0 / 1 | `RESET_STATE_NOT_CLEARED side=0 stage=3` |

两个 fault 都先完成正常上电初始化并达到相应 `RESET_TARGET`，再遗漏在途复位；不是启动时 X 值导致的偶然失败。TB 参数只改变实际模块实例的复位连线，不关闭检查器、不强制内部状态。runner 只有同时满足编译成功、仿真失败及指定故障诊断才把 fault 标为 passed。

早期 `reset_first`/`reset_minimum` 也保留在 build 中，但其窗口 1 是 capture 前取消；最终结论采用上述已收紧至 capture 后的四份 label。

## 复现与证据

在独立 UALink 工程根目录运行；替换显式 KD28 路径和全新 label：

```sh
python3 verification/endpoint_transaction/run_reset.py --label reset_review_new --kd28-root /home/ljy/work/IC/OverFlow
python3 verification/endpoint_transaction/run_reset.py --label reset_review_min_new --kd28-root /home/ljy/work/IC/OverFlow --bank-depth 1
python3 verification/endpoint_transaction/run_reset.py --label reset_review_memory_fault_new --kd28-root /home/ljy/work/IC/OverFlow --stage 2 --fault memory_reset
python3 verification/endpoint_transaction/run_reset.py --label reset_review_endpoint_fault_new --kd28-root /home/ljy/work/IC/OverFlow --stage 3 --fault endpoint_reset
```

[run_reset.py](../verification/endpoint_transaction/run_reset.py) 从脚本位置解析工程根目录，不依赖调用者 cwd。外部 KD28 模型逐一核对 `third_party/kd28_dependency.json` 中五份授权依赖哈希。输出位于 `build/verification/endpoint_transaction/<label>/`：`result.json`、源码/runner/manifest 快照，以及各 `stage_N/` 下的编译命令、日志、vvp 和运行日志。label 已存在即拒绝覆盖。

四个最终 label 的 214 份源码快照分别与记录哈希一致；正常 label 各 223 份、fault label 各 217 份输出制品哈希全部核对通过。核对时工作区源码与所有最终快照一致，审计附加文件为 `reset_final/source_audit.json`。

| 文件 | SHA-256 |
| --- | --- |
| `verification/endpoint_transaction/reset_tb.sv` | `a8b0430a737007ec84d23140a02f90bddda655120c5c30e1be2ae7a2d159032c` |
| `verification/endpoint_transaction/run_reset.py` | `d1a036319c6e26e55705701777b185dd53a14149d1c3a1ae896d9b3ef1a7df3d` |
| `rtl/endpoint/ualink_endpoint_top.v` | `9c05e865bcd700d6dcfbbd633ac1682228164e43477f4eb20a10aff66480137b` |
| `rtl/endpoint/endpoint_transaction_core.v` | `3dd32324dad4aa6513137f986b348be0f04509df578b9e81d80937b8289d2e89` |
| `simulator/vip/ualink_memory_vip.sv` | `febb0ddfc5202211222acb1cb666b54fc2ccfb73aca3f8c285d2ee4051c95e5f` |

## 结论边界

这六个正常仿真未发现统一网络同步复位取消/恢复的生产 RTL 阻断问题。检查覆盖指定窗口、同 Tag/地址重用及有限观察期内的旧事件泄漏；没有穷尽所有队列占用、复位时钟相位或并发时序。单请求/端不能替代既有四槽及参数容量压力测试；此处不覆盖错误 status、高地址和 Auth 模式。实际 600-bit 接收路径参与运行，但本检查器没有新增逐个 600-bit 记录的独立序列/释放位全量 oracle。

测试链路仍使用已有本地数字 DL 记录和显式 CRC 状态，不是标准线格式，不补写 A19 的 CRC 位序、framing、PCS/FEC/SerDes 或认证结论。统一复位假设同时清除远端和传输队列，不能据此推导独立端点复位时对迟到旧包的隔离。后续独立 LinkDown/恢复需要先明确实际事务取消及远端重同步接口和契约，再另立故障/恢复验收。
