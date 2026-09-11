# Endpoint 研发顶层接口与保持约束

`rtl/endpoint/ualink_endpoint_top.v`提取已验证双端数字链路的四个真实组件，实例名固定
`u_tx`、`u_credit`、`u_receive`、`u_dl`。它接收prepared字段/数据并交付真实接收SRAM记录；
尚未包含Read执行、Tag表或应用事务完成器。

## 先行设计与自检约束

DL预约接口不能直接接外部ready。预约后固定延迟返回的完整头、数据和序号必须已有
容量。顶层使用一个完整holding槽和一个inflight预约标志：仅两者均为空时预约；
真实`o_issue_accept`置inflight；下一拍实际DL输出整体写入holding并清inflight；
仅外部`valid && ready`退休holding。为使容量关系简单，消费、预约和捕获不旁路合并。

必须验证：未返回的预约不重复；holding停顿时544位字、payload/replay/sequence均稳定；
停顿撤销只发送一次；返回字不可用旧数据替代；holding或inflight被统一复位取消。
`verification/ip_tops/endpoint_buffer_tb.sv`在真实顶层的DL输出边界注入受控返回，
单独检查这个新增暂存适配器；它不替代root负责的两真实Endpoint及Switch回归。

主链路TX是`o_link_valid/o_link_data[543:0]/i_link_ready`，RX是
`i_link_valid/i_link_data[543:0]/i_link_crc_ok/o_link_ready`。
544位字为`{24-bit DL header,520-bit本地payload}`，后者是
`{6'b0,2-bit TL msg,512-bit TL flit}`。CRC状态由环境明确给出；每次预约均指定
`i_new_group=1`，属于本地研发链路约定。这不是标准640-byte DL framing或PHY接口。

RX只在valid&&ready产生事件；ready在运行时为1，初始化/同步link-reset期间为0。
实际DL去重并接纳payload后才提交真实TL账本和接收SRAM，不增加旁路信用或无限缓存。
容量必须由`i_start/i_capacities`经真实接收信用发布器初始化；20槽默认每槽1需要
40个RX存储字。初始化配置、Auth和shared模式在复位时期内保持稳定。

`i_link_reset`与低有效`i_rstn`共同形成所有四层以及holding的同步复位条件；
必须在时钟沿保持有效，之后重新进行信用初始化。此操作是研发全层清除，不是规范
LinkDown恢复，不保证保存未完成应用事务。

## 参数与应用接口

默认`WIDTH=8, HEADER_DEPTH=2, BANK_DEPTH=3, RX_DEPTH=40, DL_DEPTH=3`。
HEADER/DATA/RX计数位宽按对应深度派生，与原组件一致；WIDTH支持8..16，
DL深度仍受现有重放组件范围约束。最小容量合法性由真实子模块处理。

两类source各有256位Control与512位AuthTags，`i_source_valid[1:0]`对应Request/Response。
真实源组捕获由`o_source_captured`确认；`o_source_ready`供源观察。
两类Data分别提供最多两个256位半Flit，`i_data_valid`和`o_data_accepted`每类占2位，
值为0..2；`i_data0/i_data1`各512位，每类占256位。Header捕获不代表Data已全部接纳。

应用接收接口包含`o_read_valid/flit/msg/classes/releases`与`i_read_ready`，
完整600位记录一次握手退休。释放向量仍交真实信用归还路径，应用不得另造信用归还。

`o_link_payload/o_link_replay/o_link_sequence`随holding整体保持，仅用于监视，
不是新增线上字段。公开容量、余额、pending、各层计数及验证状态用于研发诊断。
`o_done`为本地信用发布完成；`o_peer_done/o_peer_shared`来自实际收到的对端初始化。

`o_error`汇总真实致命、配置/源格式、不可满足容量、DL tag/metadata，以及
TL/DL提交、接收、FC/退休和holding预约不一致。正常信用等待、应用/链路背压、CRC
触发重放、收到重复重放记录不是新增fatal。`o_error`是组合诊断，环境需采样或锁存。

最终两顶层链路回归、独立轨迹审计、lint和综合由root运行并另行记录；本文不预先
宣称这些检查已通过。

## 接口观察与自检执行

完整端口声明位于模块源文件。除上述应用与链路握手外，配置输入为
`i_start/i_capacities/i_auth/i_shared/i_rx_replay_limit`，启动输出为
`o_start_ready/o_start_taken/o_config_error`。重放阈值由环境显式给出，基准测试取50。
观察输出为`o_capacity/o_available/o_pending/o_tx_pending/o_tx_validation_state`、
`o_header_count/o_data_count/o_rx_count/o_unacked_count/o_scheduled_count`。
`o_pending`是本地待发布信用，`o_tx_pending`是对端TL发送序列剩余半Flit数，两者不可互换。

可从仓库根目录按下列命令运行新增暂存器自检，`KD28_ROOT`须指向已授权外部依赖：

```sh
KD28_ROOT=/path/to/authorized/dependency
mkdir -p build/verification/ip_tops/endpoint_buffer_manual
iverilog -g2012 -s endpoint_buffer_tb \
  -o build/verification/ip_tops/endpoint_buffer_manual/sim.vvp \
  verification/ip_tops/endpoint_buffer_tb.sv $(rg --files rtl -g '*.v') \
  "$KD28_ROOT"/Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v \
  "$KD28_ROOT"/Library/models/kd28/sram/rtl/kd28_sram_sp_model.v \
  "$KD28_ROOT"/Library/models/kd28/sram/rtl/kd28_sram_sdp_model.v \
  "$KD28_ROOT"/Library/models/kd28/sram/rtl/kd28_sram_tdp_model.v \
  "$KD28_ROOT"/Library/models/kd28/sram/rtl/kd28_sram_cells.v
vvp build/verification/ip_tops/endpoint_buffer_manual/sim.vvp
```

预期输出`sim.vvp`及终端`PASS endpoint holding`。本轮实际运行使用
`build/verification/ip_tops/endpoint_buffer/`，`compile.log`与`run.log`记录编译和运行
均返回0；先前只含TB、缺少顶层时已观察到elaboration失败。
测试在真实顶层的DL返回信号边界使用受控force，隔离新增holding的时序契约；
不声称该测试单独覆盖DL/TL组合内容、信用或端到端行为。

连续无停顿时，本保守实现每三拍最多预约一个槽：预约沿、返回捕获沿、holding消费沿。
保守节拍属于研发实现选择，未作满带宽声明。下一步运行独立两Endpoint/Switch
轨迹回归并检查真实首次发送、重放、接收退休和所有信用账本，随后再做综合与时序评估。

完整模块骨架已接入 `u_scaffold`；`o_pending_features[127:0]` 的每个非零位表示相应未实现接口壳，位与模块的映射见库存及实际 aggregate。已提升模块的位保持零，既有模块的未完成能力仍须查阅库存状态。系统回归和构建入口见 `ip_top_bringup.md`。

## 真实Read事务模式

新增静态展开参数`TRANSACTION_MODE=1`选择实际`endpoint_transaction_core`；默认0仍接受原prepared源/退休接口。模式1由`i_request_*`应用描述符及`o_complete_*`结果握手、`o_mem_*`内存读与`i_mem_result_*`返回接口工作，旧prepared输入不参与源选择。完整宽度以RTL声明为准；四槽、单物理port0、Auth关闭、单64B普通Read已验证，详见[实际因果事务评审](endpoint_causal_read_review.md)。

`i_local_id`与`i_port`运行期间保持稳定；unsupported Auth/port产生`o_transaction_error`并复位局部事务核，不能作动态配置恢复。`o_outstanding_count`保持到应用完成退休，`o_completer_count`保持到Header与两半Data提交完成。Request header_taken无Tag，只反馈给唯一单Read生产者，未来多请求源必须显式扩展身份关联。

`o_error`包含事务诊断，但不是全层立即停流或协议LinkDown状态机。统一网络在途同步复位已覆盖三个窗口，详见 [复位审查](endpoint_reset_review.md)；独立端点恢复及带世代号的旧内存结果隔离尚未完成。

## 独立事务容量

`ORIGINATOR_CAPACITY` 与 `COMPLETER_CAPACITY` 追加于既有位置参数之后，默认均为 4。前者贯通实际 Tag 预约表（合法范围 1～255），后者贯通实际执行环（集成范围 1～4，保持公开 memory slot 的两位宽度）。两者可独立配置，不要求相等或为二次幂。容量非法时保留安全可展开的单槽实例，持续复位局部事务核并报告 `o_transaction_error`；请求、结果及完成握手均关闭。合法但满槽只产生背压。

实际验证范围和复现命令见 [容量验证](endpoint_capacity_review.md)。八请求的集成检查不能证明 255 槽满载；更宽 slot、完整请求长度及其他事务种类仍需后续实现。
