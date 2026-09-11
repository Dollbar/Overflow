# 共享前缀信用费用审查

`tl_control_partition` 已采用一次游标掩码解码和复用前缀费用，替代八个
候选分别实例化完整信用准入逻辑。WIDTH8/16 实际工艺面积分别下降
22.53%/14.24%，整体最差主周期 setup 从 −1.250022ns 改善到
−1.159129ns；主周期仍未收敛。所有原始端口、四位游标、时钟、同步复位、
组合提议和入队握手保持原有行为。

依据重新核对 Common2.0 §5.1.1 的自然字段布局及 §5.8：CMD按字段计费，
Data每信用对应64字节，BE不另占Data信用；Data继承字段的Pool/VC，
共享只合并Request/Response Data Pool。没有补写未确认编码、修改字段位，
也没有引入完整UPLI或单笔超容量事务拆分的声明。

## 实现与等价范围

先将游标之前的扇区清零，再用已有真实字段树及tenure模块各解码一次。
每字段的CMD/Data费用只向所属账户贡献；Data Pool在共享模式下先归一化。
二字段、四字段和八字段的平衡部分和复用于八个完整边界的容量比较。
原源格式诊断、最长合格边界、字段数量和Auth标签选择继续保留。

保留提交 `1bc57c143d3d87ac8f638e0990ee19024b474005` 的完整原模块。
WIDTH8至16九种参数均完成原版/新版529位输出和4位下一状态的二值CEC。
比较没有假设游标位于合法字段边界，也没有假设源数据在等待期间稳定；
新实现因此保留了游标落在字段内部时原掩码逻辑的行为。共享的三个依赖
均与该参考提交逐字节核对，未修改独立Python模型或原测试期望。

新实际映射网表在WIDTH8/16均通过完整输出/下一状态CEC，以及任意初态
一沿复位归零SAT。六份真实故障网表覆盖时钟接线、状态D输入和标签门
输出：两次时钟检查拒绝，状态转移/复位/标签共六个SAT反例保留；四次
状态/标签CEC均判不等价。状态与时钟、原始输出、所有活跃逻辑输入均
经过清单检查，没有新增自由状态输入或切断内部驱动。结论仍为二值
行为，不包含四态X传播或模拟时序签核。

## 独立功能、故障与工具检查

原有4,856个单位时序向量通过。正常和最小存储容量合计32组实际双端
SRAM/端口配置通过；96份线上、队列和分组trace与固定槽优化基线逐字节
相同。独立审计核对6,912个字段、2,304个完整Single-Beat读回复，以及
Data/BE、AuthTags、接收存储退休和信用返回。

最终八类单位故障共16次检出，另56次实际双端故障检出。首次沿用旧
“删除完整边界判断”变异时，单位测试没有检出差异，因此首次故障矩阵
按失败保留。随后WIDTH8/16形式证明该变异确与原实现等价：新算法对
整字段先计费、按最长前缀选择，使该判断在此范围内成为冗余条件。
生产RTL仍保留判断；不把这个等价变异算作检出的故障。新增的实际
截断多扇区字段头部变异，在两宽度均被检出，完整矩阵随后重新执行。

严格Verilator lint和通用综合两宽度通过，非法WIDTH7/17明确拒绝。
Artifact门零错误、17项风格建议；158行RTL代码均有同行中文语义注释。
首次artifact检查因输入目录混入三份日志而拒绝，改用只有声明RTL的
目录后通过，前后记录均保留。全局技能自检的既有外部缺失依赖问题未
在本阶段解决，不将artifact检查冒充全局自检通过。

干净导出实际执行 `make test rtl-smoke` 退出0，全部当前RTL及Makefile
与该导出逐字节一致。本阶段新增证据审计另外以普通Python及 `-O` 运行。
收尾确认本工程没有运行中的EDA任务后，删除260份仿真编译缓存，共
2,308,982,810字节；没有遗留波形。源码、测试输入、trace、失败反例和
实际时序报告继续保留在忽略目录，清理清单为本地 `cleanup.json`。

## 工艺结果

沿用同一映射脚本、实际SSG库、五个角以及0.640/6.400ns周期。IO延时、
负载、不确定度和时钟方式没有放宽，也没有新增时序例外。

| WIDTH | 原cells | 新cells | 原面积µm² | 新面积µm² | 主周期最差setup ns | 参考周期最差setup ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 18,743 | 14,830 | 11,121.768 | 8,615.502 | −1.159129 | +4.600871 |
| 16 | 18,893 | 14,933 | 10,519.866 | 9,021.726 | −1.116678 | +4.643322 |

正式 `run_timing.py` 在独立 `timing_reproduced` 标签下实际复跑，生成的两份网表与原测量逐字节一致，20组STA退出状态和setup数值完全一致。脚本因主周期违例按设计退出1；没有将完成测量误记为全部通过。

参考周期五角两宽度10/10通过，主周期0/10。最差慢冷角路径分别为
`i_source_control[118] → o_control[230]` 和
`i_source_control[121] → o_tags[10]`。这仍是理想时钟、无提取线寄生的
单个分组模块结果，没有完整集成顶层STA或物理签核结论。

## 复跑入口

```sh
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --label rtl_low --widths 8 9 10
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --label rtl_middle --widths 11 12 13
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --label rtl_high --widths 14 15 16
python3 verification/tl_control_partition/run_rtl.py --label shared_cost_clean
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --label shared_cost_peers
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --label shared_cost_minimum --bank-depth 1 --header-depth 1
python3 verification/tl_control_partition/run_checks.py --kd28-root /authorized/Overflow --label shared_cost_checks_closed --peers-label shared_cost_peers --boundary-fault truncated_header
python3 verification/tl_control_partition/check_evidence.py --peers-only --peers-label shared_cost_peers --minimum-label shared_cost_minimum --output-label shared_cost_evidence
python3 verification/tl_prefix_cost/run_timing.py --lib-root /authorized/NLDM --sta /installed/opensta/bin/sta
python3 verification/tl_prefix_cost/run_equivalence.py --candidate rtl/tl/tl_control_partition.v --label mapped_equivalence --widths 8 16 --mapped-root /actual/mapped/output --liberty /authorized/ssg.lib
python3 verification/tl_prefix_cost/run_mapped_faults.py
python3 verification/tl_prefix_cost/check_evidence.py
python3 -O verification/tl_prefix_cost/check_evidence.py
```

证据目录为本地 `build/verification/tl_prefix_cost/`，已有标签拒绝覆盖。
实际测量脚本、候选、参考源码、网表、反例和原始报告保留；工艺测量需
按原 `scripts/map_tl_control_partition.tcl` 和 `scripts/sta_tl_control_partition.tcl`
准备真实输入。完整阶段审计还需要已保留的历史trace、边界等价变异、
artifact和干净导出记录；缺失记录不会按通过处理。

后续继续主频路径优化、完整顶层映射/STA、UPLI格式转换、每VC调度、
超容量事务的规范处理及完整双IP其余要求。完整Goal没有结束。
