module joint_reference(input wire i_clk,i_rstn,i_commit,i_auth,input wire [255:0] i_lower,input wire [1:0] i_msg,input wire [7:0] i_type0,i_type1,output wire allowed,taken,rejected,output wire [2:0] lower,upper,output wire [6:0] pending,output wire [72:0] be,output wire [2:0] requests_available,output wire [3:0] responses_available);
reg [2:0] request_slots;reg [3:0] response_slots;
wire local_allowed,unused_taken,unused_rejected;wire [2:0] local_lower,local_upper;
wire [31:0] counts;count_reference fields(i_lower,counts);
wire control=(pending<=7'd1) && !i_msg[0];
wire [2:0] requests=control ? counts[30:28] : 3'd0;
wire [3:0] responses=control ? counts[27:24] : 4'd0;
wire fits=(requests<=request_slots) && (responses<=response_slots);
assign allowed=local_allowed && fits;
assign taken=i_commit && allowed;
assign rejected=i_rstn && i_commit && !allowed;
assign lower=allowed ? local_lower : 3'd7;
assign upper=allowed ? local_upper : 3'd7;
assign requests_available=request_slots;assign responses_available=response_slots;
// Reference uses a single common commit rather than the DUT's reciprocal commit gates.
sequence_reference sequence(i_clk,i_rstn,taken,i_auth,i_lower,i_msg,i_type0,i_type1,local_allowed,unused_taken,unused_rejected,local_lower,local_upper,pending,be);
always @(posedge i_clk)begin
 if(!i_rstn)begin request_slots<=3'd4;response_slots<=4'd8;end
 else if(taken)begin
  if(request_slots==3'd4 && requests==0)request_slots<=3'd4;else request_slots<=request_slots-requests+3'd1;
  if(response_slots==4'd8 && responses==0)response_slots<=4'd8;else response_slots<=response_slots-responses+4'd1;
 end
end
endmodule
