# 注册化 Control 的复位后 RTL 参考等价审查

本阶段完成 `tl_prepared_partition` 在 WIDTH 8–16 的二值、复位后顺序参考等价。十二个公开输出共 531 位全部比较，结论由实际 RTL 的复位/单步关系与分别证明的可达状态不变量组合得到。生产 RTL 未修改，SHA-256 为 `def8d202e6394d755485a191fb7f42ba93ec8ef3af28ca061f3f37e4bace7f78`。

本结论证明相对固定 RTL 基线的行为保持。参考依赖历史解码器，不是独立协议认证；不包含四态/X 语义、工艺网表等价、主频收敛或完整 Endpoint/Switch 顶层签核。

## 参考与状态关系

`verification/tl_prepared_partition/reference.v` 自行保存 Control、AuthTags、容量、类别、auth/shared 和所有权，实例化提交 `1e26fbd486ca4ee96de4635fd9a2442801bfc89d` 的原始字段分组器及其 admission/decode/tenure 依赖。参考拥有自己的游标与捕获/退休逻辑；候选输出不驱动参考状态。两者使用相同外部输入和真实上升沿。参考每拍重新解码保存的原始字段，候选使用已捕获元数据。

关系要求双方所有权、游标相同；拥有源组时，保存的原始 Control、标签、容量和属性也相同。空闲时双方载荷状态互相独立，不要求复位清零。候选增加一个仅用于观察的 response 历史寄存器，它只在真实 `o_captured` 时捕获 `i_response`，不影响生产状态或输出；它与元数据归纳中的类别历史寄存器具有相同更新定义。候选元数据关系仅在拥有源组时生效。

单步模型从实际展平 RTL 中提取每个真实触发器的 Q 与 D，保留全部组合方程、网别名和原接口。候选共 1,044–1,204 位状态（包含一位观察历史），参考共 956–1,116 位状态；两边均无未分类状态。移除触发器后，当前 Q 成为显式关系输入，下一状态输出仍是原触发器 D。并未把解码结果变成自由输入。

## 归纳组合

1. **复位基例：** `i_rstn=0` 时，两边每个当前状态独立任意；SAT 证明全部公开输出为零，下一沿所有权和游标都为零。未约束载荷初态。
2. **元数据归纳：** 对真实候选，只要求首沿有效同步复位；证明拥有数据时的 starts/application/counts/slots/error 等于固定参考解码函数应用于已持有原始字段和类别历史。没有切断生产状态。
3. **边界归纳：** 同样只要求首沿复位，证明 cursor 小于 8、空闲时 cursor 为零，以及拥有无格式错误数据时 cursor 为零或完整字段起点。
4. **单步关系：** 在上述关系及已证明不变量下，证明本拍全部公开输出相同，下一状态所有权/游标相同；下一状态拥有源组时，保存的原始字段及属性相同。下一拍元数据关系由第 2 项归纳提供。

因此，复位建立关系，任意后续输入流保持关系及输出相等。包括输入噪声、done 变化、反压、格式错误、容量不足、重复复位和最终退休同拍接纳下一组。

为降低求解成本，每种 WIDTH 分成复位、空闲、拥有数据且 cursor 为 0–7 共十种情况。只对真实主输入 `i_rstn`、关系所有权和关系游标代入常量，再执行优化和 SAT；未替换任何解码派生信号。第 2、3 项证明这十种情况覆盖所有复位后可达状态。错误组的非零合法范围游标也包含在证明域内。

## 实测与审核

| 检查 | 实测结果 |
|---|---|
| 元数据归纳 | WIDTH 8–16，9/9 |
| 完整字段边界归纳 | WIDTH 8–16，9/9 |
| 复位及完整单步关系 | 9 个宽度 × 10 种情况，90/90 SAT 通过 |
| 原始字段参考对独立 Python 期望 | WIDTH 8/16，各 7,718，合计 15,436 向量，比较全部 531 位 |
| 完整双状态机实际仿真 | WIDTH 8，7,718 向量通过；实际未切割 miter 的输出差异线也参与检查 |
| 实际 RTL 形式负例 | 游标边界、捕获费用清零、丢失同拍替换、标签偏移四类 × WIDTH 8/16，共 8 个 SAT 反例 |
| 完整双状态机覆盖持有数据故障 | 从复位出发，第 8 个记录点检出；参考到故障点仍匹配独立期望 |
| 证据审计 | 普通 Python 与 `-O` 均通过 |
| 审计器测试 | 8/8：正常图、D/Q/公开输出/时钟/组合节点/非固定输入破坏，以及精确注释变更允许/RTL 修改拒绝 |
| 参考 RTL lint | Verilator，Verilog-2001，零警告；只关闭文件名与模块名不一致提示 |

参考首行注释在证明后补充“模块”一词，以满足技能注释检查。审计仅允许这一处精确字节替换，其他字节必须仍匹配原证明哈希；原快照未改写。最终技能静态检查零错误、9 项版式建议，首次注释检查失败报告保留。建议涉及双语头及区域标题，验证参考保留简短结构。技能包全局自检此前因缺失依赖未完成，不能与本次 artifact 检查混为一谈。

证据审计逐项核对真实状态 D/Q、原端口、组合方程保持、各分支常量替换、固定 Git 参考、源文件哈希、成功日志和反例。归纳组合的语义理由由本审查及生成器中的明确关系给出，审计器不是外部形式证明内核。

完整未分解 PDR 的正常与故障运行分别在 180/120 秒预算内未决；不能计为成功或故障检出。第一次 PDR 准备因 Yosys 选项文件名引号处理失败；第一次单步准备因未保留观察寄存器失败。修正后的完整单步 WIDTH 8 查询通过，WIDTH 16 查询在 240 秒超时；随后十情况分解完成全部九种位宽。失败、超时、未决日志和输入均保留。

## 复跑与证据位置

从工程根目录运行；需要包含固定参考提交的 Git 历史，以及 Python、Icarus、Yosys 和 ABC。先按上一阶段审查生成 `unit_semantics` 独立向量。本阶段结果在 `build/verification/tl_prepared_equivalence/`，边界归纳在 `build/verification/tl_prepared_partition/`。运行器拒绝覆盖已有标签目录；复跑使用隔离工作区，或新标签并相应调整审计输入。

```sh
python3 verification/tl_prepared_partition/run_reference.py
python3 verification/tl_prepared_partition/run_metadata.py --label metadata --widths 8 16
python3 verification/tl_prepared_partition/run_metadata.py --label metadata_other_widths --widths 9 10 11 12 13 14 15
python3 verification/tl_prepared_partition/run_formal.py --label boundary_induction --properties boundaries --widths 8 16
python3 verification/tl_prepared_partition/run_formal.py --label boundary_other_widths --properties boundaries --widths 9 10 11 12 13 14 15
python3 verification/tl_prepared_partition/run_step.py --label step_observed --widths 8 16 --prepare-only
python3 verification/tl_prepared_partition/run_step.py --label step_other_widths --widths 9 10 11 12 13 14 15 --prepare-only
python3 verification/tl_prepared_partition/run_cases.py --step-label step_observed --label cases --widths 8 16
python3 verification/tl_prepared_partition/run_cases.py --step-label step_other_widths --label cases_low --widths 9 10
python3 verification/tl_prepared_partition/run_cases.py --step-label step_other_widths --label cases_middle --widths 11 12
python3 verification/tl_prepared_partition/run_cases.py --step-label step_other_widths --label cases_high --widths 13 14 15
```

这些命令生成九宽度正向关系证明的源快照、JSON 状态/方程图、SAT 日志及结果；prepare-only 的成功仅表示准备完成。当前完整审计还要求四类形式负例、实际双状态机正常/故障 trace 和固定标签记录齐备；上面的正向命令不替代这些输入。

```sh
python3 verification/tl_prepared_partition/test_equivalence_evidence.py
python3 verification/tl_prepared_partition/check_equivalence.py
python3 -O verification/tl_prepared_partition/check_equivalence.py
```

审核汇总为 `evidence.json`。最终本地提交及证据文件哈希另存 `manifest.json`，不会发布原始规范、工艺库或构建证据。清理只移除已终止运行的仿真可执行文件、波形与 Python 缓存；输入、日志、反例 JSON、trace 和网表保留，供后续目标继续使用。

下一步建立新模块全部真实状态的工艺映射对应及复位后等价，再依据关键路径继续优化。此前单模块实测主周期最差 setup 为 −0.819915 ns；生产 RTL 未改变，这一时序缺口仍存在。完整顶层 STA、每 VC 调度、超容量单事务处理、完整 UPLI/TL/数字 PHY/INC/安全/管理接口与双 IP Goal 继续开放。
