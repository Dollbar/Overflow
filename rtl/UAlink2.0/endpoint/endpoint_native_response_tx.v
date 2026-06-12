`timescale 1ns/1ps
`default_nettype none
// Auth-disabled ordinary/Message raw transfer, attached to the existing held Tag owner.
module endpoint_native_response_tx #(parameter integer MESSAGE_ENABLE=0)(
 input wire i_clk,i_rstn,
 input wire i_complete_valid,output wire o_complete_ready,
 input wire [1:0] i_complete_port,i_complete_vc,
 input wire [10:0] i_complete_tag,input wire i_complete_is_write,
 input wire [183:0] i_complete_payload,
 input wire [2047:0] i_complete_raw_data,input wire [255:0] i_complete_raw_headers,
 input wire [3:0] i_response_pools,
 output wire o_rd_candidate_valid,output wire [1:0] o_rd_candidate_port,o_rd_candidate_vc,
 output wire [3:0] o_rd_candidate_pools,output wire [2475:0] o_rd_candidate_payload,
 output wire o_wr_candidate_valid,output wire [1:0] o_wr_candidate_port,o_wr_candidate_vc,
 output wire o_wr_candidate_pool,output wire [100:0] o_wr_candidate_payload,
 input wire i_rd_candidate_accepted,i_rd_sent_valid,input wire [1:0] i_rd_sent_port,i_rd_sent_vc,
 input wire i_rd_sent_pool,input wire [618:0] i_rd_sent_payload,
 input wire i_wr_candidate_accepted,i_wr_sent_valid,input wire [1:0] i_wr_sent_port,i_wr_sent_vc,
 input wire i_wr_sent_pool,input wire [100:0] i_wr_sent_payload,
 output wire o_error,output wire o_busy,output wire [1:0] o_index
,input wire i_complete_is_message,input wire [2:0] i_complete_response_beats,input wire [3:0] i_complete_raw_poison // 来自同一原Tag预约及实际完整响应。
);
reg busy_q,final_q,error_q,message_q;reg [3:0] poison_q;
wire is_message=(MESSAGE_ENABLE!=0)&&i_complete_is_message;
reg [1:0] index_q,port_q,vc_q;reg [10:0] tag_q;reg write_q;
reg [183:0] payload_q;reg [3:0] pools_q;reg [2:0] beats_q;
wire [8:0] size_bytes={1'b0,i_complete_payload[21:16],2'd0}+9'd4;
wire [8:0] extent={3'd0,i_complete_payload[33:28]}+size_bytes+9'd63;
wire [2:0] beats=extent[8:6];
wire unused_extent=^extent[5:0];
wire command_write=(i_complete_payload[27:22]==6'h28)||(i_complete_payload[27:22]==6'h29);
wire admission_legal=(i_complete_payload[181:118]==64'd0)&&(i_complete_tag==i_complete_payload[97:87])&&
 (is_message?((i_complete_payload[27:22]==6'h2a)&&(i_complete_response_beats>=1)&&(i_complete_response_beats<=4)&&(!i_complete_is_write||(i_complete_response_beats==1&&i_complete_raw_poison==0))):
 ((i_complete_is_write==command_write)&&(command_write||(i_complete_payload[27:22]==6'h03))&&(beats>=1)&&(beats<=4)));

wire same_owner=i_complete_valid&&(i_complete_port==port_q)&&(i_complete_vc==vc_q)&&(i_complete_tag==tag_q)&&(i_complete_is_write==write_q)&&(i_complete_payload==payload_q)&&(!message_q||(is_message&&i_complete_response_beats==beats_q&&i_complete_raw_poison==poison_q));
wire [255:0] shifted_headers=i_complete_raw_headers>>({30'd0,index_q}*32'd64);
wire [63:0] header=shifted_headers[63:0];
wire unused_header_bits=^{shifted_headers[255:64],header[46],header[13:0]}; // TL Pool and spare stay available in the upstream raw context, not UPLI credit aliases.
wire [1:0] offset=header[43:42];
wire [2047:0] shifted_data=i_complete_raw_data>>({30'd0,offset}*32'd512);
wire unused_data_high=^shifted_data[2047:512];
wire status_legal=(message_q&&(!write_q||header[41:38]!=4'hf))||(header[41:38]==0)||(header[41:38]==2)||(header[41:38]==3)||(header[41:38]==6)||(header[41:38]==8);
wire last_index=({1'b0,index_q}+3'd1==beats_q);
wire head_legal=(header[63:60]==4'd2)&&(header[59:58]==vc_q)&&(header[57:47]==tag_q)&&(header[25:16]==payload_q[117:108])&&(header[37]==!write_q)&&(header[45:44]==0)&&(header[15:14]==0)&&status_legal&&(write_q||(({1'b0,offset}<beats_q)&&(header[36]==last_index)));
wire candidate=i_rstn&&busy_q&&!final_q&&!error_q&&same_owner&&head_legal;
wire pool=write_q?pools_q[0]:pools_q[offset]; // Explicit native per-natural-Beat policy, independent of received TL Pool.
wire [618:0] read_payload={64'd0,header[35:26],header[25:16],header[57:47],2'd0,shifted_data[511:0],header[41:38],offset,header[36],(message_q&&poison_q[offset]),2'd0};
wire [100:0] write_payload={64'd0,2'd0,header[57:47],header[41:38],header[35:26],header[25:16]};
assign o_rd_candidate_valid=candidate&&!write_q;
assign o_rd_candidate_port=o_rd_candidate_valid?port_q:2'd0;
assign o_rd_candidate_vc=o_rd_candidate_valid?vc_q:2'd0;
assign o_rd_candidate_pools=o_rd_candidate_valid?{3'd0,pool}:4'd0;
assign o_rd_candidate_payload=o_rd_candidate_valid?{1857'd0,read_payload}:2476'd0;
assign o_wr_candidate_valid=candidate&&write_q;
assign o_wr_candidate_port=o_wr_candidate_valid?port_q:2'd0;
assign o_wr_candidate_vc=o_wr_candidate_valid?vc_q:2'd0;
assign o_wr_candidate_pool=o_wr_candidate_valid&&pool;
assign o_wr_candidate_payload=o_wr_candidate_valid?write_payload:101'd0;
wire read_fire=i_rd_candidate_accepted&&i_rd_sent_valid&&o_rd_candidate_valid&&(i_rd_sent_port==port_q)&&(i_rd_sent_vc==vc_q)&&(i_rd_sent_pool==pool)&&(i_rd_sent_payload==read_payload);
wire write_fire=i_wr_candidate_accepted&&i_wr_sent_valid&&o_wr_candidate_valid&&(i_wr_sent_port==port_q)&&(i_wr_sent_vc==vc_q)&&(i_wr_sent_pool==pool)&&(i_wr_sent_payload==write_payload);
wire feedback_bad=((i_rd_candidate_accepted||i_rd_sent_valid)&&!read_fire)||((i_wr_candidate_accepted||i_wr_sent_valid)&&!write_fire);
wire owner_bad=busy_q&&(!same_owner||(!final_q&&!head_legal));
wire admission_bad=!busy_q&&i_complete_valid&&!admission_legal;
assign o_error=i_rstn&&(error_q||feedback_bad||owner_bad||admission_bad);
assign o_complete_ready=i_rstn&&busy_q&&final_q&&same_owner&&!o_error; // Registered final state is reached only after the real last native transfer.
assign o_busy=i_rstn&&busy_q;
assign o_index=index_q;
always @(posedge i_clk)begin
 if(!i_rstn)begin message_q<=0;poison_q<=0;busy_q<=0;final_q<=0;error_q<=0;index_q<=0;port_q<=0;vc_q<=0;tag_q<=0;write_q<=0;payload_q<=0;pools_q<=0;beats_q<=0;end
 else begin
  if(feedback_bad||owner_bad||admission_bad)error_q<=1'b1;
  if(!busy_q&&i_complete_valid&&admission_legal&&!error_q)begin
   message_q<=is_message;poison_q<=is_message?i_complete_raw_poison:4'd0;busy_q<=1'b1;final_q<=1'b0;index_q<=0;port_q<=i_complete_port;vc_q<=i_complete_vc;tag_q<=i_complete_tag;write_q<=i_complete_is_write;payload_q<=i_complete_payload;pools_q<=i_response_pools;beats_q<=is_message?i_complete_response_beats:(i_complete_is_write?3'd1:beats);
  end
  if(!o_error&&(read_fire||write_fire))begin
   if(write_q||last_index)final_q<=1'b1;else index_q<=index_q+2'd1;
  end
  if(o_complete_ready&&i_complete_valid)begin busy_q<=1'b0;final_q<=1'b0;index_q<=0;end
 end
end
generate if(MESSAGE_ENABLE!=0&&MESSAGE_ENABLE!=1)begin:invalid_message_mode
 ENDPOINT_NATIVE_RESPONSE_MESSAGE_MODE_MUST_BE_ZERO_OR_ONE invalid_configuration();
end endgenerate
endmodule
`default_nettype wire
