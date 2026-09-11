# 最小真实 Read 事务闭环实施计划

> **执行约定：** 后续实施使用 `executing-plans` 按任务推进；每项先建立独立失败检查再实现。本轮只读子任务仅核对规范、契约与RTL并生成本计划，不修改生产RTL或验证脚本，不启动子代理；此限制只适用于本次子任务，不限制root后续按用户授权将独立模型、字段RTL、接收组装等按依赖并行实施。

**Goal:** 在已实测双端TL/DL数字接口上，完成请求发起→真实接收解码→本地读执行接口→真实完成生成Response→发起侧Tag关联与应用完成，取代两侧独立预生成Response流。

**Architecture:** 两端各实例化原有 `tl_tx_prepared`、信用端口、接收SRAM与DL replay；新增小规模事务编码/接收组装/Tag表/读执行适配器。最初只接受一个明确的普通Read子集，保留独立内存模型和端到端scoreboard；下一阶段扩展合法读长度与两种响应模式，原数字链路边界保持显式。

**Tech Stack:** Verilog-2001生产模块、Python独立事务模型和检查器、SystemVerilog集成测试、Icarus与显式授权KD28同步SRAM行为模型。

**Spec:** `specs/private/common.txt`（Common 2.0；私有输入，不复制到交付包）、`specs/requirements.json` R078–R081/R085、`docs/transaction_recovery_plan.md`、本计划所列冻结契约与RTL。

## 全局约束与核对结果

- 完整交付范围仍为 `docs/ip_delivery_plan.md` 的双IP目标；本计划的“首阶段”是工程实施子集，不是标准允许删除其它强制接收能力的产品profile。
- 所有新增生产源文件不带版本号；外部依赖显式传入；新测试使用新 `--label` 保存证据，不覆盖前次结果。
- 本轮只读确认 Common 原始PDF SHA-256 为 `d1431f080621c46b2df9b34bbeb2b7fe7bdc95b14785e717e17687fe37fcc8e6`，文本 SHA-256 为 `15cd742c536e1e701a958db8a04f54666b072b8d95a72a834b0aa7d2c58e3383`，与 `specs/private/inventory.json` / `config/tl_tx_buffered_contract.json` 对应。以下为工程字段映射和摘要，不转载原表正文。
- `docs/specification_issues.md` A05/A06影响认证映射，A09影响部分压缩响应，A19影响线上CRC位序，A21影响完整LLR watchdog。不得从首阶段关闭这些问题。
- 首阶段采用未压缩字段、Auth关闭、单station单端口、双端直连；520-bit本地TL记录及显式CRC-status链路沿用 `docs/endpoint_link_integration_review.md` 的边界。不能把它叫标准640-byte DL framing、数字PHY或互操作。
- 这里提出的握手、表项数、执行器容量和诊断信号是**内部实现选择，待实现任务冻结**，不是额外线上协议字段。完整原生UPLI仍是信用/TDM接口，不把内部ready/valid冒充UPLI。

## 1. 已明确、可以立即实现的首阶段

选择普通Read，CMD=0x03；每笔64 bytes、64-byte对齐，ReqLen=15、ReqAttr=0xff、ReqNumBeats=0；无OrigData。来源和目的PhysAccID保留完整10位，普通Tag保留完整11位；首阶段端口0、VC0、TL POOL=0，ASI=0、MetaData=0作为测试内存接口的实现定义选择。CLOAD=0，CWAY发送0；不使用地址缓存压缩。依据如下：

| 决定 | 已有依据 | 解释与限制 |
|---|---|---|
| Read编码0x03且无请求Data | C §2.7.4.7/Table2-12 p57；`common.txt` 中 `Table 2-12 Commands`；`model/tl/tl_tenure.py:derive_control` | 现有tenure模型也将0x03归为无Data请求；完整Read命令执行逻辑尚无RTL |
| 64-byte对齐、Len=15 | C §2.7.4.4–5 p55、§2.8 p74–75；R080 | 满足4-byte对齐、最大256bytes且不跨256-byte边界；首阶段不覆盖全部合法长度 |
| 首末DWORD全部使能 | C Table2-7 p55、§2.8 p74–75 | Attr=0xff为本子集选择，不推断所有Read固定该值 |
| Tag宽11、按端口唯一、结束前不复用 | C Table2-2 p49、§2.7.4.2 p52、§2.7.5 p62；R078 | 表容量4是实现选择，不能把Tag宽度等同2048并发 |
| ASI/MetaData选0 | C §2.7.4.1 p52、Table2-2 p50 | 两者普通访问语义含实现定义；此处明确为测试内存映射配置，非标准固定值 |
| 未压缩请求/响应 | C §5.9.1–2/Table5-29/30 pp137–139 | 可承载本次合法请求/响应，发送侧不需要猜测A09格式 |
| 单Beat响应 | C §2.7.8 pp71–72、§2.8 p74；R079 | 单Beat事务在两种UPLI响应模式下相同；不能由此删除后续多Beat接收支持 |
| 响应Tag与目的ID | C Table2-15 p62、Table5-30 pp138–139 | TAG=请求TAG，响应DST=请求SRC；响应SRC仅用于调试，不能加入功能关联键 |
| 成功/地址译码错误状态 | C §2.7.5.1/Table2-16 pp64–65；R081 | OKAY=0，DECODE ERROR=3。地址不在本地测试memory映射时仍回复一个完整beat及LAST，不能静默丢请求 |
| 应答必须可接收 | C §2.7.8 p71；`common.txt` 的 `sink` 规则 | 发出请求前保留本地结果存储；接收应答不依赖先完成另一请求 |

选择首阶段成功数据为完整64-byte内存行；内存BFM使用明确的4KiB测试地址空间，生产读执行器接口仍传57-bit地址，越界或高位非零地址返回DECODE ERROR，禁止截低地址后产生别名。4KiB是测试配置，不是UALink寻址能力上限或系统内存模型声明。

两端允许各4个不同Tag outstanding，读执行器可变延迟但首阶段按请求顺序完成。来源Tag使用0、1、1023、2047等稀疏值，不能只用低两位索引。两端同时发读，以证明Response确实从各自收到的请求和内存返回产生。

## 2. 首阶段字段映射与来源

下列位号相对于单个字段最低位。源全文为 `specs/private/common.txt` 的同名章节/表；参数通过完整宽度接口传递，不从现有随机fixture的数值推断协议。

| 未压缩Request字段 | 位段 | 本阶段来源/值 | 规范来源 |
|---|---|---|---|
| FTYPE / CMD | [127:124] / [123:118] | 1 / 0x03 | C Table5-29 p137；CMD另见Table2-12 p57 |
| VCHAN / ASI | [117:116] / [115:114] | 配置VC0 / 测试ASI0 | Table5-29；ASI语义另见§2.7.4.1 |
| TAG / POOL | [113:103] / [102] | 完整应用Tag / TL VC信用即0 | Table5-29；POOL与UPLI信用独立 |
| ATTR / LEN / METADATA | [101:94] / [93:88] / [87:80] | 0xff / 15 / 测试0 | Table5-29；Table2-7、Table2-2 |
| ADDR | [79:25] | req_addr[56:2] | Table5-29；解码后补低2位00 |
| SRCACCID / DSTACCID | [24:15] / [14:5] | 10-bit本地ID / 10-bit对端ID | Table5-29 |
| CLOAD / CWAY / NUMBEATS | [4] / [3:2] / [1:0] | 0 / 0 / 0 | Table5-29；Read NumBeats=0另见Table2-2 p50 |

请求编码器先每个Control只放一个128-bit字段于低位，其余sector填NOP；这符合 `config/tl_control_partition_contract.json` 的自然对齐完整字段接口。字段位置提取器应处理实际合法起点，不能把“低位一个字段”的首发策略写成接收器通用限制。

| 未压缩Read Response字段 | 位段 | 本阶段来源/值 | 规范来源 |
|---|---|---|---|
| FTYPE / VCHAN | [63:60] / [59:58] | 2 / 配置VC0 | C Table5-30 p138 |
| TAG / POOL | [57:47] / [46] | 请求TAG / TL VC信用即0 | Table5-30 |
| LEN / OFFSET | [45:44] / [43:42] | 0 / 0 | Table5-30；首阶段完整一beat |
| STATUS / RD-WR / LAST | [41:38] / [37] / [36] | 执行返回状态 / 1 / 1 | Table5-30；状态Table2-16 |
| SRCACCID / DSTACCID | [35:26] / [25:16] | 请求DST（调试）/ 请求SRC（路由） | Table5-30 pp138–139；Table2-15 p62 |
| RSPTYPE | [15:14] | 00，普通unicast | Table5-30 p139、Table2-15 p63 |
| SPARE | [13:0] | 本地编码器发送0，不用作关联信息 | Table5-30 p139标为未分配；本计划不由此定义新的非零接收错误策略 |

Response数据是512 bits，按低/高256-bit分送 `tl_tx_prepared.i_data0/i_data1` 对应的有序半Flit流，不能在缺失后半数据时宣布事务完成。Auth关闭时不生成标签，鉴权接口固定零；RSPTYPE=00的非认证格式已有定义，因此A06不阻止这一非认证子集。

## 3. 复用模块与明确缺口

| 现有资产 | 直接复用内容 | 不能据此声称已经具备 |
|---|---|---|
| `rtl/tl/tl_tx_prepared.v`、`tl_prepared_partition.v`、`tl_tx_buffered.v` | 原子源组捕获、容量分组、真实两类SRAM/打包、部分Data入队确认 | 从完整请求/内存完成生成标准字段 |
| `rtl/tl/tl_control_decode.v`、`tl_control_tenure.v` | 完整字段起点、FTYPE结构、Data/BE tenure | TAG/地址/操作语义解析与事务关联 |
| `rtl/tl/tl_credit_admitted_port.v` | 唯一发送/接收字段准入与TL账本 | Originator outstanding Tag表、请求完成判定 |
| `rtl/tl/tl_receive_credit.v`、`tl_receive_storage.v` | 完整600-bit SRAM字、类别、释放元数据和真实FC返回 | Control拆成描述符、Data两半组装、请求到内存执行 |
| `rtl/dl/dl_replay_data_port.v`及子模块 | 实际DL正常/重放/去重与SRAM | 标准TL↔DL framing、CRC、完整watchdog/复位恢复 |
| `rtl/upli/upli_receive_channel.v`、`upli_burst_sender.v`；对应config契约 | 原生UPLI信用/接收存储、Request/OrigData burst所有权基础 | 当前Request payload仍为不透明字段；没有完整Read Response调度器/Tag关联器 |
| `model/tl/{credit_context,receive_context,tl_sequence,tl_tenure}.py` | 独立Flit类别/tenure/信用释放检查 | 独立按Tag/地址/beat完成与内存字节oracle |
| `verification/endpoint_link/` | 双实际TL/DL和SRAM、独立源/重放/交付检查、实际接线故障 | 现有Response是独立fixture，不能用它证明completer行为 |

必须新增的是事务层职责，不能继续用扩大既有fixture矩阵代替实际接收、内存完成和Tag关联。

## 4. 拟新增内部接口及所有权

以下是供实施任务冻结的本地接口；全部`valid && ready`在同一时钟沿转移所有权，valid保持时字段稳定。端口/ID/Tag宽度来自前述UPLI定义；slot和ready是实现元信息，不上链路。首阶段同一同步低有效reset时期，不能把此reset策略推广为Link Down恢复。

| 接口 | 内容与方向 | 容量/责任 |
|---|---|---|
| 应用读请求→Originator | `read_valid/ready`, `port[1:0]`, `tag[10:0]`, `addr[56:0]`, `len[5:0]`, `attr[7:0]`, `dst[9:0]` | 首阶段约束port=0/Len15/Attrff/addr低6位0。配置提供本地SRC、VC、ASI、Metadata；非本子集输入用本地诊断拒绝，不假称协议定义的远端错误策略 |
| Originator保留表 | `(port,tag)→{dst,addr,len,attr,sent,received_mask,result,status}` | 精确4个条目，保留完整Tag；请求接纳时保留条目和512-bit结果空间，实际TL Header消费后标sent；应用接纳完成后才允许本地再次分配该Tag |
| TL接收记录→事务组装 | 现有 `o_read_valid/o_read_flit[511:0]/o_read_msg[1:0]/o_read_classes[5:0]/o_read_releases[79:0]` 和 `i_read_ready` | 一次原子捕获整个600-bit记录到有界holding word，随后按类别/字段推进；只有保证完整保存后才能让原SRAM退休，释放向量继续交原FC路径，不另造归还 |
| 解码读请求→Completer | `request_valid/ready`, `ingress_port[1:0]`, `tag[10:0]`, `src/dst[9:0]`, `addr[56:0]`, `len[5:0]`, `attr[7:0]`, `vc[1:0]`, `asi[1:0]`, `metadata[7:0]` | 地址/Tag/源目的来自实际收到的字段。4个事务描述符和4个512-bit执行结果槽；入口资源不足只能背压本地消费者，不可丢已接纳请求 |
| Completer→内存服务 | `mem_read_valid/ready`, `slot[1:0]`, `addr[56:0]`, `len[5:0]`, `attr[7:0]`, `asi[1:0]`, `metadata[7:0]` | slot只关联本地4个在用描述符；57-bit地址不可截断；先保留返回存储再请求执行 |
| 内存服务→Completer | `mem_result_valid/ready`, `slot[1:0]`, `data[511:0]`, `status[3:0]` | 首阶段支持0/3，错误也返回完整数据字（测试填0）；尚不生成DataError/Poison。内存服务可以BFM实现，但实际RTL必须只由该握手触发Response来源 |
| Completer→现有发送器 | `i_source_valid[1] / i_source_control[511:256] / o_source_captured[1]`及Response类Data接口 | Header与两半Data均来源于同一个已保存执行结果；尊重 `o_data_accepted` 的部分接纳。Header捕获不能提前丢Data，也不能重复提交Header |
| 响应组装→Originator | `rsp_valid/ready`, `ingress_port[1:0]`, `tag[10:0]`, `dst[9:0]`, `offset[1:0]`, `last`, `num_beats[1:0]`, `status[3:0]`, `data[511:0]`, `data_error` | 首阶段从完整Response字段和两个真实Data半Flit组装；功能匹配不使用调试SRC。验证本地DST、活跃且已发送Tag、长度/offset/LAST、重复beat |
| Originator→应用完成 | `complete_valid/ready`, `port[1:0]`, `tag[10:0]`, `status[3:0]`, `data[511:0]` | 成功才提交有效数据；错误不更新应用成功数据存储。首阶段只在完整两半Data、offset0/LAST1收齐后完成一次 |

Request与Response描述符、完成结果存储相互独立。两端各最多4个在途请求的测试域内，为每个已发Tag预留独立应答空间；Completer也为已接纳请求预留执行结果空间。这样接收Response不需要先消费另一请求。不能在请求队列已满时让同一个holding word无条件挡住所有响应；必须测试lower新Request/upper旧Response Data的合法混合记录，并记录两类消费进度。若实际共享FIFO架构仍出现循环等待，应在此接收分流边界修复，不能增加无依据的线上信用或无限队列掩盖问题。

## 5. 分阶段任务与验收

以下文件都是计划新增，不表示已存在或已运行；本轮不创建对应RTL、契约或测试脚本。

### Task 1：独立事务oracle与字段编码/解码

**Files:** 新建 `config/endpoint_transaction_contract.json`、`model/ualink/endpoint_transaction.py`、`rtl/endpoint/endpoint_read_encode.v`、`rtl/endpoint/endpoint_response_encode.v`、`verification/endpoint_transaction/test_model.py`、`verification/endpoint_transaction/run_fields.py`。

- [ ] 先将第1–4节写成契约，分别标注normative字段与local实现参数；核对每个位段有来源。
- [ ] 独立测试使用明确的原始期望字段位段，而非调用编码器再用它自己解码。测试Tag=0/1/1023/2047、10-bit ID边界、地址bit56及低位补00、Read Cmd和RSPTYPE；交换SRC/DST、截断Tag/地址、改变RD-WR都必须被检出。
- [ ] 模型按 `(port,tag)` 保存请求和独立内存期望，发出前保留返回容量；定义重复活跃Tag、本地非法profile、未知response Tag的诊断，不生成未经规范确认的线上恢复消息。
- [ ] 观察失败后实现两个编码器，并与独立常量向量比较。首阶段Request tenure为0；Response tenure恰为两个D，剩余sector合法NOP。
- [ ] 执行拟定入口 `python3 verification/endpoint_transaction/test_model.py` 与 `run_fields.py --label fields_read`。退出条件为字段全位/边界通过，且至少一项实际字段位修改被独立向量检出；形成源码/输入/结果哈希证据。

### Task 2：实际接收字段分发与响应Data组装

**Files:** 新建 `rtl/endpoint/endpoint_receive_transactions.v`、`verification/endpoint_transaction/run_receive.py`；复用现有TL接收SRAM模块，不修改它的信用语义。

- [ ] 先用人工确定的Control/Data记录构造失败检查：无Data的Read、Response Header+第一Data半、跨Flit第二Data半、空隙、同字新Request+旧Response Data、两个Request字段、接收端有限停顿。
- [ ] 实现600-bit holding word及完整字段提取，分别保存Request描述符和Response组装上下文；仅保存后退休原字一次，不能在消费一半时丢掉另一半。
- [ ] 两个Data半收齐才能发出一份512-bit响应；DataError/Poison在首阶段不接纳为成功，预留明确诊断边界，不把其它Status值等同Poison。
- [ ] 执行拟定入口 `run_receive.py --kd28-root PATH --label receive_read`，对照完整字段、Data和每次实际SRAM退休。实际交换两半Data、提前退休、重复消费均须失败。退出条件包含固定容量下有限背压后排空。

### Task 3：真实Originator/Completer状态与内存接口

**Files:** 新建 `rtl/endpoint/endpoint_read_originator.v`、`rtl/endpoint/endpoint_read_completer.v`、`verification/endpoint_transaction/run_engines.py`。

- [ ] 先测试“没有实际收到请求、或没有收到内存完成时不能生成Response”；用不同Tag/地址和非对称内存数据，防止固定回应或镜像请求伪通过。
- [ ] Originator实现4条完整Tag匹配和请求/结果容量保留；Completer实现实际解码请求捕获、带slot的内存执行和完成缓存。结果保持到Header/Data全部转移，不能仅按Header捕获释放整条执行结果。
- [ ] 用独立字节数组内存BFM可变延迟返回数据；超出4KiB测试映射返回Status3，始终保留完整57-bit地址检查。成功结果来源于被请求地址，不从测试预生成Response读取。
- [ ] 测试Tag提前复用/同低位不同Tag/未知Tag、调试SRC改变、错误DST、错误offset/LAST、内存结果重复slot、应用完成背压；错误不能造成另一Tag的数据完成。
- [ ] 执行拟定入口 `run_engines.py --label engines_read`。退出条件：每个实际请求仅执行一次，每个实际内存结果仅生成一条Response，应用完成一次；成功数据和错误状态分别匹配独立oracle，所有本地容量守恒。

### Task 4：接入双实际TL/DL，删除Response fixture依赖

**Files:** 新建 `verification/endpoint_transaction/run_link.py`、`verification/endpoint_transaction/check.py`；复用 `verification/endpoint_link` 的链路约定和实际模块连接，不复制旧检查器当作事务oracle。

- [ ] 从实际Originator发起读；只允许Completer内存完成驱动Response源。任何fixture提供Response Header/Data的旧路径必须从本场景断开。
- [ ] 两端各4个Tag并发，双向相同Tag但不同地址/数据；使用有限DL预约停顿、接收退休停顿、内存延迟和应用完成停顿。记录请求接纳、TL发送、DL重放/交付、Completer执行、Response发送、应用完成的独立事件链。
- [ ] 重跑CRC-status错误/丢槽场景；DL replay不能触发第二次内存执行或第二次应用完成。保留已有整520-bit记录、600-bit退休字、信用/重放窗口对照。
- [ ] 实际故障挑战包括回应错误Tag、地址高位截断、未执行先回应、重复响应、Data bit翻转和重放重复执行；要求独立事务oracle失败，不能只有双方共同编码器往返一致。
- [ ] 执行拟定入口 `run_link.py --kd28-root PATH --label actual_read_link`。退出条件：每条成功或错误请求恰有一次正确关联完成，4条容量耗尽时正确背压，释放后可复用Tag；有限停顿撤销后全链路与本地所有队列排空。此时可称“普通单Beat Read的实际事务闭环”，仍不称完整G2完成。

### Task 5：扩展全部普通Read长度与两种响应模式

**Files:** 扩展Task1/2/3的契约、模型、组装/关联器；新增 `verification/endpoint_transaction/run_read_modes.py`，不靠重写已发请求或压缩A09字段扩展。

- [ ] 按R080先建立独立字节掩码和beat oracle：`bytes=4*(len+1)`；`beats=ceil(((addr mod 64)+bytes)/64)`；4-byte对齐且`(addr mod 256)+bytes<=256`。例addr60/8bytes必须两beat；单DWORD只使用Attr低4位。
- [ ] 先让Completer选择规范允许的Single-Beat模式，响应每beat LEN=0，OFFSET标记该beat在原事务的位置；可按测试选择置换offset、插空和交织不同Tag；LAST跟随最后发出的beat，不强制最大offset。
- [ ] Originator按请求预期覆盖beat mask和实际LAST同时决定完整性；`NumBeats=0`不释放整笔Tag。Status全beat一致，错误仍完成全部beat，数据错误与普通错误状态分离。
- [ ] 增加Multi-Beat输入接收与对应UPLI重新生成验证：TL字段LEN与后续2×(LEN+1)个Data半Flit对应；原生UPLI需连续端口slot、offset升序和末beat LAST。Single/Multi输入都经过真实接收SRAM，不能只测模型。
- [ ] 执行拟定入口 `run_read_modes.py --kd28-root PATH --label read_modes`，覆盖1–4beats、addr0/4/56/60、长度和256边界、所有offset置换及低offset LAST、状态一致与错误整笔完成。新实现同时补原生UPLI Read Response发送/接收时序、信用和parity后，才能扩大为相应UPLI Read能力声明。

## 6. 真正阻塞的输入与无需等待的工作

| 项目 | 当前是否阻塞Task1–4 | 处理 |
|---|---|---|
| 普通未压缩Read/Rsp字段、Tag/地址规则 | 否，现有正式文本完整 | 按表映射实现并先做独立原始向量 |
| 完整事务/内存内部接口 | 否，属于尚未实现且本计划具体定义的实现契约 | Task1冻结本地握手/容量，Task3实际实现；不要误报规范缺失 |
| ASI/MetaData、本地内存一致性 | 测试profile可明确选择；不能据此声称真实SoC I/O一致性 | 传递字段，测试采用明确内存模型；产品集成需接系统内存语义 |
| Auth字段/响应认证 A05/A06 | 不阻塞Auth关闭子集；阻塞完整安全路径 | Auth关闭仍保留完整ID/Tag，不丢弃最终能力 |
| 压缩响应 A09 | 不阻塞未压缩发送与首阶段单Beat闭环 | 产品完整压缩接收能力另行关闭，不把未压缩子集当豁免 |
| CRC线上位序 A19、PCS/FEC输入D01 | 不阻塞已定义DL数字事件接口；阻塞标准线协议/PHY | 保持显式CRC-status及520-bit本地适配证据标签 |
| 完整LLR watchdog A21、Drop/Isolation/Link Down竞态 | 不阻塞无reset且有限恢复场景；阻塞完整故障恢复声明 | 后续遵循R087–R092；不能用本轮全局reset清空outstanding当作实现 |
| 多端口/多station/完整排序、写/原子/INC/安全/管理 | 不是本计划首阶段已覆盖项 | 继续完整交付路线，不由Read子集给出全协议符合性结论 |

本轮没有实施上述计划，也没有新事务闭环测试成绩。最近已运行的是 `docs/endpoint_link_integration_review.md` 描述的独立Request/Response流TL/DL集成；它只提供后续Task4可复用的真实链路基础。
