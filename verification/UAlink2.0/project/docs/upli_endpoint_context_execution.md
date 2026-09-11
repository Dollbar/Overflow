# UPLI 与 Endpoint 因果上下文实施契约

本文件起始于对真实 RTL 的只读实施审查，不是 Native Endpoint 已完成声明。目标为普通单播 Read、Write、WriteFull 的全部合法 4..256B 几何；不增加 Atomic、INC、Vendor、Message 或压缩能力声明，也不退回只支持 64B。审查时源码身份和定位保存于 `build/development/upli_endpoint_context_review/sources.json`。其中 ordered receive 与 Request/OrigData 完整 holding 已按后续执行记录实现并验证；Backend/Response 因果路径及其余接口仍是待实现的本地契约。

## 规范依据与必须保留的身份

本地 Common Rev 2.0：§2.4 的接口路由例（pp.37–40）、§2.5（pp.41–42）、§2.6（pp.43–45）、Table 2-2/§2.7.4.2（pp.49–52）、§2.7.4.4–7（pp.55–57）、Table 2-15/§2.7.5（pp.62–65）、Table 2-18/§2.7.6（pp.66–68）、Table 2-21/§2.7.7–9（pp.69–73）、§2.8（pp.74–75）、§3.1.1–2（pp.85–86）、§4.1–3（pp.101–104）、§5.3（pp.114–115）、§5.9.1–2/Tables 5-29/30（pp.137–139）。只记录实现释义，不复制受限正文。

Tag 在一个 Source Accelerator 的本地 station/port 上跨命令类型共享，VC、pool、Read/Write kind 都不能形成另一套可复用 Tag 空间。同 port 同 Tag 的 Read 与 Write 冲突；不同 port 可以使用相同 Tag。实例覆盖多个 station 时还必须保留 station 身份或用独立实例隔离。请求 Kind 是校验属性，不是扩大唯一性域的索引。响应 Src 仅调试，不得用来匹配 Tag、选择功能路由或鉴权。

Port 是当前 station 的接口和路由上下文，**不编码到 TL 请求字段，也不端到端原样传播**。远端根据真实入口重新生成 port；最终执行者保存该入口 station/port，在返回时选择同一个本地出口。Request Src/Dst 则需要跨网络保留；普通 Response Dst=原 Request Src，Src 可取原 Request Dst，无法准确重建时规范允许零。不能把远端 Request port 当本地 originator port，也不能用 Tag 高位暗藏 port。

普通 Read CMD=0x03 的 ReqNumBeats=0；响应 N 由地址和 LEN 推导。Write/WriteFull CMD=0x28/0x29 的 ReqNumBeats=N−1，与实际 OrigData 拍数一致。S=4×(LEN+1)，ADDR DWORD 对齐且 (ADDR mod256)+S≤256；N=ceil(((ADDR mod64)+S)/64)。Full 还要求 ADDR 64B 对齐和完整 64B 整数倍长度。全部 57 位地址、11 位 Tag、10 位 ID 必须保留。

Read ATTR 首/尾 DWORD BE 和 LEN0 规则、两种响应模式/五状态/完整错误 Data，沿用已核对的 [普通 Read 契约](endpoint_read_contract_review.md)。Write 区域 BE、全零仍一次执行和真实结果才响应，沿用 [Write 契约](endpoint_write_contract_review.md)。DataError 是独立的数据完整性标识，不能从 status 非零推导；Status=0/2/3/6/8 与完整 N 拍的关系不因接入 Native 改变。

## 两个接口角色，四条真实因果路径

这里必须区分 TL 桥和执行者，避免把已有 core 的本地应用 Tag 分配当成一个新的线上请求。

| 本地职责 | 输入 → 输出 | 因果所有者 |
|---|---|---|
| Originator-facing TL 端 | Native RX Req/OrigData → 实际 TL prepared/Data → DL | 保存外部已选 Tag/Src/VC，不另生成 Tag；本地预约记录只是跟踪同一事务 |
| 同一个端的返回方向 | 实际 TL RX Read/Write Response → Native TX RdRsp/WrRsp | 在 Tag 聚合/应用 mask 之前保留原始响应并预约转发；真实网络响应是唯一数据/状态来源 |
| Completer-facing TL 端 | 实际 TL RX Request/Write Data → Native TX Req/OrigData | 保存真实入口 port 与请求身份；向外部原生执行者提交同一请求 |
| 同一个端的返回方向 | Native RX RdRsp/WrRsp → 实际 TL Response/Data | 来自真实外部执行者的结果；不能在 Request 发送或 OrigData 尾拍时预制成功响应 |

现有内置 memory executor 可以作为远端执行者的另一种显式配置：TL RX 请求进入 `endpoint_read_completer`/`endpoint_write_completer`，实际 memory result 再产生响应。它与“向外部 Native 执行者转交”二选一，不能同一事务同时走两路。也可用一个真实 Native 接收执行适配层接这两个 completer 做端到端测试，但不能绕过 native RX 存储或伪造 backend result。旧 application 接口及 TRANSACTION_MODE=0 默认行为保留为独立模式。

## 实际源码中的上下文缺口

| 精确边界 | 当前实际行为 | 最小必要修改 |
|---|---|---|
| `ualink_endpoint_top.v` 的 `transactions/u_core` 与 selected_tags | core reset 被 `!i_auth && i_port==0` 限定；tags 固定零；没有 Native RX/TX 接口 | 增加明确 Native 模式和 typed 连接；端口选择真实 TL lane。禁止只放开 reset 条件后宣称多 port/Auth 已支持 |
| `endpoint_transaction_core.v` 的 `mixed_originator/u_originator` | formatter 的 NUM_PORTS 固定1，输入只有 Dst，Src 取全局 local_id；没有 Auth/VC/poison | 将 Native Src/VC/Num/Cmd 等在预约沿保存；NUM_PORTS 与实际物理 lane 域一致。保持 existing application wrapper，而非修改其已定义语义 |
| `endpoint_request_formatter.v` 的 request_fire、Read_Encode_Inst、Write 子模块 | request_fire 同时预约 Tag/holding；Read/Write 编码使用 local_id、VC0/pool0；保存 r_port/r_tag/r_control | typed request holding 接收完整 descriptor；Src 不能被 local_id 覆盖。UPLI pool 与 TL pool 分开，由各自资源准入选择 |
| `endpoint_write_originator.v` 的保存数据与半字序列化 | 完整 data2048/区域BE256 已保存；无逐 Beat Error；Data/BE 通过正常 Data 类别发送 | 保留 error[3:0]，在实际 TL 数据类型/MSG 生成边界接 poison，而不是只附加一个永远不用的 sideband |
| `endpoint_receive_transactions.v` 的 mixed 请求输出 | 内部有 request_port，但公共请求没有 port；保存128位 header、data2048/BE256；VC非零/pool1被预检拒绝 | 公共请求输出真实 port；不要在多个入口交错后从当前 i_port 重取。恢复普通原生 VC，上游 TL pool按TL规则处理 |
| 同模块 mixed 响应输出 | 保存64位 header；只输出 Tag/Dst/Status/Offset/Last/Num/Data；Src、VC、pool、RSPTYPE 未公开；DataError恒0；AuthTags/poison 预检停流 | 在此输出完整 raw response tuple；保存 Auth 关联及逐 Beat poison。Src可合法清零但应有明确策略；不能误称已完整保留所有字段 |
| `endpoint_read_completer.v` / `endpoint_write_completer.v` 的 request_fire | 保存 Tag/Src/Dst/address/len/attr/asi/meta；无 port/Auth/VC，资格限定VC0/pool0 | 每执行槽追加不丢失的 routing/context token 与 VC；真实结果通过 token/slot 找原上下文，不能依赖实时输入 |
| Read completer full_read 的 result_fire/response_encode | 后端全2048位；五状态；错误结果改成零；按 offset升序发 N 个 Num0 single；无 Auth/poison输出 | 本地执行可继续采用完整 single 发送策略；透明 relay 不能借用其错误清零或重排。若后端支持 poison，完整保存每 Beat Error 并接真实发送格式 |
| Write completer 的 result_fire/retire | 只接受已 issued 且合法 slot/status 的实际结果；Header capture 才释放槽 | 保留这条因果约束；增加 typed result/response owner，不在 memory_ready 或 OrigDataLast 直接出成功 |
| `endpoint_tag_table.v` 的 response_masked_data、r_data、retire_fire | port+tag+kind校验与多Beat seen 已存在；DataError拒绝；应用数据按mask/错误清零；应用complete_ready才释放Tag | 保留为 application sink；Native透明返回应在此前分流并用独立元数据 scoreboard 跟踪，不从 o_complete_data_full 逆向恢复 raw fields/顺序 |

当前 core 的 shared dispatch 只在真实已 issued slot 返回合法状态后释放，响应 Header 选择在 source_captured 前锁定；这两个机制应保留。扩大字段不能把 dispatch 接纳、issued 或完成三个状态折叠。响应 Src 零化本身可符合其可选调试语义，但 Request Src、Response Dst/Tag/VC 不可用同样理由丢弃。

## 原生 RX 存储、顺序与事务预约

`upli_receive_channel` 的真实头含 payload+原VC+原pool，port来自消费者所选账户；`o_head_valid` 不代表可退休。唯一消费是 `o_consume_valid && i_consumer_ready`，它同时释放真实 FIFO 和保存信用归还元数据。不能用 `o_head_valid` 归还信用，也不能把注册的 `o_receive_accepted` 当原生 ready。该 accepted 是上一沿的存储诊断，关联它时必须保存同沿字段快照。

每 port 的五账户是独立 FIFO，**没有跨账户到达顺序**。因此需要在实际 Native 写入沿保存每 port 的通道顺序 journal：至少包括账户、原VC、序号与 Req/OrigData owner/Beat 关联。Req 与 OrigData 共相位；新 Write 的 Req 与首 OrigData 同沿，后续连续占本 port 槽，Read overlay 不得替换旧 Write owner。不同 pools 的尾拍不能按账户轮询顺序重组。所有 Native 原始字段/parity、TDM 和连续性检查须在信息尚未丢失的入站边界执行。

主线已实现并验证最小顺序接口 `upli_ordered_receive_channel`：每 port 保存 account3 的接受顺序队列，消费者只选 port/ready，队头 account 驱动真实 receive_channel 并原子退休。队列用既有注册 `o_receive_accepted` 加上与原输入沿对齐的 account 元信息寄存写入，深度由该 port 五账户的真实容量总和派生；不能晚一拍读取变化的候选元信息。当前1/2/4端口异构及零容量回归和三项真实故障注入通过，范围只覆盖单通道正常顺序及真实信用归还；四通道仍须分别实例化，不能一个全通道队头相互阻塞。

Endpoint 适配层在该顺序边界之外仍须保存当前 Req/OrigData 多拍 owner、Req与首Data同沿关系、Read overlay 和 Tag 上下文；account顺序队列不替代这些检查。每 port 强顺序是允许的保守微架构，无需为了普通接入立即实现按VC重排；它可能造成跨VC队头阻塞，后续容量/公平调度审查应明确影响，同时维持跨通道独立前进。Read/Write Response 的同port跨pool顺序由同类wrapper保留，不能任意改变同Tag single顺序与LAST所指事件。

registered接受实现应检查 `order_count + accepted_pending <= 该port容量总和`，并准确处理同沿序列入队/退休；accepted_pending是尚未写入order FIFO的已实际存储事件。journal 容量必须覆盖所有已声明账户容量和自身在途写入，不得形成未计入初始信用的隐藏“满而仍收”条件。零容量账户不生成虚假资源。原生接口无 ready；对已发放合法信用的 Beat 应始终有真实保存能力。错误包的隔离/丢弃与信用恢复需要独立 RAS 契约，不能静默删一项继续错配。

当一个 Request 从 SRAM 退休，先原子获得完整 context 和最多4拍 data/BE 的组装位置；之后可逐拍消费 OrigData，归还其原账户信用，最终齐套才向 TL formatter 或 memory executor 公开。不能等待所有 Data 已同时堆在输入 FIFO 才开始转移，也不能在复制一半后释放组装位置。Input SRAM、assembler、TL prepared 各有独立容量，不能用对端还未发送的未来响应当本地已预留空间。

Req 队列堵塞不得阻止 Response 收取、结果发送或任何正常信用返回。响应在原请求接纳时已有足够结果/转发资源，不能要求额外新 Request 被执行才前进。若整笔 staged TX 所需信用大于所配某账户容量，那种 pool 计划应保持背压，不借同沿归还或声称该资源配置能发送任意四拍计划。

## 可编码的 typed 接口与字段映射

建议保持存储层既有四种 opaque payload184/580/619/101，外侧使用完整 typed descriptor；不把这些容器误称新增线上字段。新增 token 是局部容量/执行关联索引，**不替换线上 Tag**。token 带 epoch 或在统一 reset 中清空，所有大小参数由真实槽容量派生。

| 本地 descriptor | 字段 | 保存/退休位置 |
|---|---|---|
| `request_context` | token、station实例/port2、Cmd6、Tag11、Src10、Dst10、VC2、ASI2、AuthTag64、Addr57、Len6、Attr8、Meta8、NumBeats2；原RX pool单独记账 | Native/TL实际入队时保存；formatter/executor握手后转交完整所有权，不重新分配网络身份 |
| `write_payload` | token、data2048、relativeBE256、regionalBE256、error4、received bitmap4、每Beat原pool4 | 顺序journal/owner明确关联后组装；全部N拍合法才公开，DataError不变成普通成功数据 |
| `read_response_beat` | token或查找所需port2/Tag11、Auth64、Src10、Dst10、Num2、Data512、Status4、Offset2、Last1、DataError1、TypeInfo2、VC2；原RX pool独立 | receiver原始输出之前保存；握手进入native返回队列或TL响应序列化器，不能先应用mask |
| `write_response` | port2、Auth64、TypeInfo2、Tag11、Status4、Src10、Dst10、VC2；原RX pool独立 | 真实结果队列或实际接收字段；一拍发送，无虚构Data |
| `memory_command/result` | command沿用完整addr/len/attr/asi/meta/data/BE并带context token；result带token/slot、status、Read data2048/error4，授权另走明确结果接口 | command accepted仅标issued；合法result accepted才允许创建响应候选 |

每个事务/响应输出接口使用 `valid/ready` 和 `fire=valid&&ready`，完整 tuple 在等待期间稳定。Native sender 入口则沿用 `candidate_valid/.../candidate_accepted`，accepted 代表首 Beat 实际发出；其多拍尾部此后由 sender 保存。不可在多拍首 accepted 时释放“已对外完成”的 Tag：收到全部合法网络响应与最终 Native `o_valid && o_last` 是两个时间点，应保守保持上下文到最终原生返回实际发出。透明桥的内部元数据完成不代表外部 Originator 已收到最后 Beat。

具体映射规则：

- Request Cmd/Tag/Src/Dst/Addr/Len/Attr/ASI/Meta/VC 转普通 TL 128bit 字段；Num 按原合法 Cmd 保留（Read零，Write N−1）。CLOAD=0、CWAY为无效建议值，不造压缩缓存。TL pool由真实 TL credit 准入选择，不能接 Native ReqPool。
- Read 结果的 TypeInfo=0 只因为已验证原请求属于 ordinary unicast；接收响应必须校验 RSPTYPE/TypeInfo=0，不能先强写0再绕过错误。INC/Atomic不靠kind布尔位压成普通Read/Write。
- Response VC 必须匹配原 Request VC。Response pool是本次输出通道信用选择，可以与 Request pool及入站TL pool不同；每个 receive_channel仍用自己的原pool/VC归还。
- Native Write Beat k/lane b 对应地址 `floor(ADDR/64)*64+64*k+b`。相对数据最低512位为Beat0。regionalBE索引为 `(ADDR & 0xC0)+64*k+b`，由对应 OrigDataByteEn 置位；反向适配按相同地址关系提取每Beat64位。普通Write范围外有效BE按既有几何契约拒绝，全零BE仍执行一次；Full忽略线上无意义BE并重建结构范围。不能把区域BE直接当relativeBE。
- Read 数据保留自然lane位置和无效lane原值，只有 application sink 可以按ATTR生成mask再清零。合法错误仍转发全部N Beat；本地执行者无可用错误数据时可选择固定图样，透明桥不能擅自改变已有错误数据图样。
- AuthTag是请求/响应各自的授权值，**不能把 ReqAuthTag 原样回填为 ResponseAuthTag**。当前安全关闭时输入需满足零Auth契约、输出零。完整授权需将真正响应Auth附带到结果或原始响应描述符，并把控制字段与AuthTags半Flit按实际字段序号关联；不得只移除top的i_auth拒绝。公共parity只是完整性保护，不是授权验证。
- DataError4按实际Beat保留；向TL发出的受损Beat在对应两个Data半Flit的 MSG/type=0x20表达，BE/AuthTags不能冒充poison Data。TL接收在Data owner下消费class5并记录完整错误归属；不能当普通Message跳过。现tx输入仅Data位、receiver拒poison、Tag拒poison，这三处都需改才能声称支持；同Beat单半受损标记的规范处理应沿现poison契约做定向检查，不靠状态覆盖。

single 模式每Beat Num0，Offset可乱序、不同Tag可交织，LAST是最后实际到达/发出的那一Beat，不等于最大Offset。透明路径保存并输出其原次序。multi接收按N收集完整burst后送现RdRsp sender的4×619 staged输入，重建Offset0..N−1及末Last；原生Src逐Beat可不同，不作功能相等检查。既有 TL multi Header 的无效OFFSET和LAST归约待澄清点，维持 [Read 契约](endpoint_read_contract_review.md) 已记录的保守解释，不新增拒绝条件。本地memory completer可继续统一发送Single，完整长度不依赖multi发送。

## 三个不得短接的事件及最小改动顺序

| 事件 | 发生条件与意义 | 禁止替代 |
|---|---|---|
| request accepted / request_fire | 原生接收层已保存，并在下一级实际ready时转交/预约完整上下文；Native线上valid不能被应用ready撤销 | 不能等于TL source_captured，也不能代表Header已发送 |
| source_captured | `tl_tx_prepared.o_source_captured` 已保存该Header及应有Auth源组；其后上游可改源字段 | 不代表TL/DL已接纳，不把Tag标成sent |
| header_taken | `tl_tx_prepared.o_header_taken` 对应实际发送消费，top已经要求它与DL接纳一致 | 才推进请求sent；不能拿DL重放每次发送再次计一次新Header |

Data `i_data_accepted` 是每类别0..2个半Flit真实转移，与Header捕获独立；Write holding必须等Header/Data/BE全部交付后释放。memory command accepted、memory result accepted以及native response sender accepted也分别保留。多拍返回的末Native beat完成，是最后一条外部可观察事务事件。

下一轮直接按以下顺序推进，不新增不必要的大型调度器：

1. 定义完整 context/raw-response typed 端口及 Native RX 顺序journal；复用四个实际receive_channel和现有parity/connection，不重复扣账/归还。先测跨pool、Req首Data同沿与Read overlay的正确所有者。
2. 将 formatter 的编码holding与application completion collector职责分开：复用现Read/Write序列化器，追加完整Src/VC/context及poison表达。Bridge使用同一外部Tag的元数据预约，应用模式保留原Tag collector与mask。
3. 扩展 TL receiver 的request port、raw response完整字段/poison/Auth上下文输出；在其握手边界路由到Native bridge或现memory completer。不得双消费者同时退休同一个600bit记录，也不二次归还TL releases80。
4. 在现completer槽或外部Native执行上下文槽保存 routing token/VC；保留真实result检查和response header锁。选择内置memory或native backend其一，接现三sender与独立信用返回闭环。
5. 真实顶层采用1/2/4份每物理port TL/DL lane复用方案优先；station统一调度native TDM，各lane保存自己的port映射。比直接把当前只支持port0的core改成一个混杂多port parser更容易保持原有已验证行为。最后贯通Auth/poison能力时单独关闭其pending项，不能因普通长度通过而一起晋升。

## 必须由真实端到端测试关闭的用例

- 两个真实 Native 侧、真实RX SRAM/credit、两端TL/DL与实际memory执行：同地址Write→Read读回；独立byte oracle核对全部有效数据/BE和真正执行次数。普通4096几何判定、2080合法Read/Write、10合法Full，覆盖高Addr/高Tag、LEN0首BE、区域边界和全零BE一次执行。
- 相同Tag同时用于两个port应各归各路；同port Read/Write重复Tag不得被VC/pool分成两项。远端重新生成不同port、Src/Dst互换，最终回复原本地port；故障把port锁0或Src取local_id必须检出。
- Req/OrigData同沿、Read覆盖旧Write尾部、每Beat pool变化、不同账户FIFO不同时可读、不同port交错；真实顺序journal故障交换两项必须导致明确tuple或数据失配。
- TL backpressure分别延迟source_captured、header_taken及两半Data接纳；三事件计数独立。注错把captured当sent，应使未真实发送前伪响应被scoreboard检出。DL replay不得重复计新事务或后端执行。
- Read N1..4错误状态0/2/3/6/8完整Data；single offset置换、低offset Last和跨Tag交织；multi完整按序尾部。错误原始Data非零、无效lane随机值、逐BeatSrc不同，确保透明路径没有借application complete口清零或排序。
- 延迟真实backend result、乱序合法slot结果、未知slot/重复/错误kind/status；memory_ready或最后OrigData本沿绝不能产生WrRsp，至少后续周期且确有执行完成。真实接线故障提前制造成功必须检出。
- Response信用耗尽与应用不消费时，已接纳请求结果有预留位置；新Request阻塞不妨碍Response或credit返回。最小容量需按实际N/pool计划满足整笔预约，不用假credit使测试“通过”。
- 完整poison及Auth作为明确独立能力用例：数据/BE/parity真实位翻转、Auth源组错配、错误status与DataError分别验证。尚未实现时保留拒绝/错误证据，不标绿色功能覆盖。
- 统一reset置于Native已收未转交、TL captured未taken、Write部分Data、memory已执行结果未回、Read部分response和Native尾部未发等窗口。清空所有上下文/顺序/Tag/credit/TDM并重新建连；内存已发生副作用保留，旧结果/尾部不得污染新epoch。

## 尚未闭合的接口与恢复边界

当前 `i_link_reset` 实际与全域reset合并，同时清除事务、TL和DL，不能叫独立LinkDown恢复。未来独立LinkDown必须定义已发Tag的失败完成、未发holding/地址压缩cache、在途memory result与Native连接是否保留；不能简单复位一个lane后保留同Tag旧响应入口。UPLI连接握手保持到reset的假设仍有效，停止流量/Isolation/DVFS不由此计划自动支持。

Auth算法、请求到响应的安全上下文生成与验证、Response AuthTagParity表Driver矛盾、TL multi Header LAST归约、完整控制错误隔离/信用恢复均保持公开未关闭。当前格式支持以普通未压缩为准；压缩接收、Atomic/INC等需独立规范与实现，不得靠更宽bundle推定功能存在。此轮无新仿真、综合、STA或PPA结果，只交付可实施的接口/所有权修改契约。
