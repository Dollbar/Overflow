# 普通 Write 混合事务集成审查

状态：真实写后读、完整普通写长度、WriteFull合法几何及最小bank/重放回归已通过；完整 IP Goal 保持进行。新增 `WRITE_ENABLE=0` 参数默认保留既有 Read 模式；置1时使用统一 Request Formatter/Tag 表、完整 Write 接收组装和独立 Write 后端结果接口。应用及后端字段定义见 [实施契约](endpoint_write_execution.md)。

## 接线及次序

应用的 Read/Write 共用一个 Tag 容量。类别0 prepared Header和Data/BE来自同一个有序formatter；类别1为Read/Write完成Header仲裁，Read Data单独保存原次序。响应Header在反压期间锁定选择，捕获后轮换优先级。

接收请求按原顺序派发到Read或Write Completer。前一笔命令实际后端result返回前保持共享dispatch占用；内存命令ready不释放该占用。此实现有意保守串行化后端操作，尚未做吞吐优化。result必须匹配保存的种类、slot和合法状态；应用完成反压不参与后端派发条件。

顶层追加独立完整Write memory命令及结果接口，保持原Read memory接口、原参数位置及默认模式。同步reset取消局部槽所有权；后端仍须遵守统一取消旧结果的契约，不代表独立LinkDown/epoch恢复。

## 当前检查

独立审查发现首批ESE测试平台的posedge计数器更新会反馈同沿组合激励。该组通过记录保留为初步运行证据；已将反馈计数改为NBA更新并固定副本源身份；`write_ese_final_*`六组全部重跑达到预期，作为最终发布依据。生产RTL未因此修改。

- `write_core_red`：修改前真实core不具备WRITE_ENABLE参数，新接口展开失败，旧core源码与编译日志保留。
- `write_core_elaboration`：混合core在Verilog-2001下实际编译通过。
- `write_top_elaboration`：混合Endpoint（originator8/completer3）和Switch的Yosys hierarchy/proc/opt/check通过；显式SRAM黑盒边界保持原定义。不是工艺STA或PPA签核。
- `write_core_legacy_read`：原默认模式真实两端Read及恢复回归通过。`write_legacy_reset`三种在途统一复位窗口全部通过。
- `write_legacy_capacity`正常/默认/非法配置28项通过；故障注入器因两个generate分支出现相同容量锚点而拒绝运行。已修复注入器明确检查两个锚点，`write_legacy_capacity_fault_fixed`、`write_legacy_data_fault`、`write_legacy_tag_fault`三份实际RTL故障均编译成功、运行失败并被检出；没有把注入器自身异常算成故障检测通过。
- `write_core_static_complete`仅选择完整core依赖的严格Verilator检查仍因16条警告返回1，无抑制flag；既有Read completer位宽及Write未用位/空输出等需后续清理，不宣称完整静态门限闭合。前两个静态尝试分别包含全树未用模块噪声和遗漏response encoder依赖，均保留原失败日志。
- `write_legacy_capacity_final`：修复注入器后完整29项重跑全部通过（20合法容量组合、3默认、1实际故障及5非法参数）；不覆盖混合Write容量矩阵。
- `write_modules_structure`：202条RTL清单，69个部分实现、133个未实现壳，所有结构检查通过。移除三个已替换壳的通用服务实例；保留其稳定功能槽编号，不把部分实现记为完整服务。

`write_core_review_c1/c2/c3/c4`各通过双真实core、38笔请求/完成，含18次Write及20次Read后端结果，独立8192字节最终内存核对，三项实际core接线故障被检出。桥是明确的prepared-record行为模型，不能替代TL/DL检查，详见[核心审查](endpoint_write_core_review.md)。`write_ese_first`使用实际双Endpoint、Switch、TL prepared与DL路径，通过20笔应用请求/完成，包含每端各三次实际Write执行（Full256、跨Beat稀疏、零BE），在792周期排空。独立字节fixture与实际后端执行/读回比较，扩展`write_ese_lengths`通过566笔请求/完成，真实执行154次Write，覆盖每端全部64种普通长度及10种Full合法几何；`write_ese_minimum_recovery`在bank1下20笔完成、8次重放，Write仍只执行6次。完整记录见[ESE审查](endpoint_write_endpoint_switch_review.md)。

接收器`write_receiver_release`及优化Python运行各33项通过（主路径2097请求/8851记录/26响应，另含非法、回压、因果场景和四项真实RTL故障）。默认Read接收兼容41项通过，详见[接收器审查](endpoint_write_receiver_review.md)。

最终四组正常ESE运行（basic、lengths、minimum_recovery、lengths_minimum_recovery）共1172笔请求与完成、320次Write执行、16次重放；两项后端BFM接线/提前结果故障被检查器检出。提前结果项证明检查器能发现虚假后端完成，不代表RTL可识别接口合法但语义虚假的返回。源码身份、记录哈希和范围见[增量证据](endpoint_write_evidence.json)及[独立测试审查](endpoint_write_test_audit.md)。

## 复跑

```sh
python3 verification/ip_tops/run_elaboration.py --kd28-root /path/to/authorized/Overflow --label fresh_write_elaboration --writes --originator-capacity 8 --completer-capacity 3
python3 verification/endpoint_transaction/run_transactions.py --kd28-root /path/to/authorized/Overflow --label fresh_legacy_read --inject
python3 scripts/check_ip_structure.py --label fresh_write_structure
```

输出位于`build/verification/ip_tops/`、`build/verification/endpoint_transaction/`和`build/verification/ip_structure/`对应新label目录，保留命令、源哈希和日志。下一步按独立字节oracle验证写后读、执行次数、区域BE、反压和真实信用约束；`make test`整个现有模型/工具入口通过（工具组199项，2项按既有条件跳过）；新Write测试使用本文及各模块独立入口。完整Read、原子、UPLI、压缩/poison、安全、管理、PHY及工艺签核仍未完成。
