`timescale 1ns/1ps
`default_nettype none
// 已证实普通profile的fabric envelope到native TL重排器。
// V1每个Control只放一个自然字段；多拍包用一个256-bit carry恢复真实Control/Data tenure。
module switch_fabric_tl_native_repacker #(
 parameter integer C_PORTS=4,parameter integer C_COUNT_WIDTH=4
)(
 input wire i_clk,input wire i_rstn,input wire[C_PORTS-1:0] i_valid,output wire[C_PORTS-1:0] o_ready,
 input wire[C_PORTS*512-1:0] i_data,input wire[C_PORTS*128-1:0] i_meta,input wire[C_PORTS*2-1:0] i_class,
 input wire[C_PORTS*2-1:0] i_original_vc,input wire[C_PORTS-1:0] i_original_pool,input wire[C_PORTS*10-1:0] i_source_port,input wire[C_PORTS*10-1:0] i_dst_port,
 input wire[C_PORTS-1:0] i_sop,input wire[C_PORTS-1:0] i_eop,input wire[C_PORTS*C_COUNT_WIDTH-1:0] i_packet_flits,
 output wire[C_PORTS-1:0] o_tl_valid,input wire[C_PORTS-1:0] i_tl_ready,output wire[C_PORTS*512-1:0] o_tl_data,output wire[C_PORTS*2-1:0] o_tl_msg,output wire[C_PORTS*80-1:0] o_tl_demands,
 output wire[C_PORTS-1:0] o_tl_sop,output wire[C_PORTS-1:0] o_tl_eop,
 output wire[C_PORTS-1:0] o_busy,output wire[C_PORTS-1:0] o_error,output wire o_config_error
);
 localparam CONFIG_LEGAL=(C_PORTS>=1)&&(C_PORTS<=1024)&&(C_COUNT_WIDTH==4);
 wire[C_PORTS-1:0] repack_valid,repack_ready,repack_sop,repack_eop,boundary_error,demand_error;
 wire[C_PORTS*512-1:0] repack_data;wire[C_PORTS*128-1:0] repack_meta;
 wire[C_PORTS*2-1:0] repack_class,repack_vc,repack_msg;wire[C_PORTS-1:0] repack_pool;
 wire[C_PORTS*10-1:0] repack_src,repack_dst;wire[C_PORTS*4-1:0] repack_flits;
 wire[C_PORTS-1:0] boundary_tl_valid,boundary_tl_ready;wire[C_PORTS*512-1:0] boundary_tl_data;wire[C_PORTS*2-1:0] boundary_tl_msg;
 wire boundary_config_error;wire[C_PORTS*512-1:0] unused_original_data;wire[C_PORTS*128-1:0] unused_meta;
 wire[C_PORTS*2-1:0] unused_class,unused_vc;wire[C_PORTS-1:0] unused_pool,boundary_sop,boundary_eop;
 wire[C_PORTS*10-1:0] unused_src,unused_dst;wire[C_PORTS*4-1:0] unused_flits;
 assign o_config_error=!CONFIG_LEGAL||boundary_config_error;assign repack_msg={C_PORTS*2{1'b0}};
 genvar p;
 generate for(p=0;p<C_PORTS;p=p+1)begin:g_port
  reg active_q,first_q,error_q,pool_q;reg[255:0] control_q,carry_q;reg[127:0] meta_q;
  reg[1:0] class_q,vc_q;reg[9:0] src_q,dst_q;reg[3:0] input_flits_q,physical_flits_q,halves_remaining_q,fabric_remaining_q;
  wire[511:0] in_data=i_data[p*512+:512];wire[127:0] in_meta=i_meta[p*128+:128];wire[1:0] in_class=i_class[p*2+:2];wire[1:0] in_vc=i_original_vc[p*2+:2];wire[9:0] in_src=i_source_port[p*10+:10];wire[9:0] in_dst=i_dst_port[p*10+:10];wire[3:0] in_flits=i_packet_flits[p*4+:4];
  wire request=(in_class==2'd0);wire response=(in_class==2'd1);wire[5:0] command=in_data[123:118];
  wire[3:0] request_halves=(command==6'd3)?4'd0:({1'b0,in_data[1:0],1'b0}+4'd2+((command==6'd40)?4'd1:4'd0));
  wire[3:0] response_halves=in_data[37]?({1'b0,in_data[45:44],1'b0}+4'd2):4'd0;
  wire[3:0] parsed_halves=request?request_halves:response_halves;wire[3:0] parsed_fabric_flits=4'd1+((parsed_halves+4'd1)>>1);
  // i_original_pool已由Route policy选择UPLI信用账户；native TL header中的POOL属于
  // 独立TL hop语义并原样保留在in_data中，两者不要求编码相同。
  wire request_profile=request&&(in_data[511:128]==384'd0)&&(in_data[127:124]==4'd1)&&((command==6'd3)||(command==6'd40)||(command==6'd41))&&((command!=6'd3)||(in_data[1:0]==2'd0))&&(in_dst==in_data[14:5])&&(in_vc==in_data[117:116]);
  wire response_profile=response&&(in_data[511:64]==448'd0)&&(in_data[63:60]==4'd2)&&(in_data[15:14]==2'd0)&&(in_dst==in_data[25:16])&&(in_vc==in_data[59:58]);
  wire header_legal=i_sop[p]&&(request_profile||response_profile)&&(in_flits==parsed_fabric_flits)&&(i_eop[p]==(parsed_fabric_flits==4'd1));
  wire need_input=active_q&&(first_q||(halves_remaining_q!=4'd0));
  wire identity_legal=!i_sop[p]&&(in_meta==meta_q)&&(in_class==class_q)&&(in_vc==vc_q)&&(i_original_pool[p]==pool_q)&&(in_src==src_q)&&(in_dst==dst_q)&&(in_flits==input_flits_q);
  wire data_shape_legal=(halves_remaining_q!=4'd1)||(in_data[511:256]==256'd0);
  wire data_legal=identity_legal&&(i_eop[p]==(fabric_remaining_q==4'd1))&&data_shape_legal;
  wire header_direct=!active_q&&i_valid[p]&&header_legal&&(parsed_halves==4'd0);
  wire header_capture=!active_q&&i_valid[p]&&header_legal&&(parsed_halves!=4'd0);
  wire active_candidate=active_q&&((first_q&&i_valid[p]&&data_legal)||(!first_q&&((halves_remaining_q==4'd0)||(i_valid[p]&&data_legal))));
  assign repack_valid[p]=CONFIG_LEGAL&&!error_q&&(header_direct||active_candidate);
  // 仅余一个旧Data half时，TL序列要求lower恢复为Control/NOP槽，尾Data占upper。
  assign repack_data[p*512+:512]=header_direct?{256'd0,in_data[255:0]}:first_q?{in_data[255:0],control_q}:(halves_remaining_q==4'd0)?{carry_q,256'd0}:{in_data[255:0],carry_q};
  assign repack_meta[p*128+:128]=header_direct?in_meta:meta_q;assign repack_class[p*2+:2]=header_direct?in_class:class_q;assign repack_vc[p*2+:2]=header_direct?in_vc:vc_q;assign repack_pool[p]=header_direct?i_original_pool[p]:pool_q;
  assign repack_src[p*10+:10]=header_direct?in_src:src_q;assign repack_dst[p*10+:10]=header_direct?in_dst:dst_q;
  assign repack_sop[p]=header_direct||first_q;assign repack_eop[p]=header_direct||(active_q&&((first_q&&(halves_remaining_q==4'd1))||(!first_q&&((halves_remaining_q==4'd0)||(halves_remaining_q==4'd1)))));
  assign repack_flits[p*4+:4]=header_direct?4'd1:physical_flits_q;
  wire repack_fire=repack_valid[p]&&repack_ready[p];
  assign o_ready[p]=CONFIG_LEGAL&&i_rstn&&!error_q&&((!active_q)?(header_legal&&((parsed_halves==4'd0)?repack_ready[p]:1'b1)):(need_input&&data_legal&&repack_ready[p]));
  assign o_busy[p]=CONFIG_LEGAL&&i_rstn&&(active_q||boundary_tl_valid[p]);assign o_error[p]=!CONFIG_LEGAL||(i_rstn&&(error_q||boundary_error[p]||demand_error[p]));
  always @(posedge i_clk)begin
   if(!i_rstn)begin active_q<=0;first_q<=0;error_q<=0;pool_q<=0;control_q<=0;carry_q<=0;meta_q<=0;class_q<=0;vc_q<=0;src_q<=0;dst_q<=0;input_flits_q<=0;physical_flits_q<=0;halves_remaining_q<=0;fabric_remaining_q<=0;end
   else if(CONFIG_LEGAL)begin
    if((!active_q&&i_valid[p]&&!header_legal)||(need_input&&i_valid[p]&&!data_legal)||boundary_error[p])error_q<=1'b1;
    if(header_capture&&o_ready[p])begin active_q<=1;first_q<=1;pool_q<=i_original_pool[p];control_q<=in_data[255:0];meta_q<=in_meta;class_q<=in_class;vc_q<=in_vc;src_q<=in_src;dst_q<=in_dst;input_flits_q<=in_flits;physical_flits_q<=4'd1+(parsed_halves>>1);halves_remaining_q<=parsed_halves;fabric_remaining_q<=in_flits-4'd1;end
    else if(repack_fire&&active_q)begin
     if(first_q)begin fabric_remaining_q<=fabric_remaining_q-4'd1;first_q<=0;if(halves_remaining_q==4'd1)begin active_q<=0;halves_remaining_q<=0;end else begin carry_q<=in_data[511:256];halves_remaining_q<=halves_remaining_q-4'd2;end end
     else if(halves_remaining_q==4'd0)active_q<=0;
     else begin fabric_remaining_q<=fabric_remaining_q-4'd1;if(halves_remaining_q==4'd1)begin active_q<=0;halves_remaining_q<=0;end else begin carry_q<=in_data[511:256];halves_remaining_q<=halves_remaining_q-4'd2;end end
    end
   end
  end
 end endgenerate
 switch_station_tl_egress_repack_boundary #(.C_PORTS(C_PORTS),.C_COUNT_WIDTH(4),.C_NUM_CLASSES(2),.C_SUPPORTED_CLASS_MASK(4'b0011))u_boundary(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_valid(repack_valid),.o_ready(repack_ready),.i_data(repack_data),.i_meta(repack_meta),.i_class(repack_class),.i_original_vc(repack_vc),.i_original_pool(repack_pool),.i_source_port(repack_src),.i_dst_port(repack_dst),.i_sop(repack_sop),.i_eop(repack_eop),.i_packet_flits(repack_flits),.i_repack_valid(repack_valid),.i_repacked_tl_data(repack_data),.i_repacked_tl_msg(repack_msg),.o_tl_valid(boundary_tl_valid),.i_tl_ready(boundary_tl_ready),.o_tl_data(boundary_tl_data),.o_tl_msg(boundary_tl_msg),.o_original_data(unused_original_data),.o_meta(unused_meta),.o_class(unused_class),.o_original_vc(unused_vc),.o_original_pool(unused_pool),.o_source_port(unused_src),.o_dst_port(unused_dst),.o_sop(boundary_sop),.o_eop(boundary_eop),.o_packet_flits(unused_flits),.o_error(boundary_error),.o_config_error(boundary_config_error));
 generate for(p=0;p<C_PORTS;p=p+1)begin:g_demand
  wire demand_allowed,unused_taken,unused_rejected,unused_store;wire[2:0] unused_lower,unused_upper;wire[79:0] live_demands,unused_releases;wire[6:0] unused_pending;wire[72:0] unused_be;wire[583:0] unused_metadata;reg demand_error_q;
  wire[511:0] native_data=boundary_tl_data[p*512+:512];wire[1:0] native_msg=boundary_tl_msg[p*2+:2];wire output_fire=o_tl_valid[p]&&i_tl_ready[p];
  tl_receive_context u_tx_demand(.i_clk(i_clk),.i_rstn(i_rstn),.i_commit(output_fire),.i_auth(1'b0),.i_lower(native_data[255:0]),.i_msg(native_msg),.i_type0(native_data[7:0]),.i_type1(native_data[263:256]),.o_allowed(demand_allowed),.o_taken(unused_taken),.o_rejected(unused_rejected),.o_lower(unused_lower),.o_upper(unused_upper),.o_demands(live_demands),.o_releases(unused_releases),.o_store(unused_store),.o_pending(unused_pending),.o_be(unused_be),.o_metadata(unused_metadata));
  assign o_tl_valid[p]=CONFIG_LEGAL&&i_rstn&&boundary_tl_valid[p]&&demand_allowed&&!demand_error_q;
  assign boundary_tl_ready[p]=CONFIG_LEGAL&&i_rstn&&i_tl_ready[p]&&demand_allowed&&!demand_error_q;
  assign o_tl_data[p*512+:512]=o_tl_valid[p]?native_data:512'd0;assign o_tl_msg[p*2+:2]=o_tl_valid[p]?native_msg:2'd0;assign o_tl_demands[p*80+:80]=o_tl_valid[p]?live_demands:80'd0;assign demand_error[p]=demand_error_q;
  assign o_tl_sop[p]=o_tl_valid[p]&&boundary_sop[p];assign o_tl_eop[p]=o_tl_valid[p]&&boundary_eop[p];
  always @(posedge i_clk)begin if(!i_rstn)demand_error_q<=1'b0;else if(CONFIG_LEGAL&&boundary_tl_valid[p]&&!demand_allowed)demand_error_q<=1'b1;end
  wire unused_demand=^{unused_taken,unused_rejected,unused_store,unused_lower,unused_upper,unused_releases,unused_pending,unused_be,unused_metadata};
 end endgenerate
 wire unused_boundary=^{unused_original_data,unused_meta,unused_class,unused_vc,unused_pool,unused_src,unused_dst,unused_flits};
endmodule
`default_nettype wire
