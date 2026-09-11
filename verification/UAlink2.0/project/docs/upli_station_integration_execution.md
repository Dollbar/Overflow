# UPLI station TX 集成实施契约

本轮只读审查与计划，基线 `273998b`；不增加 RTL，不将候选或计划标成已完成。下一轮按本文件逐任务执行 TDD，适用 `executing-plans` 与 RTL 技能；各任务可按依赖并行，不限制 root 已获授权的子代理调度。目标是把真实四类 TX 字段层接到有信用、连接和 TDM 所有权的发送路径，并为完整 station 的 RX、事务与恢复留下明确边界。

技术范围为同一 UPLI 同步域内 Verilog-2001、已有实际 credit/SRAM 模块、本地 Icarus/Verilator/Yosys 与独立 Python 事件模型。没有器件实现、STA 或认证目标。本文件的 bundle、模块名、队列策略与调度吞吐约定均为本地实现契约；原生信号宽度、连接/信用和传输规则以 Common Rev 2.0 为依据。

## 来源与当前实际边界

| 来源 | 对本计划的约束 |
|---|---|
| Common §2.5 pp.41–42；`docs/upli_model_contract.md` 的 TDM 小节 | station 端口数 1/2/4；Req/OrigData 共相位，RdRsp 和 WrRsp 各自独立相位；各相位首次真实有效事件建立，空周期继续轮转；信用返回不受 TDM 限制 |
| Common §2.6 pp.43–45；`specs/requirements.json` R006–R014 | 四通道分别有各 port 的 VC0..3/pool 五账户；沿前信用准入、初始化连续确认、原账户归还；UPLI 与 TL 信用环独立 |
| Common §2.7.4/Table 2-2 pp.49–52；`docs/upli_request_channel_execution.md` | 完整 Request 字段及保护组；Tag 与请求类别、身份不能在 transport 中截断 |
| Common §2.7.5/Table 2-15 pp.62–65；`docs/upli_read_response_channel_execution.md` | 每 RdRsp 同时有 512bit Data；完整控制 48bit；两响应模式、错误完整返回及 Src 仅调试语义 |
| Common §2.7.6/Table 2-18 pp.66–68；`docs/upli_write_response_channel_execution.md` | WrRsp 为单 Beat，控制 42bit 与 AuthTag64，独立发送相位 |
| Common §2.7.7/Table 2-21、§2.7.8 pp.69–72；`docs/upli_orig_data_channel_execution.md` | Req/首 OrigData 同沿，发送前具有整笔信用，尾部连续占本 port 时隙；Read 允许覆盖既有尾部 |
| Common §3.1.1–3.1.2 pp.85–86；`docs/upli_parity_execution.md` | valid parity 每周期检查，完整保护组不能按无效 lane 遮蔽；发送重算不是接收校验或恢复 |
| Common §4.1–4.3 pp.101–104；`config/upli_connection_contract.json` | 共同同步 reset、四握手电平与两个方向资格；已有连接承诺保持到 reset |
| `specs/requirements.json` R077–R084、R016/R018 | 两响应模式、完整错误数据、最后 OrigData 后下一周期才可发 WrRsp、跨通道前进、Tag 退休、reset 清理事务和压缩上下文 |

本轮查阅的生产 `rtl/upli/upli_station_port.v`、`rtl/station/ualink_station.v` 与 `rtl/upli/upli_tdm_scheduler.v` 仍为 generic 未实现壳。实际 Req/OrigData 传输已在 `rtl/upli/upli_request_data_sender.v` 内：一个 `upli_burst_sender`、一个共同 burst/TDM 控制、两个 credit bank，再连接 Request 与 OrigData typed leaf。不得因存在 scheduler 壳而另建第二套 Req/OrigData 相位。

Read/Write Response 当前候选是纯组合 typed TX leaf，接口由各自 execution 文档冻结；不依据候选单元通过推定已存在 Response sender。两个 leaf 的 `i_rstn` 与实际发送状态共 reset、`o_valid=i_rstn&&i_valid`、idle 所有字段清零；有效错误状态下保留实际字段和 Data。它们没有 clk、ready、信用银行或接收端。

`upli_receive_channel` 已有每账户实际 SRAM FIFO、初始化与归还队列，保存 opaque payload 和原 VC/Pool；它不检查原生 parity、TDM、命令、Response 模式、Tag 或恢复。其依据为 `config/upli_receive_channel_contract.json`、`upli_credit_return_contract.json`、`upli_credit_initialization_contract.json`。返回队列与 initializer 已包含在 receive_channel 内，station 不得再次串接一组导致重复归还。

## 角色、连接与资源所有权

一个物理 UPLI 单侧的角色必须明确。Originator 侧 TX Req/OrigData、RX RdRsp/WrRsp；Completer 侧 RX Req/OrigData、TX RdRsp/WrRsp。四种 TX 的可复用聚合只是两角色发送组件集合，不代表一个单侧电气接口同时拥有双方所有信号。

每个真实侧实例化自己的 `upli_connection_side`，显式接外部 peer Req/Ack；不能在 station 内制造假对端来强置 connected。若测试同时实例化双方，双方控制器使用同一时钟/reset 并按真实外部连线交叉。关系固定为：

| 本侧消费者 | 接入本侧 connection 输出 |
|---|---|
| 本侧 TX bank 的 `i_credit_connected` | `o_rx_connected`，信用从对端返回 |
| 本侧 RX receive_channel 的 `i_credit_connected` | `o_tx_connected`，本侧向对端发布/归还信用 |
| 所有发送/接收 Beat 的 `i_beats_connected` | `o_beats_connected` |

`i_ready` 是建连前能够承担已声明接收资源的能力承诺，不是任一 native Beat 的 ready。它不能随队列拥塞撤销已建立连接。发送器无条件接收合法信用返回，不把候选停止、输出拥塞或应用 complete_ready 作为返回信用 enable。

一个完整两角色 TX 聚合含四个账户银行、三个相位：Req/OrigData 共享现有相位与完整尾部预约，RdRsp 和 WrRsp 各一个独立 bank/phase。每个实际 Beat 只扣其本通道一个信用；RdRsp Data 不扣 OrigData 信用。多拍发前检查整笔信用并保留尾部所有权，每拍实际发出再扣账。禁止使用同沿新信用/新 InitDone 作为当前准入依据，保持现有保守银行语义。

统一 reset 同时取消 bank、相位、候选/尾部暂存、RX 所有权、归还元数据与 Tag 事务，禁止旧完成泄漏；接入 TL 后还须清理对应地址压缩缓存。TX leaf 不可由独立 reset 截断已经扣账的实际 Beat。统一 reset 验证不能代替独立 LinkDown、Drop、Isolation 或 DVFS；后者不能用 UPLI 全 reset 冒充合法恢复。

## 冻结本地字段容器与发送入口

下表容器只用于模块连接，不是新增线上格式。原生有效、Port/VC/Pool 及 parity 均继续独立连接，不做 TL 128/256bit header 替代。收到的完整保护必须在可信存储前检查；下面 payload 不包含保护码本身，后续 RX 实现仍需定义连续保护覆盖，不能借此表声称完成 SRAM/RAS 保护。

| 通道 | 除 Port/VC/Pool 外的 payload（高位到低位） | 位数 |
|---|---|---:|
| Request | `{ASI2,AuthTag64,Src10,Dst10,Tag11,NumBeats2,Addr57,Cmd6,Len6,Attr8,Meta8}` | 184 |
| OrigData | `{Data512,ByteEn64,Offset2,Last1,Error1}` | 580 |
| Read Response | `{AuthTag64,Src10,Dst10,Tag11,NumBeats2,Data512,Status4,Offset2,Last1,DataError1,TypeInfo2}` | 619 |
| Write Response | `{AuthTag64,TypeInfo2,Tag11,Status4,Src10,Dst10}` | 101 |

RX 对应 `C_PAYLOAD_WIDTH` 可取 184/580/619/101；receive_channel 另保存原 VC2/Pool1，port 由实际账户选择确定。RX 的 payload 原子接纳、原账户元数据与实际消费必须同一事件，不能只保存数据而从后续候选重取 Tag/VC。

Req/OrigData 沿用已存在 wrapper 全部端口。候选 `request184/data2048/byte_enable256/error4`，最低片段为相对 Beat0；`has_data`、`num_beats` 和原生 Cmd/NumBeats 必须在发前一致。ByteEn256 为四组自然 Beat 的 lane mask；Endpoint 的区域 BE256 必须根据地址对齐转换，不能直接逐位硬接。当前 wrapper 没有 `authorization_active` 输入，AuthTag 只是透明透传；未授权 AuthTag=0 由候选资格层保证。早期 Request execution 的授权清零描述已修正：当前 wrapper 仍不承担该功能。

建议直接冻结下一批 sender 接口如下，局部所有权事件统一叫 `o_candidate_accepted`，语义是本沿实际首 Beat 发出，不是先行 buffer capture：

- `upli_write_response_sender`：`i_clk/i_rstn/i_credit_connected/i_beats_connected`；`i_candidate_valid/port[1:0]/vc[1:0]/pool/payload[100:0]`；一个完整原生信用返回组；输出 accepted、完整 WrRsp typed 字段/parity、真实 balances/init/error/tdm_known/tdm_port。上游候选保持到 accepted，发送器无需新增 payload 队列；无信用和非本 port 时隙时不接受。
- `upli_read_response_sender`：同样域/连接；`i_candidate_valid/port[1:0]/vc[1:0]/pools[3:0]/payload[2475:0]`，低 619bit 为 Beat0，其后为三个可能尾部；一个完整 RdRsp 信用返回组。输出 accepted、完整 RdRsp typed 字段/parity、balances/init/error/busy[3:0]/tdm_known/tdm_port。首 payload 的 NumBeats 位 `[523:522]` 唯一决定此候选 N，不另造重复的线上长度字段。

Read 首 NumBeats=0 时仅接纳一个 single Beat，保留该 Beat 任意 Offset/Last；不得把 Last=0 的 single Beat 当成缺尾部、或把 Last=1 当作最大 Offset。可在后续同 port 时隙选择其他 Tag，再回来继续原 Tag。首 NumBeats=1..3 时以完整 staged multi 候选接纳 N=NumBeats+1 拍：所有有效 payload 的 NumBeats、Tag、Dst、TypeInfo、Status 与 VC 上下文一致，Offset=0..N-1、只有末 Last=1，Src 仅供调试，不参与功能准入或跨 Beat 一致性检查；Src/AuthTag/DataError/Data 各拍完整保存。发前检查这些局部几何前提，非法候选不接受、不扣账并产生本地诊断；保留编码的合法性判断归事务资格层。未声明尾部不参与有效几何判断或信用预约。

Read multi 在开始前按 pools[0..N-1] 对 VC 与 pool 分别计数、检查全部沿前容量并锁定本 port 尾部；真实发送时逐拍取所保存 payload/pool。相同 port 有 multi 尾部时不接受新的响应候选，最后尾部沿也可保守不覆盖；其它 port 可并发交错。空周期不停止已建立的 RdRsp 相位。Single 候选只扣一信用；multi 完整 staged 是为履行连续时隙的本地微架构，不是要求所有 UPLI 产品必须整笔缓存。

所有 sender 使用相同参数形状：`C_NUM_PORTS=1/2/4`、`C_CREDIT_WIDTH=3..16`、`C_CAPACITIES[C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0]`、`C_INIT_COUNT_WIDTH/C_INIT_CYCLES`；与现有 bank 原端口参数一致。Read/Write bank 分别接自己的真实接收容量配置，不能沿用另一通道默认值当成资源声明。

## 信用保护与完整 station 接收依赖

每通道返回总线固定为 `CreditVld4,Pool4,VC8,Num8,InitDone4`，另外 valid parity1、credit parity1。公共 `upli_parity` 位13保护全部 valid4，每周期检查；位14保护完整 Pool4/VC8/Num8，任一 valid 时检查，不遮蔽未激活 port。InitDone4 不属于这两个保护集合。

下一批 `upli_credit_guard` 只提供无状态完整返回组校验、原始事件诊断与同沿完整性结果，实例化公共 primitive，不复制 XOR。`upli_credit_return_adapter` 可把 receive_channel 已合并的注册信用输出接到公共生成器并直接输出；不得再寄存一拍、加 ready 或按 TDM 过滤。guard 的分类结果及 bank 的非法/溢出诊断必须保留到 station 的故障所有者；不能将错误输入重算 parity 后交 bank。正常 TX 总装的初版只验合法信用路径及错误准确上报，受损信用抑制、已有预约尾部处置与 Isolation 状态转移必须另行冻结后才宣称错误后可继续运行。

真正替换 `upli_station_port` 壳至少还需：按角色实例化两入站 receive_channel、完整 native 字段/parity检查、三相位接收观察（Req/OrigData 共一相位）、Req/OrigData配对和连续尾部验证、Read两模式/Tag关联、返回信用保护、命令资格、有效保护的存储延续、控制错误隔离及 reset 全所有权协调。`upli_station_tx` 的三 sender 通过不关闭这些职责，也不关闭 `ualink_station` 的 bifurcation、station 身份和速率管理。

## Endpoint 接入的精确缺口

当前 `ualink_endpoint_top` 的 TRANSACTION_MODE 路径是应用请求预约接口到 `endpoint_transaction_core`，再直接驱动 `tl_tx_prepared` 的两类控制源/半 Flit Data；RX 来自真实 TL flit/600bit SRAM 读接口。它没有原生 UPLI Req/RdRsp/WrRsp/OrigData、连接或四通道信用端口；core 实例把 formatter 的 `NUM_PORTS` 固定为1。现有 ESE 事务回归因此不证明 Native station 总装。

下一阶段需要分别设计两个桥接职责，不能将 accepted、source_captured 和 header_taken 短接：

1. `upli_endpoint_request_adapter`：从实际 Native RX 保存队列取得完整 Request 与匹配 OrigData，先预约完整本地事务/数据容量，再向现有普通 Read/Write 事务入口提交。Req 与首 Data 同沿及 Read 覆盖尾部必须被 RX 保留；不能把无原生 ready 的 Beat 直接接到可背压的 app request。Native FIFO 何时退休取决于实际复制/转移了全部保存信息；该时刻释放 UPLI 信用，与下一级 TL 实际接纳时扣 TL 信用独立。原 Cmd/Type/Tag/身份/授权上下文的所有者要保留到响应，不允许把再次经过 formatter 的本地 Tag 预约当作新线上事务。
2. `upli_endpoint_response_adapter`：从真实事务/接收层取得逐 Beat Read 与 Write Response，映射完整 type/status/dst/tag/vc/auth/data_error，再送对应 response sender。现有 `o_complete_data_full2048` 是按应用 mask 处理后的整笔完成，错误数据已清零，缺少原生逐 Beat AuthTag/TypeInfo/Src/VC/Pool/DataError 与任意 single Beat 顺序；它不能直接冒充完整 RdRsp。需从尚未丢弃原生信息的事务边界建立明确接口或增加保存上下文，避免逆向猜测被压缩/屏蔽字段。

现有普通 Read/Write/WriteFull 几何与 Tag/result 容量可复用，Atomic、Messages、Collective、Vendor 命令、授权仍不能只因原生字段层透传就算已支持。Response Src 可为不准确调试值，不能用于功能 Tag 匹配/路由/安全域身份。两 Response AuthTagParity 的表格 Driver 列与 AuthTag 方向不一致仍保留为规范待澄清项；本地 TX 生成与所驱动 AuthTag 同侧的 parity 是已记录实现选择，不是关闭勘误。A19 等 DL 开放项不由 station 计划改写。

## 下一批任务与独立验收

以下文件名是下一轮新增/替换目标，本轮均未创建。先实现 TX sender 与保护接线，随后集成正常传输；Endpoint bridge 和完整 RX/恢复须各自契约复核，不能混入 TX 完成声明。

| 任务 / 可独立拥有文件 | 依赖 | 必须可单独验收的内容 |
|---|---|---|
| A：`rtl/upli/upli_write_response_sender.v`；`verification/upli_channels/run_write_response_sender.py` 与 TB/独立参考 | 既有 bank、冻结 WrRsp leaf、公共 parity | 1/2/4 ports；首真实发送建相位，idle推进；初始化/无信用/不同 pool；每实际 Beat 恰好一扣；候选噪声不改等待元组；full字段保持；复位重建；真实高Tag/相位/信用扣账故障检出 |
| B：`rtl/upli/upli_read_response_sender.v`；`verification/upli_channels/run_read_response_sender.py` 与 TB/独立参考 | 既有 bank、冻结 RdRsp leaf、公共 parity；不依赖 A | 全部1..4拍 multi、各pool组合、各port交织；信用差一禁发；完整候选一经接受可立即变化；尾部无气泡、payload/auth/error保持；single Offset置换/跨Tag间隔/低Offset Last；status2/3/6/8完整N拍且逐拍Error独立；非法multi原子拒绝；真实尾部/预约/相位故障检出 |
| C：`rtl/upli/upli_credit_guard.v`、`upli_credit_return_adapter.v`；`verification/upli_channels/run_credit_adapter.py` | 公共 parity；不依赖 A/B | 所有4valid组合、逐位完整20bit控制、inactive port位翻转仍检出、valid0保护、InitDone不混入parity；实际 receive_channel 的注册返回直接传递，无多一拍/取消/TDM过滤；故障只声称检测，不冒称恢复 |
| D：`rtl/upli/upli_station_tx.v`；`verification/upli_channels/run_station_tx.py` 与真实两角色 TB | A/B/C、现有 request_data_sender、connection_side/receive_channel | 三相位故意不同初值；四通道独立银行与receiver容量；请求饱和仍能响应/归还；最后 OrigData 前/同沿的虚假 WrRsp由事务monitor检出；正常下一沿允许；响应不依赖再处理新请求；共同reset清空并重建 |
| E：Native RX/Endpoint桥契约与实现（`upli_endpoint_request_adapter.v`、`upli_endpoint_response_adapter.v`） | D 的可信事件接口、完整RX检查/容量方案、Endpoint上下文接口冻结 | 两实际Endpoint/TL路径因果响应、真实backend执行后响应、相同Tag跨port、两响应模式、三所有权事件区分；不预生成响应、不用发送器内部尾部队列作为oracle |

A/B/C 可以立即并行，分别独立保留候选，不同时修改已有公共 bank、parity 或 Req/OrigData sender。D 等接口和各自红绿证据冻结后连接；不能让一个先写的公共 scheduler 固定三条流共相位。E 必须先核定 bridge 的事务上下文，不要求 TX 实现代理猜出完整 Endpoint 改造。

每项测试执行顺序：

- [ ] 写独立固定字段/事件预期和实际旧壳或缺模块红测，保留失败来源和返回码；缺接口编译失败与功能失败分开记。
- [ ] 实现该任务唯一负责的 RTL；输入候选在负沿准备或使用沿前快照，积分计数不得在同一采样沿反馈 ready/候选/相位。
- [ ] 用外部接受事件建立不可变 payload/credit journal；实际 native valid 为唯一发送事实，不能读取 DUT bank/尾部状态生成 expected。
- [ ] 运行新 `--label` 正常矩阵及至少一项真实接线/状态突变；负例必须编译成功并被具体 checker 检出。检查完整字段与实际资源事件，不能只计发送次数。
- [ ] 完成 g2001、严格 lint、Yosys结构检查及适用技能 artifacts；保存同次读取的源副本与 hash、依赖清单、命令、返回码和日志。已有技能安装门禁异常与实际 EDA 结果分开记录。

计划中的 runner 命令统一为 `python3 verification/upli_channels/run_<任务名>.py --label NEW`，结果落 `build/verification/upli_channels/<任务名>/NEW/`；它们尚未执行，不列为测试通过。真实 SRAM 测试显式传授权 KD28 根，不能将 receive_channel 替为只返回ready的假 FIFO。

本计划完成判据是上述分工、固定 bundle、发送所有权和未闭合边界可供直接评审/分派；四 TX 发送总装的完成判据限于 D 正常 Native 传输。完整 station 还需要 E 与完整 RX/错误恢复、station 配置/速率管理证据，不能提前移除相应 pending 功能标记。
