# 注册化 Control 费用进位保存审查

本阶段在 `tl_prepared_partition` 内替换费用前缀的加法结构，保留所有寄存器、公开接口、捕获和退休逻辑。采用十个可复用的六位进位保存节点，每个完整前缀末级只执行一次进位传播加法。完整双 IP Goal、640 ps 收敛及完整顶层 STA 仍未完成。

基线为 `3127705b9aca1051d0915b9b8be51e41216968eb`，原 RTL SHA-256 `0e58dd764016974129329bd1c9c6cc7d854c19ff8cb4bb1e7529b52ef1190dc0`；候选 SHA-256 `d8df94f8b36b7d037366dca0a60c0f389fbf4965e725ec3073f5becdcfeb571a`。解码、tenure 及其余模块源码未变。本阶段仅本地续作。

## 结构与证明

三操作数按同位异或得到部分和，按多数位左移得到进位，重复压缩到两个六位操作数再相加。所有中间值采用与原费用输出相同的六位模加法；其恒等式对任意六位输入成立，不依赖“合法事务最大费用”假设。CMD 和 Data 的费用来源、物理账户匹配、游标掩码、完整字段边界和容量比较仍使用原逻辑。

独立算术证明从实际原版和实际候选各提取完整费用块，分别与直接前缀求和比较。两个 SAT 都覆盖 48 个任意输入位和全部八个六位输出，且无假设。随后核对候选只替换这段纯组合代码并删除两个不再使用的局部临时数组；块外完整源码逐字节相同。检查器禁止隐藏状态、外部临时变量引用，以及算术依赖 `account` 或证明专用输入等情形。这样，账户索引仅改变输出切片位置，不会把只在账户零成立的等式外推到全部账户。

此外仍执行原、新整模块完整 CEC。图准备器沿用不可变祖先 `8bf4afc` 为金参考，比较全部 531 位公开输出与真实 FF 下一状态；该祖先和当前 `3127705` 的对应已由前阶段证明。两种图均保留全部真实上升沿时钟和状态，WIDTH 8–16 的状态数仍为 `855 + 20*(WIDTH+1)`，只有原有八个 count 最低位为常量。两个证明路线相互补充，算术分解不代替实际 CEC 端口/状态清单。

复位/空闲捕获 SAT 允许两边初始载荷彼此独立；复位先建立所有权与游标关系，捕获再建立完整状态关系。完整状态 CEC 保持该关系并比较公开输出。因此，结论是有效同步复位后的二值顺序等价，包括反压、噪声源输入、格式错误、容量不足和同拍退休替换。四态 X 传播和模拟时序不在此结论中。

## 当前验证范围

- 原版/新版独立算术 SAT：2/2；真实进位移位故障产生 SAT 反例。
- 完整 RTL CEC：WIDTH 8–16，9/9；独立复位/捕获关系 18/18。
- 独立模型实际单位向量：九位宽共 69,462 个，全部 531 位输出比较；每宽度包含 100 次同拍退休替换。
- 实际 RTL 故障：原 14 类 × 两位宽为 28 次，全部检出；进位左移从 1 改为 2 的真实变异又在两位宽实际仿真检出，合计 30 次。编译失败不计检出。
- 实际双端 SRAM/信用：正常和最小队列各 16 配置，共 32/32；完整原始 trace 由独立检查器在普通 Python 与 `-O` 下审计。
- 当前真实 TSMC28 网表：两位宽完整 CEC 及四条独立复位/捕获 SAT。原网表与映射后的组合图、真实 D/Q 和全部公开端口逐项对应。
- Verilog-2001 严格 lint 无警告；技能 artifact 检查零错误、19 条建议。六项新增上下文审计器测试在普通与优化 Python 下通过。

本轮没有重新跑当前候选的完整门级向量仿真或前阶段网表负例，不把历史成绩转记为当前成绩。实际双端仍使用带组间气泡的退休适配器；本模块的同拍替换能力由独立单位向量验证，不据此宣称端到端无气泡吞吐。

干净导出的 `make test rtl-smoke` 已通过，含原有 20 项与新增 6 项检查器测试；导出使用候选覆盖生产 RTL，其他非文档源文件与当前工作区逐字节一致，源码/日志哈希和退出状态保存在 `compatibility.json`。

## 实际 PPA 与取舍

| 参数 | 原面积 µm² | 新面积 µm² | 新单元数 | 原最差主 setup ns | 新最差主 setup ns |
|---|---:|---:|---:|---:|---:|
| WIDTH 8 | 10,614.744 | 11,272.590 | 17,358 | −0.735223 | −0.707760 |
| WIDTH 16 | 11,748.618 | 11,753.280 | 18,335 | −0.723638 | −0.712052 |

主 setup 分别改善 27.463/11.586 ps；面积分别增加约 6.20%/0.04%。两位宽整体最差由 −0.735223 改善到 −0.712052 ns，仍有明显缺口。本阶段接受这项面积代价，因为两个宽度都改善主周期约束，且不增加初始延迟或改变状态/握手。不能据此声称主频已收敛。

五角、两周期、两位宽共 20 组 STA：主周期 0/10，参考周期 10/10。原 0.640/6.400 ns 周期、32/10 ps setup/hold uncertainty、128/20 ps 输入 max/min、128/−20 ps 输出 max/min、50 ps transition、5 fF load 均保持。使用理想时钟且未加载布局寄生，无新增假路径或多周期例外。参考最差 slack 为 WIDTH 8 的 5.052240 ns、WIDTH 16 的 5.047947 ns。

新最差 SSG 低温路径从 WIDTH 8 的 `r_cursor[1]`、WIDTH 16 的 `r_slots[7]` 到 `o_control[128]` 等输出。路径回溯使用实际 STA 网表中的触发器 Q 名。Yosys JSON 与最终 Verilog 的自动实例名并不相同，不能直接用 STA 实例名索引前者；首次回溯尝试遇到这一差异，改为读取实际 Verilog 实例端口后完成。

## 证据及复跑

本地根目录为 `build/verification/tl_cost_compression`，含候选、基线、算术正负例、上下文审计、关键路径和总清单。完整 RTL 图/CEC/复位关系保存在 `tl_selection_reduction/cost_*`，以复用现有准备器；目录名字不改变其纯 RTL 图属性。单位/故障/STA 在 `tl_prepared_partition/cost_compression_*`，真实映射证明在 `tl_prepared_mapping/cost_compression_*`，实际双端在 `tl_control_partition/cost_compression_*`。这些路径均在 `build/verification` 下。

```sh
python3 verification/tl_prepared_partition/test_cost_relation.py
python3 -O verification/tl_prepared_partition/test_cost_relation.py
python3 verification/tl_prepared_partition/check_cost_relation.py
python3 -O verification/tl_prepared_partition/check_cost_relation.py
python3 verification/tl_prepared_partition/check_cost_evidence.py --adopted
python3 -O verification/tl_prepared_partition/check_cost_evidence.py --adopted
```

输出依次为测试日志、`relation.json` 和 `evidence.json`。固定标签审计用于原始留存证据；它不会将其他重跑标签当作原阶段结果。新标签重建可使用各脚本 docstring 与前阶段审查列出的相同入口，新增费用证明命令为：

```sh
python3 verification/tl_prepared_partition/run_cost_lemma.py --candidate rtl/tl/tl_prepared_partition.v --label cost_replay
python3 verification/tl_prepared_partition/run_cost_lemma.py --candidate build/verification/tl_cost_compression/baseline.v --legacy --label baseline_cost_replay
make test rtl-smoke
```

算术证明会保存实际候选、原始 miter、Yosys 脚本、完整日志和 SAT 反例。新环境还需不可变 Git 参考和获授权的原工艺/SRAM 依赖。所有通过、失败和实际网表证据留存；只清理终止任务的波形与编译缓存，不发布工艺库或 SRAM 模型。

下一阶段优先把已验证准备器接入生产发送组合：当前它仍只由验证顶层实例化，`tl_tx_buffered` 接收已准备好的 Control。需要定义完整源组捕获、标签所有权和实际头部入队的关系，并去除测试用退休适配气泡，之后测量实际组合顶层。账户/游标到费用选择路径的进一步注册或分级同时保留为时序工作，不以单模块微优化替代完整端口、Endpoint/Switch、数字 PHY、INC、安全和管理范围。
