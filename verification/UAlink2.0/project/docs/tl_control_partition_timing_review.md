# Control分组模块工艺时序基线审查

本阶段对已有 `tl_control_partition` 做实际TSMC28标准单元映射和OpenSTA测量，RTL行为未修改。对象仅为字段分组模块及其解码/信用准入依赖，不包含整个Tx/Rx SRAM端口或完整Endpoint/Switch。

## 方法与范围

两种信用宽度8/16，共同使用SSG 0.81V 125C库映射，并在TT 0.9V 25C、SSG 0.81V 125C/−40C、FFG 0.99V 125C/−40C五角，分别检查0.640ns和6.400ns。约束沿用已有数字接口预算：setup/hold不确定度32/10ps，输入max/min128/20ps，输出max/min128/−20ps，输入及理想时钟转换50ps，输出负载5fF。没有时序例外、case analysis、线寄生或实布时钟树。

脚本显式接收私有Liberty路径，结果保存原始命令、源码快照和源码/库/网表SHA256。报告检查同时要求进程结果、完整的setup/hold结果、匹配的模块/周期完成标记，以及没有工具诊断、未约束路径或库限制违例。审计脚本通过只表示记录一致，不代表时序通过。

初始ABC快速映射在buffer阶段因无扇出节点失败；独立重放实际ABC脚本获得明确的 `node 2283 has no fanout` 诊断。修复流程沿用工程已有的 `cleanup -i -o`，在缓冲前移除悬空节点。还显式规范化Yosys参数展开后的顶层名。失败脚本和对应源快照保留在 `baseline/`，修复后的独立运行在 `mapped_baseline/`。

## 当前记录

20组实际STA已经结束，其中6组通过：两个宽度在6.400ns的TT/FFG三角通过。0.640ns的10组全部失败；6.400ns的四个SSG组合也失败。所有hold slack非负，最小为0.011613ns。

| WIDTH | 映射cells | 库面积µm² | FF位 | 主模式最差setup ns | 参考模式最差setup ns |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8 | 103,634 | 56,881.692 | 4 | −8.500162 | −2.740163 |
| 16 | 103,601 | 57,934.422 | 4 | −8.615259 | −2.855259 |

这是未经布局布线的实际单元映射面积和时序基线，不是完整顶层面积或最终PPA。最差角为SSG 0.81V −40C。WIDTH8首条最差路径从实际游标FF到`o_tags[128]`，报告包含264条单元引脚行（含启动FF的CP和Q，不把264直接当作组合逻辑级数）。

两个宽度的整体映射等价检查都在复位收敛SAT查询的180秒求解时限处失败，没有获得不等价反例，后续时序归纳未执行。问题规模分别约1,144万/1,145万变量和3,072万/3,077万子句。另对WIDTH8实际运行结构化`equiv_make`方法，要求全部内部比较项通过；600秒整体时限结束时仍停在`equiv_simple`，未到最终`equiv_status -assert`。因此本阶段映射等价均保持未证明，不能将测得时序等同于映射功能已证明。

结构化实验第一次因脚本在证据子目录中的相对根路径错误而无法读取RTL；明确传入工程根后才开始实际求解，两个记录均保留。最终普通Python与`-O`证据审计通过，独立核对了20份报告、精确源码/库/网表哈希、映射面积与单元数，以及JSON和实际Verilog中四个FF的原始时钟连接。35项STA报告工具测试在普通Python与`-O`下均通过。未修改RTL，未重跑或挪用旧功能回归成绩。

源码复查显示`tl_credit_admission`在八个字段循环中动态读写120位信用需求向量，`tl_control_partition`又使用八套准入实例。后续优先尝试每个固定信用槽的并行字段贡献累计及平衡归约，减少动态选择链，再评估共享解码和分组路径。此为待验证的优化方向，未修改RTL，也未宣称能达到目标频率。

## 复跑

```sh
python3 -m unittest discover -s verification/tools -p 'test_*sta_report.py'
python3 verification/tl_control_partition_timing/run.py --lib-root /authorized/NLDM --sta /installed/opensta/bin/sta --label mapped_baseline
python3 verification/tl_control_partition_timing/check_evidence.py --label mapped_baseline
python3 -O verification/tl_control_partition_timing/check_evidence.py --label mapped_baseline
```

输出在 `build/verification/tl_control_partition_timing/`，已有运行目录拒绝覆盖。失败的时序或证明使测量命令返回非零；结果中的 `complete` 仅代表运行结束，`all_gates_passed` 才表示所有门槛通过。后续必须优化重复解码、需求累计和选择路径，保持协议字段与握手语义，并重新证明等价和检查原约束；完整顶层STA与最终物理签核仍未完成。
