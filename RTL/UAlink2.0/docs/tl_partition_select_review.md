# Control分组选择路径与tenure并行计数审查

本阶段采用 `tl_control_tenure` 内部描述符与错误状态并行计算，分组模块的
主周期最差setup从−1.159129ns改善到−1.057862ns。主周期仍未收敛。
完整Endpoint/Controller、Switch、UPLI、数字PHY、INC、安全、管理及
完整顶层STA的目标继续保持；本阶段仅验证一个实际Control分组模块。

## 保留与采用的实现

先测了两个并行选择候选：一个同时使用最高合格边界的独热选择及每扇区
使能，另一个仅改变扇区输出。两者均通过WIDTH8/16完整RTL等价及各自
4,856个单位向量，却在同一工艺预算下变慢，因此没有采用。原始候选、
证明和实际时序报告均保留，不能把面积下降写成时序优化成功。

随后沿实际关键路径定位到tenure的全局错误汇总先清零所有Data计数，再
进行费用累计，而分组出口仍再次检查同一个错误状态。新增默认开启的
`ZERO_ON_ERROR` 参数；只有 `Masked_Tenure_Inst` 显式关闭描述符清零，
使内部计数与错误汇总并行。它原有的 `masked_status==0` 准入条件不变。
其他实例保持默认行为。格式错误仍阻止入队，不修改编码、字段位、标签
顺序、四位游标、同步复位、端口、时钟、周期延迟或实际握手。

被修改的tenure文件原有声明内赋值和模块首尾注释触发18项Artifact错误。
将声明与assign分开，并修正模块注释后，最终两文件Artifact门零错误、
28项风格建议。前后检查记录保留。此前技能全局自检的外部缺失依赖问题
没有在本阶段解决；本阶段Artifact门不代表该全局自检通过。

## 实测结果

沿用实际TSMC28五角库、0.640/6.400ns周期、350ps ABC优化目标、5fF负载
及相同IO/不确定度预算，无新增时序例外。

| 方案 | WIDTH | cells | 面积µm² | 最差主周期setup ns |
| --- | ---: | ---: | ---: | ---: |
| e34ea20基线 | 8 | 14,830 | 8,615.502 | −1.159129 |
| e34ea20基线 | 16 | 14,933 | 9,021.726 | −1.116678 |
| 并行边界及扇区，未采用 | 8 | 13,161 | 7,263.396 | −1.247491 |
| 并行边界及扇区，未采用 | 16 | 13,426 | 7,276.248 | −1.294584 |
| 仅并行扇区，未采用 | 8 | 13,542 | 7,669.620 | −1.177818 |
| 仅并行扇区，未采用 | 16 | 13,583 | 8,058.456 | −1.127425 |
| tenure并行计数，已采用 | 8 | 15,416 | 9,224.208 | −1.057862 |
| tenure并行计数，已采用 | 16 | 15,236 | 8,906.310 | −1.054325 |

采用方案两宽度分别改善101.267ps和62.353ps，WIDTH8面积增加约7.07%，
WIDTH16面积下降约1.28%。参考周期五角两宽度10/10通过，主周期0/10。
最终参考周期最差setup为+4.702137/+4.705675ns。修正声明/注释后的最终
源码重新实际测量，setup及面积与初始并行tenure候选一致。

最终慢冷角关键路径，WIDTH8从真实游标触发器到 `o_tags[20]`，WIDTH16
从 `i_source_control[94]` 到 `o_tags[172]`。后续重点是标签选择、字段
计数和游标掩码的组合依赖，并评估经过握手证明的分级计算。不能因为
某个组合重写更简洁便推定其映射延迟更低。

这是理想时钟、没有提取线寄生的标准单元模块结果，不含完整顶层、SRAM
工艺宏时序、模拟SerDes、物理签核或独立互操作结论。

## 验证范围

- 以完整提交 `e34ea20a9c44df326f97c7da6d0e75bac5d49afe` 为参考，
  WIDTH8–16九参数直接CEC通过，覆盖529位原输出及四位下一状态。
  gold依赖逐文件取自参考Git提交，gate依赖取自候选快照；没有让修改过
  的tenure同时进入gold而掩盖差异。无游标对齐、输入稳定或合法报文假设。
- WIDTH8/16实际工艺网表CEC通过；四位真实状态及直接时钟完整对应，
  一沿复位从任意初态归零通过。六份真实变异网表产生六个SAT反例及两次
  时钟清单拒绝，状态/标签的四次CEC均判不等价。
- tenure独立SAT：默认模式全部46位输出对所有256位输入保持原行为；
  并行模式的错误状态始终一致，状态为零时所有描述符一致。两种模式的
  实际单Beat计数故障均产生具体SAT反例。
- 原独立模型未改：4,856个单位向量、32组正常/最小容量实际双端SRAM
  回归通过。96份线上、队列、分组trace与e34ea20阶段逐字节一致，独立
  trace审计通过。完整16次单位故障和56次实际双端故障全部检出。
- 两宽度严格lint、通用综合通过。干净导出实际 `make test rtl-smoke`
  退出0，采用的全部RTL与Makefile和该导出逐字节一致。阶段审计在普通
  Python及 `-O` 下通过。证明限定为二值行为，不宣称四态X传播等价。

## 复跑入口

候选可先放在独立目录，通过 `--dependency-root` 显式传入。以下命令
使用已采用源码；实际输出标签拒绝覆盖，需要使用新标签或干净工作副本。

```sh
python3 verification/tl_control_partition/run_rtl.py --label select_tenure_clean
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --label select_tenure_peers
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --label select_tenure_minimum --bank-depth 1 --header-depth 1
python3 verification/tl_control_partition/run_checks.py --kd28-root /authorized/Overflow --label select_tenure_checks --peers-label select_tenure_peers --boundary-fault truncated_header
python3 verification/tl_control_partition/check_evidence.py --peers-only --peers-label select_tenure_peers --minimum-label select_tenure_minimum --output-label select_tenure_evidence
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --dependency-root rtl/tl --reference e34ea20a9c44df326f97c7da6d0e75bac5d49afe --label select_tenure_low --widths 8 9 10
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --dependency-root rtl/tl --reference e34ea20a9c44df326f97c7da6d0e75bac5d49afe --label select_tenure_middle --widths 11 12 13
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --dependency-root rtl/tl --reference e34ea20a9c44df326f97c7da6d0e75bac5d49afe --label select_tenure_high --widths 14 15 16
python3 verification/tl_prefix_cost/run_timing.py --candidate rtl/tl/tl_control_partition.v --label select_tenure_clean_timing --lib-root /authorized/NLDM --sta /installed/opensta/bin/sta
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --dependency-root rtl/tl --reference e34ea20a9c44df326f97c7da6d0e75bac5d49afe --label select_tenure_mapped --widths 8 16 --mapped-root build/verification/tl_prefix_cost/select_tenure_clean_timing --liberty /authorized/ssg.lib
python3 verification/tl_prefix_cost/run_mapped_faults.py --proof-label select_tenure_mapped --label select_tenure_mapped_faults
python3 verification/tl_partition_select/prove_tenure.py --candidate rtl/tl/tl_control_tenure.v
python3 verification/tl_partition_select/check_evidence.py
python3 -O verification/tl_partition_select/check_evidence.py
```

完整审计还依赖本地保留的候选、失败选择器试验、历史trace、Artifact及
干净导出记录；缺失时明确失败。此前阶段审计绑定各自参考源码和运行器
快照，需在相应历史提交/工作副本复核，不能直接把旧检查点成绩贴到新
依赖上。本阶段本地提交，不追加对外推送。

收尾确认没有运行中的本工程EDA任务后，清理154份仿真编译缓存，共
1,400,898,409字节；源码、trace、反例及真实测量保留，清理清单位于
本地 `build/verification/tl_partition_select/cleanup.json`。
