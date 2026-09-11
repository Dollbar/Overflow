# Endpoint / Switch 完整模块库存

日期：2026-09-11。机器可读权威清单为 `config/ip_module_inventory.json`。这是工程模块拆分与所有权清单，不是全部规范 SHALL 的统计，也不是功能完成率。库存优先供两套顶层建立全部模块层级，随后逐模块冻结接口、实现功能，再验证相邻连接。

## 状态和使用规则

当前记录 60 个部分实现RTL模块、142 个显式未实现RTL壳、13 个软件管理模块和4类外部平台边界。已有顶层文件也只是 `existing_partial`；文件存在不代表其所有功能已实现。骨架生成后，库存的 `planned` 仍表示功能未实现，不能因文件出现就自动变更为完成。

- `existing_partial`：保持现有真实RTL及其接口，不复制或替换为壳。实际验证范围仍以对应契约/证据为准。
- `planned`：稳定模块名、目标文件、角色、职责和依赖已登记；不存在可用功能。所有新壳采用明确的内部provisional service接口，后续用逐模块契约替换。
- `dependencies`：模块职责依赖；既有RTL来自源实例名扫描，计划模块是目标组合。依赖表不替代真实端口连线或elaboration检查。
- `source_refs`：引用既有规范族和交付计划，不推测未冻结字段、CSR地址、命令码或算法常量。`functional_inputs/outputs`记录职责，未冻结接口明确标local provisional。
- 软件代理和模拟SerDes/PLL/可信平台/持久化为独立交付或平台边界，不能用RTL壳声称实现其功能。

## 顶层与接口壳

```text
ualink_endpoint_top
  ├─ endpoint_transaction_core ── 原生请求/执行/响应/Tag完成
  ├─ upli_station_port ── 原生UPLI通道/连接/信用/TDM
  ├─ station_array ── ualink_station ── TL / DL / digital PHY
  └─ security_core / management_csr / ras_controller / clock_reset_manager
ualink_switch_top
  ├─ switch_core ── 入口/路由/VC队列/仲裁/fabric/出口重打包
  ├─ inc_core ── primitive / Block生命周期 / 完整数值矩阵
  ├─ station_array ── 共享station数字协议路径
  └─ security_core / management_csr / ras_controller / clock_reset_manager
```

共享模块的Endpoint/Switch角色标签表示复用资格；普通Switch transit不会因此执行Endpoint内存操作或完整INC认证。物理station数、bifurcation和实际端口实例化仍按 `config/project.json` 与交付计划约束；一个壳不代表任何规模配置已经验证。

所有planned壳的临时接口为：

```text
input  i_clk, i_rstn, i_enable, i_valid
input  i_data[511:0], i_meta[127:0]
output o_ready, o_valid, o_data[511:0], o_meta[127:0]
output o_implemented, o_error
```

`i_data/i_meta`仅是不透明内部研发服务边界，既不是原生UPLI，也不是UALink线上格式。未实现时固定 `o_implemented=0`、`o_ready=0`、`o_valid=0`、输出数据/元数据清零，`o_error=i_rstn && i_enable && i_valid`仅报告请求了尚未实现的服务。不得旁路回显、伪造接纳、自动ACK或生成看似成功的协议完成。

## 稳定功能位

Endpoint使用128-bit角色内位图，已分配slot0–108（109个）；Switch使用128-bit角色内位图，已分配slot0–126（127个）。每个最初planned条目自带 `feature_slots`，晋升后仍保留。Endpoint的11/12、Switch的53已由typed子集实现替代，当前壳位分别107/126个。shared模块通过同一稳定module id映射到各角色独立slot。未分配位和已移除壳的slot为0，其余未实现壳位为1；零位仅表示该壳不再待实现，不证明相应子系统或集成完整符合性。

不得因排序或实现进展重编号已分配slot；用已验证typed子集替换壳时保留slot，更新部分实现状态、实际集成父模块与证据；清除位不代表全部规范功能完成。新增模块追加slot；超过128时先显式扩展位图版本/本地接口，不截断。此位图是研发可观测性，不是标准能力协商字段。

## 子系统边界概览

| 子系统 | 功能输入职责 | 功能输出职责 |
|---|---|---|
| endpoint | 完整请求/响应描述符、Data/BE、端口与Tag、本地执行/应用握手 | 格式化请求/响应、内存操作、完整应用完成及事务诊断 |
| upli | 原生UPLI字段、TDM端口、初始/归还信用、连接与时钟状态 | 实际UPLI通道beat、信用归还、接纳/退休及parity诊断 |
| tl | 准备好事务字段、Data/Auth/BE、合法消息、VC/Pool信用与TL Flit | 完整TL发送Flit、接收字段/数据上下文、信用和控制/错误事件 |
| dl | TL载荷与侧带、DL控制/消息、接收header/data、链路状态 | 标准DL发送/接收事务、ACK/replay、TL交付及链路错误/恢复事件 |
| phy | DL/RS记录、数字lane数据、合法速率/宽度/FEC模式和物理状态 | RS/PCS/FEC处理结果、lane输出/对齐状态及纠错/失锁事件 |
| station | 各端口事务、station数量/bifurcation、速率和平台时钟状态 | 按角色实例化的TL/DL/PHY端口、完整ID映射和受控速率/模式状态 |
| switch | 入口事务/路由元数据、各出口VC容量、路由/vPod/plane配置 | 出口转发/重打包事务、复制/仲裁结果及隔离/非法路由事件 |
| inc | 标准INC/Block请求、组成员/描述符、参与者数据和完成状态 | 成员请求、完整数值/响应归约、Block状态写回及资源完成/错误 |
| security | 原协议字段/数据、可信密钥/上下文、流身份、算法请求与配置 | 密码/认证/PCRC结果、经认证准入数据、安全上下文和错误事件 |
| management | 本地CSR请求、协议状态/计数/错误、固件代理操作 | 受控配置、能力/状态读回、中断/快照和软件事件 |
| ras | 协议错误、端口/连接状态、超时、真实事务完成和软件恢复动作 | 按规范角色作用域的Drop/Isolation/恢复、dummy完成及CPER事件 |
| common | 数据/控制跨域请求、reset/clock/lock、SRAM读写及诊断事件 | 同步后的握手/数据、复位/时钟状态和存储/诊断结果 |

## 全部RTL文件清单

下表E/S分别为Endpoint/Switch，`E:n/S:n`为稳定角色slot。`—`表示已有部分RTL没有新增壳slot。接口/依赖细节保存在JSON对应条目。

### endpoint

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/endpoint/ualink_endpoint_top.v` | E / existing_partial / — | Endpoint完整数字IP顶层：原生UPLI、事务、安全、station、CSR与RAS汇合；已存在文件，功能范围须按对应实现审查 |
| `rtl/endpoint/endpoint_transaction_core.v` | E / planned / E:0 | 请求发起、目的执行、Tag关联和完成接口的端点事务总装 |
| `rtl/endpoint/endpoint_request_admission.v` | E / planned / E:1 | 完整请求合法性、长度对齐、目的配置和本地资源联合准入 |
| `rtl/endpoint/endpoint_tag_table.v` | E / planned / E:2 | 按端口和完整Tag保留请求/结果容量、跟踪全部响应和一次退休 |
| `rtl/endpoint/endpoint_read_originator.v` | E / planned / E:3 | 普通Read发起、已发送状态和两种响应模式Tag完成 |
| `rtl/endpoint/endpoint_read_completer.v` | E / planned / E:4 | 实际收到Read后发出内存读并由真实完成产生响应 |
| `rtl/endpoint/endpoint_write_originator.v` | E / planned / E:5 | Write/WriteFull请求与完整Data/BE所有权及写响应关联 |
| `rtl/endpoint/endpoint_write_completer.v` | E / planned / E:6 | Write/WriteFull接收组装、最终数据后执行完成和写响应 |
| `rtl/endpoint/endpoint_atomic_transport.v` | E / planned / E:7 | 协议Atomic操作数与mask无语义分解传输、返回/不返回响应关联 |
| `rtl/endpoint/endpoint_receive_transactions.v` | E / planned / E:8 | 从实际TL退休字解析完整字段并分流Request/Response和Data/BE |
| `rtl/endpoint/endpoint_response_assembler.v` | E / planned / E:9 | 按响应上下文收齐Data半Flit、offset/LAST/status并恢复完整beat |
| `rtl/endpoint/endpoint_request_formatter.v` | E / planned / E:10 | 完整普通读写原子及合法消息请求的未压缩字段构造 |
| `rtl/endpoint/endpoint_read_encode.v` | E / existing_partial / E:11 | 已冻结单64-byte普通Read的128-bit字段编码 |
| `rtl/endpoint/endpoint_response_encode.v` | E / existing_partial / E:12 | 已冻结单Beat普通Read Response的64-bit字段编码 |
| `rtl/endpoint/endpoint_response_formatter.v` | E / planned / E:13 | 真实执行完成转读/写响应字段及有序Data，含多Beat语义 |
| `rtl/endpoint/endpoint_ordering.v` | E / planned / E:14 | 每对端/VC/流/256-byte区域的SO、SOL、non-SO调度与端口亲和 |
| `rtl/endpoint/endpoint_memory_adapter.v` | E / planned / E:15 | 加速器本地内存/原子执行接口的准入、原请求上下文和完成交接 |
| `rtl/endpoint/endpoint_message_handler.v` | E / planned / E:16 | 标准UPLI消息和端点适用TL消息向执行/安全/RAS控制分派 |
| `rtl/endpoint/endpoint_completion_sink.v` | E / planned / E:17 | 预留响应接收空间，成功数据和错误完成分离，应用退休释放Tag |

### upli

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/upli/upli_burst_control.v` | E/S / existing_partial / — | Native normal Request/OrigData full-credit admission and per-port TDM control. |
| `rtl/upli/upli_burst_sender.v` | E/S / existing_partial / — | UPLI normal complete-staged sender; Common 2.0 sections 2.5 and 2.7.8. |
| `rtl/upli/upli_connection_side.v` | E/S / existing_partial / — | UPLI single-side connection controller; Common 2.0 sections 4.1-4.3. |
| `rtl/upli/upli_credit_bank.v` | E/S / existing_partial / — | UPLI single-channel credit bank; Common 2.0 sections 2.6 and 4.3. |
| `rtl/upli/upli_credit_initializer.v` | E/S / existing_partial / — | UPLI initial credit publisher; Common 2.0 sections 2.6 and 4.3. |
| `rtl/upli/upli_credit_return_queue.v` | E/S / existing_partial / — | UPLI normal credit return metadata queue; Common 2.0 sections 2.6 and 4.3. |
| `rtl/upli/upli_receive_channel.v` | E/S / existing_partial / — | UPLI per-account receive storage and initial/normal credit handoff. |
| `rtl/upli/upli_receive_fifo.v` | E/S / existing_partial / — | Synchronous receive FIFO controller for a one-cycle registered SDP SRAM. |
| `rtl/upli/upli_receive_storage.v` | E/S / existing_partial / — | Bind the synchronous receive FIFO to externally supplied KD28 SDP storage. |
| `rtl/upli/upli_station_port.v` | E/S / planned / E:18/S:0 | 原生station UPLI四通道、连接、TDM、信用与parity总装 |
| `rtl/upli/upli_request_channel.v` | E/S / planned / E:19/S:1 | 完整Request字段的原生UPLI发送/接收与独立信用账户 |
| `rtl/upli/upli_read_response_channel.v` | E/S / planned / E:20/S:2 | 完整Read Response/Data原生通道、Single/Multi-Beat时序和信用 |
| `rtl/upli/upli_write_response_channel.v` | E/S / planned / E:21/S:3 | Write Response含适用本地控制事件的原生通道及信用 |
| `rtl/upli/upli_orig_data_channel.v` | E/S / planned / E:22/S:4 | 512-bit OrigData、64-bit ByteEn、Error和连续burst原生通道 |
| `rtl/upli/upli_tdm_scheduler.v` | E/S / planned / E:23/S:5 | 按station bifurcation管理1/2/4端口原生通道slot与连续burst |
| `rtl/upli/upli_parity.v` | E/S / planned / E:24/S:6 | 请求/响应/OrigData控制和完整数据parity生成检查、错误分类 |

### tl

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/tl/tl_atomic_admission.v` | E/S / existing_partial / — | 完整逻辑Flit分类与打包预算共同提交 |
| `rtl/tl/tl_content.v` | E/S / existing_partial / — | 已分类完整Flit的内容与Beat配对检查 |
| `rtl/tl/tl_control_decode.v` | E/S / existing_partial / — | tl_control_decode模块：自然对齐树保持原控制半Flit结构接口 |
| `rtl/tl/tl_control_partition.v` | E/S / existing_partial / — | tl_control_partition模块：按总信用容量分组完整字段，保持单笔事务不变 |
| `rtl/tl/tl_control_tenure.v` | E/S / existing_partial / — | tl_control_tenure模块：按自然字段派生tenure，默认错误时清零描述符 |
| `rtl/tl/tl_credit_admission.v` | E/S / existing_partial / — | tl_credit_admission模块：当前确认字段的整段信用准入 |
| `rtl/tl/tl_credit_admitted_port.v` | E/S / existing_partial / — | tl_credit_admitted_port模块：真实端口前置整段准入，WIDTH为8至16 |
| `rtl/tl/tl_credit_context.v` | E/S / existing_partial / — | 请求关联元数据与20槽信用需求 |
| `rtl/tl/tl_credit_events.v` | E/S / existing_partial / — | 实际信用事件解码 |
| `rtl/tl/tl_credit_integration.v` | E/S / existing_partial / — | 实际Flit信用集成，WIDTH至少8 |
| `rtl/tl/tl_credit_ledger.v` | E/S / existing_partial / — | 二十逻辑槽信用账本，WIDTH至少1 |
| `rtl/tl/tl_credit_port.v` | E/S / existing_partial / — | 真实Rx信用与Tx关联上下文，WIDTH至少8 |
| `rtl/tl/tl_credit_publish.v` | E/S / existing_partial / — | tl_credit_publish模块：退休信用累积与可停顿FC发布 |
| `rtl/tl/tl_full_flit.v` | E/S / existing_partial / — | tl_full_flit模块：完整512位Flit分类、预算及内容原子接收 |
| `rtl/tl/tl_packing_budget.v` | E/S / existing_partial / — | Common2.0第5.7节逻辑TL Flit打包预算 |
| `rtl/tl/tl_prepared_partition.v` | E/S / existing_partial / — | tl_prepared_partition模块：寄存完整源字段元数据并按容量分组 |
| `rtl/tl/tl_receive_context.v` | E/S / existing_partial / — | tl_receive_context模块：接收存储的预约与延后消费释放元数据 |
| `rtl/tl/tl_receive_credit.v` | E/S / existing_partial / — | tl_receive_credit模块：实际接收FIFO与FC发布器的消费原子连接 |
| `rtl/tl/tl_receive_storage.v` | E/S / existing_partial / — | tl_receive_storage模块：实际TL Flit与消费信用元数据存储 |
| `rtl/tl/tl_sequence.v` | E/S / existing_partial / — | 真实Control派生与两半Flit分类推进 |
| `rtl/tl/tl_tx_buffered.v` | E/S / existing_partial / — | tl_tx_buffered模块：两个类别实际SRAM发送队列与原子打包 |
| `rtl/tl/tl_tx_channels.v` | E/S / existing_partial / — | tl_tx_channels模块：独立Request与Response候选及Data所有权选择 |
| `rtl/tl/tl_tx_data_fifo.v` | E/S / existing_partial / — | tl_tx_data_fifo模块：双bank有序半Flit发送SRAM缓存 |
| `rtl/tl/tl_tx_packer.v` | E/S / existing_partial / — | tl_tx_packer模块：准备好的Control、Data及FC按半Flit打包 |
| `rtl/tl/tl_tx_packer_core.v` | E/S / existing_partial / — | tl_tx_packer_core模块：复用已计算资格，仅选择来源并打包 |
| `rtl/tl/tl_tx_prepared.v` | E/S / existing_partial / — | tl_tx_prepared模块：完整源组捕获、容量分组与实际SRAM发送组合 |
| `rtl/tl/tl_port.v` | E/S / planned / E:25/S:7 | 完整TL收发端口：现有prepared发送和信用/SRAM加完整接收转换 |
| `rtl/tl/tl_transaction_demux.v` | E/S / planned / E:26/S:8 | TL实际Control字段与Data/Auth/BE上下文分发到端点或交换核心 |
| `rtl/tl/tl_vc_scheduler.v` | E/S / planned / E:27/S:9 | Request/Response各VC及Pool独立候选、保留资源、公平性与前进 |
| `rtl/tl/tl_stream_order.v` | E/S / planned / E:28/S:10 | TL端口各流和VC顺序约束与调度资格 |
| `rtl/tl/tl_request_compress.v` | E/S / planned / E:29/S:11 | 请求压缩资格、地址cache命中与未压缩旁路编码 |
| `rtl/tl/tl_request_decompress.v` | E/S / planned / E:30/S:12 | 请求压缩字段还原、CLOAD/CWAY和完整地址恢复 |
| `rtl/tl/tl_response_compress.v` | E/S / planned / E:31/S:13 | 合法读/写/Block响应压缩资格和编码，未决格式保持未实现 |
| `rtl/tl/tl_response_decompress.v` | E/S / planned / E:32/S:14 | 全部适用响应格式还原与错误诊断，A09相关编码待澄清 |
| `rtl/tl/tl_address_cache.v` | E/S / planned / E:33/S:15 | 按角色ID索引的地址cache有效位、way、load及失效边界 |
| `rtl/tl/tl_message_control.v` | E/S / planned / E:34/S:16 | 完整合法TL Message类型、流/信用语义和控制动作分派 |
| `rtl/tl/tl_poison_control.v` | E/S / planned / E:35/S:17 | Data/BE/Poison跨beat配对、错误状态及应用侧传播 |

### dl

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/dl/dl_basic_message_control.v` | E/S / existing_partial / — | 控制时钟周期以皮秒明确声明。 |
| `rtl/dl/dl_control_controller.v` | E/S / existing_partial / — | 语义控制器时间精度统一为皮秒 |
| `rtl/dl/dl_control_port.v` | E/S / existing_partial / — | 实际组合消息端口所有状态共享一个原始时钟域。 |
| `rtl/dl/dl_message_arbiter.v` | E/S / existing_partial / — | DL 两级消息仲裁器：选择完整且已具备发送资格的外部消息源。 |
| `rtl/dl/dl_message_port.v` | E/S / existing_partial / — | 全部子模块和双SRAM在同一原始时钟域运行。 |
| `rtl/dl/dl_replay_data_port.v` | E/S / existing_partial / — | dl_replay_data_port模块：预约Flit槽的一拍头数据响应 |
| `rtl/dl/dl_replay_event_port.v` | E/S / existing_partial / — | dl_replay_event_port模块：LLR接收事件和发送头的同域连接 |
| `rtl/dl/dl_replay_header_tx.v` | E/S / existing_partial / — | dl_replay_header_tx模块：LLR发送头调度与可选提前元数据保护 |
| `rtl/dl/dl_replay_receiver.v` | E/S / existing_partial / — | LLR receive event state for UALink 200G DL/PL 2.0. |
| `rtl/dl/dl_replay_tx_control.v` | E/S / existing_partial / — | dl_replay_tx_control模块：ACK窗口与实际重放存储环控制 |
| `rtl/dl/dl_replay_tx_storage.v` | E/S / existing_partial / — | dl_replay_tx_storage模块：实际同步SRAM重放与输出保持槽 |
| `rtl/dl/dl_uart_port.v` | E/S / existing_partial / — | 实际发送、接收与复位控制共享单一原始时钟。 |
| `rtl/dl/dl_uart_reset_control.v` | E/S / existing_partial / — | Stream0复位控制：实际维护提交、时钟推导的十毫秒等待和逐请求响应队列。 |
| `rtl/dl/dl_uart_rx_path.v` | E/S / existing_partial / — | UALink stream0 receive framing, actual SRAM storage and firmware read credits. |
| `rtl/dl/dl_uart_tx_path.v` | E/S / existing_partial / — | Stream0 UART 固件发送路径：复用实际 SRAM FIFO、完整消息暂存源及两级仲裁器。 |
| `rtl/dl/dl_uart_tx_source.v` | E/S / existing_partial / — | UART 发送来源：先预留整条消息的信用，再完整暂存 payload 后参与仲裁。 |
| `rtl/dl/dl_port.v` | E/S / planned / E:36/S:18 | DL完整端口：线格式、消息、重放、初始化和恢复汇合 |
| `rtl/dl/dl_tx_framer.v` | E/S / planned / E:37/S:19 | 标准TL到DL payload/侧带聚合、保留字段和CRC输入边界 |
| `rtl/dl/dl_rx_deframer.v` | E/S / planned / E:38/S:20 | 完整DL接收格式/CRC分类、TL payload及M信息恢复 |
| `rtl/dl/dl_crc_tx.v` | E/S / planned / E:39/S:21 | 标准DL CRC0-CRC3发送计算和线上位序映射，A19开放 |
| `rtl/dl/dl_crc_rx.v` | E/S / planned / E:40/S:22 | 标准DL CRC检查及各错误状态输出，A19开放 |
| `rtl/dl/dl_link_state.v` | E/S / planned / E:41/S:23 | 链路初始化、online/offline、reset握手及上下层事件 |
| `rtl/dl/dl_watchdog.v` | E/S / planned / E:42/S:24 | LLR ACK计时、重装和超时事件，A21首次装载未决 |
| `rtl/dl/dl_resiliency.v` | E/S / planned / E:43/S:25 | 所选链路Resiliency模式状态、能力和错误恢复边界 |
| `rtl/dl/dl_folding.v` | E/S / planned / E:44/S:26 | Folding/Unfolding、Tx Ready/热保护及恢复顺序 |
| `rtl/dl/dl_uart_firmware_adapter.v` | E/S / planned / E:45/S:27 | 标准带内UART不透明DWORD固件入口/出口和状态，无自定义命令码 |

### phy

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/phy/rs_tx_block_formatter.v` | E/S / existing_partial / — | 模块 rs_tx_block_formatter：将一拍连续DL数据或已选控制Flit位置转换为并行RS块字段。 |
| `rtl/phy/rs_tx_calendar_frame.v` | E/S / existing_partial / — | 模块 rs_tx_calendar_frame：连接真实日历和完整帧的同域包装器 |
| `rtl/phy/rs_tx_frame_control.v` | E/S / existing_partial / — | 模块 rs_tx_frame_control：保持整条Flit元数据并按实际块组提交推进八十块序列。 |
| `rtl/phy/rs_tx_rate_scheduler.v` | E/S / existing_partial / — | 模块 rs_tx_rate_scheduler：按实际码字提交推进共同相位的RS调度器 |
| `rtl/phy/phy_port.v` | E/S / planned / E:46/S:28 | 共享数字PHY总装：RS、PCS、FEC、lane映射、对齐及SerDes数字边界 |
| `rtl/phy/rs_rx_calendar_frame.v` | E/S / planned / E:47/S:29 | 接收RS帧/块日历恢复、控制和DL事件输出 |
| `rtl/phy/rs_rx_block_parser.v` | E/S / planned / E:48/S:30 | 接收RS合法块、控制码和帧边界解析 |
| `rtl/phy/phy_pcs_tx.v` | E/S / planned / E:49/S:31 | 所需PCS发送编码/扰码和FEC前格式，D01参考基线依赖 |
| `rtl/phy/phy_pcs_rx.v` | E/S / planned / E:50/S:32 | PCS接收同步、FEC后格式恢复及解扰，D01参考基线依赖 |
| `rtl/phy/phy_fec_encode.v` | E/S / planned / E:51/S:33 | 全部所选合法100G/200G FEC发送码字编码 |
| `rtl/phy/phy_fec_decode.v` | E/S / planned / E:52/S:34 | 全部所选合法FEC纠错、不可纠错分类和统计 |
| `rtl/phy/phy_fec_interleave.v` | E/S / planned / E:53/S:35 | 所选合法标准/低延迟FEC interleaving发送映射 |
| `rtl/phy/phy_fec_deinterleave.v` | E/S / planned / E:54/S:36 | 与已协商FEC模式对应的接收deinterleaving |
| `rtl/phy/phy_scrambler_tx.v` | E/S / planned / E:55/S:37 | 按锁定PCS条款扰码，未确认常量不填入壳 |
| `rtl/phy/phy_scrambler_rx.v` | E/S / planned / E:56/S:38 | 按锁定PCS条款解扰与状态同步 |
| `rtl/phy/phy_lane_align.v` | E/S / planned / E:57/S:39 | 块/标记同步和lane对齐状态机 |
| `rtl/phy/phy_deskew.v` | E/S / planned / E:58/S:40 | 多lane差分延迟缓冲、失锁和重对齐 |
| `rtl/phy/phy_rate_match.v` | E/S / planned / E:59/S:41 | PCS/RS节奏及合法IDLE插入移除和弹性缓冲 |
| `rtl/phy/phy_lane_map.v` | E/S / planned / E:60/S:42 | x1/x2/x4 lane排序、bifurcation和收发映射 |
| `rtl/phy/phy_mode_control.v` | E/S / planned / E:61/S:43 | 100G/200G、宽度/FEC/增强的合法组合配置与切换控制 |
| `rtl/phy/phy_serdes_adapter.v` | E/S / planned / E:62/S:44 | 数字PMA/SerDes lane数据、ready/lock/error与平台模型边界 |

### station

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/station/ualink_station.v` | E/S / planned / E:63/S:45 | 一个四lane station中TL/DL/PHY端口及模式/速率控制总装 |
| `rtl/station/station_array.v` | E/S / planned / E:64/S:46 | NUM_STATIONS非二次幂展开、派生端口数和实例隔离 |
| `rtl/station/station_bifurcation.v` | E/S / planned / E:65/S:47 | x4/2x2/4x1能力、当前运行模式及受控重配置 |
| `rtl/station/station_port_identity.v` | E/S / planned / E:66/S:48 | station内PortID、设备PortNum与安全身份的完整范围映射 |
| `rtl/station/station_rate_controller.v` | E/S / planned / E:67/S:49 | Accelerator双阶段UPLI调频、所有受影响端口ACK与Switch固定速率 |
| `rtl/station/tx_pacing.v` | E/S / planned / E:68/S:50 | 按已确认对端UPLI速率归一化的发送节奏与在途预算 |

### switch

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/switch/ualink_switch_top.v` | S / existing_partial / — | Switch完整数字IP顶层：station、交换、INC、安全、管理与RAS；已存在文件，功能范围须按对应实现审查 |
| `rtl/switch/switch_core.v` | S / planned / S:51 | 多端口消息路由、VC缓冲、仲裁和重打包总装 |
| `rtl/switch/switch_ingress.v` | S / planned / S:52 | 实际TL事务拆包、入口元数据和错误/INC分类 |
| `rtl/switch/switch_route_lookup.v` | S / existing_partial / S:53 | 按目的ID/角色选择合法出口或INC处理，不截断ID |
| `rtl/switch/switch_route_table.v` | S / planned / S:54 | 独立合法路由表组织、配置原子更新和lookup容量 |
| `rtl/switch/switch_egress_vc_queues.v` | S / planned / S:55 | 按出口/Request-Response/VC分离的有界实际缓存 |
| `rtl/switch/switch_arbiter.v` | S / planned / S:56 | 多入口到出口无饥饿调度、请求不阻塞应答资源 |
| `rtl/switch/switch_fabric.v` | S / planned / S:57 | 实际多入口多出口数据交叉连接及并发冲突控制 |
| `rtl/switch/switch_egress_repack.v` | S / planned / S:58 | 转发字段顺序保持、TL完整字段重打包和Data关联 |
| `rtl/switch/switch_vpod_filter.v` | S / planned / S:59 | 入口/出口/ID/成员关系的vPod边界和非法路由隔离 |
| `rtl/switch/switch_ordering.v` | S / planned / S:60 | 每ingress-egress流保序、Single-Beat立即转发和区域顺序 |
| `rtl/switch/switch_multicast.v` | S / planned / S:61 | 规范组播成员复制、出口backpressure和复制完成记录 |
| `rtl/switch/switch_multiplane.v` | S / planned / S:62 | 平面/端口选择配置与完整ID映射，不引入外部级联语义 |
| `rtl/switch/switch_port_state.v` | S / planned / S:63 | 单端口up/down、转发资格与其它端口运行保持 |
| `rtl/switch/switch_uturn.v` | S / planned / S:64 | 规范允许的U-turn路由与同端口转发条件 |
| `rtl/switch/switch_credit_reservation.v` | S / planned / S:65 | 交换出口信用/缓冲预留和并发转发消费守恒 |

### inc

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/inc/inc_core.v` | S / planned / S:66 | 完整INC primitive与Block生命周期和数值管线总装 |
| `rtl/inc/inc_request_classifier.v` | E/S / planned / E:69/S:67 | 区分普通/primitive/Block请求与合法类型，不猜未决命令 |
| `rtl/inc/inc_group_table.v` | S / planned / S:68 | 组成员、操作属性、有效性和管理配置存储 |
| `rtl/inc/inc_membership_tracker.v` | S / planned / S:69 | 参与者到达/缺失、各成员进展和完成判定 |
| `rtl/inc/inc_primitive_dispatch.v` | S / planned / S:70 | 完整标准primitives请求复制/执行路径与回包分派 |
| `rtl/inc/inc_multicast_engine.v` | S / planned / S:71 | INC参与者请求复制与出口资源控制 |
| `rtl/inc/inc_reduction_context.v` | S / planned / S:72 | 按事务/组/beat保留归约状态和参与者集合 |
| `rtl/inc/inc_response_reduce.v` | S / planned / S:73 | Read/Write响应归约、返回路由与全部参与者完成 |
| `rtl/inc/inc_block_control.v` | S / planned / S:74 | Block Allocate/Invoke/Deallocate生命周期总装 |
| `rtl/inc/inc_block_queue.v` | S / planned / S:75 | 物理队列/SQ条目分配、容量和并发资源守恒 |
| `rtl/inc/inc_block_descriptor.v` | S / planned / S:76 | 标准Control Block描述符获取、检查与字段展开 |
| `rtl/inc/inc_block_address.v` | S / planned / S:77 | 输入/输出/状态地址、mask、stride和精度放大进位 |
| `rtl/inc/inc_block_tag_allocator.v` | S / planned / S:78 | Block独立Tag命名空间与已发访问完成资源 |
| `rtl/inc/inc_block_status_writer.v` | S / planned / S:79 | Allocate/Deallocate和Invoke不同状态格式的真实写回 |
| `rtl/inc/inc_block_drain.v` | S / planned / S:80 | DO=0释放顺序、在途访问排空及DO=1待澄清结束边界 |
| `rtl/inc/inc_numeric_dispatch.v` | S / planned / S:81 | 完整合法算子/类型/精度矩阵分派，不虚构A10编码 |
| `rtl/inc/inc_integer_alu.v` | S / planned / S:82 | 标准整数算子及适用bitwise/min/max/add语义 |
| `rtl/inc/inc_fp_alu.v` | S / planned / S:83 | FP64/FP32/FP16/BF16/FP8等目标矩阵浮点运算和NaN边界 |
| `rtl/inc/inc_rounding.v` | S / planned / S:84 | 标准舍入、随机舍入/允许回退及特殊数边界 |
| `rtl/inc/inc_widen_convert.v` | S / planned / S:85 | 标准输入/中间/输出精度扩展与格式转换 |
| `rtl/inc/inc_deterministic_reduce.v` | S / planned / S:86 | 规定成员和归约顺序下的确定性结果组织 |
| `rtl/inc/inc_error_aggregate.v` | S / planned / S:87 | 参与者失败、混合状态、部分执行和状态写回错误聚合 |

### security

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/security/security_core.v` | E/S / planned / E:70/S:88 | 端点/INC安全数据流、算法与上下文生命周期总装 |
| `rtl/security/security_request_map.v` | E/S / planned / E:71/S:89 | UALink请求AAD/MSG/地址/Tag/ASI映射，A05开放 |
| `rtl/security/security_response_map.v` | E/S / planned / E:72/S:90 | 读写响应认证映射与类型域绑定，A06开放 |
| `rtl/security/aes_core.v` | E/S / planned / E:73/S:91 | 由规范锁定模式调用的AES块密码算法，不独立代表安全协议 |
| `rtl/security/ghash_core.v` | E/S / planned / E:74/S:92 | GCM认证乘法与累加算法 |
| `rtl/security/gcm_core.v` | E/S / planned / E:75/S:93 | GCM加解密/标签算法和明确counter block规则 |
| `rtl/security/keccak_core.v` | E/S / planned / E:76/S:94 | KMAC所需Keccak置换算法 |
| `rtl/security/kmac_core.v` | E/S / planned / E:77/S:95 | KMAC上下文认证与规范输入映射接口 |
| `rtl/security/pcrc_core.v` | E/S / planned / E:78/S:96 | PCRC计算/校验与协议映射接口，区别于DL CRC |
| `rtl/security/security_stream_context.v` | E/S / planned / E:79/S:97 | 按请求/读响应/写响应流及端口的安全上下文隔离 |
| `rtl/security/security_key_store.v` | E/S / planned / E:80/S:98 | 密钥/有效性和受控访问状态，外部可信注入边界 |
| `rtl/security/security_key_roll.v` | E/S / planned / E:81/S:99 | 三流独立换钥、切换ACK和在途安全上下文生命周期 |
| `rtl/security/security_counter.v` | E/S / planned / E:82/S:100 | 安全计数器单调性、预算/过期与重置作用域 |
| `rtl/security/security_auth_check.v` | E/S / planned / E:83/S:101 | 实际认证结果与数据释放/错误隔离之间的原子准入 |
| `rtl/security/security_inc_domain.v` | E/S / planned / E:84/S:102 | INC组身份/成员及普通事务安全域绑定 |
| `rtl/security/security_trusted_config.v` | E/S / planned / E:85/S:103 | 受信配置、LOCK与平台RoT/TEE/密钥注入边界 |

### management

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/management/management_csr.v` | E/S / planned / E:86/S:104 | 数字IP配置/状态CSR与固件管理桥总装 |
| `rtl/management/csr_decode.v` | E/S / planned / E:87/S:105 | 本地CSR地址译码、访问权限和一致读写；地址图待冻结 |
| `rtl/management/csr_capability.v` | E/S / planned / E:88/S:106 | 角色/模式/station能力及已实现功能位报告 |
| `rtl/management/csr_route_config.v` | E/S / planned / E:89/S:107 | 设备/端口/路由/vPod配置提交与可见性 |
| `rtl/management/csr_security_config.v` | E/S / planned / E:90/S:108 | 密钥/安全上下文配置控制与访问隔离 |
| `rtl/management/telemetry_counters.v` | E/S / planned / E:91/S:109 | 端口/协议错误/性能计数、快照与溢出语义 |
| `rtl/management/interrupt_controller.v` | E/S / planned / E:92/S:110 | 事件mask、pending、确认和主机/固件中断接口 |
| `rtl/management/error_snapshot.v` | E/S / planned / E:93/S:111 | 协议错误上下文、时间戳和RAS快照的原子保存 |
| `rtl/management/management_agent_bridge.v` | E/S / planned / E:94/S:112 | SMA/NMA/Controller软件与CSR/固件事件的边界，不实现网络协议 |

### ras

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/ras/ras_controller.v` | E/S / planned / E:95/S:113 | 故障分类、隔离、恢复与管理事件总装 |
| `rtl/ras/ras_error_classify.v` | E/S / planned / E:96/S:114 | 控制错误、Data/BE/parity/poison与不可定位错误作用域分类 |
| `rtl/ras/ras_tl_drop.v` | E/S / planned / E:97/S:115 | 按适用端口TL双向Drop及可信/不可信信用状态区分 |
| `rtl/ras/ras_originator_isolation.v` | E/S / planned / E:98/S:116 | 端点station或Switch INC出口Originator Isolation与迟到响应丢弃 |
| `rtl/ras/ras_completion_timeout.v` | E/S / planned / E:99/S:117 | 有状态请求watchdog、dummy完成和同拍真实完成竞态 |
| `rtl/ras/ras_link_recovery.v` | E/S / planned / E:100/S:118 | 按角色Link Down/Up作用域、既有UPLI信用保持与恢复 |
| `rtl/ras/ras_cper_bridge.v` | E/S / planned / E:101/S:119 | 硬件错误记录到软件CPER/持久化服务交接，不伪装片上持久存储 |

### common

| 文件 | 角色 / 状态 / slot | 职责 |
|---|---|---|
| `rtl/common/clock_reset_manager.v` | E/S / planned / E:102/S:120 | 各域时钟/复位状态、释放同步和平台控制总装 |
| `rtl/common/reset_domain_controller.v` | E/S / planned / E:103/S:121 | 同步/异步边界明确的reset分发、释放和epoch状态 |
| `rtl/common/clock_platform_adapter.v` | E/S / planned / E:104/S:122 | PLL/无毛刺MUX/lock和参考时钟平台接口，不实现模拟PLL |
| `rtl/common/cdc_event_bridge.v` | E/S / planned / E:105/S:123 | 跨域控制事件/握手的可靠传递，域与时限契约待冻结 |
| `rtl/common/cdc_data_fifo.v` | E/S / planned / E:106/S:124 | 真实异步数据缓冲、完整占用和跨域reset边界 |
| `rtl/common/sram_ecc_adapter.v` | E/S / planned / E:107/S:125 | 生产SRAM端口、ECC错误和替换模型边界，不继承旧工程宏签核 |
| `rtl/common/diagnostic_event_mux.v` | E/S / planned / E:108/S:126 | 统一内部诊断来源/时间戳路由及无丢失背压边界 |

## 管理软件与外部平台

| 文件 | 职责 |
|---|---|
| `software/agents/sma_agent.py` | 设备/端口管理、邻居信息与状态访问 |
| `software/agents/nma_agent.py` | 节点管理汇聚、设备生命周期与事件 |
| `software/controller/pod_controller.py` | Pod发现/配置、vPod建立删除及全局资源协调 |
| `software/services/gnmi_service.py` | 官方UALink扩展/YANG锁定后的gNMI控制与遥测服务 |
| `software/services/redfish_service.py` | 规范Redfish/RAS映射与管理服务 |
| `software/controller/topology_manager.py` | ID/plane/邻居/bifurcation拓扑验证与发现 |
| `software/controller/route_manager.py` | 合法路由对象、更新提交和转发一致性 |
| `software/controller/vpod_manager.py` | vPod创建/成员隔离/teardown生命周期 |
| `software/agents/security_manager.py` | 可信配置/密钥注入/LOCK和访问权限平台协调 |
| `software/agents/ras_manager.py` | 故障工作负载处置、恢复与headless运行边界 |
| `software/ras/cper_store.py` | CPER记录转换及平台跨重启持久化 |
| `software/services/telemetry_service.py` | 时间戳/计数/错误快照的订阅与导出 |
| `software/drivers/ip_driver.py` | CSR、事件、中断和固件通道主机驱动参考 |

| 外部边界 | 数字适配模块 | 平台职责 |
|---|---|---|
| analog_serdes | `phy_serdes_adapter` | PMA analog TX/RX/CDR/equalization and package channel |
| clock_platform | `clock_platform_adapter` | PLL/reference clock/glitchless mux characterized library |
| trusted_platform | `security_trusted_config` | RoT/TEE/attestation/secure provisioning and protected key storage |
| persistent_store | `ras_cper_bridge` | Across-restart CPER/log storage platform |

SMA/NMA/Pod Controller、gNMI/YANG/Redfish/CPER的官方配套资产、schema和TLS/mTLS要求仍需按M规范及D02/D03锁定；本清单不分配厂商UART命令、Vendor ID或私有协议。UART模块仅保留标准带内不透明DWORD收发与管理交接。

## 未决规范与骨架边界

| 未决项 | 涉及模块 |
|---|---|
| A05/A06 | `security_request_map`, `security_response_map` |
| A09 | `tl_response_compress`, `tl_response_decompress` |
| A10 | `inc_numeric_dispatch`, `inc_fp_alu` |
| A13 | `station_port_identity`, `security_inc_domain` |
| A18 | `inc_block_drain` |
| A19 | `dl_crc_tx`, `dl_crc_rx`, `dl_tx_framer`, `dl_rx_deframer` |
| A20 | `dl_uart_tx_source`, `dl_uart_firmware_adapter` |
| A21 | `dl_watchdog` |
| D01 | `phy_pcs_tx`, `phy_pcs_rx`, `phy_fec_encode`, `phy_fec_decode` |
| D02/D03 | `gnmi_service`, `redfish_service`, `cper_store` |

未决项允许先建立明确标记未实现的模块边界，不允许填入猜测的CRC位序、压缩响应编码、安全字段映射、DO=1结束动作、UART信用时基或LLR首次watchdog装载规则。

## 后续逐模块验收顺序

1. **层级齐全**：全部planned文件存在、module名不重、两个角色聚合层各slot覆盖一次；既有源保持原接口；两个top可展开，未实现服务必须失败关闭。此项只表示结构完整。
2. **模块契约与功能**：按依赖图分批冻结原生接口/本地接口，逐个写独立向量/模型与失败检查，再替换壳；功能通过不自动修改相邻模块的协议假设。
3. **相邻连接**：核对时钟/复位时期、握手、信用/所有权、上下文与数据关联，补接口故障注入；先完成Endpoint真实Read请求到完成，再扩全部事务，同时推进实际Switch转发。
4. **系统闭环**：Endpoint—Switch—Endpoint、多VC/多station、INC/安全/管理和故障恢复并发验证；覆盖、性能、CDC/RDC、实际PHY/宏和工艺签核独立报告。

第一阶段不得以未实现壳的数量、展开通过或pending位图覆盖宣称协议功能完成。当前模块库存所用规范族F01–F21仍不是完整逐条规范分母，后续发现真正独立职责时按稳定slot规则追加。
