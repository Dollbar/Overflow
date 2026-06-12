`timescale 1ns/1ps
`default_nettype none
// Station RX TL到Switch internal flit的可信envelope边界。
// tl_msg只作为原始半Flit Message标志保存，绝不被解释为事务class。
// 当前接口要求相邻已验证TL decoder证明本拍恰好对应一个typed envelope；packed多目的TL必须在前级拆分。
module switch_station_tl_ingress_adapter #(
 parameter integer C_PORTS=8,parameter integer C_COUNT_WIDTH=4,parameter integer C_NUM_CLASSES=4
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_PORTS-1:0] i_valid,output wire [C_PORTS-1:0] o_ready,
 input wire [C_PORTS*512-1:0] i_tl_data,input wire [C_PORTS*2-1:0] i_tl_msg,
 input wire [C_PORTS-1:0] i_decode_valid,input wire [C_PORTS-1:0] i_single_envelope,
 input wire [C_PORTS*10-1:0] i_dst_id,input wire [C_PORTS*2-1:0] i_class,
 input wire [C_PORTS*2-1:0] i_original_vc,input wire [C_PORTS-1:0] i_original_pool,
 input wire [C_PORTS*10-1:0] i_source_port,input wire [C_PORTS-1:0] i_sop,input wire [C_PORTS-1:0] i_eop,
 input wire [C_PORTS*C_COUNT_WIDTH-1:0] i_packet_flits,
 output wire [C_PORTS-1:0] o_valid,input wire [C_PORTS-1:0] i_ready,
 output wire [C_PORTS*512-1:0] o_data,output wire [C_PORTS*2-1:0] o_tl_msg,
 output wire [C_PORTS*10-1:0] o_dst_id,output wire [C_PORTS*2-1:0] o_class,
 output wire [C_PORTS*2-1:0] o_original_vc,output wire [C_PORTS-1:0] o_original_pool,
 output wire [C_PORTS*10-1:0] o_source_port,output wire [C_PORTS-1:0] o_sop,output wire [C_PORTS-1:0] o_eop,
 output wire [C_PORTS*C_COUNT_WIDTH-1:0] o_packet_flits,output wire [C_PORTS-1:0] o_error,
 output wire o_config_error
);
 localparam CONFIG_LEGAL=(C_PORTS>=1)&&(C_PORTS<=1024)&&(C_COUNT_WIDTH>=1)&&(C_COUNT_WIDTH<=16)&&(C_NUM_CLASSES>=1)&&(C_NUM_CLASSES<=4);
 assign o_config_error=!CONFIG_LEGAL;
 genvar p;
 generate for(p=0;p<C_PORTS;p=p+1)begin:g_port
  reg hold_valid_q,hold_sop_q,hold_eop_q,hold_pool_q,error_q,owner_q,owner_pool_q;
  reg [511:0] hold_data_q;reg [1:0] hold_msg_q,hold_class_q,hold_vc_q,owner_class_q,owner_vc_q;
  reg [9:0] hold_dst_q,hold_src_q,owner_dst_q,owner_src_q;
  reg [C_COUNT_WIDTH-1:0] hold_flits_q,owner_flits_q,remaining_q;
  wire output_fire=CONFIG_LEGAL&&i_rstn&&hold_valid_q&&i_ready[p];
  wire load_space=!hold_valid_q||output_fire;
  wire [1:0] input_class=i_class[p*2+:2];
  wire [C_COUNT_WIDTH-1:0] input_flits=i_packet_flits[p*C_COUNT_WIDTH+:C_COUNT_WIDTH];
  wire new_phase=!owner_q;
  wire class_legal=(C_NUM_CLASSES==4)||((C_NUM_CLASSES==3)&&(input_class!=2'd3))||((C_NUM_CLASSES==2)&&!input_class[1])||((C_NUM_CLASSES==1)&&(input_class==2'd0));
  wire common_legal=i_decode_valid[p]&&i_single_envelope[p]&&class_legal&&(input_flits!={C_COUNT_WIDTH{1'b0}});
  wire identity_legal=new_phase?i_sop[p]:(!i_sop[p]&&
   (i_dst_id[p*10+:10]==owner_dst_q)&&(input_class==owner_class_q)&&
   (i_original_vc[p*2+:2]==owner_vc_q)&&(i_original_pool[p]==owner_pool_q)&&
   (i_source_port[p*10+:10]==owner_src_q)&&(input_flits==owner_flits_q));
  wire end_legal=new_phase?(i_eop[p]==(input_flits=={{(C_COUNT_WIDTH-1){1'b0}},1'b1})):
   (i_eop[p]==(remaining_q=={{(C_COUNT_WIDTH-1){1'b0}},1'b1}));
  wire input_legal=common_legal&&identity_legal&&end_legal;
  wire input_fire=CONFIG_LEGAL&&i_rstn&&!error_q&&i_valid[p]&&input_legal&&load_space;
  assign o_ready[p]=CONFIG_LEGAL&&i_rstn&&!error_q&&input_legal&&load_space;
  assign o_valid[p]=CONFIG_LEGAL&&i_rstn&&hold_valid_q;
  assign o_data[p*512+:512]=o_valid[p]?hold_data_q:512'd0;
  assign o_tl_msg[p*2+:2]=o_valid[p]?hold_msg_q:2'd0;
  assign o_dst_id[p*10+:10]=o_valid[p]?hold_dst_q:10'd0;
  assign o_class[p*2+:2]=o_valid[p]?hold_class_q:2'd0;
  assign o_original_vc[p*2+:2]=o_valid[p]?hold_vc_q:2'd0;
  assign o_original_pool[p]=o_valid[p]&&hold_pool_q;
  assign o_source_port[p*10+:10]=o_valid[p]?hold_src_q:10'd0;
  assign o_sop[p]=o_valid[p]&&hold_sop_q;assign o_eop[p]=o_valid[p]&&hold_eop_q;
  assign o_packet_flits[p*C_COUNT_WIDTH+:C_COUNT_WIDTH]=o_valid[p]?hold_flits_q:{C_COUNT_WIDTH{1'b0}};
  assign o_error[p]=!CONFIG_LEGAL||(i_rstn&&error_q);
  always @(posedge i_clk)begin
   if(!i_rstn)begin
    hold_valid_q<=1'b0;hold_sop_q<=1'b0;hold_eop_q<=1'b0;hold_pool_q<=1'b0;error_q<=1'b0;owner_q<=1'b0;owner_pool_q<=1'b0;
    hold_data_q<=512'd0;hold_msg_q<=2'd0;hold_class_q<=2'd0;hold_vc_q<=2'd0;owner_class_q<=2'd0;owner_vc_q<=2'd0;
    hold_dst_q<=10'd0;hold_src_q<=10'd0;owner_dst_q<=10'd0;owner_src_q<=10'd0;hold_flits_q<={C_COUNT_WIDTH{1'b0}};owner_flits_q<={C_COUNT_WIDTH{1'b0}};remaining_q<={C_COUNT_WIDTH{1'b0}};
   end else if(CONFIG_LEGAL)begin
    if(output_fire)hold_valid_q<=1'b0;
    if(i_valid[p]&&load_space&&!input_legal)error_q<=1'b1;
    if(input_fire)begin
     hold_valid_q<=1'b1;hold_data_q<=i_tl_data[p*512+:512];hold_msg_q<=i_tl_msg[p*2+:2];
     hold_dst_q<=i_dst_id[p*10+:10];hold_class_q<=input_class;hold_vc_q<=i_original_vc[p*2+:2];hold_pool_q<=i_original_pool[p];hold_src_q<=i_source_port[p*10+:10];
     hold_sop_q<=i_sop[p];hold_eop_q<=i_eop[p];hold_flits_q<=input_flits;
     if(new_phase)begin
      owner_dst_q<=i_dst_id[p*10+:10];owner_class_q<=input_class;owner_vc_q<=i_original_vc[p*2+:2];owner_pool_q<=i_original_pool[p];owner_src_q<=i_source_port[p*10+:10];owner_flits_q<=input_flits;
      owner_q<=!i_eop[p];remaining_q<=input_flits-{{(C_COUNT_WIDTH-1){1'b0}},1'b1};
     end else if(i_eop[p])begin owner_q<=1'b0;remaining_q<={C_COUNT_WIDTH{1'b0}};end
     else remaining_q<=remaining_q-{{(C_COUNT_WIDTH-1){1'b0}},1'b1};
    end
   end
  end
 end endgenerate
endmodule
`default_nettype wire
