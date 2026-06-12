`timescale 1ns/1ps
`default_nettype none
// 两个事务source group按稳定的Station-local port身份独占送入对应tl_port。
module endpoint_tl_group_dispatcher #(parameter integer PORTS=4,parameter [PORTS-1:0] ACTIVE_PORT_MASK=4'b0101,parameter integer RUNTIME_ACTIVE_ENABLE=0)(
 input wire i_rstn,input wire [PORTS-1:0] i_active_mask,input wire [1:0] i_source_valid,input wire [511:0] i_source_control,input wire [3:0] i_source_port,
 input wire [3:0] i_data_valid,input wire [511:0] i_data0,input wire [511:0] i_data1,
 output wire [PORTS*2-1:0] o_port_source_valid,output wire [PORTS*512-1:0] o_port_source_control,
 output wire [PORTS*4-1:0] o_port_data_valid,output wire [PORTS*512-1:0] o_port_data0,output wire [PORTS*512-1:0] o_port_data1,
 input wire [PORTS*2-1:0] i_port_source_captured,input wire [PORTS*4-1:0] i_port_data_accepted,
 output wire [1:0] o_source_captured,output wire [3:0] o_data_accepted,output wire o_error);
 wire [PORTS-1:0] effective_active_mask;wire [1:0] port0,port1;wire port0_range,port1_range,port0_active,port1_active;
 assign effective_active_mask=(RUNTIME_ACTIVE_ENABLE!=0)?i_active_mask:ACTIVE_PORT_MASK;
 assign port0=i_source_port[1:0];assign port1=i_source_port[3:2];
 assign port0_range=({30'd0,port0}<PORTS);assign port1_range=({30'd0,port1}<PORTS);
 assign port0_active=port0_range&&effective_active_mask[port0];assign port1_active=port1_range&&effective_active_mask[port1];
 genvar p;generate for(p=0;p<32'd4;p=p+32'd1)begin:route
  wire select0,select1;assign select0=port0_active&&(port0==p[1:0]);assign select1=port1_active&&(port1==p[1:0]);
  assign o_port_source_valid[p*2+:2]=i_rstn?{i_source_valid[1]&&select1,i_source_valid[0]&&select0}:2'd0;
  assign o_port_source_control[p*512+:512]=i_rstn?{select1?i_source_control[511:256]:256'd0,select0?i_source_control[255:0]:256'd0}:512'd0;
  assign o_port_data_valid[p*4+:4]=i_rstn?{select1?i_data_valid[3:2]:2'd0,select0?i_data_valid[1:0]:2'd0}:4'd0;
  assign o_port_data0[p*512+:512]=i_rstn?{select1?i_data0[511:256]:256'd0,select0?i_data0[255:0]:256'd0}:512'd0;
  assign o_port_data1[p*512+:512]=i_rstn?{select1?i_data1[511:256]:256'd0,select0?i_data1[255:0]:256'd0}:512'd0;
 end endgenerate
 assign o_source_captured[0]=(i_rstn&&port0_active)?i_port_source_captured[port0*2]:1'b0;
 assign o_source_captured[1]=(i_rstn&&port1_active)?i_port_source_captured[port1*2+1]:1'b0;
 assign o_data_accepted[1:0]=(i_rstn&&port0_active)?i_port_data_accepted[port0*4+:2]:2'd0;
 assign o_data_accepted[3:2]=(i_rstn&&port1_active)?i_port_data_accepted[port1*4+2+:2]:2'd0;
 assign o_error=i_rstn&&(((i_source_valid[0]||(i_data_valid[1:0]!=0))&&!port0_active)||((i_source_valid[1]||(i_data_valid[3:2]!=0))&&!port1_active));
 generate if(PORTS!=4)begin:invalid_config endpoint_tl_group_dispatcher_requires_four_ports Invalid_Config();end endgenerate
endmodule
`default_nettype wire
