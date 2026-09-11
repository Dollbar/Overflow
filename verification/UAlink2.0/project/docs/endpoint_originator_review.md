# Endpoint Read Originator / Tag 表实施评审

已将 `rtl/endpoint/endpoint_read_originator.v` 与 `endpoint_tag_table.v` 两个研发壳替换为真实 Verilog-2001 模块。Originator 实例化既有 `endpoint_read_encode` 和实际 Tag 表，实现 single64B Read 的请求接纳、完整结果容量预约、待发保持、TL 捕获与实际发送区分、响应关联及应用完成。单位验证不实例化 TL/DL 或 Completer；真实链路接线由 root 的集成验证单独报告。

## 规范来源与局部选择

依据为 `config/endpoint_transaction_contract.json`、`docs/endpoint_transaction_plan.md` Task 3，正式输入为 `specs/private/common.txt` 对应 Common 2.0：Table 2-2 / §2.7.4.2 / Table 2-15 定义完整 Tag、按端口身份和响应目的关联；§2.7.8 要求 Originator 能接收响应；§2.7.5.1 Table 2-16 定义 OKAY=0、DECODE ERROR=3 及错误响应仍须提供完整数据。字段编码复用 Table 5-29 的实际 Read 编码器，完整 57 位地址不按测试内存范围截断。

容量 4、内部 ready/valid、单个待发描述符、同步低有效 reset、错误事件诊断，以及完成保持到应用接纳才复用 Tag 都是局部实现选择，不是额外线协议字段。此轮应用请求固定 length=15、attr=FF、地址低 6 位零；VC/pool/ASI/metadata=0。`i_local_id[9:0]` 在复位时期内必须稳定。

## 冻结接口与生命周期

参数为 `CAPACITY=4,NUM_PORTS=1`。内部槽索引宽度按容量派生，计数端口 8 位；合法容量配置为 1..255，但本轮功能验收只覆盖 CAPACITY=4。NUM_PORTS=1/2/4 均实测，共享四槽总容量，不将端口数乘进容量。当前实际 core 拓扑使用物理 port0，多端口这里只验证身份域。

| 接口 | 信号与职责 |
|---|---|
| 应用请求 | `i_request_valid/o_request_ready`，port[1:0]、tag[10:0]、address[56:0]、dst[9:0]、length[5:0]、attr[7:0]；握手原子获得表项及待发位置 |
| TL 源组 | `o_source_valid/o_source_control[255:0]`、`i_source_captured`；捕获前完整 Control 保持，捕获后撤 source_valid，但不标记 sent |
| 真实发送 | `i_header_taken`；对应 Read Header 实际被发送器消费后才把表项标为 sent，并释放待发位置 |
| 完整响应 | `i_response_valid/o_response_ready`，port、tag、dst、status、offset、last、num_beats、data[511:0]、data_error；valid 前上游必须已组装并保存两个 Data 半 Flit |
| 应用完成 | `o_complete_valid/i_complete_ready`，port、tag、status、data[511:0]、data_valid；只在应用接纳后释放完整 Tag/结果槽 |
| 观察/诊断 | `o_count[7:0]` 包含未发送、等待响应、已完成未退休；`o_error` 为当周期有效非法事件诊断 |

Tag 表内部接口冻结为 `i_allocate_valid/o_allocate_ready + port/tag`、`i_sent_valid + port/tag`，以及上述完整响应/完成接口。Originator 的应用握手与 table.allocate 是同一沿；table.sent 只由真实 Header 消费事件触发。表项保存完整 `(port,tag)`，不使用 Tag 低两位索引。四个默认结果槽各拥有 512 位数据存储和独立时序状态；即使应用阻塞全部完成，已经预约的合法响应仍可接纳。

`tl_tx_prepared.o_source_captured[0]` 与 `o_header_taken[0]` 必须分别反馈。`i_header_taken` 本身不含 Tag，要求 Originator 是对应 Request 发送通路的唯一实际 producer，且每个源组只有一个 Read 字段；未来加入其他 Request producer 时须先增加明确的反馈所有权路由，不能混用任意 Header 消费事件。TL 重放不应再次触发此事件。

为了保持所有权简单，待发位置直到实际 Header 消费才开放下一请求；同拍释放不直接旁路给新预约。因此吞吐存在气泡，但仍支持四个已发送请求同时 outstanding。应用退休也不将释放槽同拍旁路到新预约。响应合法性按沿前 `sent` 判断；与该 Tag 首次 Header 消费同拍到达的响应会诊断为未发送。正常实际链路具有往返延迟。

## 异常和背压行为

响应 ready 在有效配置、非复位时为 1。未知 Tag、未发送、已完成 Tag 的重复响应、错误 DST、非法 port、status 不为 0/3、offset/num_beats 非零、LAST=0、DataError=1 可以被消费并报告 `o_error`，但绝不更新结果、置完成或释放任何槽。没有 SRC 输入；debug-only 响应源 ID 不参与功能匹配。

完整且合法的 status=3 响应能完成事务，但 `o_complete_data_valid=0`、`o_complete_data=0`。status=0 才输出完整成功数据。此接口无法独立识别上游虚报“完整 Data”；收齐两个半 Flit 才置 `i_response_valid` 是接收组装器必须履行的边界。本测试确认 response_valid=0 时改变数据不会产生完成，不将这项检查称作物理半 Flit 组装验证。

完成仲裁先锁定一条已完成槽，背压期间保持 valid、身份、状态和全数据。后来的较低槽完成不能覆盖当前输出。非法或 idle 完成输出均清零。合法请求在 holding 或满容量时正常背压，不报错；有效非法字段始终诊断，重复活跃 Tag 在待发位置空闲、实际尝试预约时诊断。等待发送期间保持中的应用输入不被重复预约。

同步 reset 清空待发、全部预约和完成；reset 有效时组合输出亦被抑制。此局部取消行为不实现 Link Down、timeout、epoch、Isolation 或 Drop 恢复。合法复用 Tag 后的历史迟到响应不能仅靠 Tag 区分，本轮不提供这种保证。

## TDD 与实际测试

运行脚本 `verification/endpoint_transaction/run_originator.py` 只使用 Python 标准库及 Icarus；工具默认从 PATH 查找，可显式传 `--iverilog` 和 `--vvp`。从脚本位置确定工程根，必须指定新的 `--label`，不会覆盖证据。

```sh
python3 verification/endpoint_transaction/run_originator.py --label originator_final --faults
python3 -O /absolute/repo/verification/endpoint_transaction/run_originator.py --label originator_optimized
```

这些标签已实测；重新运行须换新标签。产物为 `build/verification/endpoint_transaction/<label>/result.json`，每个正向/故障目录保存实际 RTL 快照、完整生成 TB、Icarus 可执行文件和编译/运行日志。结果记录工具路径/版本、命令、Python 优化模式及源/产物 SHA256。

先对两原始壳运行 `--shell-baseline --label originator_red`，均成功编译，随后实际仿真在首笔预约检查失败：ready=0/error=1。此阶段只验证旧壳无法提供任何预约服务，不声称旧通用服务端口等价于新 typed 接口。完整时序 TB 在生产实现前写入；首版运行修正了 TB 完成稳定性记录总宽度少一位，以及单端口事件总数门槛错误，保留失败证据于 `originator_first` / `originator_first_checked`。之后槽索引宽度告警已修复，最终通过结果如下。

| NUM_PORTS（CAPACITY=4） | 周期 | 实际预约 | 实际 Header 发送 | 合法完整响应 | 应用退休 | 诊断周期 |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 239 | 14 | 12 | 11 | 10 | 20 |
| 2 | 275 | 16 | 14 | 13 | 12 | 20 |
| 4 | 273 | 16 | 14 | 13 | 12 | 18 |

每例六个 reset 沿：两个初始沿及四个有意取消场景；预约和退休差额来自 reset 分别取消待 capture、capture 后未发送、已完成背压、已发送待响应四种状态，不是静默丢事务。有限停顿撤销后每轮明确检查 count=0 且无剩余完成。

Scoreboard 用 8192 个完整 `(port,Tag)` 身份记录独立状态，不复制 RTL 的四槽分配或完成仲裁。它按实际握手追踪容量、pending/captured/sent、响应和退休；每周期比较 ready/error/count，检查完整 256 位请求 Control 及完整 512 位成功结果。请求 oracle 使用固定 Table 5-29 基础 hex 加独立位覆盖，不调用 RTL 编码器或模型 encode/decode。

覆盖包括：Tag=0/4/1024/2044 同低两位四笔同时已发送；第五笔容量背压；capture 前后、header_taken 前的响应拒绝；应用输入非法 profile；未知/错误/重复响应；状态 3；完成背压后低槽到达；Tag 退休后复用；不同端口相同 Tag；预约、另一 Tag 响应和旧完成退休三事件同拍；完整高地址；四种 reset 取消。计数由测试中的固定期望核对，不能靠减少实际执行事件获得 PASS。

`originator_final` 三个正向例全部通过，七项实际 RTL 副本故障全部成功编译并由 `ORIGINATOR_SCOREBOARD` 检出：capture 冒充 sent、响应 Tag 低位别名、允许重复响应、背压期间重新选择完成、错误数据误标可提交、忽略错误 DST、复位不清 pending。最后一项在初始复位释放后即因遗留未知 pending 被检出；四种非初始 reset 行为另由正向场景验证。

`originator_optimized` 从 `/tmp` 运行 Python `-O`，三配置同样通过，脚本没有用 Python assert 代替检查。`originator_static_final` 中两模块分别通过 `iverilog -g2001 -Wall` 和 Verilator 5.050 `--lint-only -Wall`。Icarus 12.0 的 `@*` 覆盖完整数组敏感性提示保留在日志，不是缺失敏感项。

技能 `validate_verilog_artifacts` 按单模块及显式 i_clk/i_rstn 契约检查：两模块均 0 errors；Originator 有 9 个模板布局警告，Tag 表 11 个（同九项模板布局及按字段名误识别出的 FSM 命名建议）。实际模块以槽状态标志管理生命周期，不声称这些建议已消除。`validate_verilog_skill.py --no-require-remote` 仍因环境缺少 `agents-md-generator/scripts/manage_docs.py` 中止，未宣称全局技能门通过。

## 冻结交付与未完成范围

最终 `originator_final` 所有源文件及产物校验值已重新核对一致：

- `endpoint_read_originator.v` SHA256：`5e421dcc320c3a79c3777fddaa5e442b1bc3391628d89eec748b1b1ccc366461`
- `endpoint_tag_table.v` SHA256：`43938584873ab2aeb577eb4cc619498f57b9ed5d275023c871550207e6438663`

本任务未改库存、聚合层、其他 RTL 或发布脚本，也未提交。单位 tests 的 capture/header_taken 和完整 response 是明确的驱动边界；实际 TL/DL、接收组装、Completer/内存因果链和 Switch 接线由集成任务检验。原生 UPLI、任意 Read 长度/模式、其它状态、Write/Atomic/INC、安全、CDC/RAS 和全协议恢复仍未覆盖；A19 CRC 位序等开放问题保持开放。
