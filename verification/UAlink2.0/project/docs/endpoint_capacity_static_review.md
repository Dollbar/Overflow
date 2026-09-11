# Endpoint 容量结构静态复核

本次只读复核 `endpoint_read_completer`、`endpoint_transaction_core` 和 `ualink_endpoint_top`，没有修改 RTL、降低 lint 严重度或豁免现有规则。结论：实际 Verilog-2001 展开通过；未发现新增容量结构的功能缺陷，但严格风格及无警告 lint 门限仍未闭合，不能标成 strict-style PASS。

## 原始静态诊断的归类

`build/verification/endpoint_transaction/capacity_static/` 的原报告保持原样：Completer 为 4 error / 16 warning，Core 为 114 / 10，Top 为 343 / 11。

| 诊断 | 独立判断 |
| --- | --- |
| Core 缺少 `posedge i_clk`、显式低有效复位、流水 always | 所用 spec 要求叶模块自身含流水状态，不能直接套用纯层级 Core。Core 把同一 `i_clk` 和经过配置合法性门控的复位传给三个实际有状态模块；不能为满足模板而凭空添加流水。 |
| Top 缺少对 `i_rstn` 的显式低有效判断 | Top 先定义 `rstn=i_rstn&&!i_link_reset`，其真实时序块使用 `if(!rstn)`。这是合法复位别名；只匹配原始端口名的检查不能据此判定没有复位。 |
| Core `WIRE_INIT` | `wire transaction_rstn=i_rstn&&CONFIG_LEGAL` 是 Verilog 网线声明中的连续赋值，会随输入变化，不是寄存器初始值。实际编译接受，未发现硬件语义问题；严格风格要求拆开声明与 assign 仍未满足，本轮不修改源码。 |
| Completer `SEQ_BLOCKING_ASSIGN` / `MIXED_ASSIGN` | 顺序块中的阻塞赋值只出现在 `for(reset_slot=0; ...; reset_slot=reset_slot+1)` 的循环控制。实际槽状态、数据及指针均使用 `<=`；没有用阻塞赋值更新事务状态。循环索引必须在当前展开迭代中推进，不能机械改成非阻塞赋值。 |
| Completer `FOR_CONST_BOUNDS` | 两处上界均为展开期参数 `CAPACITY`，循环变量分别为 `read_slot`、`reset_slot`，更新步长固定 1；不是运行期无界循环。Icarus、Yosys 实际展开与映射均接受；原检查结果保留，不能把它当作无界硬件证据。 |
| 逐行注释、双语头、区域名、FSM/实例命名、常量风格 | 多数属于既有源码与严格模板的风格差距，部分修改行也未满足该模板。属于真实风格欠账，不能由功能回归通过抵销。本次不做大范围注释或命名重排。 |

## 实际工具辅助检查

新证据在 `build/verification/endpoint_transaction/capacity_static_independent/`：保存三个模块快照、完整源 SHA-256、各命令 JSON、日志、返回码、耗时以及 `summary.json` / `scoped_summary.json`；检查期间源哈希无漂移。使用本地 `iverilog` 和 `verilator`，完整命令可从对应 JSON 重放，产物写入该目录。

- `iverilog -g2001` 实际展开 `ualink_endpoint_top`，`TRANSACTION_MODE=1, ORIGINATOR_CAPACITY=8, COMPLETER_CAPACITY=3`，返回 0，输出 `top.vvp`。使用实际源 RTL、授权 KD28 mapper 与 SRAM blackbox 声明；这是语法/结构检查，不是黑箱 SRAM 的行为验证。
- Verilator 使用 `--lint-only --language 1364-2001 -Wall`，未使用 `-Wno-fatal`、关闭规则或修改源码。限定实际 Core 依赖的检查返回 1：6 项 `TIMESCALEMOD`、7 项 `WIDTHEXPAND`、1 项未使用信号（无 OrigData 的类别 0 接纳反馈）。其退出原因仅为这 14 项警告；不能记为无警告 lint 通过。
- 单独 Completer 容量 3、两位 slot 检查返回 1，只有 7 项 `WIDTHEXPAND`；修改前快照同参数为 5 项。新增两项是两位 `issue_q/head_q` 与 32 位循环索引比较时的扩展。在验证范围内索引只取非负真实槽号，比较采用扩展而非截断，不会把未用槽别名到有效槽。其余五项是既有 count/容量、结果 slot/容量及三个回绕比较。未在 Completer/Core 定向检查中报告 `LATCH`、`MULTIDRIVEN`、`UNDRIVEN`、`UNOPTFLAT` 或 `BLKANDNBLK`。
- 全源 Top lint 保留返回 1 和全部 1,556 项警告，主要是既有空 pin、未连接观测输出、未使用信号及时间单位等。唯一 `UNDRIVEN` 指向明确使用的外部 SRAM blackbox `Q`，不能混同此前已经修复的 Completer 第四行读选择未驱动问题。该运行不构成完整 Top lint 闭合证据。

容量 1～4、自动/显式两位 slot 的真实事务与 Yosys 映射检查见 [Completer 容量审查](endpoint_completer_capacity_review.md)；跨 Endpoint 的组合与非法配置测试见 [容量集成审查](endpoint_capacity_review.md)。这些功能与结构证据没有替代原始严格风格失败。下一步应单列与实际层级契约相符的静态规则及风格整理任务，保留本轮已验证接口和功能行为。
