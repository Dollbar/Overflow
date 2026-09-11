# 工程状态

更新时间：2026-09-11。完整 Endpoint/Controller 与 Switch 数字 RTL IP 的 Goal 仍在进行；本次整理没有改变交付完成条件。

优先交付的[Endpoint/Switch 顶层](ip_top_bringup.md)已可构建并运行实际两端通信。模块清单中 216 个 RTL 条目均有源码：93 个已有部分实现、123 个明确标识的接口壳；两套顶层均实例化相应预留层级。结构检查、通用逻辑综合及 Endpoint→Switch→Endpoint 正常/重放回归通过。Switch 目前为显式目标侧带的数字 fabric，标准逐跳 TL/DL、完整事务、PHY、INC、安全与管理仍须实现。模块存在不代表功能完成。TRANSACTION_MODE=1 的初始固定64B Read因果路径已进一步扩展为下述可选完整普通Read。此前通用门级综合结论属于 57+145 模块快照，当前增量单独记录结构与集成验证。

最新原生接收增量：`upli_receive_tdm_monitor` 已对实际四通道 valid/port 事件实现三组独立相位观察；正式回归覆盖1/2/4端口共24,923个单元时隙，并通过真实 station 三发送器、四 SRAM 接收链路的3,483沿/1,034个原生事件，三项时隙故障全部检出。`upli_ordered_receive_channel` 复用唯一实际接收存储和信用归还所有者，按每端口实际接纳次序跨 VC/Pool 退休；1/2/4端口异构及零容量配置共8,736周期，完成3,699次接纳、3,696次退休和3,696次原账户信用归还，另有3项真实接线故障检出。定向reset各取消一拍已接纳在途事件。它们不实现parity poison、Req/OrigData关联、Drop/Isolation或Endpoint上下文桥，完整native RX仍开放。见[时隙执行记录](upli_receive_tdm_monitor_execution.md)、[有序接收执行记录](upli_ordered_receive_channel_execution.md)和[完整RX契约](upli_native_rx_execution.md)。

`upli_native_rx_protection/channel` 已把四种原生通道的收到 parity 检查、数据/BE错误逐拍 poison、受保护封套、有序 SRAM 退休和真实信用返回连成一条可综合路径。四 kind × 1/2/4端口覆盖152,957个采样沿，完成9,529次真实接纳、9,517次退休和12次reset取消；6项控制、数据、BE、信用、坏头与Drop门控故障全部检出。角色级Drop/Isolation状态机、认证执行及初始化未完成时的Drop政策仍开放，见[接收封装记录](upli_native_rx_channel_execution.md)。

`upli_endpoint_request_bridge` 已从两个实际 ordered receive/KD28 SRAM 头组装完整 Request184、Data2048、relative BE256、poison与Port/VC/Pool/Auth/Src/Tag 上下文。1/2/4端口完成981笔descriptor、2,459次头部转交和同数原账户信用归还；长背压、Read/Write排队、reset与4项实际故障通过。它尚未接入 `ualink_endpoint_top` 的Backend/Response因果链，见[请求桥记录](upli_endpoint_request_bridge_execution.md)。

`upli_endpoint_native_rx_path` 已把四个受保护 native RX、三相位monitor和请求桥接为一个可综合Endpoint接收前端。普通及优化重放各在1/2/4端口完成216笔descriptor、1,341次head transfer和同数原账户信用归还；四项接线故障全部检出。Drop期间新拍阻断、holding取消、可信旧信用排空和共同reset后同Tag恢复均已覆盖。`upli_rx_role_fault_controller` 另完成9组参数、19,530个单位时隙、9组真实RX/SRAM连接及6类控制器故障；正向Beat和反向返回信用按不同角色归属。响应collector、backend因果连接、Isolation/dummy completion和恢复epoch仍开放，见[Native RX生产记录](upli_endpoint_native_rx_path_execution.md)和[角色故障控制器记录](upli_rx_role_fault_controller_execution.md)。

最新Switch增量：真实包仲裁器、完整字交叉连接和shadow/active原子路由表已替换三个壳并接入顶层。默认保留静态路由，`ROUTE_CONFIG_ENABLE=1`开放显式本地配置；只有无输入valid且无在途owner时可提交。详见[Switch集成审查](switch_integration_review.md)。

`switch_credit_reservation` 已替换库存壳，实现各出口独立轮询与整包所需缓冲单位的原子预约/真实释放记账。普通和优化两轮各覆盖1/2/4端口、3/4/16位容量、3,970周期、6项实际故障及9项静态检查。真实egress packet queue、VC与请求/响应资源分区和顶层一次性reservation token仍待接入，见[预约模块记录](switch_credit_reservation_review.md)。

`switch_egress_packet_queue` 和 `switch_egress_vc_queues` 已进入生产RTL：单资源队列普通及优化各覆盖7,600正常周期、5,700非法输入周期、7项RTL故障和10项静态检查；VC组合各覆盖6,900正常周期、13,800非法输入周期、40个启用资源槽、2个禁用槽、5项RTL故障和9项静态检查。共接纳2,234个header和4,693个body word，退休2,220个完整packet；Request满时仍有257次Response接纳，VC0满时有170次其它VC接纳。当前完成的是独立分区缓存，物理出口scheduler、标准TL分类/重打包及Switch顶层连接仍开放，见[单资源队列审查](switch_egress_packet_queue_review.md)和[VC队列审查](switch_egress_vc_queues_review.md)。

最新完整Read复位验证：10个正常配置及4项真实漏复位故障均达到判据，覆盖bank1/3、精确1/2/3个响应Beat、后端待结果和完成背压。20笔旧Read取消、80笔新Read复用Tag正确完成，20次先前Write的内存副作用保留。见[复位审查](endpoint_read_reset_review.md)。

最新完整普通 Read 增量：`FULL_READ_ENABLE=1`已贯通4..256B合法DWORD长度、首尾字节掩码、2048位后端结果及完整Tag收齐。三组真实双Endpoint经Switch回归完成1652笔事务，包含12次Write执行及8次重放；接收器/Tag另验证single乱序及multi响应。独立参考模型与RTL编码器分别覆盖532480合法几何/ATTR组合。写在途统一reset在两bank、三窗口通过；完整Read部分响应的统一reset已补齐，独立LinkDown/epoch尚未闭合。详见[Read集成审查](endpoint_read_integration_review.md)。

最新普通 Write 增量：Write Originator、共享 Request Formatter/Tag 表及 Write Completer 已有真实单元实现，覆盖普通4..256B及WriteFull合法几何；`WRITE_ENABLE=1`的core/top接线通过Verilog-2001编译和Yosys展开，混合接收和双实际Endpoint/Switch写后读已通过首批及全部64种普通长度、10种合法Full几何回归（长度组566笔请求/完成），最小bank与DL重放也通过。完整IP功能仍未完成，实施契约见[Write计划](endpoint_write_execution.md)。

最新容量与复位增量：20组独立事务容量组合完成320笔真实Read，三组默认回归另完成48笔；五组非法容量和一项容量接线故障按预期检出。三种在途统一同步复位窗口在两种bank配置下通过，12笔旧预约取消后产生12笔新轮次完成，两个漏复位故障被检出。严格静态风格门限仍未闭合，新顶层工艺STA未完成，详见[增量审查](endpoint_capacity_review.md)。

```sh
make ip-structure IP_RUN_LABEL=fresh_structure
make ip-top-smoke KD28_ROOT=/authorized/path IP_RUN_LABEL=fresh_system
make ip-top-synth KD28_ROOT=/authorized/path IP_RUN_LABEL=fresh_synth
```

实际因果事务范围、复跑入口与缺口见[Read集成评审](endpoint_causal_read_review.md)。

模块职责、状态和依赖见[完整清单](ip_module_inventory.md)，机器可读定义见[库存](../config/ip_module_inventory.json)。

此前[实际 TL/DL 跨层集成](endpoint_link_integration_review.md)：7 组正常配置、4 项真实接线故障全部达到预期；2,686 个唯一 TL 记录全部交付、2,313 次 SRAM 退休、66 次 DL 重放、双向序号环回完成，普通/优化 Python 检查一致。Request/Response 仍为独立测试源，尚无真实 completer/Tag 关联，测试的 520-bit DL 槽也不是标准 framing。

实际固定 SRAM 映射新增 95/96 配置的宏引脚与整字 bank 选择归纳，另有 96/96 生产参数行为回归、2,362,336 次整字比较及 24 组实际 FIFO/mapper/功能宏包装器接线检查。600-bit、深度 65,535 的形式查询仍因资源时限未完成；不计通过，也不阻塞真实端点事务实施。宏 Q 在引脚证明中为任意输入，行为仿真和接线检查分开成立；尚无完整 TL 联合载荷归纳及真实宏签核。详见[映射证据](sram_storage_mapping_evidence.json)。

研发 RTL 基线保持 `c84c113` 信用槽直接匹配；最新发送组合 640 ps 为 0/30 收敛，6.4 ns 为 26/30。WIDTH8/16 最差 setup 为 −1.816202/−1.799045 ns，hold 均为 −0.008036 ns；synthetic SRAM、布局前测量不能当作真实宏签核。下一步推进真实端点事务路径，不再让局部 PPA 实验替代功能里程碑。

以下阶段记录按各自源码和证据范围保留，不能将历史候选的“最新”措辞解释为当前生产基线。

## 当前工作基线

- UPLI：连接、接收、信用初始化/归还、Burst 控制等模块及模型、测试保留。
- DL：实际 Basic/UART/Control 消息端口、重放收发控制与 SRAM 数据端口迁入 `rtl/dl/`。新 128×32 集成顶层历史联合证明为 468/468；旧 255×64 核为 616/616，两者范围不同。
- TL：完整 Flit 验证、发送上下文、共享信用账本、实际双向端口、600 位接收存储和 FC 发布器迁入 `rtl/tl/`。
- PHY/RS：速率日历、帧控制、块格式化及其集成模块迁入 `rtl/phy/`。这是数字 RS 子集，没有完成 PCS/FEC/SerDes。

原有功能 RTL 保留各自已验证的限定范围；新增顶层与模块壳按 `config/ip_module_inventory.json` 区分部分实现和未实现状态。放入主源码目录不表示产品签核或完整协议实现。历史源码来源见 `config/source_provenance.json`，本轮顶层及结构证据见 `ip_top_evidence.json`。

## 已完成的阶段验证

| 阶段 | 历史实测范围 |
|---|---|
| Channel/Width 语义控制 | 367,256,110 沿，14 项 RTL 故障检出 |
| 旧 Basic/UART 接口联合证明 | 64/64 配置、2,304 次 SAT 查询 |
| DL 双实际端口重放 | 20 组、154,882 沿、71,600 个载荷 |
| TL 完整信用端口 | 4 配置、12,988 沿；8 类接线故障、32 次负向运行 |
| 双 TL 实际端口载荷 | 16 配置、3,088 周期；3,456 Flit、3,456 Data/BE token、768 次归还 FC |
| TL 接收存储 | 6 配置、6,750 沿；2,163 存储、2,121 消费，42 字恰好在满状态复位时丢弃；30 次故障运行 |
| TL 信用发布器 | 8 配置、147,457 沿；60,564 FC；7 类故障、56 次负向运行 |
| 发布器到实际信用端口 | 8 配置、520 周期；192 次付费 CMD 和 192 次归还 |

发布器还完成 12 条安全性/可达状态相关 SAT 查询及 2 条真实故障反例。保持输出的证明依赖已证明的 `valid ⇒ active` 不变量；任意不可达初态下原始保持性质有反例，不能将其写成无条件全状态证明。发布器尚无完整独立参考归纳证明。

上述历史日志与证明缓存已按整理要求删除；`docs/status.json` 保留有限摘要。新目录下重新执行的检查见 `docs/workspace_verification.json`。重新运行脚本会生成新的运行证据。

## 时序边界

- DL 数据端口候选最差 640 ps setup slack 为 −0.641033828 ns，未收敛。
- RS 日历选定的历史物理配置共 24 组，10 组收敛、14 组仍开放；摘要在 `config/rs_profiles.json`。生成网表已清理，不能直接重用该成绩作为当前源码综合成绩。
- 较早的接收信用集成候选有工艺分析，但最新 TL 完整端口、接收存储和发布器尚未完成工艺映射与 STA。
- SRAM 时序使用过 synthetic 视图；不是工艺签核模型。功能验证、形式验证、标准单元 STA 和真实互操作分别成立。

## 下一步

1. 实际 FIFO 消费到 FC 闭环已通过16配置（详见下方新增阶段）；继续证明声明初始信用、在途消息与实际FIFO空间的在线守恒。
2. 检查小 Data 信用下的双端持续前进性。当前按 Data 第一半扣信用，事务中间可能没有 FC 插入位置；已在真实双端组合中复现持续停顿；新增整段准入修复了总容量足够的压力反例，单笔超过总容量和完整持续前进性证明仍开放。
3. 补齐释放上下文、存储和信用端口的联合参考归纳、完整容量与参数覆盖。
4. 完成跨 UPLI/DL/TL/PL 集成、INC、安全、管理、尚未确认的规范问题，以及 Endpoint/Switch 顶层和工艺时序收敛。

独立 RTL 技能包的全局自检此前因缺失 `agents-md-generator/scripts/manage_docs.py` 未完成；已执行的 RTL artifact 检查不等同于该全局检查通过。

## 新增实际存储/信用闭环

`tl_receive_credit` 在16组实际双端组合中通过5,412周期、3,072个SRAM保存/消费字、1,712个FC；7类接线故障共112次检出。小信用容量下已复现中途停顿，未宣称持续前进性或工艺STA完成。详见 [本阶段审查与复跑命令](tl_receive_credit_review.md)。新证据仍保存在本地build目录，前面的历史档案清理说明不代表新证据被删除。

## 整段发送信用准入

`tl_credit_admitted_port` 在真实发送头部前检查该 Control 所需的全部 CMD/Data 信用，继续由原端口逐实际 Data 对扣费。两类负载共 32 配置、6,912 个实际 SRAM 字完成消费，3,944 次 FC 转移；16,742 个准入组合向量通过，28 次真实故障全部检出。

原压力反例每类四个 Data 信用、两条连续三 Beat 事务，旧端口卡在剩余 5/5 半 Flit 且 FIFO 为空；新端口相同负载完成排空。每类一个 Data 信用的原多 Beat 场景仍不能完整前进，新端口在头部发送之前报告容量不足。不能将此诊断当作超容量事务处理完成。详见 `docs/tl_credit_admission_review.md`。此阶段仍没有新产品顶层或工艺 STA。

## 实际半Flit发送打包

新增 `tl_tx_packer`，将准备好的Control、Data/BE、AuthTags和FC分开握手，再构造真实端口发送候选。实际双端16配置通过：1,792个Control队首、7,840个Data/BE半Flit、5,680个SRAM字消费、3,738次FC/完成消息转移。观察到70次新头部携带旧尾部、522次FC携带旧尾部、182次旧尾独立排空和186次catch预算NOP。3,170个周期向量通过，48次真实故障全部检出。

新模块解决旧尾部被未获信用新头阻塞及合法Control位置的FC仲裁；它仍只有一条准备好的Control输入，尚非独立Request/Response事务队列仲裁器。单信用多Beat场景仍真实超时且报告容量不足，未丢弃输入；工艺STA、真实Tx数据缓存、Poison/其余消息和完整联合归纳仍开放。详见 `docs/tl_tx_packer_review.md`。

## 独立Request/Response候选选择

新增 `tl_tx_channels`，独立检查两类准备好头部的信用、catch预算和本拍负载，并区分新头部类与旧Data所有者。正常、Request永久超容量、Response永久超容量三模式各16配置通过；正常模式有38次跨类头尾合并。被阻塞类保持所有输入，另一类完成发送、真实SRAM消费和信用排空。1,258个单位时序向量及80次实际故障完成。

这里完成的是外部两类队列的候选选择和独立消费接口，模块尚未实例化Tx FIFO/SRAM；每VC独立性、超容量事务完成和完整调度归纳仍开放。详见 `docs/tl_tx_channels_review.md`。新顶层仍未完成工艺STA。

## 实际发送SRAM缓存

新增两类独立的头部/标签FIFO与双bank Data/BE FIFO。实际最小容量原子写等待反例已用明确的部分入队确认修复，未扩大容量或丢弃输入。80组双端配置、6种FIFO深度和76次最终实际负例通过；审计关联实际入队、线上消费、SRAM退休及信用守恒。默认结构有64个SRAM宏实例，仍未完成工艺STA。完整容量感知UPLI、每VC与超容量事务处理及联合证明继续开放。详见 `docs/tl_tx_buffered_review.md`。

## 按容量分组完整Control字段

新增 `tl_control_partition`，把独立完整字段分到实际初始化容量可容纳的Control中，保留字段位、顺序、Data/BE及对应AuthTags。32组实际双端配置完成1,536个源组、6,912个字段和2,304个完整Single-Beat模式读回复；4,856个单位RTL向量和72次实际负例通过。模块仍不拆分单个多Beat事务，也不替代完整UPLI转换或每VC调度。工艺STA保持开放。详见 `docs/tl_control_partition_review.md`。

## Control分组模块工艺时序基线

WIDTH8/16两种参数已完成真实TSMC28标准单元映射和五角、两周期共20组STA。6组通过，主周期全部失败、慢角参考周期也失败；最差setup为−8.615259ns，参考周期最差−2.855259ns。两个宽度的映射等价检查在复位收敛SAT阶段超时，尚未得到通过结论。原始RTL未修改，接下来优先优化信用需求动态累计和重复分组计算。该结果仅覆盖单个模块，不关闭完整集成顶层STA或Goal。详见 `docs/tl_control_partition_timing_review.md`。

## 固定信用槽累计优化

把信用需求动态读写改为固定槽的平衡归约，九种宽度共207个SAT查询证明原版与重构RTL的全部123位输出二值组合等价。16,742个准入及4,856个分组向量、32组双端SRAM、28次功能故障与3个形式反例实际重放通过。96份原版/新版周期trace完全一致。分组模块映射面积下降80.45%/81.84%，参考周期五角两宽度10/10 STA通过；主周期最差setup仍为−1.250022ns，工艺映射等价仍超时。详见 `docs/tl_credit_reduction_review.md`；完整Goal未完成。

## 工艺网表复位前置证明

WIDTH8/16 的实际工艺网表与当前 RTL 均已证明一沿有效复位后全部四位真实游标为零，起始状态任意。两次真实复位旁路故障产生 SAT 反例，两次真实时钟接线故障被状态/时钟清单拒绝；普通 Python 与 `-O` 证据审计通过。十个原输出、529 位输出及四个状态观察位的清单完整，但复位后的归纳和原输出等价仍未完成，多种证明试验的超时均保留。详见 [本阶段审查](tl_partition_mapping_review.md)。

已按用户本次授权将工艺基线与固定槽信用优化推送至 `origin/main`（`51e1392599d3d974d9c6ab5d5cce2d63d76518c1`）。后续复位证明阶段为本地续作。完整 Goal 继续，主频收敛与完整顶层 STA 未完成。

## Control分组模块工艺映射等价闭合

WIDTH8/16 的当前 RTL 与实际 TSMC28 网表已完成一沿复位后的二值顺序等价证明。直接 CEC 对应十个原输出共529位及四位下一状态，完整检查真实状态/时钟并结合已证明的复位基例；两组分别约26.77/26.52秒通过。新增状态转移和标签输出两类共四次实际网表故障均被 CEC 检出，且完整时序 miter 产生 SAT 反例。加上原复位/时钟负例共八次故障检查。普通 Python、`-O` 审计及三个证明逻辑清理检查通过。详见 [工艺网表等价审查](tl_partition_mapping_review.md)。

此前 SAT 超时和带无用别名警告的首次 CEC 保留为历史记录；当前闭合结论仅适用于上述模块、参数、实际网表与二值范围。主周期 setup 最差仍为−1.250022ns，完整顶层 STA、完整协议证明及双 IP Goal 未完成。该阶段已于2026-09-11按用户新授权推送至 `origin/main`（`1bc57c1`）。

## 共享前缀信用费用优化

`tl_control_partition` 已采用一次掩码解码与平衡前缀费用复用。WIDTH8–16九种参数的原版/新版二值等价、WIDTH8/16的实际工艺网表等价及一沿复位证明通过；4,856个单位向量、32组实际双端配置通过，96份trace与前一阶段逐字节相同。最终16次单位故障、56次双端故障均检出，另保留6个实际网表SAT反例和2次时钟接线拒绝。

两种位宽面积分别为8,615.502/9,021.726µm²，较固定槽版本下降22.53%/14.24%。正式复跑脚本产生完全相同的两份网表与20组STA结果：参考周期10/10通过，主周期0/10，最差setup为−1.159129ns。干净导出的 `make test rtl-smoke` 通过，普通Python及 `-O` 阶段审计通过。旧边界判断删除变异经形式证明等价，未计作有效检出；首次失败矩阵保留。详见[本阶段审查与复跑入口](tl_prefix_cost_review.md)。完整顶层STA、主周期收敛和双IP Goal继续开放。

## tenure描述符与错误并行计算

已采用内部tenure计数与错误状态并行计算，保持原有出口错误拒绝和其余实例默认行为。九位宽RTL等价、两位宽实际网表等价与复位/故障门通过；tenure默认46位输出及合法并行描述符合约完成独立SAT。4,856个单位向量、32组实际双端回归和72次功能故障通过，96份trace与前阶段逐字节相同。

WIDTH8/16主周期最差setup改善到−1.057862/−1.054325ns，参考周期10/10通过、主周期0/10。面积为9,224.208/8,906.310µm²：WIDTH8增加约7.07%，WIDTH16下降约1.28%。两种并行输出选择候选因实际时序退步而保留为未采用记录。干净导出兼容性及普通/优化Python审计通过。本阶段本地续作，完整顶层STA和双IP Goal仍开放，详见[本阶段审查](tl_partition_select_review.md)。

## AuthTags共享移位

四个输出标签槽复用同一已消费字段偏移，原错误、字段数、Auth与入队条件不变。九位宽RTL、两位宽实际网表等价及复位/故障门通过；4,856个单位向量、32组双端回归、72次功能故障通过，96份trace与前阶段逐字节相同。干净导出兼容性及普通/优化Python审计通过。

WIDTH8/16主周期最差setup为−1.044205/−1.044889ns，分别改善13.657/9.436ps；面积为8,864.604/8,989.848µm²，WIDTH8下降3.90%，WIDTH16增加0.94%。参考周期10/10通过，主周期0/10。约1.04ns缺口仍需更深的结构处理，完整顶层STA及完整双IP Goal继续，详见[本阶段审查](tl_auth_selection_review.md)。本阶段没有追加推送。

## 注册化 Control 元数据

新增 `tl_prepared_partition`，用显式捕获与整组退休接口持有源数据和真实预解码元数据。九位宽共69,462个实际时钟向量、32组真实SRAM双端配置、28次有效RTL故障通过；两位宽所有权/复位/捕获/保持归纳通过，4个真实形式故障产生SAT基例反例。独立trace、普通Python与`-O`审计、严格lint和干净导出`make test rtl-smoke`通过。

两位宽实际工艺主setup为−0.819915/−0.808205ns，参考10/10、主周期0/10，面积为12,195.288/13,660.416µm²。新接口增加一拍初始延迟和寄存面积，原组合接口保留。完整字段边界宽属性集仅WIDTH16已归纳，WIDTH8仍超时；完整时序参考等价、新网表等价、完整顶层STA及双IP Goal继续开放。详见[本阶段审查](tl_prepared_partition_review.md)。本阶段仅本地续作，最近获授权远端提交仍为`1bc57c1`。

## 注册化 Control 完整 RTL 参考等价

WIDTH 8–16 已完成复位后的二值参考等价，比较十二个公开输出共 531 位。9 项元数据归纳、9 项完整字段边界归纳和 90 项穷尽分支单步/复位 SAT 全部通过；8 个实际 RTL 形式故障产生反例。参考对独立期望通过 15,436 向量，完整双状态机实际仿真通过 7,718 向量并检出覆盖持有数据故障。普通与优化 Python 审计、8 项审计器测试和参考 RTL lint 通过；技能静态检查零错误、9 项版式建议。详见 [本阶段审查](tl_prepared_equivalence_review.md)。

直接 PDR 仍未决，完整结论来自已证明不变量与实际 RTL 单步关系的组合。生产 RTL 未改变；当前模块工艺网表等价、640 ps 收敛、完整顶层 STA 和双 IP Goal 仍开放。按用户授权，已有实现推送并核对远端 `main` 为 `c34f40f`；上述新增等价验证作为后续本地工作留存。

## 注册化 Control 工艺网表等价

WIDTH 8/16 与原实际 TSMC28 网表已完成复位后二值顺序等价：全部 531 位公开输出及 1,035/1,195 位真实下一状态均被完整 CEC 比较，并结合两组任意初态复位、两组独立载荷空闲/捕获 SAT 及常量位归纳。8 项实际网表故障全部检出，其中三类在相同 CEC 入口又完成 6 次负向检查。实际网表对独立期望共 15,436 个向量通过，未切割网表捕获故障从复位后第 8 个向量检出。普通与优化 Python 审计、20 项检查器测试及兼容性检查通过。详见 [本阶段审查](tl_prepared_mapping_review.md)。

本阶段生产 RTL 未改变，源码和实际网表仍绑定此前时序结果。主周期最差 setup 仍为 −0.819915 ns；实际关键路径集中在游标/费用选择至 AuthTags 输出。后续继续路径分级、真实完整端口与 Endpoint/Switch 顶层集成及其余协议工作。新验证提交仅在本地，完整 Goal 未完成。

## 注册化 Control 并行选择与直接账户匹配

采用并行扇区/标签资格归约及静态物理账户匹配，保持一拍捕获延迟、全部状态和同拍退休替换能力。WIDTH 8–16 九组完整输出/下一状态 CEC、18 项独立复位/捕获 SAT、69,462 个独立单位向量、32 组实际 SRAM 双端配置、28 次 RTL 变异均通过；新实际工艺网表在 WIDTH 8/16 完成全部状态 CEC 及 4 项复位/捕获 SAT。普通和优化 Python 审计及干净导出的 `make test rtl-smoke` 通过，其中含 20 项已有检查器测试。详见 [本阶段审查与复跑入口](tl_selection_reduction_review.md)。

WIDTH 8/16 面积为 10,614.744/11,748.618 µm²，下降 12.96%/14.00%；主周期最差 setup 改善至 −0.735223/−0.723638 ns，参考周期 10/10、主周期 0/10。当前最差路径移至账户/游标到字段数输出；完整顶层 STA、640 ps 收敛和双 IP Goal 未完成。本轮没有重跑当前候选的完整门级向量，相关结论限定为新网表等价与当前 RTL 验证；历史门级成绩不转记。新工作仅本地提交，最近已核对远端 main 仍为 `c34f40f`。

## 注册化 Control 费用进位保存

当前费用前缀已采用进位保存结构，全部寄存器、接口及同拍退休替换语义不变。九位宽完整 RTL CEC、18 项独立复位/捕获 SAT、两位宽真实工艺网表 CEC 及 4 项复位/捕获 SAT 通过；另以两个无假设的 48 输入位/48 输出位算术 SAT 和严格源码替换审计交叉证明。69,462 个单位向量、32 组实际 SRAM 双端配置、30 次实际 RTL 故障检出通过。普通/优化 Python 审计和干净导出 `make test rtl-smoke` 通过，含 26 项检查器测试。

WIDTH 8/16 主周期最差 setup 为 −0.707760/−0.712052 ns，分别改善 27.463/11.586 ps；面积为 11,272.590/11,753.280 µm²，分别增加约 6.20%/0.04%。主周期仍 0/10，参考周期 10/10；完整顶层 STA 和 Goal 未完成。本轮未重新执行完整门级向量或历史网表负例。详见 [本阶段审查](tl_cost_compression_review.md)。

下一步优先补齐生产发送组合：当前准备器只在验证顶层实例化，`tl_tx_buffered` 仍接收已分组的 Control。完整源组捕获、标签所有权、实际头部入队以及去除测试适配气泡需要在生产连接中明确并验证，再进行实际组合顶层 STA。新工作仍为本地续作。

## 完整源组到实际发送队列的生产连接

新增 `tl_tx_prepared`，在生产 RTL 内连接两份注册化准备器和实际 SRAM 发送队列。完整源组与八标签在捕获时释放，最后分组入队与线上消费分别报告；新实际双端回归不再使用退休适配器。32 组配置通过，1,536 源组、5,248 分组和 6,912 字段完整到达，观察到 1,308 次同拍退休/捕获替换。九位宽 × Auth × 队列深度共 36 组、5,760 周期独立模型测试通过；22 次实际接线故障和 8 次带负载复位故障全部检出。

普通/优化 Python 的捕获、线上和汇总审计，以及干净导出的 `make test rtl-smoke prepared-tx-smoke` 通过。完整自有 RTL 依赖层级 artifact 零错误；旧解码器格式修正已独立证明全部 256 输入位/32 输出位不变，最终集成检查全部重跑。结构综合核对 6,254/6,574 位 FF 和各 64 个 SRAM 黑盒，全部使用原始上升沿时钟，无锁存器。详见 [生产集成审查](tl_tx_prepared_review.md)。

新组合尚无完整时序参考证明或工艺 STA，SRAM 黑盒不代表真实宏时序签核。下一步推进组合证明、实际映射/STA及最终端口和 Endpoint/Switch 集成；完整双 IP Goal 仍进行，新工作未追加推送。

## 生产发送组合所有权归纳

当前 `tl_tx_prepared` 完整组合在 WIDTH 8～16、HEADER_DEPTH 1/2/3 的27配置上，每组35项断言通过无界归纳。证明两类源组捕获减最终入队只为0或1且等于真实owned位、分组入队减线上消费等于实际头部FIFO占用，以及标签原子性、缓存/在途守恒和复位取消。唯一环境假设为初始同步复位，未切断内部控制逻辑；64个SRAM读输出为任意值，因此不构成载荷一致性或宏时序证明。

3类实际接线故障在WIDTH 8/16共6次由复位可达SAT反例检出；两组可达性见证覆盖双类同拍替换、满队列和占用中复位。15项审计器测试及普通/优化模式证据审计通过。RTL本轮未改动，完整载荷形式证明、Data bank守恒、实际映射等价、组合顶层STA与最终双IP仍开放。详见 [证明范围及复跑命令](tl_tx_prepared_formal_review.md)。

## 生产发送组合工艺基线

WIDTH 8/16 的完整 60 组 STA 已测量完毕，普通及优化 Python 证据审计通过。640 ps 主周期 0/30 收敛，6.4 ns 参考周期 26/30 收敛；两位宽最差 setup 为 −3.217651/−3.261416 ns，最差 hold 均为 −0.008036 ns。标准单元面积 47,213.082/48,461.994 µm²，各保留 64 个固定 SRAM 宏，宏时序视图仍为 synthetic，不能视作真实宏签核。

实际关键反馈路径由头部 FIFO 缓存计数经过发送选择返回预取计数，WIDTH 16 还跨越 Request/Response 仲裁。完整映射等价和时序收敛继续开放。旧 STA 任务已结束，详见 [完整物理基线审查](tl_tx_prepared_timing_review.md)。

按用户本次授权，现有提交 `7b45017` 已推送至 GitHub `work/tl-receive-credit` 分支。随后继续显式 binary/one-hot 状态编码关系验证；完整双 IP Goal 仍在进行。

## 生产发送组合映射对应准备

两位宽完整 D/Q 及 4,144 位公开/SRAM 事务输出库存复核通过。实际综合将两份 4 位 binary 游标重编码为 9 位 one-hot，已从原映射日志建立完整编码关系。5 项编码关系测试和 20 项既有状态检查器测试在普通/优化 Python 模式均通过。

新增 wrapper 的 BLIF lowering 错误已修正。修正后的两位宽整体 CEC，以及 WIDTH 8 自动分区 CEC，均在 150 秒外部时限内未完成；完整映射等价仍未决。原始失败、超时、完整 D/Q 与去除无用别名后的 BLIF 保留在本地证据目录，所有本轮任务已终止。下一步继续完整分区证明、复位/独立空闲载荷关系与实际映射故障检出。详见 [映射对应检查点](tl_tx_prepared_mapping_review.md)。

## 生产发送组合复位后工艺映射等价

WIDTH 8/16 已完成实际 TSMC28 标准单元网表对生产 RTL 的复位后二值顺序等价。12 个完整分区比较全部 4,144 位公开/SRAM 事务输出及 6,254/6,574 位实际映射下一状态；4 项独立任意初态复位、4 项游标关系闭合、4 项独立空闲载荷/捕获 SAT 全部通过。两类真实映射 D 引脚故障在两位宽共 4 次被反例检出，复位类故障又在同一分区 CEC 入口完成 2 次检出。

普通和优化 Python 的完整审计一致；21 项新增分区、结果分类、复位/空闲库存及证据检查器测试在两模式通过。原 BLIF 读入失败、整体/自动分区超时和已终止的小块探索都保留，未改写为成功。结论采用共同任意 SRAM 读值，并比较所有原宏的时钟、控制、地址、掩码与写数据；不构成真实宏签核或协议/完整载荷形式证明。详见 [证明组合、故障与复跑入口](tl_tx_prepared_mapping_review.md)。

本轮生产 RTL 未改动，640 ps 仍 0/30，6.4 ns 参考周期 26/30；下一步处理头部 FIFO 经仲裁返回预取计数的关键路径。完整双 IP Goal 继续进行，新增证明作为本地检查点留存。

## 发送资格复用优化

已将仲裁后的重复头部解码拆出，集成通道直接复用每类已计算的资格；保留原公开接口、状态与拍数。WIDTH8–16、两顶层共18组完整输出/实际下一状态等价及36次独立复位证明通过。32组真实双端配置、36组生产单元配置、27组所有权归纳证明及对应故障检查通过；干净克隆的基础/RTL/生产发送回归通过。

实际新顶层60项工艺测量及普通/优化Python审计完成。WIDTH8/16面积分别下降5.331%/4.927%，主周期最差setup从−3.217651/−3.261416ns改善到−1.853540/−1.861665ns；640ps仍0/30收敛，6.4ns为26/30，最差hold仍−0.008036ns。新网表的复位、游标与未占用载荷证明通过，完整编码分块证明继续运行；没有将旧网表的完整等价成绩移用于新候选。详见[本阶段审查](tl_tx_qualification_reuse_review.md)。

已按本次授权将此前已提交检查点`1f917a1`推送至`origin/work/tl-receive-credit`。完整双IP Goal继续进行。

## 资格复用候选的实际网表证明完成

`2228187` RTL对应的新工艺网表已完成两位宽共12个完整输出/下一状态分块、4次独立复位、4次游标范围及4次未占用载荷/捕获证明。6次实际映射单元故障检出，组合审计在普通Python与`-O`下产生相同证据；31项证明/审计辅助检查通过。该结论限定为复位后的二值对应，并将真实SRAM读输出作为两侧共同任意输入，不表示SRAM实现、模拟PHY或完整协议已经签核。当前没有遗留运行中的证明任务。

下一步按[选择资格路径计划](tl_tx_ready_selection_plan.md)继续修复640ps时序；完整Endpoint/Switch、协议载荷、数字PHY、INC、安全与管理目标保持开放。

## 选中ready旁路实验未采用

九位宽完整RTL等价、18次复位查询、32组实际双端回归及27组所有权证明通过；128份实际trace与此前逐字节相同。但完整60项工艺测量显示WIDTH8/16面积变为44,770.698/47,464.452µm²，最差setup变为−1.859017/−1.953218ns，均劣于现有基线。经普通/优化Python审计后，已将唯一RTL改动精确恢复到`6839cac`，保留候选、反例和全部测量证据；没有宣称该被拒绝候选的映射等价完成。

现用RTL和已证明的PPA基线不变。下一项针对FIFO无效数据清零门控与头部解码的组合路径，具体见[失败实验审查](tl_tx_ready_selection_review.md)及[下一步计划](tl_tx_header_visibility_plan.md)。完整双IP Goal仍在进行。

## 前序 FIFO 与信用优化检查点记录

最新实验结论：`161ed37` 的 FIFO 预取调整已完成 60 项测量并被拒绝。WIDTH 8 面积增加 0.880%、setup 退化 3.065 ps；WIDTH 16 面积增加 3.685%，setup 仅改善 11.215 ps，收敛配置数不变。普通/优化 Python 物理审计一致后，全部 RTL 已恢复为 `6f10b33`；候选功能证明、27 组所有权、干净克隆和失败实验记录保留。下一项[信用槽直接匹配](tl_credit_slot_selection_plan.md)在隔离副本中验证。详见[FIFO 实验审查](tl_fifo_issue_selection_review.md)。

后续候选已进入主源码验证：[信用槽直接匹配](tl_credit_slot_selection_review.md)通过九位宽 207 项 SAT、16,742 个独立模型向量、4 组 packer/channel 完整状态比较和实际故障检查。36 组发送单元、32 组实际双端及独立审计通过，128 份轨迹与基线一致；27 组所有权和新 60 项物理矩阵已完成，普通/优化审计一致；干净克隆检查通过。最新候选面积为 43,569.792/45,162.054 µm²，最差 setup 为 −1.816202/−1.799045 ns，主周期仍 0/30 收敛。12/12 实际映射分区、独立复位/游标/空闲关系及 6 项映射故障完成，普通/优化审计一致。`c84c113` 现采用为研发基线；保留 WIDTH8 setup 退化 9.817 ps 的明确记录。下方 Header visibility 的历史物理/映射结论限定于 `6f10b33` 基线。

最新检查点：`1194c73` 的 Header 有效性/资格判断调整已完成最终验证并采用为研发基线。两组九位宽 Channel 证明、36 组 FIFO、27 组完整 buffered 组合、36 组发送单位回归、32 组实际双端回归及 27 组所有权证明通过。实际工艺映射 12/12 分区等价、独立复位/游标/空闲载荷证明和 6 次实际映射故障检出完成；普通/优化 Python 的映射、物理、所有权和线上结果审计一致。

当前发送顶层 STA 已完成 60/60 项测量，640 ps 主周期仍为 0/30 收敛。WIDTH 8/16 最差 setup 为 −1.806385/−1.834665 ns，最差 hold 均为 −0.008036 ns；标准单元面积 44,790.732/45,603.936 µm²。未完成项包括时序收敛、真实宏/布局后签核、功耗、完整顶层 CDC/RDC、双 IP 集成与剩余协议/PHY/INC/安全/管理范围。详见[最新审查](tl_tx_header_visibility_review.md)和[证据摘要](tl_tx_header_visibility_evidence.json)。下方各阶段记录保留其当时范围及未决状态，不能逐条当作当前结论。

新增实际 FIFO + 授权同步 SRAM 行为模型的载荷证明：8/32/512 位 × 深度 1/2/3/5 × 两种输出模式共 24 配置通过。20 项整体归纳和 32 个覆盖全部载荷位的分区归纳完成；2 项真实 SAT 故障已在 Icarus 重放，12 项审计测试通过，普通/优化汇总证据一致。固定 SRAM bank 映射与完整 TL 载荷组合仍未证明。详见 [载荷证明审查](upli_fifo_payload_proof_review.md)。完整交付差距见 [里程碑检查](delivery_gap_review.md)。

## 原生 Request/OrigData 发送增量

原生 Request、OrigData、公共 parity 已替换三个占位壳，新增一个实际共享发送总装，保持单 sender、两组信用银行与共同 TDM。最终源码通过 970 个 Request、3688 个 OrigData、7084 个 parity 向量和 1/2/4 端口实际发送测试；16 项实际故障均检出。完整 Read 三 Beat 后统一复位兼容检查通过。Read/Write Response typed 子模块正在隔离开发，完整 station/端点适配、RX 隔离、独立 LinkDown/epoch、CDC/RDC 和工艺 STA 未完成。详见 [发送增量审查](upli_native_sender_integration_review.md)。

## 两类原生响应字段层

Read/Write Response typed TX 已替换两个占位壳，四类原生通道现在均有完整发送字段与 parity RTL。最终读响应7396向量、写响应3508向量通过，13项实际故障检出，g2001/严格lint/Yosys通过。两类响应的独立信用/TDM sender及完整station仍未实现；不能把组合字段层当作完整响应通道。详见 [响应增量审查](upli_response_integration_review.md)。

## 原生四通道 TX 信用与 SRAM 闭环

新增 Read/Write Response 独立发送器、信用保护/返回适配及三发送器 TX 总装。五配置覆盖1/2/4端口、3/4/16位信用与4/5容量；两轮真实SRAM传输完成1480拍，统一reset取消249拍已发送未退休数据，重建无旧数据泄漏。最终静态检查、3项总装接线故障、14项发送器/适配故障与兼容检查通过。独立审查确认四银行、三相位与完整typed字段接线。完整station RX/RAS和Endpoint后端因果适配仍开放，见 [本轮审查](upli_station_tx_integration_review.md)。
