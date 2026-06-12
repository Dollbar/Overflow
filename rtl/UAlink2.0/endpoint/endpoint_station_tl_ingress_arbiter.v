`timescale 1ns/1ps
`default_nettype none

// Four independent Station-local, DL-context-committed TL word streams share one
// downstream typed interface.  A stalled winner remains selected until its real
// ready/valid handshake.  This block owns only arbitration: TL credit, DL sequence,
// replay and CRC verdict ownership remain outside this boundary.
module endpoint_station_tl_ingress_arbiter(
 input wire i_clk,input wire i_rstn,
 input wire [3:0] i_tl_valid,output reg [3:0] o_tl_ready,
 input wire [2047:0] i_tl_flit,input wire [7:0] i_tl_msg,
 output reg o_tl_valid,input wire i_tl_ready,
 output reg [511:0] o_tl_flit,output reg [1:0] o_tl_msg,
 output reg [1:0] o_tl_port
);
reg [1:0] rr_q;
reg lock_q;
reg [1:0] winner_q;
reg [1:0] selected;
reg selected_valid;
wire output_fire;

assign output_fire=o_tl_valid&&i_tl_ready;

always @* begin
 selected=rr_q;
 selected_valid=1'b0;
 if(lock_q)begin
  selected=winner_q;
  selected_valid=i_tl_valid[winner_q];
 end else begin
  case(rr_q)
   2'd0:begin
    if(i_tl_valid[0])begin selected=2'd0;selected_valid=1'b1;end
    else if(i_tl_valid[1])begin selected=2'd1;selected_valid=1'b1;end
    else if(i_tl_valid[2])begin selected=2'd2;selected_valid=1'b1;end
    else if(i_tl_valid[3])begin selected=2'd3;selected_valid=1'b1;end
   end
   2'd1:begin
    if(i_tl_valid[1])begin selected=2'd1;selected_valid=1'b1;end
    else if(i_tl_valid[2])begin selected=2'd2;selected_valid=1'b1;end
    else if(i_tl_valid[3])begin selected=2'd3;selected_valid=1'b1;end
    else if(i_tl_valid[0])begin selected=2'd0;selected_valid=1'b1;end
   end
   2'd2:begin
    if(i_tl_valid[2])begin selected=2'd2;selected_valid=1'b1;end
    else if(i_tl_valid[3])begin selected=2'd3;selected_valid=1'b1;end
    else if(i_tl_valid[0])begin selected=2'd0;selected_valid=1'b1;end
    else if(i_tl_valid[1])begin selected=2'd1;selected_valid=1'b1;end
   end
   default:begin
    if(i_tl_valid[3])begin selected=2'd3;selected_valid=1'b1;end
    else if(i_tl_valid[0])begin selected=2'd0;selected_valid=1'b1;end
    else if(i_tl_valid[1])begin selected=2'd1;selected_valid=1'b1;end
    else if(i_tl_valid[2])begin selected=2'd2;selected_valid=1'b1;end
   end
  endcase
 end
end

always @* begin
 o_tl_ready=4'd0;
 o_tl_valid=1'b0;
 o_tl_flit=512'd0;
 o_tl_msg=2'd0;
 o_tl_port=selected;
 if(i_rstn&&selected_valid)begin
  o_tl_valid=1'b1;
  case(selected)
   2'd0:begin o_tl_flit=i_tl_flit[511:0];o_tl_msg=i_tl_msg[1:0];end
   2'd1:begin o_tl_flit=i_tl_flit[1023:512];o_tl_msg=i_tl_msg[3:2];end
   2'd2:begin o_tl_flit=i_tl_flit[1535:1024];o_tl_msg=i_tl_msg[5:4];end
   default:begin o_tl_flit=i_tl_flit[2047:1536];o_tl_msg=i_tl_msg[7:6];end
  endcase
  if(i_tl_ready)o_tl_ready[selected]=1'b1;
 end
end

always @(posedge i_clk)begin
 if(!i_rstn)begin
  rr_q<=2'd0;
  lock_q<=1'b0;
  winner_q<=2'd0;
 end else if(lock_q)begin
  if(output_fire)begin
   rr_q<=winner_q+2'd1;
   lock_q<=1'b0;
  end
 end else if(selected_valid)begin
  if(output_fire)rr_q<=selected+2'd1;
  else begin lock_q<=1'b1;winner_q<=selected;end
 end
end
endmodule
`default_nettype wire
