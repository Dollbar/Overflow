`timescale 1ns/1ps
`default_nettype none
// TL端口到四类内部事务的最小真实集成边界。
// i_read_kind/i_read_sop/i_read_eop必须与当前tl_port接收FIFO头严格对齐，并在头项未退休时保持稳定；
// 它们代表相邻明文TL解码阶段的结果，不是Station共享状态，也不建立第二份credit账本。
module tl_port_transaction_demux #(
 parameter integer WIDTH=8, // 每个TL credit计数器的位宽。
 parameter integer HEADER_DEPTH=2, // 发送header队列深度，原样传给tl_port。
 parameter integer BANK_DEPTH=3, // 发送data bank深度，原样传给tl_port。
 parameter integer RX_DEPTH=40, // 唯一接收存储深度，仍由tl_receive_credit拥有。
 parameter integer HEADER_COUNT_WIDTH=(HEADER_DEPTH<2)?1:(HEADER_DEPTH<4)?2:3, // header计数宽度。
 parameter integer DATA_COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:3, // data计数宽度。
 parameter integer RX_COUNT_WIDTH=(RX_DEPTH<2)?1:(RX_DEPTH<4)?2:(RX_DEPTH<8)?3:(RX_DEPTH<16)?4:(RX_DEPTH<32)?5:(RX_DEPTH<64)?6:7, // RX计数宽度。
 parameter integer PACKET_BOUNDARY_ENABLE=0
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire i_link_reset, // 端口时钟、复位、使能和每链路复位。
 input wire i_start,input wire i_shared,input wire i_security_enable,input wire i_compression_enable, // credit启动、池模式及不支持特性门控。
 input wire [20*WIDTH-1:0] i_capacities, // 二十类本地接收容量。
 input wire [1:0] i_source_valid,input wire [511:0] i_source_control, // Request/Response发送控制输入。
 input wire [1:0] i_source_tags_valid,input wire [1023:0] i_source_tags, // 发送tag输入。
 input wire [3:0] i_data_valid,input wire [511:0] i_data0,input wire [511:0] i_data1, // 发送payload输入。
 output wire [1:0] o_source_ready,output wire [1:0] o_source_captured,output wire [1:0] o_data_ready, // 发送源握手。
 output wire [3:0] o_data_accepted, // 四个payload半部的真实接纳事件。
 output wire o_tx_valid,output wire [511:0] o_tx_flit,output wire [1:0] o_tx_msg,output wire o_tx_packet_sop,o_tx_packet_eop,input wire i_tx_ready, // 相邻DL方向的TL TX通道。
 input wire i_rx_valid,input wire [511:0] i_rx_flit,input wire [1:0] i_rx_msg,output wire o_rx_ready,output wire o_rx_taken, // 已验证明文TL RX通道。
 output wire o_head_valid,output wire [511:0] o_head_flit,output wire [1:0] o_head_msg, // 暴露真实FIFO头，decoder不得从退休计数猜测语义。
 input wire i_decode_valid,output wire o_decode_ready, // decoder声明kind/边界对应当前头后才允许唯一退休握手。
 input wire [2:0] i_read_kind,input wire i_read_sop,input wire i_read_eop, // 当前接收FIFO头的语义分类和packet边界。
 output wire [3:0] o_kind_valid,input wire [3:0] i_kind_ready, // Request/OrigData/ReadRsp/WriteRsp独立握手。
 output wire [2047:0] o_kind_data,output wire [511:0] o_kind_meta, // 每类512-bit payload和128-bit opaque metadata。
 output wire [11:0] o_kind,output wire [3:0] o_kind_sop,output wire [3:0] o_kind_eop, // 每类kind与边界观察口。
 output wire o_owner_valid,output wire [2:0] o_owner_kind, // demux packet tenure观察口。
 output wire o_invalid_kind,output wire o_kind_change_error,output wire o_framing_error, // sticky语义诊断。
 output wire o_read_retired, // 唯一RX FIFO头退休事件；与原tl_receive_credit事件完全相同。
 output wire [1:0] o_read_msg,output wire [5:0] o_read_classes,output wire [79:0] o_read_releases, // 当前头项信用元数据观察口。
 output wire o_start_ready,output wire o_start_taken,output wire o_local_done,output wire o_peer_done,output wire o_peer_shared, // credit初始化状态。
 output wire [20*(WIDTH+1)-1:0] o_capacity,output wire [20*(WIDTH+1)-1:0] o_available,output wire [20*(WIDTH+1)-1:0] o_pending, // 现有唯一ledger观察口。
 output wire [89:0] o_tx_validation_state,output wire o_idle,output wire o_feature_error,output wire o_error,output wire o_implemented // 端口状态和组合错误证书。
);
 wire read_valid;wire [511:0] read_flit; // tl_port唯一接收FIFO的当前头项。
 wire demux_ready;wire port_error,port_implemented,demux_error,demux_implemented,port_idle,unused_port_feature_error; // 两个真实叶模块的组合状态。
 wire [127:0] read_meta={40'd0,o_read_releases,o_read_classes,o_read_msg}; // 完整保存credit释放向量、class和msg，不产生新账本。
 wire unused_legacy_ready,unused_legacy_valid;wire [511:0] unused_legacy_data;wire [127:0] unused_legacy_meta; // tl_port旧scaffold固定失败关闭观察线。
 wire unused_demux_valid;wire [511:0] unused_demux_data;wire [127:0] unused_demux_meta; // demux旧聚合scaffold固定失败关闭观察线。

 // 现有tl_port继续独占TX/RX credit、接收FIFO和FC publish；demux_ready是它唯一的读退休条件。
 tl_port #(.WIDTH(WIDTH),.HEADER_DEPTH(HEADER_DEPTH),.BANK_DEPTH(BANK_DEPTH),.RX_DEPTH(RX_DEPTH),.HEADER_COUNT_WIDTH(HEADER_COUNT_WIDTH),.DATA_COUNT_WIDTH(DATA_COUNT_WIDTH),.RX_COUNT_WIDTH(RX_COUNT_WIDTH),.PACKET_BOUNDARY_ENABLE(PACKET_BOUNDARY_ENABLE)) u_port(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_link_reset(i_link_reset),.i_start(i_start),.i_shared(i_shared),
  .i_security_enable(1'b0),.i_compression_enable(1'b0),.i_capacities(i_capacities),
  .i_source_valid(i_source_valid),.i_source_control(i_source_control),.i_source_tags_valid(i_source_tags_valid),.i_source_tags(i_source_tags),
  .i_data_valid(i_data_valid),.i_data0(i_data0),.i_data1(i_data1),.o_source_ready(o_source_ready),.o_source_captured(o_source_captured),.o_data_ready(o_data_ready),.o_data_accepted(o_data_accepted),
  .o_tx_valid(o_tx_valid),.o_tx_flit(o_tx_flit),.o_tx_msg(o_tx_msg),.o_tx_packet_sop(o_tx_packet_sop),.o_tx_packet_eop(o_tx_packet_eop),.i_tx_ready(i_tx_ready),.i_rx_valid(i_rx_valid),.i_rx_flit(i_rx_flit),.i_rx_msg(i_rx_msg),.o_rx_ready(o_rx_ready),.o_rx_taken(o_rx_taken),
  .i_read_ready(i_decode_valid&&demux_ready),.o_read_valid(read_valid),.o_read_flit(read_flit),.o_read_msg(o_read_msg),.o_read_classes(o_read_classes),.o_read_releases(o_read_releases),
  .o_start_ready(o_start_ready),.o_start_taken(o_start_taken),.o_local_done(o_local_done),.o_peer_done(o_peer_done),.o_peer_shared(o_peer_shared),
  .o_capacity(o_capacity),.o_available(o_available),.o_pending(o_pending),.o_tx_validation_state(o_tx_validation_state),.o_idle(port_idle),.o_feature_error(unused_port_feature_error),.o_error(port_error),.o_implemented(port_implemented),
  .i_valid(1'b0),.i_data(512'd0),.i_meta(128'd0),.o_ready(unused_legacy_ready),.o_valid(unused_legacy_valid),.o_data(unused_legacy_data),.o_meta(unused_legacy_meta));

 // demux仅拥有一个弹性槽和packet owner；接纳头项时由上面的同一个ready使tl_receive_credit退休一次。
 tl_transaction_demux u_demux(
  .i_clk(i_clk),.i_rstn(i_rstn&&!i_link_reset),.i_enable(i_enable),
  .i_valid(read_valid&&i_decode_valid),.i_data(read_flit),.i_meta(read_meta),.i_kind(i_read_kind),.i_sop(i_read_sop),.i_eop(i_read_eop),.o_ready(demux_ready),
  .o_kind_valid(o_kind_valid),.i_kind_ready(i_kind_ready),.o_kind_data(o_kind_data),.o_kind_meta(o_kind_meta),.o_kind(o_kind),.o_kind_sop(o_kind_sop),.o_kind_eop(o_kind_eop),
  .o_owner_valid(o_owner_valid),.o_owner_kind(o_owner_kind),.o_invalid_kind(o_invalid_kind),.o_kind_change_error(o_kind_change_error),.o_framing_error(o_framing_error),
  .o_implemented(demux_implemented),.o_error(demux_error),.o_valid(unused_demux_valid),.o_data(unused_demux_data),.o_meta(unused_demux_meta));

 assign o_head_valid=read_valid;assign o_head_flit=read_valid?read_flit:512'd0;assign o_head_msg=read_valid?o_read_msg:2'd0; // 无头项时不泄露旧FIFO内容。
 assign o_decode_ready=read_valid&&demux_ready; // 只有真实头存在且demux可接纳时，decoder valid才能形成事务。
 assign o_read_retired=read_valid&&i_decode_valid&&demux_ready; // 该事件就是u_port.u_receive的retired/release_taken条件，没有旁路或复制。
 reg unsupported_q; // Security/Compression不属于本版本，只记sticky unsupported，绝不作为运行时reset清除在途明文包。
 always @(posedge i_clk)begin
  if(!i_rstn||i_link_reset)unsupported_q<=1'b0; // 只由真实链路复位清除诊断。
  else if(i_enable&&(i_security_enable||i_compression_enable))unsupported_q<=1'b1; // 任一不支持请求被明确记录。
 end
 assign o_feature_error=unsupported_q; // sticky unsupported状态不伪装成安全功能。
 assign o_idle=port_idle&&!(|o_kind_valid)&&!o_owner_valid; // demux已退休但尚未交付或packet owner存在时仍为busy。
 assign o_error=port_error||demux_error||unsupported_q; // 任一真实叶模块或unsupported请求都在集成边界可见。
 assign o_implemented=port_implemented&&demux_implemented; // 两个组成模块都实现时才声明partial wrapper存在。
 wire unused_observation=unused_port_feature_error||unused_legacy_ready||unused_legacy_valid||unused_legacy_data[0]||unused_legacy_meta[0]||unused_demux_valid||unused_demux_data[0]||unused_demux_meta[0]; // 明确消费失败关闭观察线，避免lint隐藏未接通路径。
endmodule
`default_nettype wire
