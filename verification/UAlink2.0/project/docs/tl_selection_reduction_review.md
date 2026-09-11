# 注册化 Control 并行选择与直接账户判断审查

`tl_prepared_partition` 采用并行扇区/标签资格归约，以及按物理账户静态展开的共享 Pool 匹配。WIDTH 8/16 主周期最差 setup 分别改善 84.692/84.567 ps，面积下降 12.96%/14.00%。全部状态寄存器、捕获和退休条件保留；初始一拍延迟及最后分组退休时同拍接纳下一源的能力不变。640 ps 尚未收敛，完整双 IP Goal 和完整顶层 STA 仍开放。

基线为提交 `8bf4afcd54eaec3bc4ac35811fd6266b4ba86e61`；原 RTL SHA-256 为 `def8d202e6394d755485a191fb7f42ba93ec8ef3af28ca061f3f37e4bace7f78`。采用源码 SHA-256 为 `0e58dd764016974129329bd1c9c6cc7d854c19ff8cb4bb1e7529b52ef1190dc0`。解码和 tenure 依赖未改变。候选经过验证后按字节复制到 `rtl/tl/tl_prepared_partition.v`，本阶段仅本地提交。

## 改动与等价依据

- 扇区属于最长合格前缀，当且仅当游标不超过该扇区，且某个结束于该扇区之后的边界合格。输出只需每扇区一次掩码，删除八份 256 位前缀的优先选择链。
- 每个输出标签槽用“存在一个合格边界，其字段数超过槽编号”直接决定是否保留。实际字段前缀数单调且完整表示 0–8；标签资格无需经过最长字段数优先选择再比较。
- Data 账户 10 直接匹配原账户 10 或共享模式的账户 15；账户 15 只匹配非共享模式的原账户 15；其余账户直接比较原编号。删除共享编号多路选择后再比较的层级。CMD 账户和信用数值不变。

完整字段数与结束边界仍采用原最长合格优先逻辑。接口格式、错误拒绝、容量快照、标签移位及源数据所有权均未改变。

## 本轮实际验证

| 检查 | 范围与结果 |
|---|---|
| 实际选择方程独立 SAT | 20 个任意输入位，1,048,576 种 application/cursor/fit 组合，12 位扇区/标签掩码；无协议有效性假设 |
| 原版/新版实际状态 CEC | WIDTH 8–16，9/9；全部 531 位公开输出、全部真实 FF 下一状态与语义观察输出 |
| 独立初态复位/空闲捕获 SAT | 9 位宽 × 2 条关系，18/18 |
| 独立流式模型向量 | 9 位宽 × 7,718，69,462/69,462；每个位宽含 100 次同拍退休替换 |
| 实际 RTL 变异 | 14 类 × WIDTH 8/16，28/28；均成功编译并产生功能失配 |
| 实际双端 SRAM/信用 | 正常与最小队列各 16 配置，32/32；1,536 源组、5,248 分组、6,912 字段、2,304 个完整 SingleBeat read reply |
| 新实际 TSMC28 网表 CEC | WIDTH 8/16，2/2；1,035/1,195 位实际 FF 下一状态及全部公开输出 |
| 新实际网表独立复位/捕获 SAT | 4/4 |
| RTL 静态检查 | 零错误、19 条版式/字面量建议；严格 Verilog-2001 Verilator lint 无警告 |

顺序等价的组合关系沿用已审查方法：复位建立所有权/游标对应；空闲时允许两份载荷状态彼此独立，实际捕获建立全部存活状态对应；完整 CEC 在相同当前状态下比较所有输出及真实下一状态。不存在将输出相等作为输入假设的循环证明。九位宽真实状态数为 `855 + 20*(WIDTH+1)`；仅八个已有 count 最低位为常量，未删除其他状态。原 RTL 参考证明由对基线完整输出和状态转移的等价关系传递。

`direct_pair` 与 `direct_other_pair` 是两份 RTL 图。为复用 CEC 工具，其目录内 `mapped.v` 只是通用候选快照文件名；记录明确为 `mode=rtl_pair, library=null`，不将其称为工艺网表。真实网表仅来自 `selection_direct_timing/width*/mapped.v`，真实映射等价位于 `tl_prepared_mapping/selection_direct_mapped*`。

本轮没有重新执行当前候选的完整门级向量仿真，也未重跑前阶段的八项工艺网表故障。上述当前网表结论来自新网表完整 CEC、独立复位/捕获关系和当前 RTL 的独立模型/实际双端验证。前阶段门级向量与网表负例留作历史证据，不转记为本轮成绩。实际双端测试仍使用带组间气泡的退休适配器；同拍替换能力由单位向量覆盖，不能把双端测试写成无气泡端到端吞吐证明。

首次并行掩码候选在实现前保留缺少候选的红灯记录，之后实际 `<` 改为 `<=` 的标签故障产生 SAT 反例，并在 WIDTH 8/16 实际仿真第 3 个向量检出。该负例属于首个候选 A，与最终 B 的 28 次变异分开计数。两次最初双端调用误传 SRAM 模型子目录，属于依赖准备失败，保留日志但不计入协议故障检出。

干净导出的 `make test rtl-smoke` 已通过，包括 20 项已有实际状态/CEC/SAT/数值比较检查器测试。导出源码与当前非文档源文件逐字节核对，退出状态、日志及源码哈希见 `tl_selection_reduction/compatibility.json`。

## 三个实测候选

所有面积单位为 µm²，slack 单位为 ns；每个候选都完成两位宽、五角、两周期的实际测量。

| 候选 | WIDTH 8 面积 / 最差主 setup | WIDTH 16 面积 / 最差主 setup |
|---|---:|---:|
| 原始注册化基线 | 12,195.288 / −0.819915 | 13,660.416 / −0.808205 |
| A：并行扇区与标签掩码 | 10,778.040 / −0.809471 | 11,902.590 / −0.770807 |
| **B：再加入直接物理账户匹配，采用** | **10,614.744 / −0.735223** | **11,748.618 / −0.723638** |
| C：再并行选择最高合格字段数，未采用 | 10,607.310 / −0.736943 | 11,860.002 / −0.716446 |

B 的标准单元数为 16,542/17,564；参考周期最差 slack 为 5.024776/5.036361 ns。主周期 0/10 通过，参考周期 10/10 通过。C 在 WIDTH 16 的 setup 略好，但 WIDTH 8 最差 slack 略退步、WIDTH 16 面积增加；本轮采用整体最差 slack 更好且两宽度面积均明显下降的 B。C 只完成两位宽 RTL CEC 和 PPA 试验，不宣称其已完成九位宽/双端资格验证。

约束保持主周期 0.640 ns、参考 6.400 ns、setup/hold uncertainty 32/10 ps、输入 max/min 128/20 ps、输出 max/min 128/−20 ps、50 ps transition、5 fF load；理想时钟，无布局布线寄生，也无新增假路径或多周期例外。工具沿用 Yosys 0.33/ABC/OpenSTA 与已授权 TSMC28 五角库。当前最差路径在 SSG 低温角，WIDTH 8 从 `r_slots[2]`、WIDTH 16 从 `r_cursor[0]` 到 `o_fields[0]`。后续应处理账户费用至字段选择的深路径，必要时预注册账户信息或分级，但必须重新证明握手、所有权与吞吐。

## 复跑与留存

完整本地证据根为 `build/verification/tl_selection_reduction`；当前单位/变异/STA 在 `tl_prepared_partition/selection_direct_*`，真实网表证明在 `tl_prepared_mapping/selection_direct_*`，实际双端在 `tl_control_partition/selection_direct_*`。各路径均位于 `build/verification`。普通和 `-O` 审计入口为：

```sh
python3 verification/tl_prepared_partition/check_selection.py --adopted
python3 -O verification/tl_prepared_partition/check_selection.py --adopted
```

输出 `tl_selection_reduction/evidence.json`。审计逐项核对实际源文件、公开端口、真实 D/Q 图、CEC 输入和完整端口、SAT 关系、独立向量、变异源码、实际网表及工艺库哈希；不以汇总 `complete` 标志替代这些检查。双端完整 trace 审计入口如下，输出两个可比较报告：

```sh
python3 verification/tl_control_partition/check_evidence.py --peers-only --peers-label selection_direct_peers --minimum-label selection_direct_minimum --output-label selection_direct_peer_evidence
python3 -O verification/tl_control_partition/check_evidence.py --peers-only --peers-label selection_direct_peers --minimum-label selection_direct_minimum --output-label selection_direct_peer_evidence_optimized
```

新环境可用以下生产源码入口重建验证；运行器拒绝覆盖已有标签，使用隔离导出或新标签。`LIB_ROOT`、`STA_BIN` 和 `KD28_ROOT` 由已获授权的本地配置提供，不写入公共脚本。

```sh
python3 verification/tl_prepared_partition/run_selection_lemma.py --candidate rtl/tl/tl_prepared_partition.v --label masks_replay
python3 verification/tl_prepared_partition/run_selection_equivalence.py --candidate rtl/tl/tl_prepared_partition.v --label pair_replay --widths 8 9 10 11 12 13 14 15 16
python3 verification/tl_prepared_partition/run_mapped_cec.py --base build/verification/tl_selection_reduction --parent pair_replay --label cec_replay --widths 8 9 10 11 12 13 14 15 16
python3 verification/tl_prepared_partition/run_state_cases.py --base build/verification/tl_selection_reduction --parent pair_replay --label reset_replay --widths 8 9 10 11 12 13 14 15 16
python3 verification/tl_prepared_partition/run_rtl.py --label unit_replay --widths 8 9 10 11 12 13 14 15 16
python3 verification/tl_prepared_partition/run_faults.py --unit-label unit_replay --label faults_replay
python3 verification/tl_prepared_partition/run_timing.py --lib-root "$LIB_ROOT" --sta "$STA_BIN" --label timing_replay
python3 verification/tl_prepared_partition/run_mapped.py --timing-root build/verification/tl_prepared_partition/timing_replay --label mapped_replay --cases reset empty
python3 verification/tl_prepared_partition/run_mapped_cec.py --parent mapped_replay --label mapped_cec_replay
python3 verification/tl_control_partition/run_peers.py --prepared --kd28-root "$KD28_ROOT" --label peers_replay
python3 verification/tl_control_partition/run_peers.py --prepared --kd28-root "$KD28_ROOT" --bank-depth 1 --header-depth 1 --label minimum_replay
make test rtl-smoke
```

每个入口的完整命令、输出路径和下一步在脚本 docstring 中说明。时序命令因真实违规返回 1；这不代表测量未完成。以上新标签需传入对应双端审计；本阶段固定标签汇总审计用于核验原始留存证据，不会自动把新标签写成旧阶段结果。新环境的原版/新版证明还需保留 Git 基线提交。

保留通过、失败、未采用候选、源快照、原始日志、向量、trace、SAT 反例和实际网表。仅清理已结束任务的 `.vvp`、Python 字节码和波形缓存。工艺库和 SRAM 模型继续留在授权的外部依赖目录，未入 Git。下一步继续 640 ps 优化、完整真实端口/Endpoint/Switch 顶层集成与未完成协议范围。
