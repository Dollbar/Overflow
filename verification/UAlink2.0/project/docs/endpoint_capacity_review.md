# 实际 Endpoint 事务容量与复位增量

本轮修复顶层把两种事务容量硬编码为四槽的问题，并修复 Completer 非二次幂容量的综合未驱动读取。完整双 IP 目标保持不变，模块库存仍为 66 个部分实现与 136 个未实现壳。

顶层新增 `ORIGINATOR_CAPACITY` 和 `COMPLETER_CAPACITY`，分别贯通真实 Tag 预约表和内存执行环。默认均为 4，原有位置参数顺序及端口声明保持不变。集成内存 slot 仍为两位，支持执行槽 1～4；Tag 表保留原有 1～255 的参数范围。非法组合采用安全单槽展开并持续复位事务核，公开请求/内存/完成接口不能接纳事务，诊断有效。正常满槽只背压。

## 真实失败与修复

`capacity_red` 先证明旧顶层没有容量参数（编译失败）；`capacity_red_behavior` 去掉不受支持的绑定，但仍要求单槽行为，旧四槽设计在实际第二次预约后触发 `CAUSAL_CAPACITY_BOUND`（编译0、运行1）。两者分别保存，不能把前者当作功能红测。

Completer 容量3的旧实现通过单位功能仿真，但在 Yosys memory mapping 后存在628项未驱动问题。有界组合选择现在仅读取真实槽，不再推断额外补齐行；默认四槽综合结构从313变为342个通用 cell，此数字不是工艺面积。完整单位矩阵及故障见[执行器容量审查](endpoint_completer_capacity_review.md)。

## 最终验证范围

`capacity_final/summary.json` 的29例全部通过，实际源码与产物SHA已复核：

- Originator 1/2/3/4/8 × Completer 1/2/3/4，共20组，每组双端8请求、16完成，合计320笔。内存延迟400周期，交错选择 bank 1/3 与丢包/CRC重放。
- 独立应用握手账本逐周期核对预约计数；检查两个所有者容量上界、实际内存slot范围、全部512位固定数据及完成因果链。发起端达到测试目标预约数后才解除完成背压，饱和要求为 `min(originator,8)`；执行器观察目标为 `min(originator,completer,8)`。Originator小于Completer的组合不声称填满全部执行槽。
- 默认配置的正常、恢复与最小缓存三例通过，另48笔事务。故意忽略实际Originator容量的接线故障被检出。
- 0/256/-1个Originator槽和0/5个Completer槽共五组非法组合，主动持续驱动合法应用请求及内存结果valid，确认请求/结果ready及完成/内存valid均关闭，计数为零且诊断有效。

较早 `capacity_matrix_o8_c1` 的16笔事务完成，但固定时间解除完成背压导致未达到八槽覆盖，报告保留为失败。之后改为根据实际请求预约数解除背压，保留饱和断言；并行审查发现非法配置激励依赖链路启动，也已改为主动有效激励。最终29例使用这些修正后的检查，不覆盖或重标旧记录。

两顶层在 Originator8/Completer3 配置下 `hierarchy/proc/opt/check` 通过（`capacity_elaboration`），未执行新顶层工艺 STA。结构清单检查通过。严格技能模板静态检查未闭合：叶模块模板不完全适用于层级包装，且现有逐行注释/编码风格仍有欠账；报告与独立复核见[静态审查](endpoint_capacity_static_review.md)，不以功能仿真替代该门限。

## 复位与下一步

真实网络在已捕获未发送、内存待结果、完成被背压三个窗口统一同步复位；bank 3/1各运行三窗口。六例共24次预约、12次取消、12次新轮次完成；两个漏复位接线故障全部检出。详见[复位审查](endpoint_reset_review.md)。此结论要求两个Endpoint、Switch、传输寄存器和内存VIP同时取消旧轮次，未建立独立端点LinkDown或带世代号的内存恢复。

```sh
make ip-transaction-capacity KD28_ROOT=/path/to/authorized/Overflow IP_RUN_LABEL=fresh_capacity
python3 verification/endpoint_transaction/run_reset.py --kd28-root /path/to/authorized/Overflow --label fresh_reset
python3 verification/ip_tops/run_elaboration.py --kd28-root /path/to/authorized/Overflow --label fresh_elaboration --transactions --originator-capacity 8 --completer-capacity 3
```

输出保存在 `build/verification/endpoint_transaction/` 和 `build/verification/ip_tops/`；复跑须使用新标签。概要哈希见 `endpoint_capacity_evidence.json`。下一步按已核对的[Write/WriteFull契约](endpoint_write_contract_review.md)实现统一Tag、Data/BE归属队列及无Data写完成；完整长度、压缩、PHY、INC、安全、管理、CDC/RDC与工艺STA仍未完成。八请求测试不证明255槽满载。
