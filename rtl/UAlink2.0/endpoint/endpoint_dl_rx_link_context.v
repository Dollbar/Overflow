`timescale 1ns/1ps
`default_nettype none

// 单Logical Port、单hop的DL RX上下文。完整缓存CRC wrapper输出的10x512 frame，
// 从已证实Figure 2-4位置恢复逻辑FH，再由唯一dl_replay_receiver判定sequence/replay。
// CRC0..CRC3线上octet到数学判决的A19映射仍在本模块外，i_crc_ok须与该frame绑定。
module endpoint_dl_rx_link_context(
 input wire i_clk,input wire i_rstn,input wire i_link_reset,input wire i_epoch_cleanup,input wire i_enable,
 input wire i_frame_valid,output wire o_frame_ready,input wire [511:0] i_frame_data,
 input wire i_frame_sop,input wire i_frame_eop,input wire i_fec_complete,input wire i_crc_ok,
 input wire [7:0] i_replay_limit,
 output wire o_tl_valid,input wire i_tl_ready,output wire [511:0] o_tl_flit,output wire [1:0] o_tl_msg,
 output wire o_control_valid,input wire i_control_ready,output wire o_control_replay_request,
 output wire [8:0] o_control_target,
 output wire o_received_command_valid,output wire o_received_command_replay_request,
 output wire [8:0] o_received_command_target,
 output wire o_frame_event,output wire o_frame_accept_event,
 output wire [2:0] o_bad_crc_count,output wire [7:0] o_unexpected_count,output wire o_ambiguous,
 output wire [15:0] o_reject_frame_count,
 output wire [8:0] o_last_sequence,output wire o_in_replay,
 output wire o_crc_error_event,output wire o_sequence_error_event,
 output wire o_ras_event,output wire o_error,output wire o_busy,output wire o_quiescent
);
localparam [1:0] S_CAPTURE=2'd0,S_CLASSIFY=2'd1,S_FORWARD=2'd2;
reg [1:0] state_q;reg[5119:0] frame_q;reg[3:0] capture_count_q,forward_count_q;
reg fec_q,crc_q,protocol_error_q;reg ctl_valid_q,ctl_replay_q;reg[8:0] ctl_target_q;
reg sequence_valid_q,payload_accept_q;
wire [23:0] frame_header;
wire rx_ingress,rx_accept,rx_payload_accept,rx_sequence_valid,rx_replay_request;
wire rx_command_valid,rx_command_request,rx_crc_error,rx_zero_sequence,rx_zero_command;
wire rx_storage_drop,rx_unexpected,rx_ambiguous_drop,rx_replay_drop,rx_ambiguous;
wire [8:0] rx_sequence,rx_command_target,rx_last_sequence;wire[2:0] rx_bad_crc_count;wire[7:0] rx_unexpected_count;
wire rx_replay;
wire classify_fire,control_space,path_ready,path_ras,path_validation_error,path_protocol_error,path_busy,path_quiescent;
wire[3:0] path_reject_sticky;wire[15:0] path_reject_count;
wire path_rstn;
assign path_rstn=i_rstn&&!i_link_reset;
assign frame_header=frame_q[632*8+:24];
assign control_space=!ctl_valid_q||i_control_ready;
assign classify_fire=(state_q==S_CLASSIFY)&&control_space;
assign o_frame_ready=path_rstn&&i_enable&&(state_q==S_CAPTURE);
assign o_control_valid=path_rstn&&ctl_valid_q;
assign o_control_replay_request=ctl_replay_q;
assign o_control_target=ctl_target_q;
assign o_received_command_valid=rx_command_valid;
assign o_received_command_replay_request=rx_command_request;
assign o_received_command_target=rx_command_target;
assign o_frame_event=rx_ingress;assign o_frame_accept_event=rx_accept;
assign o_bad_crc_count=rx_bad_crc_count;assign o_unexpected_count=rx_unexpected_count;assign o_ambiguous=rx_ambiguous;
assign o_reject_frame_count=path_reject_count;
assign o_last_sequence=rx_last_sequence;assign o_in_replay=rx_replay;
assign o_crc_error_event=rx_crc_error;
assign o_sequence_error_event=rx_unexpected||rx_ambiguous_drop||rx_replay_drop||rx_zero_sequence;
assign o_ras_event=rx_crc_error||rx_unexpected||rx_ambiguous_drop||rx_replay_drop||rx_zero_sequence||rx_zero_command||rx_storage_drop||path_ras;
assign o_error=protocol_error_q||path_validation_error||path_protocol_error||(|path_reject_sticky);
assign o_busy=path_rstn&&((state_q!=S_CAPTURE)||(capture_count_q!=0)||ctl_valid_q||path_busy);
assign o_quiescent=path_rstn&&(state_q==S_CAPTURE)&&(capture_count_q==0)&&!ctl_valid_q&&path_quiescent;

dl_replay_receiver u_replay_receiver(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_link_reset(i_link_reset),.i_epoch_cleanup(i_epoch_cleanup),.i_event_valid(classify_fire),
 .i_event_discard(1'b0),.i_crc_ok(crc_q&&fec_q),.i_header(frame_header),.i_replay_limit(i_replay_limit),
 .o_ingress_event(rx_ingress),.o_accept(rx_accept),.o_payload_accept(rx_payload_accept),
 .o_sequence_valid(rx_sequence_valid),.o_sequence(rx_sequence),.o_replay_request(rx_replay_request),
 .o_command_valid(rx_command_valid),.o_command_request(rx_command_request),.o_command_target(rx_command_target),
 .o_crc_error(rx_crc_error),.o_zero_sequence(rx_zero_sequence),.o_zero_command(rx_zero_command),
 .o_backpressure_drop(rx_storage_drop),.o_unexpected(rx_unexpected),.o_ambiguous_drop(rx_ambiguous_drop),
 .o_replay_drop(rx_replay_drop),.o_last_sequence(rx_last_sequence),.o_bad_crc_count(rx_bad_crc_count),
 .o_unexpected_count(rx_unexpected_count),.o_ambiguous(rx_ambiguous),.o_replay(rx_replay));

endpoint_dl_to_tl_rx_path u_dl_to_tl(
 .i_clk(i_clk),.i_rstn(path_rstn),.i_enable(i_enable),
 .i_frame_valid(state_q==S_FORWARD),.o_frame_ready(path_ready),.i_frame_data(frame_q[forward_count_q*512+:512]),
 .i_frame_sop(forward_count_q==0),.i_frame_eop(forward_count_q==9),
 .i_fec_complete(fec_q),.i_crc_commit(crc_q),.i_sequence_valid(sequence_valid_q),.i_replay_accept(payload_accept_q),
 .o_tl_valid(o_tl_valid),.i_tl_ready(i_tl_ready),.o_tl_flit(o_tl_flit),.o_tl_msg(o_tl_msg),
 .o_ras_event(path_ras),.o_validation_error(path_validation_error),.o_protocol_error(path_protocol_error),
 .o_reject_sticky(path_reject_sticky),.o_reject_frame_count(path_reject_count),
 .o_busy(path_busy),.o_quiescent(path_quiescent));

always @(posedge i_clk)begin
 if(!i_rstn||i_link_reset)begin
  state_q<=S_CAPTURE;frame_q<=5120'd0;capture_count_q<=0;forward_count_q<=0;fec_q<=0;crc_q<=0;
  protocol_error_q<=0;ctl_valid_q<=0;ctl_replay_q<=0;ctl_target_q<=0;sequence_valid_q<=0;payload_accept_q<=0;
 end else begin
  if(ctl_valid_q&&i_control_ready)ctl_valid_q<=1'b0;
  case(state_q)
   S_CAPTURE:if(i_frame_valid&&o_frame_ready)begin
    if((capture_count_q==0&&(!i_frame_sop||i_frame_eop))||(capture_count_q!=0&&(i_frame_sop||((capture_count_q==9)!=i_frame_eop))))begin
     capture_count_q<=0;protocol_error_q<=1'b1;
    end else begin
     frame_q[capture_count_q*512+:512]<=i_frame_data;
     if(capture_count_q==0)begin fec_q<=i_fec_complete;crc_q<=i_crc_ok;end
     if(capture_count_q==9)begin capture_count_q<=0;state_q<=S_CLASSIFY;end
     else capture_count_q<=capture_count_q+1'b1;
    end
   end
   S_CLASSIFY:if(classify_fire)begin
    // payload接纳产生hop-local ACK；坏序列由真实receiver产生Replay Request。
    if(rx_replay_request||rx_payload_accept)begin
     ctl_valid_q<=1'b1;ctl_replay_q<=rx_replay_request;
     ctl_target_q<=rx_replay_request?((rx_last_sequence==9'd511)?9'd1:(rx_last_sequence+1'b1)):rx_sequence;
    end
    sequence_valid_q<=rx_sequence_valid;payload_accept_q<=rx_payload_accept;forward_count_q<=0;
    if(rx_command_valid&&!frame_header[20])state_q<=S_CAPTURE;else state_q<=S_FORWARD; // 纯ACK/Replay命令不进入TL；带payload的压缩头仍须继续解包。
   end
   S_FORWARD:if(path_ready)begin
    if(forward_count_q==9)begin forward_count_q<=0;state_q<=S_CAPTURE;end
    else forward_count_q<=forward_count_q+1'b1;
   end
   default:begin state_q<=S_CAPTURE;capture_count_q<=0;forward_count_q<=0;protocol_error_q<=1'b1;end
  endcase
 end
end

endmodule
`default_nettype wire
