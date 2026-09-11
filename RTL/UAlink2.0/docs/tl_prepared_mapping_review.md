# 注册化 Control 工艺网表等价审查

本阶段针对 `tl_prepared_partition` 的 WIDTH 8/16，建立当前 RTL 与前一阶段实际 TSMC28 网表的一沿复位后二值顺序等价关系。生产 RTL 没有修改。完整 Endpoint/Switch IP、640 ps 收敛和完整集成顶层 STA 仍未完成。

## 实际对象与状态覆盖

使用 `build/verification/tl_prepared_partition/timing/results.json` 记录的源文件、SSG 工艺库和实际 STA 网表；逐项核对哈希，未重新生成另一套网表代替原 STA 对象。由该 Liberty 导入真实单元的布尔函数与触发器行为，展平后检查全部逻辑原语、驱动关系以及真实原始上升沿时钟。

| 项目 | WIDTH 8 | WIDTH 16 |
|---|---:|---:|
| 原公开输出 | 12 个，531 位 | 12 个，531 位 |
| RTL/工艺网表全部真实触发器 | 1,035 / 1,035 | 1,195 / 1,195 |
| CEC 下一状态比较 | 1,035 位 | 1,195 位 |
| 附加语义状态观察 | 1,043 位 | 1,203 位 |
| CEC 总输出比较 | 2,609 位 | 2,929 位 |
| CEC 实测用时 | 4.12 秒 | 3.82 秒 |

附加语义观察包含常量位，不是额外真实触发器。两个宽度均仅将 `r_counts[0,4,8,12,16,20,24,28]` 作为常零位；其他语义位都有实际 FF Q 对应，未遗漏状态。另对未切割的原始 RTL 证明：拥有数据时这八位为零，两个宽度均归纳通过；将捕获的八位故意置一产生两个 SAT 反例。这两个性质负例不计入下面的八项网表故障。

状态观察保留全部原接口。每个真实 FF 的 Q 作为当前状态输入，D 作为下一状态输出，组合方程和原网别名保持不变。单独的审计器重新检查 Q/D、所有原端口、状态集合、语义位与常量对应，拒绝改接时钟、遗漏状态、将下一状态换成当前 Q、删除输出或错误的别名。

## 复位后的组合归纳

不能假定两份未复位载荷寄存器初值相同。证明采用如下关系：双方所有权与游标相同；拥有源组时，全部存活状态相同；空闲时其余状态互相独立。

1. **复位基例，2/2 SAT：** 两边每个当前真实状态独立任意，复位周期全部公开输出为零，下一状态所有权及游标均为零。
2. **空闲分支，2/2 SAT：** 双方所有权和游标为零，其余当前状态独立任意。全部公开输出相同；下一状态所有权与游标相同；若下一状态拥有数据，全部下一状态相同。这覆盖首个实际捕获，以及任意时长的空闲。
3. **完整状态 CEC，2/2：** 两边全部当前真实状态一一对应，比较所有原公开输出和全部实际 FF 下一状态，无协议、字段有效性、容量或游标范围假设。其范围比仅验证持有态更强。CEC 同时比较完整语义观察输出；未删除公开输出或选择性省略难证明的状态。

因此，复位建立关系，空闲分支在真实捕获时建立完整状态对应，CEC 保持对应并给出输出相等；退休或再次复位后继续回到已覆盖的关系。结合原 RTL 的常量位性质，结论适用于一沿有效同步复位后的任意二值输入流，包括反压、源输入噪声、错误组、容量不足和同拍替换。

此处的 CEC 将有明确对应的真实 FF 状态作为组合输入，并比较真实 D 方程。它不把输出相等作为假设，也不宣称直接未分解顺序 PDR 已求解。原始直接持有态 SAT 在两个宽度均超时 180 秒，日志保留。

## 实际负例和交叉验证

| 实际网表故障 | WIDTH 8/16 结果 |
|---|---|
| 所有权 FF 时钟改接 `i_ready` | 两次真实时钟清单拒绝 |
| 所有权 FF 的 D 绕过复位 | 两次复位 SAT 反例 |
| Control 位 FF 的 D 改接实时错误输入位 | 两次空闲/捕获 SAT 反例 |
| 有效输出时翻转一个实际 AuthTags 位 | 两次持有态 SAT 反例 |

网表负例合计 8/8。相同 CEC 入口又对捕获、标签与复位故障各两个位宽进行交叉检查，6/6 均报告不等价。捕获故障还通过未切割的实际映射 Verilog、由原 Liberty 导出的功能单元模型和独立 Python 期望进行交叉仿真：从复位开始，第 8 个向量检出首次差异，前七个向量相同。该仿真是数字功能检查，未加载单元延迟，也不代表模拟 SerDes 或后布局时序仿真。

完整正常网表在两个位宽各通过 7,718 个向量，合计 15,436 个；全部 531 位输出逐位匹配独立期望。实际用时约 294.45/300.57 秒。初次 240 秒预算的超时保持原记录，新标签以 600 秒预算完成，未缩减向量数量。普通 Python 与 `-O` 汇总审计均通过；汇总证据在 `build/verification/tl_prepared_mapping/evidence.json`。

检查器测试覆盖实际状态/组合图约束、D/Q 破坏、缺失公开输出、非零 Verilog 位下标、短 SAT 失败日志、实际输出别名、无关高输入、语法错误和超时混入反例，以及十六进制补零、未知值与超位宽拒绝，共 20 项通过。`make test` 已通过，之后新增的检查器回归又单独运行通过。

保留的探索记录包括：未提前暴露语义寄存器时清理掉内部名字的首次准备；首个 CEC 命名审计把 `[7:1]` 当作 `[6:0]` 的失败；首个标签钳零故障使无用途状态变为未驱动观察、被清单拒绝；短反例只输出 `o_bad` 的实际输入别名导致过窄的首次审计失败；首个 trace 审计将补零十六进制与无补零期望按文本比较，修正为完整 531 位数值比较且拒绝 X/Z 和超位宽；直接 SAT 和初始门级仿真预算超时。后续修正均使用新标签或新日志，未改写旧证明输入。

## 复跑入口

在工程根目录运行。需要已授权的原工艺库、前一阶段实际映射/STA 结果及 `unit_semantics` 独立向量。运行器从时序清单读取库路径，并核对库与网表哈希；私有库、由其导出的功能模型、网表和波形不发布。独立模型及原始向量的绑定还要求前一阶段 `tl_prepared_partition/manifest.json`（提交 `c34f40f`）可供核查。

```sh
python3 verification/tl_prepared_partition/test_mapped_state.py
python3 verification/tl_prepared_partition/run_formal.py --label mapped_constants --properties count_constants
python3 verification/tl_prepared_partition/run_mapped.py --label actual_relation
python3 verification/tl_prepared_partition/run_mapped_cec.py --parent actual_relation --label complete_cec_verified
python3 verification/tl_prepared_partition/run_mapped.py --label fault_clock --fault clock --prepare-only
python3 verification/tl_prepared_partition/run_mapped.py --label fault_capture --fault capture --seconds 60
python3 verification/tl_prepared_partition/run_mapped.py --label fault_reset --fault reset --seconds 60
python3 verification/tl_prepared_partition/run_mapped.py --label fault_output_verified --fault output --seconds 60
python3 verification/tl_prepared_partition/run_mapped_cec.py --parent fault_capture --label cec_fault_capture
python3 verification/tl_prepared_partition/run_mapped_cec.py --parent fault_output_verified --label cec_fault_output
python3 verification/tl_prepared_partition/run_mapped_cec.py --parent fault_reset --label cec_fault_reset
python3 verification/tl_prepared_partition/run_mapped_vectors.py --parent actual_relation --label mapped_vectors_w8 --widths 8 --seconds 600
python3 verification/tl_prepared_partition/run_mapped_vectors.py --parent actual_relation --label mapped_vectors_w16 --widths 16 --seconds 600
python3 verification/tl_prepared_partition/run_mapped_vectors.py --parent fault_capture --label mapped_fault_vectors --widths 8 --expect-mismatch
python3 verification/tl_prepared_partition/check_mapped.py
python3 -O verification/tl_prepared_partition/check_mapped.py
```

运行器拒绝覆盖已有标签；在隔离工作区重跑上述固定标签，或使用新标签并调整审计入口。直接 SAT 的超时、实际故障证明和时钟拒绝命令返回非零；CEC 和最终组合审计单独决定等价结论。输出包括源快照、原始/观察/切割 JSON、状态清单、BLIF、完整原始日志、SAT witness 和实际仿真期望/观察记录。

下一步继续处理实测 −0.819915 ns 的最差主周期 setup 缺口，明确分级流水线的握手、所有权和吞吐代价，并推进完整顶层集成及其余协议范围。当前生产 RTL 与实际网表未变，不能把新等价证明写成时序收敛。

实际最差路径已回溯到原网表触发器：WIDTH 8 从 `r_cursor[0]` 到 `o_tags[10]` 等输出，WIDTH 16 从 `r_cursor[3]` 到 `o_tags[51]` 等输出，均在 SSG 低温角。下一阶段结合已证明的游标范围，评估显式消除恒零高位及费用/边界/标签路径分级；不通过放宽周期或虚构时序例外消除违规。
