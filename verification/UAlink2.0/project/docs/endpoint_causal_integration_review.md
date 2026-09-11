# 真实 Read 总装的独立局部审查

本轮只读审查 `endpoint_transaction_core`、`ualink_endpoint_top` 的 TRANSACTION_MODE=1、实际事务 testbench/runner 及已保留日志；未修改 RTL 或验证器，也未重新运行 root 的矩阵。以下结论限定于非认证、单物理端口、64 字节对齐普通 Read；不扩展为完整 Endpoint/Switch、标准 DL framing、PHY、PPA 或形式验证声明。

## 实际连接核对

| 边界 | 查见的实际连接与局部结论 |
|---|---|
| 请求来源 | `endpoint_transaction_core.u_originator` 实例化真实 Read 编码器与 Tag 表；TRANSACTION_MODE=1 在展开时选择 core 输出，TB 的旧 prepared Request/Response/Data 输入全置零。未发现预生成 Response fixture 旁路。 |
| capture 与发送 | core 分别接 `o_source_captured[0]` 和实际 `header_taken[0]`。top 的 Header 消费由 `tl_tx_prepared`、`tl_credit_admitted_port` 的 `tx_taken` 驱动；信用端口发送输入为 DL 的首次 `dl_accept`。重放不再次推进 TL 源，top 仍有 `dl_accept==tx_taken` 及消费原子性检查。 |
| 响应 Data lane | core 的 `o_data_valid={completer_data_valid,2'd0}`；`o_data0[511:256]` 为响应低 256 位，`o_data1[511:256]` 为响应高 256 位；Request 类低 lane 全零。`tl_tx_buffered` lane1 恰从这两段取第一个/第二个 Data，并将接受数量 `[3:2]` 反馈 Completer。部分只接受一个时，Completer 把原高半前移到下一次 data0，未见交换或漏移。 |
| 接收 SRAM 退休 | top 的 `selected_read_ready` 来自实际 receiver；receiver 仅 EMPTY 时接纳，把 `{releases[79:0],classes[5:0],msg[1:0],flit[511:0]}` 整 600 位同拍保存。随后从 holding record 消费字段，未从实时 SRAM 输出取后续数据。释放继续由原 `tl_receive_credit` 承担，receiver 不重复归还信用；top 检查 `retired==release_taken`。 |
| 完整响应组装 | `endpoint_response_assembler` 在第二个 Data 半 Flit 实际接纳后才置 response_valid，数据为 `{第二半,第一半}`；响应 Header 在两半 Data 期间保持。core 将该完整响应交给 Originator，不直接把 Header 当完成。 |
| 内存因果 | Completer 先保存真实收到的请求，只有 `o_mem_valid&&i_mem_ready` 才标 issued；只有已 issued、尚未 complete 的槽接受一次合法内存结果。响应资格是 `busy&&complete`，Header/两半 Data 均来源于该槽保存的真实结果。未见未收到内存结果就从请求生成响应的路径。 |
| Tag 与错误 | Originator 使用真实四槽完整 `(port,Tag)` 表；结果空间在请求接纳时预约。响应不使用 debug-only SRC 作为匹配键；status=3 同样经完整组装，但应用 data_valid=0、data=0。已完成槽在应用退休前仍占容量。 |

`i_header_taken` 无 Tag，因此只适用于当前唯一 Read Request producer、每源组一个普通 Read 字段的所有权约定。后续混入其它 Request producer 时必须扩展反馈路由；不能把所有 Header 消费脉冲直接交给此单待发描述符。

Switch 在本测试中路由 545 位本地记录：544 位 DL 头/520 位 TL 记录加显式 CRC 状态，目的 ID 使用 TB 的侧带配置。它证明当前两端经实际 Switch 端口存储/仲裁通路传送事务记录，不证明 Switch 已从标准线格式解析全部 TL 路由、vPod 或多站点语义。

## 已核对的最终保留证据

已逐项只读复核以下六个目录 `result.json` 所列全部产物 SHA256，均一致；本轮未重新运行 root 的矩阵。每例保存 209 份 Verilog 源快照，三个正向例的快照全部与所记录原始源哈希一致；三个故障例仅各有一个预期修改文件，逐行核对恰为清零响应高半、强制接收 ready=1、截断响应 Tag bit10，没有其他源差异。

| 最终 label | 配置与实际结果 |
|---|---|
| `causal_final` | BANK_DEPTH=3、无注入；compile=0/run=0，16 请求/16 完成，每端最大 4 outstanding，562 周期，重放 0/0。 |
| `causal_final_recovery` | BANK_DEPTH=3、丢失及 CRC-status 注入；compile=0/run=0，16 请求/16 完成，624 周期，重放 4/4。 |
| `causal_final_minimum` | BANK_DEPTH=1、同类恢复注入；compile=0/run=0，16 请求/16 完成，624 周期，重放 4/4。 |
| `causal_final_data_fault` | compile=0/run=1、passed=true；响应高半清零被 `CAUSAL_COMPLETION_DATA` 在 time=1015000 检出。 |
| `causal_final_retirement_fault` | compile=0/run=1、passed=true；接收 ready 强制为 1 被 `CAUSAL_COMPLETION_DATA` 在 time=1295000 检出。 |
| `causal_final_tag_fault` | compile=0/run=1、passed=true；响应 Tag bit10 截断被 `CAUSAL_DUT_ERROR` 在 cycle=175 检出。 |

三个正向场景合计 48 请求/48 完成；每个恢复场景各为两个方向 4+4 次重放。故障例的 passed=true 仅表示预期故障被检查器检出，不表示故障 RTL 功能通过。历史 `causal_fault_retirement` 的旧 JSON 仍为 passed=false（当时 runner 未接受已经出现的 DATA fatal 分类）；新 `causal_final_retirement_fault` 才是最终预期故障通过证据，不改写历史结果。

六例的 `tb.sv` 快照都与当前 `transactions_tb.sv` 逐字节一致，也与各自 sources manifest 中 TB 哈希一致：`b573a5bb621dfe27b40189bbfe698e46bceedcd4d4611ffcfbd2595f9e43f811`。正向例中的 core/top/Originator/Tag 表/Completer/receiver 快照同时与审查时生产源一致；故障例只有上述显式副本修改。

TB 从应用握手数驱动八个稀疏 Tag/地址；在真实 Header 消费时独立检查 Tag→地址；内存 BFM 只在真实内存请求握手后保存 slot/address，再经可变延迟返回。每个地址的真实内存请求/结果最多一次，应用完成要求该 Tag 已实际发送、对侧内存结果已返回且此前未完成。第八个高地址 Read 返回 status=3，不在生产编码/执行接口截成 4 KiB 地址。该 fixture 已形成真实请求→内存服务→响应→Tag 完成的连接，区别于此前两侧独立预生成 Request/Response 流。

当前矩阵的完整成功数据比较覆盖 512 位；故障结果说明实际接线错误能被检查器检出。它没有像此前 `endpoint_link` 独立检查器那样逐条比较全部 600 位 SRAM 退休记录，不能把旧检查器的逐字覆盖自动移植到本矩阵。

## 两项检查器问题已关闭

1. 最终 TB 在任何 `complete_valid` 时即检查已实际发送、未重复完成、对侧 `returns==1`，并要求 `result_at < cycle`；因此首次可见完成也必须有更早周期的内存结果，不能等到 cycle>350 的应用 ready 才追认因果。每次完整内存结果握手保存 result_at，严格小于检查还排除了同拍 BFM 更新顺序掩盖早完成。数据也在所有 complete_valid 周期比较；真正握手时才更新 seen 和完成计数。原“只在退休时检查”的缺口已关闭。
2. 最终完成数据期望使用 `expected_memory[2][8]` 中 16 个冻结 512 位 hex 常量，比较路径不再调用 BFM 的 `memory_word`。BFM 生成公式包含 `address>>6`；独立读取常量确认 14 个正常数据字全部互不相同、每端地址 0 与 256 不同，两个高地址错误期望均为零。原运行时同函数生成/期望及 256 字节地址别名缺口已关闭。这是明确的局部测试内存数据 fixture，不扩展为独立产品内存一致性模型或外部协议认证。

以上关闭依据是实际代码变化及与其匹配的六例新快照/结果，不是重复旧场景。当前无未关闭的这两项 checker 问题；后续仍应按各功能范围增加专门反例，不能把三类接线故障视为穷尽所有提前完成或内存服务错误。

## reset、Auth 与未覆盖范围

TRANSACTION_MODE=1 把 `rstn&&!i_auth&&(i_port==0)` 交给 core，Auth 打开或端口不为零时阻断事务并报告 transaction_error；TL/DL 使用顶层 rstn。当前 TB 固定 Auth=0、port0，只执行初始全层 reset，故未实际验证 Auth 拒绝、运行中切换 Auth/port、带在途事务的顶层 reset 或初始化恢复。Auth/port/local_id 应在复位时期稳定配置；不支持运行时切换后让旧 TL 队列与新事务时期混用。Originator/Completer 的局部复位单测不等于整个链路的恢复验收。

此次恢复是显式 CRC 状态错误与丢本地记录后的现有 DL 重放；A19 CRC 线上位序、标准 640B DL framing、完整 watchdog/Link Down/epoch 恢复保持开放。内存由有界测试 BFM 提供，不证明 SoC 一致性或实际内存控制器；四 Tag 事务子集亦不代表完整 UPLI、任意 Read 模式、Write/Atomic/INC、安全或管理功能均已实现。
