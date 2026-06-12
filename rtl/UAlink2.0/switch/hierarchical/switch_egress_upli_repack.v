`timescale 1ns/1ps
`default_nettype none
// Fabric normalized envelope to a typed UPLI reservation boundary.
// Channel order is Request, OrigData, ReadRsp, WriteRsp from low to high.
// A supported SOP reserves every UPLI beat of the packet atomically; body
// envelopes retain the reservation and therefore carry zero new demand.
module switch_egress_upli_repack #(
 parameter integer C_PORTS=4,
 parameter integer C_OWNER_MASK_WIDTH=17,
 parameter integer C_OWNER_TOKEN_WIDTH=18
)(
 input wire i_clk,input wire i_rstn,
 input wire[C_PORTS-1:0] i_valid,output wire[C_PORTS-1:0] o_ready,
 input wire[C_PORTS*512-1:0] i_data,input wire[C_PORTS*128-1:0] i_meta,
 input wire[C_PORTS*2-1:0] i_class,input wire[C_PORTS*2-1:0] i_tl_msg,
 input wire[C_PORTS*2-1:0] i_original_upli_vc,input wire[C_PORTS-1:0] i_egress_upli_pool,
 input wire[C_PORTS-1:0] i_egress_upli_pool_valid,
 input wire[C_PORTS*10-1:0] i_source_port,input wire[C_PORTS*10-1:0] i_dst_port,
 input wire[C_PORTS-1:0] i_sop,input wire[C_PORTS-1:0] i_eop,input wire[C_PORTS*4-1:0] i_packet_flits,
 input wire[C_PORTS*C_OWNER_MASK_WIDTH-1:0] i_owner_valid,
 input wire[C_PORTS*C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH-1:0] i_owner_tokens,
 output wire[C_PORTS-1:0] o_valid,input wire[C_PORTS-1:0] i_ready,
 output wire[C_PORTS*512-1:0] o_data,output wire[C_PORTS*128-1:0] o_meta,
 output wire[C_PORTS*2-1:0] o_class,output wire[C_PORTS*2-1:0] o_tl_msg,
 output wire[C_PORTS*2-1:0] o_original_upli_vc,output wire[C_PORTS-1:0] o_original_upli_pool,
 output wire[C_PORTS*10-1:0] o_source_port,output wire[C_PORTS*10-1:0] o_dst_port,
 output wire[C_PORTS-1:0] o_sop,output wire[C_PORTS-1:0] o_eop,output wire[C_PORTS*4-1:0] o_packet_flits,
 output wire[C_PORTS*C_OWNER_MASK_WIDTH-1:0] o_owner_valid,
 output wire[C_PORTS*C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH-1:0] o_owner_tokens,
 output wire[C_PORTS-1:0] o_reserved_body,
 output wire[C_PORTS*4-1:0] o_demand_valid,output wire[C_PORTS*8-1:0] o_demand_vc,
 output wire[C_PORTS*4-1:0] o_demand_pool,output wire[C_PORTS*12-1:0] o_demand_count,
 output wire[C_PORTS-1:0] o_error,output wire o_config_error
);
 localparam CONFIG_LEGAL=(C_PORTS>=1)&&(C_PORTS<=1024)&&
  (C_OWNER_MASK_WIDTH>=1)&&(C_OWNER_MASK_WIDTH<=32)&&
  (C_OWNER_TOKEN_WIDTH>=1)&&(C_OWNER_TOKEN_WIDTH<=64);
 assign o_config_error=!CONFIG_LEGAL;
 genvar p;
 generate for(p=0;p<C_PORTS;p=p+1)begin:g_port
  reg valid_q,active_q,error_q,reserved_body_q,pool_q;
  reg[511:0] data_q;reg[127:0] meta_q;reg[1:0] class_q,msg_q,vc_q;
  reg[9:0] source_q,dst_q;reg sop_q,eop_q;reg[3:0] packet_flits_q,remaining_q;
  reg[C_OWNER_MASK_WIDTH-1:0] owner_valid_q;
  reg[C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH-1:0] owner_tokens_q;
  reg[3:0] demand_valid_q,demand_pool_q;reg[7:0] demand_vc_q;reg[11:0] demand_count_q;
  wire slot_ready=!valid_q||i_ready[p];
  wire[511:0] in_data=i_data[p*512+:512];wire[127:0] in_meta=i_meta[p*128+:128];
  wire[1:0] in_class=i_class[p*2+:2];wire[1:0] in_msg=i_tl_msg[p*2+:2];
  wire[1:0] in_vc=i_original_upli_vc[p*2+:2];wire in_pool=i_egress_upli_pool[p];
  wire[9:0] in_source=i_source_port[p*10+:10];wire[9:0] in_dst=i_dst_port[p*10+:10];
  wire[3:0] in_flits=i_packet_flits[p*4+:4];
  wire[5:0] request_cmd=in_data[123:118];wire[1:0] request_num=in_data[1:0];
  wire response_read=in_data[37];wire[1:0] response_len=in_data[45:44];
  wire request_shape=(in_data[511:128]==384'd0)&&(in_data[127:124]==4'd1)&&(in_data[117:116]==in_vc);
  wire response_shape=(in_data[511:64]==448'd0)&&(in_data[63:60]==4'd2)&&(in_data[59:58]==in_vc)&&(in_data[15:14]==2'd0);
  wire read_request=request_shape&&(request_cmd==6'd3)&&(request_num==2'd0)&&(in_flits==4'd1)&&i_eop[p];
  wire write_plain=request_shape&&(request_cmd==6'd40)&&(in_flits==({2'd0,request_num}+4'd3))&&!i_eop[p];
  wire write_full=request_shape&&(request_cmd==6'd41)&&(in_flits==({2'd0,request_num}+4'd2))&&!i_eop[p];
  wire read_response=response_shape&&response_read&&(in_flits==({2'd0,response_len}+4'd2))&&!i_eop[p];
  wire write_response=response_shape&&!response_read&&(response_len==2'd0)&&(in_data[43:42]==2'd0)&&!in_data[36]&&(in_flits==4'd1)&&i_eop[p];
  wire header_common=i_sop[p]&&(in_msg==2'd0)&&i_egress_upli_pool_valid[p]&&!active_q;
  wire header_legal=header_common&&(((in_class==2'd0)&&(read_request||write_plain||write_full))||((in_class==2'd1)&&(read_response||write_response)));
  // Fabric准入只在SOP携带完整包长；body以零表示沿用已冻结的包级预约。
  wire body_legal=!i_sop[p]&&active_q&&(in_msg==2'd0)&&i_egress_upli_pool_valid[p]&&
   (in_class==class_q)&&(in_vc==vc_q)&&(in_pool==pool_q)&&(in_meta==meta_q)&&(in_source==source_q)&&(in_dst==dst_q)&&
   (in_flits==4'd0)&&(i_eop[p]==(remaining_q==4'd1));
  wire input_legal=header_legal||body_legal;
  wire input_take=CONFIG_LEGAL&&i_rstn&&!error_q&&slot_ready&&i_valid[p];
  wire output_take=o_valid[p]&&i_ready[p];
  wire[2:0] request_data_beats={1'b0,request_num}+3'd1;
  wire[2:0] response_data_beats={1'b0,response_len}+3'd1;
  assign o_ready[p]=CONFIG_LEGAL&&i_rstn&&!error_q&&slot_ready;
  assign o_valid[p]=CONFIG_LEGAL&&i_rstn&&valid_q&&!error_q;
  assign o_data[p*512+:512]=o_valid[p]?data_q:512'd0;assign o_meta[p*128+:128]=o_valid[p]?meta_q:128'd0;
  assign o_class[p*2+:2]=o_valid[p]?class_q:2'd0;assign o_tl_msg[p*2+:2]=o_valid[p]?msg_q:2'd0;
  assign o_original_upli_vc[p*2+:2]=o_valid[p]?vc_q:2'd0;assign o_original_upli_pool[p]=o_valid[p]?pool_q:1'b0;
  assign o_source_port[p*10+:10]=o_valid[p]?source_q:10'd0;assign o_dst_port[p*10+:10]=o_valid[p]?dst_q:10'd0;
  assign o_sop[p]=o_valid[p]&&sop_q;assign o_eop[p]=o_valid[p]&&eop_q;assign o_packet_flits[p*4+:4]=o_valid[p]?packet_flits_q:4'd0;
  assign o_owner_valid[p*C_OWNER_MASK_WIDTH+:C_OWNER_MASK_WIDTH]=o_valid[p]?owner_valid_q:{C_OWNER_MASK_WIDTH{1'b0}};
  assign o_owner_tokens[p*C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH+:C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH]=o_valid[p]?owner_tokens_q:{(C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH){1'b0}};
  assign o_reserved_body[p]=o_valid[p]&&reserved_body_q;
  assign o_demand_valid[p*4+:4]=o_valid[p]?demand_valid_q:4'd0;assign o_demand_vc[p*8+:8]=o_valid[p]?demand_vc_q:8'd0;
  assign o_demand_pool[p*4+:4]=o_valid[p]?demand_pool_q:4'd0;assign o_demand_count[p*12+:12]=o_valid[p]?demand_count_q:12'd0;
  assign o_error[p]=!CONFIG_LEGAL||(i_rstn&&error_q);
  always @(posedge i_clk)begin
   if(!i_rstn)begin
    valid_q<=0;active_q<=0;error_q<=0;reserved_body_q<=0;data_q<=0;meta_q<=0;class_q<=0;msg_q<=0;vc_q<=0;pool_q<=0;
    source_q<=0;dst_q<=0;sop_q<=0;eop_q<=0;packet_flits_q<=0;remaining_q<=0;owner_valid_q<=0;owner_tokens_q<=0;demand_valid_q<=0;demand_vc_q<=0;demand_pool_q<=0;demand_count_q<=0;
   end else if(CONFIG_LEGAL)begin
    if(input_take&&!input_legal)begin valid_q<=0;active_q<=0;error_q<=1'b1;end
    else if(input_take)begin
     valid_q<=1'b1;data_q<=in_data;meta_q<=in_meta;class_q<=in_class;msg_q<=in_msg;vc_q<=in_vc;pool_q<=in_pool;
     source_q<=in_source;dst_q<=in_dst;sop_q<=i_sop[p];eop_q<=i_eop[p];reserved_body_q<=!i_sop[p];
     // body输出继续携带SOP冻结的包长，供后级reservation owner校验。
     if(i_sop[p])packet_flits_q<=in_flits;
     owner_valid_q<=i_owner_valid[p*C_OWNER_MASK_WIDTH+:C_OWNER_MASK_WIDTH];
     owner_tokens_q<=i_owner_tokens[p*C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH+:C_OWNER_MASK_WIDTH*C_OWNER_TOKEN_WIDTH];
     demand_valid_q<=4'd0;demand_vc_q<=8'd0;demand_pool_q<=4'd0;demand_count_q<=12'd0;
     if(i_sop[p])begin
      if(read_request)begin demand_valid_q[0]<=1'b1;demand_vc_q[1:0]<=in_vc;demand_pool_q[0]<=in_pool;demand_count_q[2:0]<=3'd1;active_q<=1'b0;remaining_q<=0;end
      else if(write_plain||write_full)begin
       demand_valid_q[1:0]<=2'b11;demand_vc_q[3:0]<={in_vc,in_vc};demand_pool_q[1:0]<={in_pool,in_pool};
       demand_count_q[2:0]<=3'd1;demand_count_q[5:3]<=request_data_beats;active_q<=1'b1;remaining_q<=in_flits-4'd1;
      end else if(read_response)begin
       demand_valid_q[2]<=1'b1;demand_vc_q[5:4]<=in_vc;demand_pool_q[2]<=in_pool;demand_count_q[8:6]<=response_data_beats;
       active_q<=1'b1;remaining_q<=in_flits-4'd1;
      end else begin
       demand_valid_q[3]<=1'b1;demand_vc_q[7:6]<=in_vc;demand_pool_q[3]<=in_pool;demand_count_q[11:9]<=3'd1;active_q<=1'b0;remaining_q<=0;
      end
     end else begin
      if(remaining_q==4'd1)begin active_q<=1'b0;remaining_q<=0;end else remaining_q<=remaining_q-4'd1;
     end
    end else if(output_take)valid_q<=1'b0;
   end
  end
 end endgenerate
endmodule
`default_nettype wire
