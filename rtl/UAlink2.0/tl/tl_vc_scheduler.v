// Generated unimplemented interface; inventory status remains planned.
// Regenerate/check: python3 scripts/materialize_ip_scaffold.py --check
// Next implement this module deliberately and update its reviewed inventory status.
`default_nettype none
module tl_vc_scheduler(
 input wire i_clk,i_rstn,i_enable,i_valid,
 input wire [511:0] i_data,
 input wire [127:0] i_meta,
 output wire o_ready,o_valid,
 output wire [511:0] o_data,
 output wire [127:0] o_meta,
 output wire o_implemented,o_error
);
assign o_ready=1'b0;
assign o_valid=1'b0;
assign o_data=512'd0;
assign o_meta=128'd0;
assign o_implemented=1'b0;
assign o_error=i_rstn&&i_enable&&i_valid;
endmodule
`default_nettype wire
