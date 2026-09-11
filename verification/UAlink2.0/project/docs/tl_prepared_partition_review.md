# 注册化 Control 元数据阶段审查

2026-09-11，本地继续完整双 IP Goal；本阶段未对外发布。

`tl_prepared_partition` 已实现并通过本阶段功能验证。它先捕获完整源组及真实预解码结果，后续从寄存的边界、账户和 Data 计数计算分组。上游捕获确认与整组退休确认分开；首次输出增加一个周期延迟。原 `tl_control_partition` 保留，新模块通过显式 `--prepared` 模式接入实际双端验证。它不是原接口的直接替换，也尚未作为完整 Endpoint/Switch 顶层交付。

## 所有权与协议范围

合约见 [实施计划](tl_prepared_partition_plan.md)。接纳后，Control、tags、总容量、Auth、共享模式及格式状态均由本模块持有；下游停顿时，实时源或 done 变化不能改变已准备输出。最后分组退休可同拍捕获下一组；单位测试包含连续 100 次同拍替换。错误或单字段超容量组保持所有权，直到复位取消。实际信用余额仍由下游真实端口检查。

这一层只重组完整字段，不改变 Write/Atomic 的事务长度，不把超容量事务拆成多个事务。容量快照属于同一初始化时期，重新初始化必须先复位取消待发送组。输入捕获不是线上的发送成功确认。

## 已完成的验证

| 检查 | 实测范围与结果 |
|---|---|
| 独立模型定向测试 | 5 项通过；捕获/退休分离、逐字段标签、连续替换、复位取消、错误/超容量保持及容量快照 |
| 实际 RTL 向量 | WIDTH8–16 九种位宽，共 69,462 个时钟向量；每个向量比较全部 531 位公开输出 |
| 实际 RTL 故障 | 14 类 × 两位宽，共 28 次有效故障全部产生输出不匹配；编译失败和超时不计检出 |
| 真实双端集成 | 两位宽 × Auth × 共享模式 × 1/3 周期链路 × 常规/最小队列，共 32 组通过 |
| 独立双端 trace 审计 | 1,536 个源组、5,248 个分组、6,912 个字段、2,304 个完整 Single-Beat 读回复；Data/BE、标签、真实 SRAM 退休及信用守恒通过 |
| 所有权归纳 | WIDTH8/16 均通过二值复位、捕获内容、所有权守恒、状态保持与游标更新证明；实际粗综合状态观察为 1,043/1,203 位 |
| 输出保持组合论证 | 从实际综合图追溯八类可保持输出，除已证明保持的全部寄存状态外，仅依赖 `i_rstn`；结合前后拍有效复位条件，得到反压下输出保持 |
| 形式负例 | 覆盖已拥有组和游标复位旁路两类真实故障，在两位宽产生共 4 个 SAT 基例反例及 JSON witness |
| 静态与兼容性 | Verilator 严格 lint 无警告，结构检查无锁存器、所有寄存器使用同一上升沿时钟；技能静态审查 0 错误、17 项建议；干净导出 `make test rtl-smoke` 返回 0 |

实际双端测试使用既有真实 Tx 队列、信用端口、Rx SRAM 和 FC 发布器。测试源历史接口在整组退休才推进索引，因此新模式增加了每类别的已捕获标记，避免重复接纳；这个测试适配器在组间有气泡。核心无气泡替换能力由直接捕获接口的单位测试覆盖，不用带适配器的通信周期数作核心吞吐结论。

## 工艺结果与代价

实际 TSMC 28HPC+ NLDM 映射，两位宽各五角、两个周期，共 20 次 STA；主周期 0.640 ns，参考周期 6.400 ns，原 IO、负载、时钟不确定度预算不变，无时序例外。

| WIDTH | 单元数 | 面积 µm² | 最差主 setup ns | 最差参考 setup ns |
|---|---:|---:|---:|---:|
| 8 | 18,797 | 12,195.288 | −0.819915 | +4.940085 |
| 16 | 19,510 | 13,660.416 | −0.808205 | +4.951795 |

参考周期 10/10 通过，主周期 0/10。相对上一组合版本，主 setup 改善约 224/237 ps，面积增加约 38%/52%；接口和延迟也发生变化，不能仅据这一比较认定优化已可替代原模块。最差路径仍从寄存状态经过费用/选择逻辑到 AuthTags 输出，需要继续分级计算。

这是新模块实际网表的布局前测量；新增状态的 RTL/工艺网表等价尚未完成，完整端口/Endpoint/Switch 顶层 STA 也未完成。测量完成不等于时序或签核通过。

## 保留的失败与未完成项

- `missing_rtl` 保留先写测试时的缺失 RTL 失败；`model_red.log` 保留缺失模型失败。
- `faults`、`faults_semantics` 的标签偏移变异含二进制常量与三目运算相邻的词法错误，未进入仿真，均未计入有效检出。`faults_verified` 修正注入语法后，28 次均成功编译并产生实际不匹配。逐字段退休的定向标签用例同时补入最终向量。
- 包含完整字段边界可达性的宽属性集：定义性编码在两位宽均 240 秒超时；二值编码 WIDTH8 超时、WIDTH16 约 202 秒通过。这些结果不能替代两位宽完整功能等价。单独的所有权属性集两位宽约 38/53 秒完成归纳。
- 初次汇总审计对 SAT 基例失败日志的字符串格式判断过窄，保留失败日志；修正后按真实基例失败标记及非空 witness 审查，普通 Python 与 `-O` 均通过。
- 完整独立时序参考等价、全部参数的形式边界证明、新工艺网表等价、主频闭合、完整集成顶层 STA 和双 IP 全范围仍开放。

## 复跑入口与证据

从工程根目录运行。下列名字对应本阶段证据；目录已存在时保留原结果，使用新的隔离工作区复跑。`KD28_ROOT`、`UALINK_LIB_ROOT`、`UALINK_STA` 由操作者显式提供，私有规范、PDK 和 SRAM 依赖不随工程发布。

```sh
python3 verification/tl_prepared_partition/test_model.py
python3 verification/tl_prepared_partition/run_rtl.py --label unit_semantics --widths 8 9 10 11 12 13 14 15 16
python3 verification/tl_prepared_partition/run_faults.py --unit-label unit_semantics --label faults_verified
python3 verification/tl_prepared_partition/run_formal.py --label ownership_formal --properties ownership
python3 verification/tl_prepared_partition/run_formal.py --label formal_fault_overwrite --properties ownership --replace build/verification/tl_prepared_partition/faults_verified/overwrite_owned/tl_prepared_partition.v
python3 verification/tl_prepared_partition/run_formal.py --label formal_fault_reset --properties ownership --replace build/verification/tl_prepared_partition/faults_verified/reset_cursor/tl_prepared_partition.v
python3 verification/tl_control_partition/run_peers.py --prepared --kd28-root "$KD28_ROOT" --label prepared_peers
python3 verification/tl_control_partition/run_peers.py --prepared --kd28-root "$KD28_ROOT" --label prepared_minimum --bank-depth 1 --header-depth 1
python3 verification/tl_control_partition/check_evidence.py --peers-only --peers-label prepared_peers --minimum-label prepared_minimum --output-label prepared_evidence
python3 -O verification/tl_control_partition/check_evidence.py --peers-only --peers-label prepared_peers --minimum-label prepared_minimum --output-label prepared_evidence_optimized
python3 verification/tl_prepared_partition/run_timing.py --lib-root "$UALINK_LIB_ROOT" --sta "$UALINK_STA"
```

两个形式负例命令应返回非零并生成 SAT witness；时序命令应因实际主周期违规返回非零，完整测量仍写入 `timing/results.json`。单位/故障脚本保留独立期望、原始观察、源快照和工具日志。汇总门还消费本环境技能静态审查、严格 lint、干净导出兼容性记录；这些记录齐备后运行：

```sh
python3 verification/tl_prepared_partition/check_evidence.py
python3 -O verification/tl_prepared_partition/check_evidence.py
```

主要证据在 `build/verification/tl_prepared_partition/`；真实双端 trace 位于 `build/verification/tl_control_partition/prepared_*`。终止的仿真可执行文件可清理，输入、期望、trace、失败日志、SAT witness、实际网表和工艺报告保留。

下一阶段先为注册化路径建立完整独立时序参考关系和新增状态的映射证明，再依据实际关键路径继续拆分费用/选择与标签输出；保持 640 ps 目标及完整双 IP 范围。
