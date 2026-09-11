# Native UPLI RX 与 Endpoint 因果桥执行契约

本文件冻结下一批实现边界，审查基线 `cf8fd72e0b37b3b1f7fd167324d7def096c708a3`。本轮只读正文、需求映射和实际 RTL，没有新增 RTL、运行仿真或关闭 RAS 功能。以下模块名、存储封套、内部握手与首阶段 profile 是本地研发接口；原生字段和行为来源逐项列出，不定义新线上编码。私有正文不复制到交付物，阅读来源及 SHA-256 记录于 `build/development/upli_native_rx_review/sources.json`。

## 1. 已确认来源与约束

| Common Rev 2.0 来源 | 已有需求映射 | 实施约束 |
|---|---|---|
| §2.5 pp41–42 | F03；已有 UPLI TDM 契约 | Req/OrigData 相位由首个真实 ReqVld 建立；RdRsp、WrRsp 分别建立相位。空周期照常轮转；有效 PortID 才解释。接收实现可按 PortID 收取，显式相位检查是允许增加的诊断，并非规范要求必须存在一个接收 TDM 状态机 |
| §2.6 pp43–45 | R006–R014 | 每 port、channel 的 VC0..3/pool 五账户，初始化与实际容量一致；保存原 VC/Pool 后归还；信用返回不受 TDM 约束，UPLI/TL 信用独立 |
| §2.7.4/Table2-2 pp49–52；§2.7.4.2 p52 | R078、R082 | 完整11位 Tag；同源端口命名空间跨请求种类保持唯一，全部响应收到之前不能复用；OrigData 依赖首拍 Request 的身份，不自带 Tag |
| §2.7.5/Table2-15 pp62–65；§2.7.6/Table2-18 pp66–68 | R079–R081、R084、R091 | 两种 Read 模式、完整错误数据、逐拍 poison；Response Src 仅调试，不能功能依赖；ISOLATE 不按普通 Write Tag 匹配 |
| §2.7.7/Table2-21 p70；§2.7.8 pp71–72 | R041、R079、R082、R083 | Req/首 OrigData 同沿；尾部在该 port 的连续时隙，Offset 递增，Last 仅最后；允许 Read 与旧数据尾部同沿；响应不得依赖再处理新请求；WrRsp 最早在最后 OrigData 收到后的下一周期 |
| §3.1.1–3.1.2 pp85–87 | F05、R040/R041 | 接收端检查完整 parity；保护转换须有覆盖交叠；control/data/protocol 分类不能混淆 |
| §3.1.3 pp87–89；§3.1.4.1–3.1.4.2 pp91–94 | R087–R089 | 数据错误 poison 后继续；控制错误丢弃坏 Beat/信用并 Drop；Drop 和 Isolation 的范围、信用义务、尾部终止规则不同 |
| §4.1–4.3 pp101–104 | R015–R018、R055、R077、R110 | 同步共同 reset，清除信用/事务/相位且旧事务无完成；重连最早晚一周期；信用按方向连接，Beat 需双向连接 |

为决定错误动作，除了任务指定 §3.1.1–3.1.2，实际补读了 §3.1.3 与 §3.1.4.1–3.1.4.2。仅凭 parity 分类不能推导完整恢复行为。

## 2. 接收保护与错误动作

四条正向通道的 native valid/Port/VC/Pool 独立保留。payload 沿用已冻结本地格式：

| 通道 / CHANNEL_KIND | payload 高位到低位 | 位数 |
|---|---|---:|
| Request / 0 | ASI2, Auth64, Src10, Dst10, Tag11, Num2, Addr57, Cmd6, Len6, Attr8, Meta8 | 184 |
| Read Response / 1 | Auth64, Src10, Dst10, Tag11, Num2, Data512, Status4, Offset2, Last1, DataError1, Type2 | 619 |
| Write Response / 2 | Auth64, Type2, Tag11, Status4, Src10, Dst10 | 101 |
| OrigData / 3 | Data512, ByteEn64, Offset2, Last1, Error1 | 580 |

接收必须使用 `upli_parity` 校验收到的保护码，不能先把坏 parity 重算成好 parity 再声称校验通过。共同的原生保护组为：

| 错误组 | 适用与使能 | 已确认动作 / 明确限制 |
|---|---|---|
| Valid parity | 四正向通道，每个启用检查周期，包括 valid=0 | Control Error。可能是丢失或伪造有效拍；禁止以当前 Port/VC/Pool 推断可靠归属，不制造一个信用或虚构丢失 payload |
| Control parity | Request68、RdRsp48、WrRsp42、OrigData9 位；valid=1 | Control Error；坏拍不得进入可投递业务队列/后端/Tag 更新。带数据首拍某通道失败时，配对上下文不得部分提交为有效事务 |
| Address parity | Request57；valid=1 | Control Error。不能因其它字段看似正确就继续执行内存访问；首阶段与其它 control 同一 Drop 范围 |
| Data parity | RdRsp/OrigData 全512位，8个64位组；valid=1 | Data Error。包括被 mask 掉、已有 poison 或错误 status 的实际 lane；置本拍 DataError/Error，保留整拍流量，修正保护后继续。不能只留启用字节参与 parity |
| ByteEn parity | OrigData 完整64位；valid=1 | 原生 UPLI 上明确属于 Data Error，和该拍数据一样置 poison；不要转成普通控制失败。交换内部 ByteEn 定位错误另有 A17，不能套用此结论关闭 |
| AuthTag parity | Req/RdRsp/WrRsp 的64位；valid=1 | 独立 `auth_error`。它不是密码学认证结果，§3.1.2 的 control/data 枚举没有列它；不得静默吞掉或无依据改成 DataError/某个 Status |
| Credit valid parity | 每通道完整 valid4，每启用周期，包括全0 | Control Error；坏信用返回不得送入 bank。有效位错误时无可靠计数可加减 |
| Credit control parity | 每通道完整 pool4/vc8/num8；任一 valid=1 | Control Error；全部20位均检查，不屏蔽 inactive port 字段；该坏返回组不能被正常计账 |
| CreditInitDone | 不属于上述两组 parity | 使用已有 initializer/bank 的连续大于1周期确认、确认后忽略变化规则；禁止把 InitDone 混进 parity 或把数据通道 valid 用作其使能 |
| 纯协议错误 | 无 control/data parity 错误，字段/时序违反已声明 profile | 独立 protocol 诊断；规范不要求 Switch 检查所有可能协议错误。非法命令、TDM、重复/未知 Tag 不得伪装成正常完成；尚未冻结通用协议错误恢复策略 |

公共 primitive 输出位置固定：valid0、control1、address2、auth3、data11:4、ByteEn12、credit-valid13、credit-fields14。native RX 的 channel primitive 将 credit 输入及收到的 credit parity 全接0；实际 credit guard 只检查真实 credit 集合，不能把正向 valid 错误与反向信用错误互相捏造。未实现的组接0。

`poison_out = poison_in OR detected_data_error`，不是 `status!=0`。§2.7.5 pp63–65 要求 Read 的 TARGET_ABORT/DECODE_ERROR/PROTECTION_VIOLATION/CMPTO 仍返回全部所需拍及 Last，所有拍 Status 相同；无实际数据可制造，0xFF 是推荐而非唯一合法值。错误 Status 不自动置 poison，数据 parity 坏则仍置 poison。Originator 不以错误响应数据更新 cache；整笔错误完成只可在完整响应收齐后产生，不能通过抛弃错误数据拍提前释放 Tag。

普通写的 poison 不能被忽略后按 ByteEn 正常落内存。当前 Endpoint write backend 没有 poison 接口，故首次因果桥只接无 poison 请求；poison 传递在 native RX 层先独立闭合，后端的 poisoned-write 处置另冻接口，不猜某个错误 Status 代替它。

## 3. Drop、Isolation、信用与 reset 所有权

错误范围取决于检测点：

| 检测点 | 控制错误的首阶段选择 |
|---|---|
| TL 内的 Originator 或 Completer，Accelerator/Switch | 同 TL 的双 UPLI 角色、全部通道、全部端口进入 Drop。采用规范支持的粗粒度选择，不能把不可信 beat 的 PortID 当唯一隔离依据 |
| 非 TL 的 Accelerator Originator 或 Completer | 检测角色的全部端口、全部所属通道 Drop，坏拍/信用当沿禁入；错误通道未完 burst 终止 |
| Switch Core 的非 TL 接口 | 按对应角色作用域 Drop；普通 transit 不新增端到端事务 watchdog/Tag 历史。INC 的有状态 egress 另属 R087/R088 |

本轮不实现此状态机，但下一轮总装必须有唯一 role/TL 故障所有者。`upli_credit_guard` 只是诊断，不承担以上动作。若最先交付仅正常路径，须明确把遇错后外部 fail-stop 当测试边界，不能宣称已有合法自动恢复。实际错误控制当沿与 latched Drop 都必须禁止业务投递；不能迟一周期让同沿错误 Request 到达 backend。

Drop 下可以在元数据可靠且资源允许时继续接受/归还信用，不是必须无条件恢复账本。初步选择保留已经可信接纳且受保护的归还记录，坏返回组不交 bank；不能为未写入的坏 beat 按受损 VC/Pool 自动“补还”信用。未知/损坏账户的 outstanding 信用不猜修复，不通过重发 InitDone 重新初始化。若使用更保守的停止返回策略，也必须作为 Drop 内局部选择验证，不能套到正常态。

Isolation 与 Drop 独立。§3.1.3 pp87–88 要求受影响 Originator 停新 Req/OrigData、对既有及新请求合成 CMPTO、丢弃迟到真实响应，并继续正常收返信用；Accelerator 按 station Originator 全端口，Switch INC 按对应超时端口。是否终止未完 burst 的允许例外只在相应错误模式适用。单纯 poison/普通错误 Status 不能借此例外截断响应。ISOLATE 本地通知不通过普通 WrRsp Tag 完成接口处理（R091）。本轮不实现 watchdog、dummy completion、ISOLATE 或管理恢复。

正常出队是唯一 FIFO 退休/归还预约事件：`o_consume_valid && i_consumer_ready`。它与 native 输入时刻、ULPI 首拍发送、TL source capture、TL Header 实际消费均是不同所有权事件。返回队列满时不得先释放 SRAM 再丢归还记录；已有 receive_channel 已实现该约束，wrapper 不得另开第二套返还队列。

统一同步 reset 清除 connection、初始化、各账户、SRAM 有效状态、尾部/组装上下文、返回 pending、Tag/result 及检测状态；已终止事务不产生完成。内存数据阵列可保留但无旧有效所有权，不能读为新事务；相关 TL Tx 压缩缓存同时失效。新请求使用相同 Tag 时只属于新轮次。Drop/LinkDown 不是 UPLI reset；独立端口 LinkDown 必须保持适用 UPLI active/信用，不能靠全局 reset 通过恢复测试（R090）。

## 4. 最小 RX 模块与接口

不另建 generic TDM scheduler、信用队列或第二 Tag 表。下一批先增加下列实际行为块，再在真正的 station 角色边界组合。

### A. `rtl/upli/upli_native_rx_channel.v`

每实例一个固定 `CHANNEL_KIND=0/1/2/3`，复用一个 `upli_ordered_receive_channel`（其内部唯一实例化 `upli_receive_channel`）、公共 parity 的入口/出队检查与保护生成，及一个 `upli_credit_return_adapter`。端口数1/2/4、五账户容量、信用/初始化/return 参数直接传递到既有 channel；payload 宽度由 kind 唯一确定。四个 channel 各自拥有顺序 journal，不能合并成一个跨通道队头。

冻结本地接口族：

- `i_clk/i_rstn/i_credit_connected/i_beats_connected/i_drop`。`i_drop` 来自唯一角色故障所有者，不是 ready；channel 不自行清除 Drop。
- 原生输入 `i_valid/i_port[1:0]/i_vc[1:0]/i_pool/i_payload[W-1:0]/i_received_parity[12:0]`；完整typed打包按第2节，不提供 native ready。
- 输入/输出独立 `o_ingress_errors[12:0]`、`o_head_errors[12:0]`、`o_control_error/o_data_error/o_auth_error` 与既有 `o_storage_diagnostic[2:0]`；入口错误即使无成功接纳也保留。`o_receive_accepted` 保持已有上一沿实际写入观察语义，不冒充组合ready。
- 消费接口只公开 `i_consumer_port[1:0]/i_consumer_ready`，账户由 ordered journal 的最早实际接纳项选择；输出 `o_head_valid/o_consume_valid/o_head_payload[W-1:0]/o_head_vc/o_head_pool/o_head_account[2:0]/o_head_parity[12:0]`。头字段和更新后的保护码在背压下来自同一真实 SRAM 封套；公开的 `o_consume_valid && i_consumer_ready` 必须与底层顺序项、SRAM 字和信用元数据实际退休完全相同。控制、Auth 或元数据检查失败不得退休；数据错误归一化 poison 并重建保护后才可投递。
- 原生返回 `o_credit_valid/pool[3:0]、vc/num[7:0]、init_done[3:0]、valid_parity/fields_parity` 直接保护既有注册返回，无附加周期、ready 或 TDM。

首阶段 Auth inactive。入口仍检查 Auth parity，非零 Auth 与该 profile 不符须单独诊断；Auth parity 错误或 profile 违例禁止业务投递并请求本地 fail-stop，不能声称该选择已解决标准 Auth RAS 分类。局部 `fault_stop_request` 应独立于 normative `control_error` 暴露，由 role 总装接收，不能误标为某个标准错误码。

禁止使用裸 payload FIFO 冒称端到端保护。冻结存储封套为 `{saved_port2,saved_vc2,saved_pool1,parity13,normalized_payloadW}`，共 W+18 位，作为 receive_channel payload；其固有保存 VC/Pool 仍保留。parity 对归一化 poison 后的完整字段产生，头部检查时按 saved 字段重新组包、使用保存的有效拍 parity，并比较封套 Port/VC/Pool 与所选账户及 receive_channel 原元数据。数据坏拍归一化时重新生成 Error 控制组及数据保护；入口原错误检测要覆盖到新保护建立的边界。保护生成与校验必须实际实例化公共 primitive，不能留下不被使用的旁路检测器。

此封套首先保护被存储的信息，**不证明** SRAM 地址、FIFO 指针/计数、valid/选择控制已具备 RAS 保护。现有 receive_storage/fifo 无完整此类控制路径保护，§3.1.1 的全路径保护仍开放；混合 ECC 无法定位 data/control 时按 control 处理。下一步可对地址/指针保护单独立契约，不能用本封套通过替代该闭合。

### B. `rtl/upli/upli_request_rx_assembler.v`

在 native 接收沿建立 Req/OrigData 关联，不能等两个独立按账户出队的 FIFO 头出现后重新猜配对。每 port 保存带数据请求的完整身份、预计 Num+1、下一 Offset 与尾部所有权；首 Data 只从同沿成功 Request 取得身份，旧尾部从既有上下文取得。Read 覆盖旧尾部时不能覆盖这份上下文。每个 data Beat 的 Pool 可不同，VC 保留请求适用上下文，实际 credit 仍归其原账户。

冻结行为接口为双 native 入站记录（Req184、Orig580，各自 port/vc/pool/valid/保护结果）到 `o_transaction_valid/i_transaction_ready`，事务含 `request184/port2/data2048/byte_enable256/poison4`，低512位为相对 Beat0、BE同样按相对 Beat 排列。可采用每 port 完整事务槽并在入站保存带身份关联元数据的方案，但容量必须同最坏信用发布量一致。具体槽/跨账户调度在代码前以独立容量账本冻结；不得用未预约的一槽在首拍时才碰运气。

Req 与首 Data 的关联提交必须原子；无数据 Read 使用独立可用 Request 槽，不因本 port 有旧 Data 尾部被拒绝。只需保存带数据请求的关联，不给每个普通 transit 请求增加端到端 Tag 生命周期。首阶段支持普通 Read3、Write0x28、WriteFull0x29 的已冻结几何，其他命令保留原字段并诊断 unsupported，不发伪完成。原始 regional BE 与 relative BE 的转换由唯一桥接口处理，并用跨64/256byte边界独立向量验证。

对于只做 A 的首个正常接收交付，B 可以暂不实现，但此时只能宣称四类原生拍的安全接纳/保存/返还，不能宣称可把独立 FIFO 直接接现有事务执行器。A 与 B 可并行开发，B 的输入事件必须取 A 真正允许保存且已保护的记录，不能重新读取随后改变的输入。

### C. 实际角色总装与 Endpoint 桥

在 `upli_station_port` 的后续真实实现中，一个 Originator 角色 RX 为 RdRsp/WrRsp，一个 Completer 角色 RX 为 Req/OrigData。每实际侧用一个真实 connection_side；RX 信用发布接本侧 `o_tx_connected`，TX bank 收信用资格接 `o_rx_connected`，Beat 双向资格接 `o_beats_connected`。不能因为 station_tx 聚合了两种角色，就给一条物理接口制造两套相互无关的连接状态。

推荐首先完成源 Accelerator 的 local-device→TL Native 边界：真实 Native Req/OrigData→A/B→`endpoint_request_formatter` 现有共享 Tag 预约→真实 TL/DL/Switch/远端 core/backend→真实响应→本地上下文→Native RdRsp/WrRsp sender。远端 backend 必须真实执行，不预生成响应。

首次因果回归配置公开限定为普通 Read/Write/WriteFull、Auth inactive、VC0/Pool0、port0、普通 TypeInfo，以匹配当前实际 core 的 NUM_PORTS1及资格约束；这些是首测配置，不是新 Native 接口限制。A 的 transport 单元及 bridge descriptor 从第一版就保留完整 Port2、VC2、Pool、Tag11、Src/Dst10、Auth64 和 DataError，并测试1/2/4port及全VC/pool，不能将首测子集冒称完整 Native 能力。透明模式复用原请求身份和现有 formatter/发送 holding，不给 native入口再开一张相同语义的 Tag 表；旧 application Tag/result collector 保持为显式独立模式，二者不得同时拥有同一事务。

`endpoint_transaction_core` 当前 app completion 把成功数据按 mask 截取、错误数据清零，且缺逐拍 Auth/Type/VC/DataError。它不能用来证明完整 raw native Response。实施前必须暴露/保存来自真实响应的尚未掩码的逐拍记录，或明确只产生已声明应用profile允许的 manufactured错误数据；成功响应被mask的无效lane不能从未知原值“恢复”。若选择后一受限桥，需单独说明其 native重新生成行为，仍按完整原生512位生成parity，不声称透明转发。Tag表现状拒绝 poison 响应，不能直接拿它闭合 poison端到端完成。

首次 native Response 发布所需有限缓冲必须在 native请求接纳/formatter预约前可保证；不能等应用 complete_ready 后再临时申请空间，形成请求/响应互相依赖。formatter capture、Header actual take、backend result、native sender accepted、最后 native response发出分别记录。透明模式在 application mask/错误清零前分流完整 raw response，并由同一请求元数据所有者保持 `(port,Tag)` 到最后 native beat 实际发出；受限 application bridge 可选择延后 core complete 握手，但必须单独声明其重生成范围。两种模式不能通过第二张 Tag 表重复分配或提前释放同一身份。

目的侧的完整 Native device边界是下一步：真实TL接收的Request/OrigData转native sender，native实际Completer处理后返回A，再进TL响应路径。不能将源侧 bridge 通过当作已经存在该目的侧接口；两侧接口均闭合后才能声称完整 Native Endpoint 因果桥。

## 5. 可直接分派的验收任务

| 任务 | 必须通过的独立验收 |
|---|---|
| A：native_rx_channel，四 kind | 先旧缺接口红测；公共primitive实际使用；每类完整字段bit边界、valid0 parity、masked/poisoned lane、Auth独立诊断、全credit返回与InitDone隔离；实际receive_channel/KD28 SRAM，1/2/4port，背压/容量/真实退休原VC-Pool对照；控制坏拍无写入，数据坏拍保留且poison |
| B：请求关联/容量，和A并行 | 每port1..4Beat、所有首/尾边界、Read覆盖尾部、不同pool、跨账户消费顺序、容量差一不得提前发布信用；高Tag/source身份/同Tag不同源或port不串扰；真实缺尾/错Offset/错首拍/重复最后等负例，不能只计数 |
| C：role Drop集成 | 当沿错误禁止业务/坏信用计账；TL双角色范围、非TL角色范围、valid0错误与credit多port错误；可靠旧信用记录与不可靠新记录区分；未实现Isolation明确保持开放；实际断开drop/poison/信用gate故障检出 |
| D：Endpoint源侧因果桥 | 真实Native对端sender/connection、真实SRAM、实际core→Switch→远端backend；写后读、4..256B、相同Tag重用、完整Read错误拍、实际backend结果前不得native完成、native完成反压仍能接收已预约结果；不得用预生成Response或DUT内部队列作oracle |
| E：目的侧Native接口、完整保护/RAS | 目的Native backend adapter、逐Beat raw response、poison执行边界、完整控制路径保护、Isolation/ISOLATE/watchdog/管理恢复按各自契约补齐；不得借D的通过移除这些pending功能 |

每个 runner 必须支持新的 `--label`、显式 `--kd28-root`、可移植工程根；保存同份读取的源码/hash、命令、compile/run码与日志。正常数据 oracle 从独立候选/真实backend byte模型产生，接收比较不从DUT保存队列生成expected；native valid是入站事实，实际SRAM出队、返还信用、Tag最后一拍/完成各自独立账本。激励在负沿准备或用沿前快照，posedge计数不得反向改变同沿输入。

必须有实际可编译故障：control错误仍写RAM、仅有效lane参与parity、丢失poison、信用归到错pool、Read覆盖尾部改错Tag、native最后Response前提前释放Tag。反例需由明确checker检出，不以工具失败/未激活变异计通过。统一reset至少在首Req/部分OrigData、部分RdRsp、完成阻塞时测试旧事务取消及同Tag新轮；不得叫独立LinkDown恢复。

## 6. 仍开放且不得猜测的内容

AuthTagParity 分类及两Response表格Driver矛盾、A06响应安全上下文映射、A17交换内部ByteEn错误定位与处置、完整存储/控制路径保护、所有protocol错误的统一恢复策略、poison backend执行语义、INC/Atomic/Vendor/Messages的请求资格和状态路径，均不由本计划关闭。A12已用R041及§3.1.1确认原生ByteEn64保护公式，但不扩展成A17已解决。A19等DL开放项不受此次Native RX计划改写。

本文件足以先实现完整字段保护/真实SRAM接收与请求关联，再按明确子集接入Endpoint因果流。只有正常transport通过时必须继续标注它的局限；只有检测到错误而没有禁止坏业务/正确处置尾部与信用时，不得称为合法恢复。
