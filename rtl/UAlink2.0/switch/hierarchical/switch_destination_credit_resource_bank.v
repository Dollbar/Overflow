`timescale 1ns/1ps
`default_nettype none
// One destination resource owns C_CAPACITY physical slots. The bank grants at
// most one requester per cycle, but accepts independent arrivals to distinct slots.
module switch_destination_credit_resource_bank #(
 parameter integer C_REQUESTERS=32,parameter integer C_CAPACITY=4,
 parameter integer C_REQUESTER_WIDTH=5,parameter integer C_EPOCH_WIDTH=4,
 parameter integer C_GENERATION_WIDTH=16,parameter integer C_SLOT_WIDTH=2,
 parameter integer C_COUNT_WIDTH=3,
 parameter integer C_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH
)(
 input wire i_clk,input wire i_rstn,input wire [C_EPOCH_WIDTH-1:0] i_epoch,
 input wire [C_REQUESTERS-1:0] i_issue_valid,output reg [C_REQUESTERS-1:0] o_issue_ready,
 output reg [C_REQUESTERS*C_TOKEN_WIDTH-1:0] o_issue_token,
 input wire [C_REQUESTERS-1:0] i_arrive_valid,output reg [C_REQUESTERS-1:0] o_arrive_ready,
 input wire [C_REQUESTERS*C_TOKEN_WIDTH-1:0] i_arrive_token,
 input wire i_release_valid,output reg o_release_ready,input wire [C_TOKEN_WIDTH-1:0] i_release_token,
 output reg [C_COUNT_WIDTH-1:0] o_free,output reg [C_COUNT_WIDTH-1:0] o_issued,
 output reg [C_COUNT_WIDTH-1:0] o_occupied,output reg o_quiescent,
 output wire o_config_error,output reg o_issue_overflow,output reg o_arrival_error,
 output reg o_release_error,output reg o_stale_epoch,output reg o_generation_exhausted,
 output reg o_conservation_error,output wire o_error
);
 function can_encode;input integer width;input integer count;integer value,index;
  begin value=1;for(index=0;index<width;index=index+1)value=value*2;
   can_encode=(width>=1)&&(width<=30)&&(count>=1)&&(value>=count);end
 endfunction
 localparam CONFIG_LEGAL=(C_REQUESTERS>=1)&&(C_REQUESTERS<=64)&&(C_CAPACITY>=1)&&(C_CAPACITY<=32)&&
  can_encode(C_REQUESTER_WIDTH,C_REQUESTERS)&&can_encode(C_SLOT_WIDTH,C_CAPACITY)&&
  can_encode(C_COUNT_WIDTH,C_CAPACITY+1)&&(C_EPOCH_WIDTH>=1)&&(C_EPOCH_WIDTH<=30)&&
  (C_GENERATION_WIDTH>=1)&&(C_GENERATION_WIDTH<=30)&&
  (C_TOKEN_WIDTH==C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH);
 localparam [C_REQUESTER_WIDTH-1:0] LAST_REQUESTER=C_REQUESTERS[C_REQUESTER_WIDTH-1:0]-1'b1;
 localparam [1:0] SLOT_FREE=2'b00,SLOT_ISSUED=2'b01,SLOT_OCCUPIED=2'b10;
 reg [1:0] slot_state_q[0:C_CAPACITY-1];
 reg [C_REQUESTER_WIDTH-1:0] slot_requester_q[0:C_CAPACITY-1];
 reg [C_GENERATION_WIDTH-1:0] slot_generation_q[0:C_CAPACITY-1];
 reg [C_EPOCH_WIDTH-1:0] slot_epoch_q[0:C_CAPACITY-1],active_epoch_q;
 reg [C_REQUESTER_WIDTH-1:0] rr_q,issue_winner;
 reg [C_SLOT_WIDTH-1:0] issue_slot;
 reg issue_fire,issue_found,free_found,issue_exhausted;
 reg [C_CAPACITY-1:0] arrival_slot_fire;
 reg arrival_bad,arrival_stale,release_fire,release_bad,release_stale;
 integer scan,requester_index,issue_slot_index,arrival_index,arrival_slot,count_index;
 integer state_slot_index;
 reg [C_TOKEN_WIDTH-1:0] arrival_token;
 reg [C_SLOT_WIDTH-1:0] arrival_slot_bits,release_slot_bits;
 reg [C_GENERATION_WIDTH-1:0] arrival_generation,release_generation;
 reg [C_EPOCH_WIDTH-1:0] arrival_epoch,release_epoch;
 integer release_slot,total_count;

 assign o_config_error=!CONFIG_LEGAL;
 assign o_error=o_config_error|o_issue_overflow|o_arrival_error|o_release_error|
  o_stale_epoch|o_generation_exhausted|o_conservation_error;

 always @(*)begin
  o_issue_ready={C_REQUESTERS{1'b0}};o_issue_token={(C_REQUESTERS*C_TOKEN_WIDTH){1'b0}};
  issue_winner={C_REQUESTER_WIDTH{1'b0}};issue_slot={C_SLOT_WIDTH{1'b0}};
  issue_fire=1'b0;issue_found=1'b0;free_found=1'b0;issue_exhausted=1'b0;
  requester_index=0;issue_slot_index=0;
  for(scan=0;scan<C_REQUESTERS;scan=scan+1)begin
   requester_index=0;requester_index[C_REQUESTER_WIDTH-1:0]=rr_q;
   requester_index=requester_index+scan;if(requester_index>=C_REQUESTERS)requester_index=requester_index-C_REQUESTERS;
   if(!issue_found&&i_issue_valid[requester_index])begin
    for(issue_slot_index=0;issue_slot_index<C_CAPACITY;issue_slot_index=issue_slot_index+1)begin
     if(slot_state_q[issue_slot_index]==SLOT_FREE)begin
      free_found=1'b1;
      if(!issue_found&&!(&slot_generation_q[issue_slot_index]))begin
       issue_found=1'b1;issue_winner=requester_index[C_REQUESTER_WIDTH-1:0];
       issue_slot=issue_slot_index[C_SLOT_WIDTH-1:0];
      end else if(&slot_generation_q[issue_slot_index])issue_exhausted=1'b1;
     end
    end
   end
  end
  if(CONFIG_LEGAL&&(i_epoch==active_epoch_q)&&issue_found)begin
   o_issue_ready[issue_winner]=1'b1;issue_fire=1'b1;
   o_issue_token[issue_winner*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]=
    {active_epoch_q,slot_generation_q[issue_slot]+1'b1,issue_slot};
  end
 end

 always @(*)begin
  o_arrive_ready={C_REQUESTERS{1'b0}};arrival_slot_fire={C_CAPACITY{1'b0}};
  arrival_bad=1'b0;arrival_stale=1'b0;arrival_token=0;arrival_slot_bits=0;
  arrival_generation=0;arrival_epoch=0;arrival_slot=0;
  for(arrival_index=0;arrival_index<C_REQUESTERS;arrival_index=arrival_index+1)begin
   arrival_token=i_arrive_token[arrival_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];
   arrival_slot_bits=arrival_token[0+:C_SLOT_WIDTH];
   arrival_generation=arrival_token[C_SLOT_WIDTH+:C_GENERATION_WIDTH];
   arrival_epoch=arrival_token[C_SLOT_WIDTH+C_GENERATION_WIDTH+:C_EPOCH_WIDTH];
   arrival_slot=0;arrival_slot[C_SLOT_WIDTH-1:0]=arrival_slot_bits;
   if(i_arrive_valid[arrival_index])begin
    if(arrival_epoch!=active_epoch_q)arrival_stale=1'b1;
    else if(arrival_slot>=C_CAPACITY)arrival_bad=1'b1;
    else if(arrival_slot_fire[arrival_slot]||(slot_state_q[arrival_slot]!=SLOT_ISSUED)||
     (slot_requester_q[arrival_slot]!=arrival_index[C_REQUESTER_WIDTH-1:0])||
     (slot_generation_q[arrival_slot]!=arrival_generation)||(slot_epoch_q[arrival_slot]!=arrival_epoch))arrival_bad=1'b1;
    else begin o_arrive_ready[arrival_index]=CONFIG_LEGAL;arrival_slot_fire[arrival_slot]=CONFIG_LEGAL;end
   end
  end
 end

 always @(*)begin
  o_release_ready=1'b0;release_fire=1'b0;release_bad=1'b0;release_stale=1'b0;
  release_slot_bits=i_release_token[0+:C_SLOT_WIDTH];
  release_generation=i_release_token[C_SLOT_WIDTH+:C_GENERATION_WIDTH];
  release_epoch=i_release_token[C_SLOT_WIDTH+C_GENERATION_WIDTH+:C_EPOCH_WIDTH];
  release_slot=0;release_slot[C_SLOT_WIDTH-1:0]=release_slot_bits;
  if(i_release_valid)begin
   if(release_epoch!=active_epoch_q)release_stale=1'b1;
   else if(release_slot>=C_CAPACITY)release_bad=1'b1;
   else if((slot_state_q[release_slot]!=SLOT_OCCUPIED)||
    (slot_generation_q[release_slot]!=release_generation)||(slot_epoch_q[release_slot]!=release_epoch))release_bad=1'b1;
   else begin o_release_ready=CONFIG_LEGAL;release_fire=CONFIG_LEGAL;end
  end
 end

 always @(*)begin
  o_free=0;o_issued=0;o_occupied=0;o_quiescent=1'b1;total_count=0;
  for(count_index=0;count_index<C_CAPACITY;count_index=count_index+1)begin
   if(slot_state_q[count_index]==SLOT_FREE)begin o_free=o_free+1'b1;total_count=total_count+1;end
   else if(slot_state_q[count_index]==SLOT_ISSUED)begin o_issued=o_issued+1'b1;o_quiescent=1'b0;total_count=total_count+1;end
   else if(slot_state_q[count_index]==SLOT_OCCUPIED)begin o_occupied=o_occupied+1'b1;o_quiescent=1'b0;total_count=total_count+1;end
  end
 end

 always @(posedge i_clk)begin
  if(!i_rstn)begin
   rr_q<=0;active_epoch_q<=i_epoch;o_issue_overflow<=1'b0;o_arrival_error<=1'b0;
   o_release_error<=1'b0;o_stale_epoch<=1'b0;o_generation_exhausted<=1'b0;o_conservation_error<=1'b0;
   for(state_slot_index=0;state_slot_index<C_CAPACITY;state_slot_index=state_slot_index+1)begin
    slot_state_q[state_slot_index]<=SLOT_FREE;slot_requester_q[state_slot_index]<=0;
    slot_generation_q[state_slot_index]<=0;slot_epoch_q[state_slot_index]<=0;
   end
  end else begin
   if(issue_fire)begin
    slot_state_q[issue_slot]<=SLOT_ISSUED;slot_requester_q[issue_slot]<=issue_winner;
    slot_generation_q[issue_slot]<=slot_generation_q[issue_slot]+1'b1;slot_epoch_q[issue_slot]<=active_epoch_q;
    if(issue_winner==LAST_REQUESTER)rr_q<=0;else rr_q<=issue_winner+1'b1;
   end
   for(state_slot_index=0;state_slot_index<C_CAPACITY;state_slot_index=state_slot_index+1)begin
    if(arrival_slot_fire[state_slot_index])slot_state_q[state_slot_index]<=SLOT_OCCUPIED;
    if(release_fire&&(release_slot==state_slot_index))slot_state_q[state_slot_index]<=SLOT_FREE;
   end
   if(!CONFIG_LEGAL)o_conservation_error<=1'b1;
   if(issue_fire&&(o_free==0))o_issue_overflow<=1'b1;
   if(arrival_bad)o_arrival_error<=1'b1;if(release_bad)o_release_error<=1'b1;
   if(arrival_stale||release_stale||((i_epoch!=active_epoch_q)&&!o_quiescent))o_stale_epoch<=1'b1;
   if(issue_exhausted&&free_found&&(|i_issue_valid))o_generation_exhausted<=1'b1;
   if(total_count!=C_CAPACITY)o_conservation_error<=1'b1;
   if(o_quiescent&&(i_epoch!=active_epoch_q))begin
    active_epoch_q<=i_epoch;o_generation_exhausted<=1'b0;
    for(state_slot_index=0;state_slot_index<C_CAPACITY;state_slot_index=state_slot_index+1)
     slot_generation_q[state_slot_index]<=0;
   end
  end
 end
endmodule
`default_nettype wire
