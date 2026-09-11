# upli_endpoint_ip_top 隔离候选

已实现可综合的原生UPLI双角色前端聚合，并实际接入新安装的响应collector。它是完整Endpoint顶层的一部分，不是完整backend/TL/DL Endpoint。`o_backend_implemented=0` 明确保留未实现边界；没有把旧port0事务core接成假执行器，没有制造memory result或应用完成。本轮只写 `build/development/upli_endpoint_ip_top/`，生产源码/库存/现有验证器未改，未提交。

## 实际聚合和唯一所有者

- 两个 `upli_connection_side` 是唯一Originator/Completer连接状态。原生peer req/ack来自外部；TX-connected用于相应RX信用发布，RX-connected用于相应TX信用接收，两者没有交换。
- 一个 `upli_station_tx` 拥有三sender、四credit bank和三发送相位。一个已冻结 `upli_endpoint_native_rx_path` 拥有四真实native保护/SRAM/journal、三接收相位及一个完整request holding。
- 一个实际 `upli_endpoint_response_collector` 拥有Read/Write两个head选择锁。它的consumer port/ready直接驱动原RX；下游只能提供select_valid/port及retire_ready。完整响应tuple、retired和全部诊断公开。没有新增payload FIFO、Tag表或信用发行者。
- 一个双角色 `upli_rx_role_fault_controller` 是唯一Drop/通知所有者。非TL两角色独立；显式C_IS_TL=1时任一fatal扩大两角色。TX调度资格、RX业务资格和collector Stop统一使用它的Drop。共同reset是该保守策略的恢复条件，ack只确认通知。

顶层错误总线的源次序是Req/Data/Rd/Wr，controller次序是Req/Rd/Wr/Data；连线显式重排。控制错误、反向信用错误、Auth/profile、metadata/order/storage/TDM分别归类，data-only只poison不触发Drop。返回信用使用controller独立反向角色映射：Req/Data信用错误属于Originator，不与同名正向Beat的Completer范围混用。真实bank拒绝的信用语义错误也按反向通道送入本地fail-stop政策。

顶层使用四个额外raw credit guard检查未经改写的原始返回组。坏组整组valid和初始化确认资格禁止进入station；公共return adapter为内部实际交付组生成保护码，station内原guard继续检查真实交付值。正常组零新增周期，原pool/VC/num保持；此内部保护层没有新bank/initializer。代价明确为额外4 guard+4 adapter，不能隐藏在结构统计中。不能用station的error反接修改它自己的guard输入形成组合反馈，也不能让“只有诊断”的guard被称为已阻止计账。

bridge的局部错误输出会随Drop取消holding而消失，collector头metadata资格也受RX Drop影响。因此这些**本地结构错误**分别用1位及2位同步诊断桥记录，再交唯一controller扩大角色范围，避免组合反馈。它们自己的模块当沿已禁止坏头退休；全角色扩大晚一个采样沿。原生control/parity和反向credit错误仍直接同沿送controller，不使用该延迟路径。新增三位诊断不是第二Drop或恢复状态。metadata局部策略与规范Control Error分类仍严格区分。

TX远端账户容量和本地RX容量有独立参数向量。完整Port/VC/Pool/Auth/Src/Dst/Tag57位地址及Data/BE/poison保留，未硬限为port0/VC0/pool0。Response collector仅交付原始响应，不匹配Tag、解释ISOLATE或生成应用完成；响应Src仍仅透明调试字段。

## TDD、接线测试与结果

先写接口壳和自检：`red_first` compile0/run1在id5暴露壳缺少健康完整性输出；随后把壳的静态健康输出设为正确无错值，`red_connectivity` compile0/run1在cycle110/id210暴露没有连接/初始信用。实际模块连接在这两个红测之后实现。

TB使用同一top两个角色的外部local loopback，不声称双Endpoint ESE。真实station TX产生完整原生事件，经**test-only一拍同步全字段transport**进入真实RX；reset同时取消transport。最初无延迟loopback把RX组合fault→Drop→同top TX→RX绕成测试环境组合环，Icarus超时，保留 `first_actual` compile0/run124与debug日志。加测试transport后正常；未修改任何生产模块时序，不把此测试线缆当新增UPLI接口周期要求。

独立源账本在实际candidate accepted记录完整staged字段，逐位比较native TX，再按port到达顺序对照实际SRAM head。descriptor期望由原始source Request/Data构造，首次valid即检查齐套和全字段，背压始终保持。collector的首次valid及背压保持用完整Read619/Write101和原port/VC/pool/account对照同一独立来源；selector持续变化，真实collector负责锁住旧头。retired必须等于实际response_valid和下游ready，且直接对应原RX唯一退休。

正常路径另有每通道/port原账户信用journal：只有更早实际head转移可建立返回记录，normal returns必须匹配原pool/VC和数量；最终request_fire不生成第二次信用。数据parity定向场景仍运行全正常账本，证明真正poison、descriptor和信用前进。故障保持阶段使用独立的公开balance/Drop/TX/RX/通知检查，正常流水账本暂停，因此下表heads/returns仅统计正常账本覆盖的epoch，不谎称包括所有故障阶段的物理事件。

最终普通配置 `frozen_matrix`：

| ports | C_IS_TL | descriptor接纳 | 已记账head/returns | descriptor背压周期 | checks | cycles |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 0 | 50 | 301/301 | 861 | 21899 | 1307 |
| 2 | 0 | 50 | 301/301 | 846 | 22018 | 1308 |
| 4 | 0 | 50 | 301/301 | 849 | 22309 | 1310 |
| 4 | 1 (`frozen_tl`) | 50 | 301/301 | 849 | 22303 | 1305 |

四配置compile/run/g2001/无豁免Verilator `-Wall`/Yosys全部返回0。实际层级断言：1 station TX、4 bank、2 connection、1 role controller、1 RX path、4 native RX、1 request bridge、1 response collector、20 receive FIFO/storage、8 credit guard、8 credit adapter、36公共parity；无latch。PORTS1映射250个KD28功能SRAM单元，仅是功能结构，不是面积/STA/PPA结论。

每个配置含两轮24请求混合流及两笔定向请求。混合流每轮8 Read、8普通Write、8 Full，OrigData40拍、RdRsp60拍、WrRsp24拍；高Tag、地址bit56、全Auth/Src及跨VC/pool字段都由实际TX/RX传输。Read示例LEN63，普通Write64/192B，Full128/256B；不称全4..256B几何交叉。已有leaf/bridge/collector单位测试是其他独立证据。

定向检查还包括：

1. 原生OrigData data parity错误保持原512数据和64BE并置本拍poison，完整descriptor正常前进，两个角色都不Drop。
2. 一笔真实Request先花掉pool信用，再注入坏valid parity的伪返回。原始guard报告且Originator作用域Drop；下一沿实际bank余额完全不变。非TL为role01，TL为11；原始错误没有被内部重编码隐藏。
3. 真正Request control parity坏拍触发Completer作用域Drop，bad Req不得写入；非TL同一真实Originator仍尝试发送后续好Req，已Drop的Completer不得接纳。继续呈现真实WrRsp候选，受影响TX不得发出。ack之后Drop保持。
4. 在完整descriptor背压及其它RX有积压时统一reset，随后同Tag新轮恢复；最后再reset清所有故障和transport并以同Tag发送一个真实Read。

实际源码注错均compile0/run1，基线文件未改：

| 最终label | 实改内容 | 首次失败 |
|---|---|---|
| `frozen_credit_bypass` | Req坏信用绕过valid过滤，内部保护仍正确重生成 | id223/cycle1229，实际bank错误增加 |
| `frozen_scope` | 非TL误强制TL扩域 | id222/cycle1229，反向信用角色范围错误 |
| `frozen_tx_drop` | Completer TX漏接Drop资格 | id226/cycle1266，真实WrRsp候选仍发出 |
| `frozen_rx_drop` | Completer RX漏接Drop | id230/cycle1261，历史Drop后好Req仍入SRAM |
| `frozen_collector_payload` | collector的Read完整payload高位被清零 | id244/cycle28，独立完整响应tuple不符 |

历史测试修正保留：`cable_actual`各工具和仿真实际0，但runner仍沿用了20个parity的旧结构期望，因此总结果false；改为实际36及完整唯一层级后通过。`faults_actual`的单请求task曾多保持一个周期导致重复accepted；`causal_faults`在故障阶段后的初始化期间暂停了信用账本。两者都仅修TB，改用独立真实accepted计数并恢复初始化账本；不包装成生产RTL修复。

## 重放与交接

```sh
python3 build/development/upli_endpoint_ip_top/run.py --label NEW --kd28-root /explicit/OverFlow --static
python3 build/development/upli_endpoint_ip_top/run.py --label NEW_TL --kd28-root /explicit/OverFlow --ports 4 --tl-mode 1 --static
python3 build/development/upli_endpoint_ip_top/run.py --label NEW_FAULT --kd28-root /explicit/OverFlow --ports 1 --fault collector_payload
```

输出候选 `evidence/LABEL`，拒绝覆盖旧label。工程根按runner位置解析；冻结RX path依赖从相邻候选读取，其完整SHA同样入快照，安装时必须一起安装该RX path或相应调整生产布局runner。其它依赖读取生产RTL；KD28显式路径及既有manifest五份SHA必须匹配。每个source只读取一次供快照和source hash，保存实际命令、返回码、日志、hierarchy和artifact SHA。外部cells仅为strictlint按原module body拆成同名文件，没有语句修改或waiver；不可把外部功能源快照作为项目自有交付发布。

本模块skill artifact 0 errors/10模板/style warnings；真实全层级EDA另行通过。全局skill安装检查仍exit1，缺少既有 `/home/ljy/.codex/skills/agents-md-generator/scripts/manage_docs.py`，没有宣称该门限通过。

## 下一批真正Endpoint缺口

后续生产增量已加入一个 `upli_native_rx_burst_monitor`，新增同沿显式
`i_req_class_known/i_req_has_data` 分类边界，并把完整 burst 诊断送入本模块原有的
唯一 role fault controller。它没有增加 Drop、TDM 或信用所有者；详细六配置、
54 次异常和三项接线故障证据见
[`upli_endpoint_burst_fault_integration_review.md`](upli_endpoint_burst_fault_integration_review.md)。
独立 `upli_endpoint_request_context` 也已实现并与真实 request bridge 联动验证，
但尚未实例化到本顶层或连接 backend，见
[`upli_endpoint_request_context_execution.md`](upli_endpoint_request_context_execution.md)。

可直接复用但尚不能无损相接的现有模块：`endpoint_transaction_core`/formatter共享Tag结果槽，read/write completer真实memory issue/result因果，以及TL prepared/data sender。它们已有本地应用profile和字段限制，不能把这个top的descriptor ready绑高后假装接入。

建议下一批有界实现：

| 建议候选 | 真实职责与依赖 | 最小验收 |
|---|---|---|
| `upli_endpoint_request_context` | 已形成独立生产模块：实际descriptor fire预约保存station/port/Tag/Src/Dst/VC/Auth及全部几何/poison；token是本地槽，不能重分配网络Tag；尚待实例化到本top | 多port配置、满表holding、旧token拒绝、背压字段稳定和reset取消已验证；backend最终release所有者仍开放 |
| `upli_endpoint_backend_adapter` | 在真实context槽下接已有read/write executor或外部backend二选一；相对BE到区域BE按真实地址映射；request/issue/result是三个事件 | 全4..256B普通几何、zeroBE仍执行一次、实际result才响应、端口/身份/poison不丢；不把ReqAuth当RspAuth |
| `upli_endpoint_response_context` | collector retired只能进入真实Tag/转发资源；保留raw错误数据/Num/Offset/Last；控制事件单独处理，不从已mask应用结果逆构原始数据 | 五状态完整N拍、single乱序/交错、重复/未知Tag、ISOLATE单独路径、只在真正最后交付时释放原上下文 |

这些是后续建议稳定名，并非本轮已存在实现。仍缺完整TL/DL native桥、Auth验证、Isolation/dummy/watchdog、CSR/RAS固件策略和独立LinkDown/epoch恢复；当前TL参数仅证明本front end的角色扩域，不代表TL/DL全流量Drop已闭合。前端本轮完整传输对照不能称完整Endpoint因果事务闭环。

生产布局命令（从任意cwd使用绝对runner路径亦可）：

```sh
python3 verification/upli_channels/run_endpoint_ip_top.py --label NEW --kd28-root /explicit/OverFlow --static
python3 verification/upli_channels/run_endpoint_ip_top.py --label NEW_TL --kd28-root /explicit/OverFlow --ports 4 --tl-mode 1 --static
```

生产runner采用 `ROOT=Path(__file__).resolve().parents[2]`，全部RTL从ROOT/rtl/upli读取，结果在ROOT/build/verification/upli_channels/endpoint_ip_top/LABEL；不依赖build/development。此发布布局仅作路径/语法适配，由root安装后实测，本候选未冒称已重放发布布局。
