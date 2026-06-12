`timescale 1ns/1ps
`default_nettype none
// 单Logical Port的两路Response事务owner转移。输入事务在本地槽保存后，只有Header和
// 全部声明Data都被真实tl_port接纳，才向原生产者一次性返回完成反馈。
module endpoint_tl_response_owner_merge(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_normal_valid,input wire[255:0] i_normal_control,input wire[1:0] i_normal_data_valid,input wire[255:0] i_normal_data0,input wire[255:0] i_normal_data1,
 output wire o_normal_source_captured,output wire[1:0] o_normal_data_accepted,
 input wire i_atomic_valid,input wire[255:0] i_atomic_control,input wire[1:0] i_atomic_data_valid,input wire[255:0] i_atomic_data0,input wire[255:0] i_atomic_data1,
 output wire o_atomic_source_captured,output wire[1:0] o_atomic_data_accepted,
 output wire o_source_valid,output wire[255:0] o_source_control,input wire i_source_captured,
 output wire[1:0] o_data_valid,output wire[255:0] o_data0,output wire[255:0] o_data1,input wire[1:0] i_data_accepted,
 output wire o_busy,output wire o_quiescent,output wire o_error
);
reg valid_q,atomic_q,rr_atomic_q,source_done_q,error_q;reg[1:0] required_q,data_sent_q;reg[255:0] control_q,data0_q,data1_q;
wire malformed_offer=(!valid_q)&&((i_normal_valid&&(i_normal_data_valid==2'd3))||(i_atomic_valid&&(i_atomic_data_valid==2'd3)));
wire normal_legal=i_normal_valid&&(i_normal_data_valid!=2'd3);
wire atomic_legal=i_atomic_valid&&(i_atomic_data_valid!=2'd3);
wire choose_atomic=atomic_legal&&(!normal_legal||rr_atomic_q);
wire choose_normal=normal_legal&&!choose_atomic;
wire source_fire=o_source_valid&&i_source_captured;
wire source_complete=source_done_q||source_fire;wire[2:0] data_total={1'b0,data_sent_q}+{1'b0,i_data_accepted};
wire complete=valid_q&&source_complete&&(data_total=={1'b0,required_q});
assign o_source_valid=i_rstn&&i_enable&&valid_q&&!source_done_q;assign o_source_control=o_source_valid?control_q:256'd0;
assign o_data_valid=(i_rstn&&i_enable&&valid_q)?(required_q-data_sent_q):2'd0;assign o_data0=(data_sent_q==0)?data0_q:data1_q;assign o_data1=(data_sent_q==0)?data1_q:256'd0;
assign o_normal_source_captured=complete&&!atomic_q;assign o_normal_data_accepted=o_normal_source_captured?required_q:2'd0;
assign o_atomic_source_captured=complete&&atomic_q;assign o_atomic_data_accepted=o_atomic_source_captured?required_q:2'd0;
assign o_busy=i_rstn&&valid_q;assign o_quiescent=i_rstn&&!valid_q&&!error_q;assign o_error=i_rstn&&error_q;
always @(posedge i_clk)begin
 if(!i_rstn)begin valid_q<=0;atomic_q<=0;rr_atomic_q<=0;source_done_q<=0;required_q<=0;data_sent_q<=0;control_q<=0;data0_q<=0;data1_q<=0;error_q<=0;end
 else if(i_enable)begin
  if(malformed_offer||(i_source_captured&&!o_source_valid)||(i_data_accepted>o_data_valid))error_q<=1;
  if(!valid_q)begin
   if(choose_atomic)begin valid_q<=1;atomic_q<=1;required_q<=i_atomic_data_valid;control_q<=i_atomic_control;data0_q<=i_atomic_data0;data1_q<=i_atomic_data1;source_done_q<=0;data_sent_q<=0;end
   else if(choose_normal)begin valid_q<=1;atomic_q<=0;required_q<=i_normal_data_valid;control_q<=i_normal_control;data0_q<=i_normal_data0;data1_q<=i_normal_data1;source_done_q<=0;data_sent_q<=0;end
  end else begin
   source_done_q<=source_complete;if(i_data_accepted<=o_data_valid)data_sent_q<=data_total[1:0];
   if(complete)begin valid_q<=0;rr_atomic_q<=~atomic_q;end
  end
 end
end
endmodule
`default_nettype wire
