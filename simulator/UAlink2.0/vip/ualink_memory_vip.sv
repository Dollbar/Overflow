`timescale 1ns/1ps
// Simulation-only, four-slot memory service for the local single64B Read profile.
module ualink_memory_vip #(
 parameter integer SIDE=0,
 parameter integer MIN_LATENCY=3,
 parameter integer SLOT_LATENCY_STEP=5,
 parameter integer READY_PERIOD=5,
 parameter integer READY_STALL_PHASE=SIDE+1
)(
 input wire i_clk,i_rstn,
 input wire i_read_valid,output wire o_read_ready,
 input wire [1:0] i_read_slot,input wire [56:0] i_read_address,
 input wire [5:0] i_read_length,input wire [7:0] i_read_attr,
 input wire [1:0] i_read_asi,input wire [7:0] i_read_metadata,
 output wire o_result_valid,input wire i_result_ready,
 output wire [1:0] o_result_slot,
 output wire [511:0] o_result_data,output wire [3:0] o_result_status
);
 import ualink_test_pkg::*;
 reg [3:0] pending;
 reg [56:0] addresses[0:3];
 integer due[0:3];
 integer cycle,choice,index;
 reg result_valid;
 reg [1:0] result_slot;
 reg [511:0] result_data;
 reg [3:0] result_status;

 initial begin
  if(MIN_LATENCY<1||SLOT_LATENCY_STEP<0||READY_PERIOD<1||
     READY_STALL_PHASE<0||READY_STALL_PHASE>=READY_PERIOD)
   $fatal(1,"VIP_MEMORY_CONFIGURATION");
 end
 assign o_read_ready=i_rstn&&!pending[i_read_slot]&&(cycle%READY_PERIOD!=READY_STALL_PHASE);
 assign o_result_valid=i_rstn&&result_valid;
 assign o_result_slot=o_result_valid?result_slot:2'd0;
 assign o_result_data=o_result_valid?result_data:512'd0;
 assign o_result_status=o_result_valid?result_status:4'd0;

 // Due-slot arbitration is private service state. It must never be a completion oracle.
 always @* begin
  choice=-1;
  for(integer slot=0;slot<4;slot=slot+1)
   if(pending[slot]&&due[slot]<=cycle&&(!result_valid||slot!=result_slot))choice=slot;
 end
 always @(posedge i_clk)begin
  if(!i_rstn)begin
   cycle<=0;pending<=4'd0;result_valid<=1'b0;
   result_slot<=2'd0;result_data<=512'd0;result_status<=4'd0;
   for(index=0;index<4;index=index+1)begin addresses[index]<=57'd0;due[index]<=0;end
  end else begin
   cycle<=cycle+1;
   if(o_result_valid&&i_result_ready)pending[result_slot]<=1'b0;
   // Once offered, the entire result stays fixed until the actual ready/valid transfer.
   if(!result_valid||i_result_ready)begin
    if(choice>=0)begin
     result_valid<=1'b1;result_slot<=choice[1:0];
     result_data<=memory_word(SIDE,addresses[choice]);
     result_status<=(addresses[choice]<TEST_MEMORY_BYTES)?4'd0:4'd3;
    end else result_valid<=1'b0;
   end
   if(i_read_valid&&o_read_ready)begin
    if(i_read_address[5:0]!=0||i_read_length!=15||i_read_attr!=8'hff||i_read_asi!=0||i_read_metadata!=0)
     $fatal(1,"VIP_MEMORY_PROFILE");
    pending[i_read_slot]<=1'b1;addresses[i_read_slot]<=i_read_address;
    due[i_read_slot]<=cycle+MIN_LATENCY+(3-i_read_slot)*SLOT_LATENCY_STEP;
   end
  end
 end
endmodule
