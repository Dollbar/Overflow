`timescale 1ns/1ps
`default_nettype none
// 四VC分布式调度器。本模块不保存、生成或扣除信用，只消费下游ready。
module tl_vc_scheduler(
 input wire i_clk,i_rstn,i_enable,
 input wire [3:0] i_vc_enable,
 input wire [3:0] i_candidate_valid,
 input wire [2047:0] i_candidate_data,
 input wire [511:0] i_candidate_meta,
 input wire [11:0] i_candidate_vc,
 input wire [3:0] i_candidate_sop,i_candidate_eop,
 output reg [3:0] o_candidate_ready,
 output wire o_valid,output wire [511:0] o_data,output wire [127:0] o_meta,
 output wire [2:0] o_vc,output wire o_sop,o_eop,input wire i_ready,
 output wire o_owner_valid,output wire [2:0] o_owner_vc,
 output wire o_invalid_vc,o_disabled_vc,o_framing_error,o_error,o_implemented,
 // 原planned scaffold输入/ready保留，功能入口明确不支持。
 input wire i_valid,input wire [511:0] i_data,input wire [127:0] i_meta,
 output wire o_ready
);
reg r_valid,r_sop,r_eop;
reg [511:0] r_data;reg [127:0] r_meta;reg [1:0] r_vc;
reg r_owner_valid;reg [1:0] r_owner_vc;reg [1:0] r_rr;
reg r_invalid_vc,r_disabled_vc,r_framing_error;
wire active=i_rstn&&i_enable;
wire release_now=active&&r_valid&&i_ready&&r_eop;
wire effective_owner=r_owner_valid&&!release_now;
wire load_space=!r_valid||i_ready;
wire [1:0] arbitration_base=release_now?(r_vc+2'd1):r_rr;

reg selected_valid;reg [1:0] selected_vc;
reg invalid_event,disabled_event,framing_event;
reg [3:0] invalid_mask,disabled_mask,framing_mask;
integer index,offset,scan;
always @* begin
 selected_valid=1'b0;selected_vc=2'd0;o_candidate_ready=4'd0;
 invalid_event=1'b0;disabled_event=1'b0;framing_event=1'b0;
 invalid_mask=4'd0;disabled_mask=4'd0;framing_mask=4'd0;
 index=0;offset=0;scan=0;
 for(index=0;index<4;index=index+1)begin
  if(i_candidate_valid[index]&&((i_candidate_vc[index*3+:3]>3)||
     (i_candidate_vc[index*3+:3]!=index[2:0])))invalid_mask[index]=1'b1;
  if(i_candidate_valid[index]&&!i_vc_enable[index])disabled_mask[index]=1'b1;
  if(!effective_owner&&i_candidate_valid[index]&&i_vc_enable[index]&&
     (i_candidate_vc[index*3+:3]==index[2:0])&&!i_candidate_sop[index])framing_mask[index]=1'b1;
 end
 if(effective_owner)begin
  if(i_candidate_valid[r_owner_vc]&&!invalid_mask[r_owner_vc]&&i_vc_enable[r_owner_vc]&&
     (i_candidate_vc[r_owner_vc*3+:3]=={1'b0,r_owner_vc}))begin
   if(i_candidate_sop[r_owner_vc])framing_mask[r_owner_vc]=1'b1;
   else begin selected_valid=1'b1;selected_vc=r_owner_vc;end
  end
 end else begin
  for(offset=0;offset<4;offset=offset+1)begin
   scan={30'd0,arbitration_base}+offset;if(scan>=4)scan=scan-4;
   if(!selected_valid&&i_candidate_valid[scan]&&!invalid_mask[scan]&&!disabled_mask[scan]&&
      !framing_mask[scan]&&i_candidate_vc[scan*3+:3]==scan[2:0]&&i_candidate_sop[scan])begin
    selected_valid=1'b1;selected_vc=scan[1:0];
   end
  end
 end
 invalid_event=|invalid_mask;disabled_event=|disabled_mask;framing_event=|framing_mask;
 if(active&&load_space&&selected_valid&&!invalid_mask[selected_vc]&&!disabled_mask[selected_vc]&&!framing_mask[selected_vc])
  o_candidate_ready[selected_vc]=1'b1;
end

always @(posedge i_clk)begin
 if(!i_rstn||!i_enable)begin
  r_valid<=1'b0;r_sop<=1'b0;r_eop<=1'b0;r_data<=512'd0;r_meta<=128'd0;r_vc<=2'd0;
  r_owner_valid<=1'b0;r_owner_vc<=2'd0;r_rr<=2'd0;
  r_invalid_vc<=1'b0;r_disabled_vc<=1'b0;r_framing_error<=1'b0;
 end else begin
  if(invalid_event)r_invalid_vc<=1'b1;
  if(disabled_event)r_disabled_vc<=1'b1;
  if(framing_event)r_framing_error<=1'b1;
  if(r_valid&&i_ready)begin
   r_valid<=1'b0;
   if(r_eop)begin r_owner_valid<=1'b0;r_rr<=r_vc+2'd1;end
  end
  if(|o_candidate_ready)begin
   r_valid<=1'b1;r_data<=i_candidate_data[selected_vc*512+:512];
   r_meta<=i_candidate_meta[selected_vc*128+:128];r_vc<=selected_vc;
   r_sop<=i_candidate_sop[selected_vc];r_eop<=i_candidate_eop[selected_vc];
   if(!effective_owner)begin r_owner_valid<=1'b1;r_owner_vc<=selected_vc;end
  end
 end
end
assign o_valid=active&&r_valid;assign o_data=o_valid?r_data:512'd0;assign o_meta=o_valid?r_meta:128'd0;
assign o_vc=o_valid?{1'b0,r_vc}:3'd0;assign o_sop=o_valid&&r_sop;assign o_eop=o_valid&&r_eop;
assign o_owner_valid=active&&r_owner_valid;assign o_owner_vc=o_owner_valid?{1'b0,r_owner_vc}:3'd0;
assign o_invalid_vc=r_invalid_vc;assign o_disabled_vc=r_disabled_vc;assign o_framing_error=r_framing_error;
assign o_error=r_invalid_vc||r_disabled_vc||r_framing_error||(i_rstn&&i_enable&&i_valid);
assign o_implemented=1'b1;assign o_ready=1'b0;
wire [639:0] unused_legacy={i_data,i_meta};wire unused_observation=unused_legacy[0];
endmodule
`default_nettype wire
