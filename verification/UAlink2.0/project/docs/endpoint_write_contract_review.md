# Endpoint Write / WriteFull 实现契约审查

本轮仅核对规范和现有接线，没有修改 RTL、库存或回归。审核基线为 `38891f0f253b0e031904d268f5b1a09ec6df86e3`，同时阅读工作区正在贯通容量参数的 `endpoint_transaction_core`。下述是实施要求，不是 Write 已通过的功能声明。目标是普通单播 Write / WriteFull 的全部合法长度、地址位置、稀疏 BE、多 Beat、完成与错误处理；单 64B 只能作为早期贯通向量。

依据为已授权的 UALink Common Specification Rev 2.0、UALink 200G DL/PL 2.0 和 Manageability v1.0 本地正文。页码均为正文印刷页码，不是 PDF 文件页序。本文使用自己的实现摘要，不附私有正文、图表截图或完整规范。Common 文本 SHA256 为 `15cd742c536e1e701a958db8a04f54666b072b8d95a72a834b0aa7d2c58e3383`。

## 1. 命令、范围及完整字段

普通 **Write = 0x28，WriteFull = 0x29**。`0x26/0x27` 分别是 WriteMulticast / WriteFullMulticast；不能把 `0x26` 当普通 Write。BlockWriteFull、Atomic、UPLI Write Message 和供应商命令分别有自己的语义，不因共享 Data 路径就等同于普通 Write。[Common §2.7.4.7，Table 2-12，pp.57–59]

设完整地址为 `A`，字节长度 `S = 4*(LEN+1)`：

| 条件 | 普通 Write | WriteFull |
|---|---|---|
| 长度 | LEN 0..63，即 4..256 bytes | LEN 15/31/47/63，即 64/128/192/256 bytes |
| 地址 | `A[1:0]=0` | `A[5:0]=0` |
| 区域边界 | `(A mod 256)+S <= 256` | 同左 |
| Beat 数量 | `N = ceil(((A mod 64)+S)/64)`，1..4 | `N=S/64` |
| 请求 NUMBEATS | `N-1`，必须与地址、长度一致 | `N-1` |
| BE | 请求范围内任意稀疏模式，包括全零；范围外为零 | 每个传输 Beat 的 64 位 BE 全一 |
| TL 内容 | 2N 个 Data 半 Flit，随后 1 个 BE 半 Flit | 2N 个 Data 半 Flit，无 BE 半 Flit |

长度表达式必须扩宽计算，例如 256-byte 长度需至少 9 位，地址末端检查不能让截断掩盖跨界。`ceil(S/64)` 不能代替普通 Write 的 Beat 公式，例如地址 60、长度 8 必须是两个 Beat。全零 BE 的 Write 仍传输全部声明 Beat、消耗相应信用并返回完成，只是不修改内存。[Common §2.7.4，Table 2-2，pp.49–52；§2.7.4.7 p.59；§2.8 pp.77–79]

未压缩请求使用 128 位自然字段，置于 Control 半 Flit 的 sector 0 或 4；其余空 sector 填 NOP。编码服务应保留以下完整信息，不能截短 Tag、地址或物理 ID：[Common §5.1.1 Table 5-2 p.106；§5.9.1 Table 5-29 p.137]

| 请求字段 | 字段内位段 | 本次语义 |
|---|---|---|
| FTYPE / CMD | 127:124 / 123:118 | 1 / 0x28 或 0x29 |
| VC / ASI | 117:116 / 115:114 | 保留 2 位值；能力限制须显式检查 |
| TAG / POOL | 113:103 / 102 | Tag 11 位；POOL 是本跳 TL 信用选择 |
| ATTR / LEN / META | 101:94 / 93:88 / 87:80 | 8 / 6 / 8 位 |
| ADDR | 79:25 | 完整地址的 56:2；还原低两位零 |
| SRC / DST | 24:15 / 14:5 | 各 10 位，普通单播 DST 是目的 Accelerator ID |
| CLOAD / CWAY / NUMBEATS | 4 / 3:2 / 1:0 | 缓存更新、way、OrigData Beat 数减一 |

Write 的 ATTR 是实现相关附加元数据，**不是 Read 的首尾双字 BE**；不能强制沿用 `0xff`。ASI 和普通请求 META 也是 Accelerator 定义的语义，应传到后端或按公开能力拒绝，不能静默丢弃。未压缩 Write 的非零 ATTR/META 不等于规范非法。初期 TX 可固定 CLOAD=0；此时 RX 忽略 CWAY。TL POOL 和 UPLI POOL 属于不同信用域，不要求逐位复制。[Common §2.7.4.1 p.52、§2.7.4.6 p.56、§2.7.4.8 p.61；§5.6.1 p.128；§5.9.1 p.137]

## 2. Data、BE 与接收归属

内部 typed 接口建议显式区分请求描述符与逐 Beat 数据，完整保存 `port/tag/src/dst/cmd/address/length/num_beats/attr/vc/pool/asi/metadata`；数据携带 `offset[1:0]、last、data[511:0]、byte_enable[63:0]、data_error`。也可采用一次提交 2048-bit 数据和 256-bit BE 的有限缓冲实现，但外部契约仍须覆盖四个 Beat，不能只保留第一个 Beat。

数据是自然 byte lane 排列。第 j 个 Beat 的内存基址为 `B_j=(A & ~63)+64*j`，该 Beat 的 byte lane k 对应地址 `B_j+k`。Offset j 是本事务从零开始的相对序号，**不是** `A[7:6]+j`。普通 Write 的 TL BE 字段是按整个 256-byte 区域定位的位图：

`BE_TL[64*(A[7:6]+j)+k] = OrigDataByteEn_j[k]`。

其余位为零。例：地址 128、长度 64 的 BE 放在 BE_TL[191:128]，不是 [63:0]；地址 60、长度 8 的有效位位于 BE_TL[67:60]，其两个 Data Beat 分别使用 lane 60..63 和 lane 0..3。BE 字段每次固定 256 位；不能随 N 缩短，也不能把 64-bit BE 插在每个 Beat 后。WriteFull RX 按传输 Beat 重建全一 BE，而整个 256-byte 区域中没有传输的 Beat 不成为额外写入。[Common §2.8 pp.77–79；§5.1.1 p.107]

线上 Data 没有独立 Tag。Control 字段按起始 sector 递增产生数据归属描述符，每个描述符依次消费自己的 2N 个 Data 半字和可选 BE。一个 Control 内允许 Read 请求、Write 请求、Read Response、Write Response 和 FC/NOP 混排；无 Data 的 Read 请求及 Write Response 不进入 Data 所有者队列。Read Response 数据与 Write 请求数据必须由同一顺序规则仲裁归属，不能各自无条件消费遇到的 Data。[Common §5.1.1 pp.106–108]

接收器沿用实际退休记录的 classes：0=Control、1=Data、2=BE、3=mandatory NOP、4=普通 Message、5=poison Data、6=AuthTags、7=错误；低三位是下半，高三位是上半，msg[0]/msg[1] 对应下/上半。它们是本仓库派生元数据，不是额外线上字段。600-bit 记录整体接纳一次，信用释放仍由原 storage/credit 路径处理，不在 typed assembler 再归还。

不能机械地把“解析了本字下半 Control”理解成“本字上半 Data 属于新 Control”。最后一个旧 Data/BE 半字被换到上半时，下半已是下一组 Control；新描述符只能排在旧尾之后。保留整字预检和稳定 holding，在预检成功后才提交任何字段。普通 Message 0/1 延迟 Data 消费；poison 0x20 则占用一个预期 Data 半字。队列容量和先后次序必须保证能处理旧尾加新 Control：若扫描新字段时 FIFO 已满，不能永远卡住而无法消费同字上半旧尾。当前八槽是原未压缩 Read 子集的实现选择，扩展压缩与混排后需重新验证容量，不直接继承结论。[Common §5.1.1–5.1.2 pp.108–109；§5.7 pp.129–130]

Write 组装建议使用 `HEADER -> DATA(2N halves) -> BE(仅Write) -> READY_FOR_MEMORY -> WAIT_MEMORY_RESULT -> RESPONSE_PENDING`。WriteFull 跳过 BE 状态。完整普通 Write 在 BE 到达前不得产生真实内存副作用；采用整事务缓冲可先验证范围外 BE、NUMBEATS、数据数量和 poison，再交付后端。无归属 Data、BE 提前/缺失、错误 port 或不支持的未知 tenure 必须诊断并停止误归属；不能跳过字段继续猜后续边界。缺失内容只能在观察到矛盾或已定义 watchdog 到期时确认，不能把合法背压空拍当错误；静默永久等待也不能代替诊断。

## 3. Response、后端完成和 Tag 生命周期

普通 Write / WriteFull 返回一个 **没有 Data** 的 Write Response，不能送入“等齐 512 位数据才 valid”的 ReadResponse assembler。未压缩响应自然起点为 sector 0/2/4/6，字段为：[Common §2.7.6 pp.66–68；§5.9.2 Table 5-30 pp.138–139]

| 字段 | 位段 / TX 值 |
|---|---|
| FTYPE / VC / TAG / POOL | 63:60=2 / 59:58 / 57:47 / 46 |
| LEN / OFFSET | 45:44=0 / 43:42=0 |
| STATUS / RD_WR / LAST | 41:38 / 37=0 / 36=0 |
| SRC / DST | 35:26 / 25:16 |
| RSPTYPE / SPARE | 15:14=0（普通单播）/ 13:0=0 |

LEN 对 Write 必须为零；OFFSET/LAST 是无效字段且规范建议发零，RX 不应把建议升级为所有值非零即格式非法。SPARE 未分配，TX 清零，RX 不凭它匹配事务。响应 DST 必须是原请求 SRC，Tag 原样返回，VC 与请求一致；SRC 可填原请求 DST 以便调试，但规范允许其不准确或被压缩省略，不能用于功能匹配。RSPTYPE=2 是 multicast，3 是 BlockWriteFull，1 保留，普通单播不能混用。

后端需两个独立事件：`mem_write_valid && mem_write_ready` 接纳请求，以及带稳定 slot/token 的 `mem_write_result_valid && mem_write_result_ready` 确认执行结果。接纳不代表执行完成。OKAY 只能在实际后端完成后生成；对于分解执行，必须确认所有组成操作完成。UPLI 上 Write Response 最早是最后一个 OrigData Beat 到达后的下一拍，不能在同拍响应。内部 ready/valid 允许停顿，但若未来声称提供原生 UPLI，还必须在发请求前储备全部 Data 与信用，做到请求与第一 Beat 同拍、后续 Beat 连续、offset 递增、last 只标最后 Beat；不能把内部可停顿接口直接冒充 UPLI。[Common §2.7.8 pp.71–72；§2.7.10 pp.73–74]

普通预定义命令合法远端状态应保留 OKAY=0、TARGET ABORT=2、DECODE ERROR=3、PROTECTION VIOLATION=6、CMPTO=8。1/4/5/7/9..13 保留；14 是 Switch 汇总 Block Write 的混合状态；15 ISOLATE 是本地 TL 向 Accelerator 的特殊反馈，不能作为普通远端 Write completion 接收。不要复用当前 Read 编码器仅 0/3 的限制当全功能终点。[Common §2.7.6.1 Table 2-19 p.68]

每个源端口的 11-bit Tag 在所有命令类型之间共用唯一域。Read 和 Write 各开一个互不检查的 Tag 表会产生真实冲突；可共用预约表，或跨表做统一占用检查和响应 kind 验证。建议状态为 `RESERVED -> QUEUED -> ISSUED -> RESPONSE_HELD -> FREE`，记录完整 port/tag、请求种类和完成槽。只有实际请求发出事件才进入 ISSUED；prepared capture 或 Data 入队不等于已发出。正确 Write Response 被接纳并保存后满足线上 Tag 可复用的最低条件；为了避免尚未被应用消费的完成与新请求混淆，可保守地到应用完成握手后释放。提前到达、未知 Tag、重复响应、Read/Write kind 不符不得释放别人的所有权。[Common Table 2-2 p.49；§2.7.4.2 p.52]

同一源目的对、同一 VC、同一 256-byte 区域的请求顺序须保持；严格排序模式还有更强要求。接收后的内存执行策略是 Accelerator 实现责任，需要明确定义与已有 Read 的交错和重叠地址顺序。最直接实现是共享有序 dispatch，先保持更强的顺序；之后才考虑带依赖检查的并行执行。非严格模式允许 Write Responses 重排，不能靠 FIFO Tag 假设完成顺序。每个已发请求必须已有独立完成容量，防止其响应要等对端另一笔事务才能被接纳的死锁。[Common §2.7.8–2.7.10 pp.71–74]

## 4. 压缩、poison 与恢复边界

TX 可以始终选择未压缩请求/响应；这不妨碍完整普通 Write / WriteFull 的地址和长度覆盖。压缩请求 FTYPE=3，CMD=4 表示 Write、CMD=6 表示 WriteFull。它要求 64-byte 对齐、64/128/192/256-byte 长度、不跨 256-byte 边界、Write ATTR=0、META[7:3]=0，并且在实际发出前所命中的 Tx 地址缓存项仍有效。压缩 Write 仍附 256-bit BE；压缩不会自动把它变成 WriteFull。[Common §5.9.3 Tables 5-31–5-33 pp.140–141]

RX 解压须恢复 ADDR[56:20]、LEN、ATTR=0、META 高五位零和 NUMBEATS，而不是把未传位清零当完整地址。Endpoint Rx 缓存按 SRC 索引，Switch Rx 按 DST 索引，CWAY 指定 way；同 Control 内前一个 CLOAD 更新必须对后续压缩请求可见。未实现缓存同步前显式拒绝压缩和 CLOAD=1，只能声明未压缩接收能力；不能宣称具备完整压缩互操作。[Common §5.5–5.6 pp.126–128]

普通成功 Write 可用 FTYPE=5 的 32-bit 压缩响应：VC[27:26]、TAG[25:15]、POOL[14]、DST[13:4]、LEN[3:2]=0、RD_WR[1]=0、INC[0]=0。省略 STATUS 意味 OKAY，省略 SRC 不影响功能；非零状态必须用未压缩响应。每个 sector 都是合法自然起点，不能沿用未压缩偶数起点检查。[Common §5.9.5 Tables 5-37/5-39 pp.144–145]

poison 与 DL CRC 失败不同。每个受损 64B OrigData Beat 的两个 TL Data 半字都用 msg=1、type=0x20 表达；它们照常推进 Data 归属并给该 Beat 设置 data_error，不能当普通 Message 跳过。BE/AuthTags 半字不能用这个替代形式。UPLI ByteEnParity 错误也可标记相应 OrigData Beat poisoned；这不等于允许损坏的 TL BE 半字改成 poison Message。TL Rx 内部检测到的不可纠正错误是停止转发的错误路径。[Common §3.1.2 p.86、§3.1.4.1 p.91；§5.3 pp.114–115]

完整错误支持要把逐 Beat error 从源数据储存、TX 打包、RX 组装传到内存后端，不能恒零。推荐本地后端在组装检查阶段发现 poison 时不执行写入并返回显式错误，但“整事务不写入”和 poison 对应哪一个 WrRspStatus 是需要明确的产品策略，不能伪称规范强制规定。规范允许把 Data Error 按 Control Error 模式处理；若选择该模式，应有明确配置和对应恢复，而不是默默丢失事务。[Common §3.1.4.1 p.91]

DL replay/CRC 负责可靠传递，写入副作用只能由一次逻辑退休触发。丢槽或坏 CRC 不应使相同 Write 执行两次；重放 ACK 更不是 Write Response。DL/PL §2.6.1 pp.42–43 要求保留未确认负载、重放时背压并丢弃 CRC 错误 Flit。当前项目 544-bit 研发链接口仍不等同完整 640-byte DL framing。

统一同步 reset 可以清空本地所有权，但不撤销已发生的内存写入，也不自动构成协议 LinkDown/Isolation 恢复。超时需要区分远端 CMPTO 与本地 watchdog 隔离、迟到响应丢弃和软件清理。[Common §3.1.3 pp.87–88；Manageability v1.0 §4.4.1 Table 4-6 p.31 的 watchdog 配置项，以及 §4.5.2 Table 4-11 pp.31–32 的运行状态项] 本轮不新增管理寄存器，也不声称完整恢复已具备。

## 5. 实际 RTL 差距与实施顺序

| 现有模块 | 本轮读取确认的能力 / 差距 |
|---|---|
| `tl_control_decode` / `tl_control_tenure` | 结构解码已有 0x28 的 2N Data+BE、0x29 的 2N Data、无 Data WriteResponse 和普通压缩 Write/Rsp tenure；不检查地址/LEN/BE 的完整事务语义。 |
| `tl_prepared_partition` / `tl_tx_prepared` | Request lane0 和 Response lane1 可保存有序 Data/BE 半字；每 Beat 计一个 Data 信用，BE 不额外计 Data 信用。支持基础 transport 不代表 Endpoint 执行功能。 |
| `tl_tx_channels` / `tl_tx_packer_core` | 保留旧 Data lane 所有者和尾交换；普通 Data 输入没有逐半 poison sideband，o_msg 仅从独立 FC/Message 来源转发，现状不能表达完整 poisoned Write 发送。 |
| `tl_receive_context` / `tl_sequence` / storage | 已派生 Data、BE、poison 分类与命令/数据归还位置；Write 的 CMD 随最终 BE 退休，WriteFull 随最终 Data 退休。接收信用不代表内存完成。 |
| `endpoint_receive_transactions` | 目前仅允许单 64B Read 请求及 ReadResponse 0/3，拒绝 BE/poison/auth；所有 Data 都给 ReadResponse assembler。必须增加 Write 描述符与数据所有者队列及无 Data completion 出口。 |
| `endpoint_response_encode` / `endpoint_response_assembler` | 当前编码器固定 RD_WR=1、last=1，assembler 等两半 Data；二者不能直接承担 Write Response。 |
| `endpoint_write_originator` / `endpoint_write_completer` | 仍为 implemented=0 的 generic 壳，scaffold enable/valid 绑零，pending slots 5/6 保持置位。 |
| `endpoint_transaction_core` / top | 实际 core 只有 Read originator/completer；request Data lane0 恒零，公共 memory/completion 接口仍是 Read。需真实接入 Write 所有权，不能仅修改库存状态或端口名字。 |

建议按以下顺序交付，每步由独立语义 oracle 检查，最终关闭普通 Write/WriteFull 全范围而不是止于第一条 64B：

容量配置须同时覆盖完整请求的 N 个远端 Data 信用；prepared 可拆开同 Control 的多个字段，但不能把一条 4-Beat Write 的完整信用需求擅自拆成四条独立请求。总容量不足与当前余额暂不足应区分诊断。低容量测试应验证拒绝或明确支持的请求集合，不能在只给一个 Data 信用的配置上永久等待 4-Beat Write，然后将其归为正常背压。[Common §2.7.8 p.71；§5.8 pp.133–135]

1. 冻结 typed Write 请求、逐 Beat Data/BE、后端完成、无 Data completion 接口，以及 Read/Write 共用 Tag 与执行顺序契约；先让现有壳在真实能力测试中失败。
2. 实现未压缩 Write / WriteFull 和 WriteResponse 编解码，直接覆盖全部合法 LEN/地址/NUMBEATS，不复制 Read 的 attr=ff、last=1、状态仅0/3限制。
3. 实现 Write originator 保存完整事务、序列化 lane0 的 2N(+BE) 半字、区分 capture/accepted/issued；与 Read 请求共享公平且保持必要顺序的来源，先防 Tag 重复再接纳。
4. 扩展 receiver 数据归属和 Write assembler，保留整字预检、旧尾交换、FC/MSG 插空及反压；加入 Write completer，只有真实内存结果后才排无 Data 响应，并与 ReadResponse 共享 lane1。
5. 在两端真实 top、Switch 和 memory oracle 上跑全部普通长度、稀疏 BE、并发 Read/Write、乱序后端结果、容量边界及 replay/reset。随后补齐 poison、全部普通状态与隔离策略；这些仍是功能工作，不能留作“性能优化”。
6. 独立接入并验证地址缓存同步和压缩 RX/TX；安全/auth 及原生 UPLI 连续 Beat 接口按对应契约补齐。TX 永远未压缩是允许的实现选择，不能把它包装成已实现缓存压缩。Multicast/Block/Atomic 是后续独立语义，不作为本次普通 Write 测试的代用品。

## 6. 最少需要的定向证据及待确认项

独立 oracle 直接从 `(A,S,BE,逐 byte 数据)` 更新 byte-addressed memory，不复用 RTL tenure、RTL encoder 或其生成器推导期望。检查完成数量、Tag/kind、状态、内存最终值和逐事务执行次数，不能仅检查最终读回值：重复写同一数据会掩盖重放重复执行。

- 全部 64 个 4-byte 起点 × 64 个 LEN，接受恰好不跨 256-byte 的组合；WriteFull 10 个合法起点/长度组合，配相邻非法组合。测试高位地址与 Tag 1024/2047，防截断。
- 4-byte 起点中的单 byte、首尾掩码、交错稀疏、全零、全一；地址 60/124/188 跨 Beat；地址 128 和 192 的 BE 位置；范围外 BE 置一、NUMBEATS 不匹配、缺/多 Data、缺/提前 BE。
- 两 Write 同 Control，Write 与 Read/ReadResponse/WriteResponse 混排；所有自然起点；旧 Data/BE 尾加新 Control；FC 和普通 Message 插空；每个 ready 单独长停顿及最小容量，不让无 Data WriteResponse 等待数据。
- 应用同 Tag 的 Read/Write 冲突、不同 port 同 Tag、迟到/重复/未知/kind 错误响应，完成反压；后端只接纳未完成时禁止 OKAY，最后 Data 当拍禁止响应，所有状态及非法保留状态。
- 每个 Beat 的成对 poison、仅一个半字 poison 的 malformed 输入、poison 错放 BE/AuthTags；bit 翻转、BE 位置交换、Beat 次序交换必须被独立 oracle 检出。普通全零 BE 成功完成且 memory 不变。
- WriteFull 后 Read、稀疏 Write 后 Read、重叠地址混合请求顺序，丢槽+CRC replay 下执行一次；reset 分别发生在预约、半字组装、BE 前、后端进行中、响应等待中，说明已提交内存的残留效果。
- 压缩阶段加入同 Control 的 CLOAD 后立即引用、同 row 不同 way、不同 SRC/DST row、覆写/失效、错误状态不可压缩，以及压缩 Write 仍有 BE 的反例。

尚未能从本次规范核对确定或仍须产品决策的事项：

1. ASI/ATTR/META 对目标 memory backend 的具体功能、地址翻译和一致性接入是实现相关的；必须冻结能力与错误映射，不能从普通 Write 编码反推出这些含义。规范要求 coherent update，但目前 standalone memory 接口测试不能证明真实缓存一致性。
2. poison 的最终内存处理、错误状态映射和是否保证失败事务零副作用需要明确定义；Common 给出逐 Beat poison 传递，未由这些章节唯一规定上述策略。后端原子性、分解执行及 rollback 也不能擅自声称。
3. §5.9.5 p.145 的 Table 5-39 及相邻正文带有 Single-Beat Read 标题残留；按本节主题和 STATUS 省略语义将普通压缩 Write 限为 OKAY，记录为明确解释。Table 5-27 p.136 与后续 FTYPE=6/7 的 Block 压缩表存在不一致，继续保留未决，不影响本次普通 FTYPE=1/2/3/5 的路线。
4. 本轮未证明全套 authentication/encryption、管理隔离恢复和原生 UPLI 接口，现有同步 reset 及研发 DL 链路不能替代它们。完整普通数据功能与这些互操作能力应分别留出可检查的完成条件。
