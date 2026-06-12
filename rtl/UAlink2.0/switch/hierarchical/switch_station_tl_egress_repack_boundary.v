`timescale 1ns/1ps
`default_nettype none

// Internal fabric记录到Station native TL的显式repack边界。
// 本模块不从class猜tl_msg；相邻真实TL repacker必须同时给出i_repack_valid与完整TL拍。
module switch_station_tl_egress_repack_boundary #(
 parameter integer C_PORTS=8,parameter integer C_COUNT_WIDTH=4,parameter integer C_NUM_CLASSES=4,
 parameter [3:0] C_SUPPORTED_CLASS_MASK=4'b1111
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_PORTS-1:0] i_valid,output wire [C_PORTS-1:0] o_ready,
 input wire [C_PORTS*512-1:0] i_data,input wire [C_PORTS*128-1:0] i_meta,
 input wire [C_PORTS*2-1:0] i_class,input wire [C_PORTS*2-1:0] i_original_vc,input wire [C_PORTS-1:0] i_original_pool,
 input wire [C_PORTS*10-1:0] i_source_port,input wire [C_PORTS*10-1:0] i_dst_port,
 input wire [C_PORTS-1:0] i_sop,input wire [C_PORTS-1:0] i_eop,input wire [C_PORTS*C_COUNT_WIDTH-1:0] i_packet_flits,
 input wire [C_PORTS-1:0] i_repack_valid,input wire [C_PORTS*512-1:0] i_repacked_tl_data,input wire [C_PORTS*2-1:0] i_repacked_tl_msg,
 output wire [C_PORTS-1:0] o_tl_valid,input wire [C_PORTS-1:0] i_tl_ready,
 output wire [C_PORTS*512-1:0] o_tl_data,output wire [C_PORTS*2-1:0] o_tl_msg,output wire [C_PORTS*512-1:0] o_original_data,
 output wire [C_PORTS*128-1:0] o_meta,output wire [C_PORTS*2-1:0] o_class,
 output wire [C_PORTS*2-1:0] o_original_vc,output wire [C_PORTS-1:0] o_original_pool,
 output wire [C_PORTS*10-1:0] o_source_port,output wire [C_PORTS*10-1:0] o_dst_port,
 output wire [C_PORTS-1:0] o_sop,output wire [C_PORTS-1:0] o_eop,
 output wire [C_PORTS*C_COUNT_WIDTH-1:0] o_packet_flits,output wire [C_PORTS-1:0] o_error,
 output wire o_config_error
);
 localparam CONFIG_LEGAL=(C_PORTS>=1)&&(C_PORTS<=1024)&&(C_COUNT_WIDTH>=1)&&(C_COUNT_WIDTH<=16)&&(C_NUM_CLASSES>=1)&&(C_NUM_CLASSES<=4);
 assign o_config_error=!CONFIG_LEGAL;
 genvar p;
 generate for(p=0;p<C_PORTS;p=p+1)begin:g_port
  reg valid_q,sop_q,eop_q,pool_q,error_q,owner_q,owner_pool_q;
  reg [511:0] tl_data_q,original_data_q;reg [1:0] tl_msg_q,class_q,vc_q,owner_class_q,owner_vc_q;
  reg [127:0] meta_q;reg [9:0] src_q,dst_q,owner_src_q,owner_dst_q;
  reg [C_COUNT_WIDTH-1:0] flits_q,owner_flits_q,remaining_q;
  wire output_fire=CONFIG_LEGAL&&i_rstn&&valid_q&&i_tl_ready[p];wire load_space=!valid_q||output_fire;
  wire [1:0] input_class=i_class[p*2+:2];wire [C_COUNT_WIDTH-1:0] input_flits=i_packet_flits[p*C_COUNT_WIDTH+:C_COUNT_WIDTH];
  wire class_in_range=(C_NUM_CLASSES==4)||((C_NUM_CLASSES==3)&&(input_class!=2'd3))||((C_NUM_CLASSES==2)&&!input_class[1])||((C_NUM_CLASSES==1)&&(input_class==2'd0));
  wire class_legal=class_in_range&&C_SUPPORTED_CLASS_MASK[input_class];wire new_phase=!owner_q;
  wire identity_legal=new_phase?i_sop[p]:(!i_sop[p]&&(input_class==owner_class_q)&&(i_original_vc[p*2+:2]==owner_vc_q)&&
   (i_original_pool[p]==owner_pool_q)&&(i_source_port[p*10+:10]==owner_src_q)&&(i_dst_port[p*10+:10]==owner_dst_q)&&(input_flits==owner_flits_q));
  wire end_legal=new_phase?(i_eop[p]==(input_flits=={{(C_COUNT_WIDTH-1){1'b0}},1'b1})):(i_eop[p]==(remaining_q=={{(C_COUNT_WIDTH-1){1'b0}},1'b1}));
  wire input_legal=i_repack_valid[p]&&class_legal&&(input_flits!={C_COUNT_WIDTH{1'b0}})&&identity_legal&&end_legal;
  wire input_fire=CONFIG_LEGAL&&i_rstn&&!error_q&&i_valid[p]&&input_legal&&load_space;
  assign o_ready[p]=CONFIG_LEGAL&&i_rstn&&!error_q&&input_legal&&load_space;assign o_tl_valid[p]=CONFIG_LEGAL&&i_rstn&&valid_q;
  assign o_tl_data[p*512+:512]=o_tl_valid[p]?tl_data_q:512'd0;assign o_tl_msg[p*2+:2]=o_tl_valid[p]?tl_msg_q:2'd0;
  assign o_original_data[p*512+:512]=o_tl_valid[p]?original_data_q:512'd0;
  assign o_meta[p*128+:128]=o_tl_valid[p]?meta_q:128'd0;assign o_class[p*2+:2]=o_tl_valid[p]?class_q:2'd0;
  assign o_original_vc[p*2+:2]=o_tl_valid[p]?vc_q:2'd0;assign o_original_pool[p]=o_tl_valid[p]&&pool_q;
  assign o_source_port[p*10+:10]=o_tl_valid[p]?src_q:10'd0;assign o_dst_port[p*10+:10]=o_tl_valid[p]?dst_q:10'd0;
  assign o_sop[p]=o_tl_valid[p]&&sop_q;assign o_eop[p]=o_tl_valid[p]&&eop_q;assign o_packet_flits[p*C_COUNT_WIDTH+:C_COUNT_WIDTH]=o_tl_valid[p]?flits_q:{C_COUNT_WIDTH{1'b0}};
  assign o_error[p]=!CONFIG_LEGAL||(i_rstn&&error_q);
  always @(posedge i_clk)begin
   if(!i_rstn)begin valid_q<=0;sop_q<=0;eop_q<=0;pool_q<=0;error_q<=0;owner_q<=0;owner_pool_q<=0;tl_data_q<=0;original_data_q<=0;tl_msg_q<=0;class_q<=0;vc_q<=0;owner_class_q<=0;owner_vc_q<=0;meta_q<=0;src_q<=0;dst_q<=0;owner_src_q<=0;owner_dst_q<=0;flits_q<=0;owner_flits_q<=0;remaining_q<=0;end
   else if(CONFIG_LEGAL)begin
    if(output_fire)valid_q<=0;if(i_valid[p]&&load_space&&!input_legal)error_q<=1'b1;
    if(input_fire)begin
     valid_q<=1;tl_data_q<=i_repacked_tl_data[p*512+:512];original_data_q<=i_data[p*512+:512];tl_msg_q<=i_repacked_tl_msg[p*2+:2];meta_q<=i_meta[p*128+:128];class_q<=input_class;vc_q<=i_original_vc[p*2+:2];pool_q<=i_original_pool[p];src_q<=i_source_port[p*10+:10];dst_q<=i_dst_port[p*10+:10];sop_q<=i_sop[p];eop_q<=i_eop[p];flits_q<=input_flits;
     if(new_phase)begin owner_q<=!i_eop[p];owner_class_q<=input_class;owner_vc_q<=i_original_vc[p*2+:2];owner_pool_q<=i_original_pool[p];owner_src_q<=i_source_port[p*10+:10];owner_dst_q<=i_dst_port[p*10+:10];owner_flits_q<=input_flits;remaining_q<=input_flits-{{(C_COUNT_WIDTH-1){1'b0}},1'b1};end
     else if(i_eop[p])begin owner_q<=0;remaining_q<=0;end else remaining_q<=remaining_q-{{(C_COUNT_WIDTH-1){1'b0}},1'b1};
    end
   end
  end
 end endgenerate
endmodule
`default_nettype wire
