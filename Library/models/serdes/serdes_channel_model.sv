`timescale 1ns/1ps
module serdes_channel_model #(
 parameter integer LANES=1,parameter integer BLOCK_WIDTH=serdes_212g5_pam4_profile_pkg::SERDES_212G5_PCS_BLOCK_BITS,
 parameter integer PROPAGATION_CYCLES=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_PROPAGATION_CYCLES,
 parameter integer MAX_LANE_SKEW_CYCLES=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_MAX_LANE_SKEW_CYCLES,
 parameter integer CDR_LOCK_CYCLES=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_CDR_LOCK_CYCLES,
 parameter integer BLOCK_LOCK_CYCLES=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_BLOCK_LOCK_CYCLES,
 parameter integer JITTER_PERIOD_BLOCKS=0,parameter integer JITTER_EXTRA_CYCLES=0,
 parameter integer BURST_ERROR_LENGTH_BLOCKS=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_BURST_ERROR_LENGTH_BLOCKS,
 parameter integer ELASTIC_DEPTH=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_ELASTIC_DEPTH,
 parameter [63:0]LINE_RATE_BPS=serdes_212g5_pam4_profile_pkg::SERDES_212G5_LINE_RATE_BPS,
 parameter [63:0]MODULATION_BITS_PER_SYMBOL=serdes_212g5_pam4_profile_pkg::SERDES_212G5_BITS_PER_SYMBOL
)(
 input wire clk_i,input wire rst_n_i,input wire admin_up_i,input wire[LANES-1:0]signal_detect_i,
 input wire[LANES-1:0]force_loss_of_lock_i,input wire tx_group_valid_i,output wire tx_group_ready_o,
 input wire[LANES*BLOCK_WIDTH-1:0]tx_group_blocks_i,input wire[LANES-1:0]inject_drop_i,
 input wire[LANES-1:0]inject_corrupt_i,input wire[LANES-1:0]inject_burst_i,input wire[31:0]error_period_blocks_i,
 input wire[((LANES<=2)?1:$clog2(LANES))-1:0]error_lane_i,output wire[LANES-1:0]rx_lane_valid_o,
 input wire[LANES-1:0]rx_lane_ready_i,output wire[LANES*BLOCK_WIDTH-1:0]rx_lane_blocks_o,
 output wire[LANES-1:0]cdr_locked_o,output wire[LANES-1:0]block_locked_o,output wire[LANES-1:0]lane_ready_o,
 output wire[1:0]link_state_o,output wire link_up_o,output reg[63:0]offered_groups_o,
 output wire[63:0]offered_blocks_o,output wire[63:0]delivered_blocks_o,output wire[63:0]dropped_blocks_o,
 output wire[63:0]corrupted_blocks_o,output wire[63:0]overflow_blocks_o,output wire[63:0]retrain_events_o
);
 // clk_i is a digital scheduling clock: each asserted group handshake offers
 // one BLOCK_WIDTH block per lane. LINE_RATE_BPS is profile metadata only; the
 // model represents that wall-clock rate only when f(clk_i)=LINE_RATE/BLOCK_WIDTH.
 localparam[1:0]LINK_DOWN=0,LINK_TRAINING=1,LINK_UP=2,LINK_DEGRADED=3;
 wire[LANES-1:0]lane_tx_ready;wire[LANES*3-1:0]lane_state_unused;wire[31:0]lane_offered[0:LANES-1],lane_delivered[0:LANES-1],lane_dropped[0:LANES-1],lane_corrupted[0:LANES-1],lane_overflow[0:LANES-1],lane_retrain[0:LANES-1];
 reg[63:0]offered_sum,delivered_sum,dropped_sum,corrupted_sum,overflow_sum,retrain_sum;integer sum_lane;
 wire group_fire=tx_group_valid_i&&tx_group_ready_o;assign tx_group_ready_o=&lane_tx_ready;
 assign link_state_o=(!admin_up_i||!(|signal_detect_i))?LINK_DOWN:(&lane_ready_o)?LINK_UP:(|lane_ready_o)?LINK_DEGRADED:LINK_TRAINING;
 assign link_up_o=(link_state_o==LINK_UP);assign offered_blocks_o=offered_sum;assign delivered_blocks_o=delivered_sum;assign dropped_blocks_o=dropped_sum;assign corrupted_blocks_o=corrupted_sum;assign overflow_blocks_o=overflow_sum;assign retrain_events_o=retrain_sum;
 initial begin
  if(LANES<1||BLOCK_WIDTH<2||LINE_RATE_BPS==0)$fatal(1,"illegal generic SerDes geometry/rate");
  if((MODULATION_BITS_PER_SYMBOL!=1)&&(MODULATION_BITS_PER_SYMBOL!=2))$fatal(1,"generic SerDes modulation must be NRZ or PAM4");
  if((LINE_RATE_BPS%MODULATION_BITS_PER_SYMBOL)!=0)$fatal(1,"SerDes profile requires an integer symbol rate");
 end
 always @*begin offered_sum=0;delivered_sum=0;dropped_sum=0;corrupted_sum=0;overflow_sum=0;retrain_sum=0;for(sum_lane=0;sum_lane<LANES;sum_lane=sum_lane+1)begin offered_sum=offered_sum+{32'd0,lane_offered[sum_lane]};delivered_sum=delivered_sum+{32'd0,lane_delivered[sum_lane]};dropped_sum=dropped_sum+{32'd0,lane_dropped[sum_lane]};corrupted_sum=corrupted_sum+{32'd0,lane_corrupted[sum_lane]};overflow_sum=overflow_sum+{32'd0,lane_overflow[sum_lane]};retrain_sum=retrain_sum+{32'd0,lane_retrain[sum_lane]};end end
 always @(posedge clk_i or negedge rst_n_i)if(!rst_n_i)offered_groups_o<=0;else if(group_fire)offered_groups_o<=offered_groups_o+1'b1;
 genvar lane;generate for(lane=0;lane<LANES;lane=lane+1)begin:g_lane
  localparam integer LANE_SKEW=(MAX_LANE_SKEW_CYCLES==0)?0:(lane%(MAX_LANE_SKEW_CYCLES+1));wire[31:0]lane_period=(error_lane_i==lane[((LANES<=2)?1:$clog2(LANES))-1:0])?error_period_blocks_i:0;
  serdes_lane_model #(.BLOCK_WIDTH(BLOCK_WIDTH),.PROPAGATION_CYCLES(PROPAGATION_CYCLES),.STATIC_SKEW_CYCLES(LANE_SKEW),.CDR_LOCK_CYCLES(CDR_LOCK_CYCLES),.BLOCK_LOCK_CYCLES(BLOCK_LOCK_CYCLES),.JITTER_PERIOD_BLOCKS(JITTER_PERIOD_BLOCKS),.JITTER_EXTRA_CYCLES(JITTER_EXTRA_CYCLES),.BURST_ERROR_LENGTH_BLOCKS(BURST_ERROR_LENGTH_BLOCKS),.ELASTIC_DEPTH(ELASTIC_DEPTH))u_lane(
   .clk_i(clk_i),.rst_n_i(rst_n_i),.admin_up_i(admin_up_i),.signal_detect_i(signal_detect_i[lane]),.force_loss_of_lock_i(force_loss_of_lock_i[lane]),
   .tx_block_valid_i(group_fire),.tx_block_ready_o(lane_tx_ready[lane]),.tx_block_i(tx_group_blocks_i[lane*BLOCK_WIDTH+:BLOCK_WIDTH]),
   .inject_drop_i(inject_drop_i[lane]),.inject_corrupt_i(inject_corrupt_i[lane]),.inject_burst_i(inject_burst_i[lane]),.error_period_blocks_i(lane_period),
   .rx_block_valid_o(rx_lane_valid_o[lane]),.rx_block_ready_i(rx_lane_ready_i[lane]),.rx_block_o(rx_lane_blocks_o[lane*BLOCK_WIDTH+:BLOCK_WIDTH]),
   .cdr_locked_o(cdr_locked_o[lane]),.block_locked_o(block_locked_o[lane]),.lane_ready_o(lane_ready_o[lane]),.lane_state_o(lane_state_unused[lane*3+:3]),
   .offered_blocks_o(lane_offered[lane]),.delivered_blocks_o(lane_delivered[lane]),.dropped_blocks_o(lane_dropped[lane]),.corrupted_blocks_o(lane_corrupted[lane]),.overflow_blocks_o(lane_overflow[lane]),.retrain_events_o(lane_retrain[lane]));
 end endgenerate
 wire unused=^lane_state_unused;
endmodule
