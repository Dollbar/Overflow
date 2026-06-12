`default_nettype none
// Transferred CMD liability only. This does not originate credit or classify fields.
module tl_deferred_command_credit #(parameter integer COUNT_WIDTH=12)(
 input wire i_clk,i_rstn,i_move,
 input wire [39:0] i_moved,
 input wire i_release_valid,input wire [39:0] i_releases,
 input wire i_publish_ready,
 output wire o_move_allowed,o_publish_valid,o_release_taken,
 output wire [39:0] o_publish_releases,
 output wire [10*COUNT_WIDTH-1:0] o_pending,
 output wire o_error
);
 reg fault_q;
 reg [10*COUNT_WIDTH-1:0] pending_q;
 wire [9:0] underflow,overflow;
 wire bad_release=i_release_valid&&(|underflow);
 wire proposed_release=i_release_valid&&i_publish_ready&&!bad_release&&!fault_q;
 wire bad_move=i_move&&(|overflow);
 wire bad=bad_release||bad_move;
 wire active=i_rstn&&!fault_q&&!bad;
 // Ready must be derived from this unqualified vector, not from publish_valid.
 assign o_publish_releases=i_releases;
 assign o_publish_valid=active&&i_release_valid;
 assign o_release_taken=o_publish_valid&&i_publish_ready;
 assign o_move_allowed=active;
 assign o_pending=pending_q;
 assign o_error=i_rstn&&(fault_q||bad);
 genvar a;
 generate for(a=0;a<10;a=a+1)begin:account
  wire [COUNT_WIDTH+4:0] old_value={5'd0,pending_q[a*COUNT_WIDTH+:COUNT_WIDTH]};
  wire [COUNT_WIDTH+4:0] moved={{(COUNT_WIDTH+1){1'b0}},i_moved[a*4+:4]};
  wire [COUNT_WIDTH+4:0] released={{(COUNT_WIDTH+1){1'b0}},i_releases[a*4+:4]};
  wire [COUNT_WIDTH+4:0] sum=old_value+(i_move?moved:0)-(proposed_release?released:0);
  assign underflow[a]=released>old_value;
  assign overflow[a]=|sum[COUNT_WIDTH+4:COUNT_WIDTH];
  always @(posedge i_clk)begin
   if(!i_rstn)pending_q[a*COUNT_WIDTH+:COUNT_WIDTH]<=0;
   else if(active)pending_q[a*COUNT_WIDTH+:COUNT_WIDTH]<=sum[COUNT_WIDTH-1:0];
  end
 end
 if(COUNT_WIDTH<1||COUNT_WIDTH>20)begin:invalid_parameters
  tl_deferred_command_credit_invalid_width Invalid_Inst();
 end endgenerate
 always @(posedge i_clk)begin
  if(!i_rstn)fault_q<=0;
  else if(bad)fault_q<=1;
 end
endmodule
`default_nettype wire
