module integration_check #(
 parameter integer P=4,W=4,D=33,T=8,
 parameter [P*W-1:0] CAPS={P{4'd7}}
)(input wire clk,rstn,
 input wire [P-1:0] request_valid,write_valid,write_last,read_ready,
 input wire [P*P-1:0] routes,
 input wire [P*W-1:0] request_units,
 input wire [P*T-1:0] request_token,write_token,
 input wire [P*D-1:0] write_data,
 output wire [P-1:0] request_ready,write_ready,out_valid,out_last,
 output wire [P*D-1:0] out_data,
 output wire [P*T-1:0] out_token,
 output wire error
);
wire [P-1:0] admit_ready,reserve_valid,release_valid,release_accepted;
wire [P*P-1:0] grant;
wire [P*W-1:0] grant_units,release_units;
reg [P*T-1:0] reserve_token;
wire reserr,qerr;
switch_credit_reservation #(.PORTS(P),.UNIT_WIDTH(W),.CAPACITIES(CAPS)) Reservation_Inst(
.i_clk(clk),.i_rstn(rstn),.i_request_valid(request_valid),.i_route_match(routes),.i_request_units(request_units),.i_admit_ready(admit_ready),
.i_release_valid(release_valid),.i_release_units(release_units),.o_request_ready(request_ready),.o_grant(grant),.o_grant_units(grant_units),
.o_release_accepted(release_accepted),.o_available(),.o_reserved(),.o_request_error(),.o_release_error(),.o_error(reserr));
genvar g;generate for(g=0;g<P;g=g+1)begin:gen_valid
 assign reserve_valid[g]=|grant[g*P+:P];
end endgenerate
integer e,s;
always @* begin
 reserve_token={P*T{1'b0}};
 for(e=0;e<P;e=e+1)for(s=0;s<P;s=s+1)
  if(grant[e*P+s])reserve_token[e*T+:T]=request_token[s*T+:T];
end
switch_egress_packet_queue #(.PORTS(P),.DATA_WIDTH(D),.TOKEN_WIDTH(T),.UNIT_WIDTH(W),.CAPACITIES(CAPS)) Queue_Inst(
.i_clk(clk),.i_rstn(rstn),.i_reserve_valid(reserve_valid),.i_reserve_units(grant_units),.i_reserve_token(reserve_token),.o_reserve_ready(admit_ready),
.i_write_valid(write_valid),.i_write_data(write_data),.i_write_last(write_last),.i_write_token(write_token),.o_write_ready(write_ready),
.i_ready(read_ready),.o_valid(out_valid),.o_data(out_data),.o_last(out_last),.o_token(out_token),.o_release_valid(release_valid),.o_release_units(release_units),
.o_reserved(),.o_stored(),.o_completed(),.o_busy(),.o_error_now(),.o_error_sticky(),.o_error(qerr));
assign error=reserr||qerr||(|(release_valid^release_accepted));
endmodule
