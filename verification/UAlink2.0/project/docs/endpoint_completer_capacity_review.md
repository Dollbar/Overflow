# Read Completer 容量 1～4 修复与验证

本次解决 `endpoint_read_completer` 在非二次幂容量下的通用综合缺口，冻结验证范围为 `CAPACITY=1/2/3/4`：分别采用 DUT 自动 `SLOT_WIDTH` 和显式 `SLOT_WIDTH=2`。请求、内存、Response/Data 接口与此前单 64 B Read 字段及握手语义保持不变；更大容量不在本轮交付声明内。

## 先复现再修复

旧 RTL SHA-256 为 `179ace95dc7c90afe1e150c87a6e9b3499aeb8dc0025204dc1e1e3a7f481cba1`。修改前将 RTL、实际 Response 编码器和旧 runner 保存到 `reports/endpoint_transaction/completer_capacity_red/`，执行容量 3、两位 slot 的 Yosys `proc; opt; memory; opt; check -assert`，返回 1，报 628 个未驱动问题。日志定位到描述符/结果数组动态读取所生成的 `$memory...rdmux`：三行数组的二位读地址需要选择不存在的第四行。

先参数化独立 BFM 与 scoreboard，再在旧 RTL 上运行 `--label capacity3_before_fix --capacity 3 --slot-width 2 --normal-only --synth`。真实功能仿真通过，但映射检查仍失败，整体返回 1；证据保留。此前四槽单测通过不能替代这个结构性失败。

修复将描述符和队首结果的数组读取改为按实际 `CAPACITY` 展开的固定索引组合选择。每个真实槽的数据、全部 57 位地址、11 位 Tag、10 位 ID、512 位结果及接纳进度均完整保留；不存在的选择地址有组合默认值，且不会分配额外槽或发出有效事务。没有黑箱、X 常量或工具忽略开关；有效数据仍来自真实存储槽。写入、指针按实际容量回绕、结果合法性检查及退休条件未改变。`capacity3_after_fix` 同一功能与结构检查均通过。

## 最终矩阵

runner 新增 `--capacity`、可选 `--slot-width`、`--normal-only` 和 `--synth`。省略位宽时真实 DUT 实例不覆盖 `SLOT_WIDTH`，因此实际验证其默认推导。默认参数仍为四槽，并保留原有三类故障回归。每个输出目录保存实际参数、自动/显式模式、源文件及 runner 快照、字节内存、向量、编译/运行/综合命令与返回码。

| CAPACITY | 自动位宽 | 自动/显式两位周期数 | 乱序关系样本 | 自动/显式错误事件 |
| --- | --- | --- | --- | --- |
| 1 | 1 | 566 / 568 | 0 / 0（单槽不适用） | 21 / 27 |
| 2 | 1 | 395 / 397 | 3 / 3 | 18 / 24 |
| 3 | 2 | 334 / 334 | 9 / 9 | 21 / 21 |
| 4 | 2 | 302 / 302 | 17 / 17 | 18 / 18 |

八个组合全部正常通过：各 32 个请求、32 个实际内存命令、32 个内存结果、32 个完整响应，另各一笔保存结果后被复位取消的事务不计入正常 32 笔。独立 BFM 检查 slot 不超过实际容量，并在空闲及满槽时逐个注入所有可编码的未用 slot，确认消费诊断且不破坏有效槽。各组合实际覆盖完整高位地址、两半数据、满槽等待、Header/Data 分别先行、部分接纳、随机延迟、内存反压与复位后恢复。单槽只取消不可能的乱序覆盖要求，没有取消功能对照。

矩阵证据目录为 `reports/endpoint_transaction/completer_capacity_matrix_c{1,2,3,4}_{auto,fixed2}/`。例如实际执行命令：

```sh
python3 verification/endpoint_transaction/run_completer.py --label capacity_matrix_c1_auto --capacity 1 --normal-only --synth
python3 verification/endpoint_transaction/run_completer.py --label capacity_matrix_c2_fixed2 --capacity 2 --slot-width 2 --normal-only --synth
python3 verification/endpoint_transaction/run_completer.py --label capacity_matrix_c3_fixed2 --capacity 3 --slot-width 2 --synth
python3 verification/endpoint_transaction/run_completer.py --label capacity_matrix_c4_auto --capacity 4 --synth
```

其余组合使用对应容量和位宽；只有 `c3_fixed2` 与 `c4_auto` 运行隔离注错，其余使用 `--normal-only`。再次执行必须更换标签，已有证据不可覆盖。每目录的 `summary.json`、`normal/simulation.log`、`synthesis/{run.ys,synthesis.log,netlist.json}` 是实际输出；失败证据与旧四槽证据均保留。

八个配置的 Verilog-2001 编译及 Yosys 映射后 `check -assert` 全部返回 0，检查网表均为 0 latch。容量 3 的自动/显式配置均为 309 个层级累计通用 cell；默认容量 4 为 342 个，相比旧实现的 313 个增加 29 个。这是组合选择结构变化的通用综合结果，不是工艺面积或时序结论。

默认四槽的地址 bit56 截断、提前响应和高半数据翻转三类故障全部编译返回 0、运行返回 1。容量 3 的这三类以及新增“指针按 slot 位宽而非实际容量回绕”故障也全部编译返回 0、运行返回 1；后者实际报 `FAIL response_before_memory_result id=3`。错误回绕不能被补齐行或无效数据掩盖。

最终 RTL SHA-256：`4e1fe08f12eb09aa0a875785cebce4d0020e120058e266b64b2546feaf98526f`。runner SHA-256：`850ca1b88c204693669bb6ccba7912a7c86c191f2b864baea9a49f290eb86d59`。最后将新增综合入口的输入文件路径改为相对快照目录解析，再以 `capacity_synth_relative_path` 重跑容量 3 显式两位的功能、Verilog-2001 与综合检查，全部通过；RTL 未再修改。`py_compile` 和本次文件的 `git diff --check` 通过。

下一步由实际 Endpoint→Switch→Endpoint 集成回归交叉验证 Originator 容量与本次四种 Completer 容量；本单元结果不能代替整条链路验证。复位后外部内存仍须取消旧 epoch，slot 索引本身不含世代号；状态 0/3、固定请求 profile 和单 Beat 子集边界均沿用既有接口契约。
