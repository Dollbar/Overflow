# AuthTags共享移位审查

在 `9994f2d` 的已验证基线上，将四个独立的
`before_fields + output_slot` 动态标签索引，改成所有输出槽共用一个
以完整64位标签为单位的移位网络。三层依次处理1、2、4个标签偏移，
偏移达到8个标签时清零。每个输出槽仍由原来的有效、Auth及字段数条件
门控。字段顺序、未使用槽清零、Control选择、信用计算、四位游标、
复位、原端口、组合延迟语义和入队握手均保持原行为。

该改动只缩短局部选择逻辑。实测主周期仍有约1.04ns缺口，未关闭完整
顶层STA，也没有改变完整Endpoint/Controller与Switch的交付条件。

## 真实工艺结果

同一真实TSMC28库、五角、0.640/6.400ns周期及原有IO、不确定度和负载
预算；映射脚本、350ps ABC目标及5fF负载不变，没有新增时序例外。

| WIDTH | 原cells | 新cells | 原面积µm² | 新面积µm² | 原最差setup ns | 新最差setup ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 15,416 | 15,125 | 9,224.208 | 8,864.604 | −1.057862 | −1.044205 |
| 16 | 15,236 | 14,957 | 8,906.310 | 8,989.848 | −1.054325 | −1.044889 |

两宽度setup分别改善13.657ps和9.436ps。WIDTH8面积下降约3.90%，
WIDTH16面积增加约0.94%。参考周期五角两宽度10/10通过，主周期0/10。
WIDTH8慢冷角路径从真实游标触发器到 `o_tags[85]`，WIDTH16从
`i_source_control[158]` 到 `o_control[67]`。这些是无提取线寄生、理想
时钟的标准单元模块结果，不能作为完整顶层或模拟PHY签核。

## 验证范围

- 参考完整提交 `9994f2d0491e8ae444c88146d1e6e82889afb7af`，
  WIDTH8–16九个参数的完整二值CEC通过。比较529位原输出与四位下一
  状态，不增加输入稳定、游标对齐、合法编码等协议假设。三个依赖均与
  参考提交逐字节核对，gold/gate源码、实际BLIF及完整状态/时钟/活跃
  逻辑驱动清单均保存。此结论不包含四态X传播。
- WIDTH8/16的实际映射网表CEC通过，并从任意初态证明一沿同步复位
  后四个真实游标状态位归零。六份实际故障网表覆盖时钟、状态D输入及
  标签输出；两次时钟清单拒绝、六个SAT反例及四次CEC不等价均保留。
- 原独立模型和向量期望没有修改：4,856个单位向量、32组正常/最小
  容量实际双端SRAM回归通过。96份线上、队列及分组trace与前阶段逐
  字节相同，独立trace审计通过。
- 完整16次单位故障及56次双端故障通过。标签偏移故障现在直接把
  `tags_shifted` 改接输入低四标签，真实地丢弃已消费字段偏移；没有
  继续变异已经删除的旧索引。旧布局故障入口仍可识别原索引实现。
- 两宽度严格lint和通用综合通过，Artifact门零错误、17项建议。
  干净导出 `make test rtl-smoke` 通过，全部采用RTL与Makefile和导出
  逐字节一致。阶段审计在普通Python及 `-O` 下运行。既有技能全局自检
  缺失外部依赖的问题没有在本阶段解决。

## 复跑入口

使用新标签或干净工作副本，已有输出目录拒绝覆盖。传入 `--replace`
或 `--candidate` 可先验证独立候选；以下使用采用后的主源码。

```sh
python3 verification/tl_control_partition/run_rtl.py --label auth_shared_shift
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --label auth_shift_peers
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --label auth_shift_minimum --bank-depth 1 --header-depth 1
python3 verification/tl_control_partition/run_checks.py --kd28-root /authorized/Overflow --label auth_shift_checks --peers-label auth_shift_peers --boundary-fault truncated_header
python3 verification/tl_control_partition/check_evidence.py --peers-only --peers-label auth_shift_peers --minimum-label auth_shift_minimum --output-label auth_shift_evidence
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --reference 9994f2d0491e8ae444c88146d1e6e82889afb7af --label auth_shared_shift --widths 8 16
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --reference 9994f2d0491e8ae444c88146d1e6e82889afb7af --label auth_shift_low --widths 9 10 11
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --reference 9994f2d0491e8ae444c88146d1e6e82889afb7af --label auth_shift_middle --widths 12 13 14
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --reference 9994f2d0491e8ae444c88146d1e6e82889afb7af --label auth_shift_high --widths 15
python3 verification/tl_prefix_cost/run_timing.py --label auth_shared_shift_timing --lib-root /authorized/NLDM --sta /installed/opensta/bin/sta
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --reference 9994f2d0491e8ae444c88146d1e6e82889afb7af --label auth_shift_mapped --widths 8 16 --mapped-root build/verification/tl_prefix_cost/auth_shared_shift_timing --liberty /authorized/ssg.lib
python3 verification/tl_prefix_cost/run_mapped_faults.py --proof-label auth_shift_mapped --label auth_shift_mapped_faults
python3 verification/tl_auth_selection/check_evidence.py
python3 -O verification/tl_auth_selection/check_evidence.py
```

完整阶段审计还需要本地保留的候选、历史trace、Artifact及干净导出
记录；缺失时失败。此阶段本地提交，不推送。下一步优先把长组合路径
的分级计算、输入所有权、队列反压及吞吐条件落实为可验证的结构，再
进行实际顶层集成与STA；完整UPLI、每VC、单笔超容量事务、其他TL、
数字PHY、INC、安全、管理等完整双IP剩余范围继续保持。

收尾确认本工程EDA任务均已结束后，删除148份仿真缓存，共
1,394,588,842字节。源码、trace、反例与工艺报告保留，清理清单位于
本地 `build/verification/tl_auth_selection/cleanup.json`。
