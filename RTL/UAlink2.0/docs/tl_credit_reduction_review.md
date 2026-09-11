# 固定信用槽累计优化审查

`tl_credit_admission` 已把逐字段动态读写120位需求向量，改为20个固定逻辑槽各自归约八个字段贡献。三级六位加法树计算CMD/Data需求，再执行原有合法性门控和共享Data Pool合并。字段解码、计费、接口、组合延迟模型和外部握手语义不变，没有增加寄存器、时钟或时序例外。

依据仍为Common2.0 §5.8及已确认的字段tenure：每CMD一个信用，Data按完整Beat计费，BE不增加Data信用；共享池只合并逻辑槽10与15。既有独立Python模型保持不变。生成索引现在允许lint识别各字段半Flit计数最低位未使用，已显式收集并注释这些接口位；没有关闭lint警告。

## 功能与等价证据

保留提交`4376b8b`中的原始RTL及其SHA256。WIDTH8至16九种参数全部完成123位输出的二值组合等价证明，共207个实际SAT查询。每个宽度先分别无条件证明20个六位需求槽，再证明allow/wait/shortfall三个输出；后三个查询仅使用此前已经全部证明的需求向量相等关系。该关系由两份实际RTL输出驱动，不是自由输入，没有协议合法性假设、切断的内部驱动或忽略的未知单元。此为原版与重构RTL等价，不替代独立完整协议归纳或四态X传播证明。

首次整体向量SAT在WIDTH8触及180秒求解时限，停止其余同形查询后改用逐输出逻辑锥。首次逻辑锥运行已证明20个槽，但共享等价信号被未使用逻辑清理移除，导致后三项查询无法解析；将其保留为实际驱动的输出、每项查询按需暴露后，重新完成九个宽度全部23项。失败脚本、已完成查询和终止记录均保留。

独立模型期望未改写：准入逻辑两宽度各8,371向量，共16,742；Control分组两宽度各2,428，共4,856。正常与最小FIFO容量的32组实际双端SRAM配置全部通过。线上、队列和分组观察共96份trace与原版基线逐字节一致；独立审计重新验证6,912个字段、2,304个完整Single-Beat读回复、Data/BE/AuthTags、接收SRAM退休和FC守恒。

六类准入故障各两个宽度，12次实际仿真检出；另16次真实端口发送准入绕过故障均检出。故障仅更新动态槽改为静态槽后的源码锚点，原期望数据保持不变。检查器还新增缺少16个压力夹具时立即拒绝的前置检查，已实际验证缺失夹具不会得到空矩阵通过结果。

三个WIDTH8形式负例分别破坏未来Data需求、共享池合并和当前余额检查。它们分别在第10、10、20号比较项被SAT判为不等价。每个SAT反例均已导出，并用Icarus实例化原版与实际变异RTL重放，目标输出差异全部复现且无未知输出。初始汇总器错误要求额外FAIL标记、反例读取器未处理单比特WaveJSON的wave表示；原始脚本/结果保留，修复后复用相同已完成SAT结果并完成实际RTL反例重放。

## 工艺结果与限制

仍用同一SSG库映射、同五角Liberty及原0.640/6.400ns约束；IO、负载、不确定度均未放宽。模块范围是`tl_control_partition`及其解码/准入依赖，不包含完整Tx/Rx顶层。

| WIDTH | 原映射cells | 新映射cells | 原库面积µm² | 新库面积µm² | 主模式最差setup ns | 参考模式最差setup ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 103,634 | 18,743 | 56,881.692 | 11,121.768 | −1.226602 | +4.533397 |
| 16 | 103,601 | 18,893 | 57,934.422 | 10,519.866 | −1.250022 | +4.509978 |

面积分别下降80.45%和81.84%。参考周期五角两宽度10/10 STA通过；主周期10组仍未通过。两个宽度均保留4个由i_clk直接驱动的游标FF。新的最差路径由`i_source_control[119]`到Auth标签输出，下一步应评估共享字段解码、前缀需求计算及有明确握手证明的流水结构。

优化后工艺网表的整体复位收敛等价SAT仍超时，后续归纳没有执行。因此“RTL重构等价通过”和“工艺映射等价未证明”必须分别报告。当前也没有线寄生、实布时钟树、完整集成顶层STA或物理签核结论。

严格Verilator lint、两宽度通用综合、非法宽度7/17拒绝均通过。Artifact门零错误、13项风格建议，保留原生接口、静态生成索引和紧凑并行赋值；所有新增RTL代码行有同行中文注释。全局技能自检仍失败于外部缺失`agents-md-generator/scripts/manage_docs.py`，不宣称该自检通过。

干净导出副本实际执行`make test rtl-smoke`退出0，当前全部RTL与Makefile已核对和该副本一致。之后新增或完善的证据汇总、反例捕获及缺失夹具检查分别实际运行验证；不宣称导出后新增脚本属于导出时的同一快照。最终普通Python与`-O`审计通过。

## 复跑入口

```sh
python3 verification/tl_credit_reduction/run_equivalence.py --widths 8 9 10 --label proved_low
python3 verification/tl_credit_reduction/run_equivalence.py --widths 11 12 13 --label proved_middle
python3 verification/tl_credit_reduction/run_equivalence.py --widths 14 15 16 --label proved_high
python3 verification/tl_credit_admission/run_rtl.py --label static_reduction
python3 verification/tl_control_partition/run_rtl.py --label static_reduction
python3 verification/tl_credit_admission/run_checks.py --kd28-root /authorized/Overflow --label static_reduction_checks
python3 verification/tl_credit_reduction/run_formal_faults.py
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --label reduction_peers
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --bank-depth 1 --header-depth 1 --label reduction_minimum
python3 verification/tl_control_partition/check_evidence.py --peers-label reduction_peers --minimum-label reduction_minimum --peers-only --output-label reduction_evidence
python3 verification/tl_control_partition_timing/run.py --lib-root /authorized/NLDM --sta /installed/opensta/bin/sta --label static_reduction
python3 verification/tl_control_partition_timing/check_evidence.py --label static_reduction
python3 verification/tl_credit_reduction/run_skill_gate.py --skill-root /path/to/verilog-generator
python3 verification/tl_credit_reduction/check_evidence.py
python3 -O verification/tl_credit_reduction/check_evidence.py
```

输出保存在本地`build/verification/`，不复制或发布规范/PDK/外部SRAM。既有压力夹具由`verification/tl_receive_credit/run_rtl.py --traffic-pressure --admission --label pressure_verified --kd28-root /authorized/Overflow`生成；已存在时保留。完整阶段审计还需要原版功能trace、工艺基线和本阶段干净导出回归记录。新的checkout须先按基线提交的入口生成这些记录，缺失基线不能替代为通过。

完整Goal继续：主频优化、工艺映射等价与集成顶层STA之外，完整UPLI、每VC调度、单笔超容量事务、Poison及其余TL消息、完整协议证明和两套数字IP其余模块均未关闭。
