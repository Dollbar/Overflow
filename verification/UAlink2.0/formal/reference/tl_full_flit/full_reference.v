module full_reference(input wire i_clk,i_rstn,i_commit,i_auth,input wire [511:0] i_flit,input wire [1:0] i_msg,output wire allowed,taken,rejected,output wire [2:0] lower,upper,output wire [6:0] pending,output wire [72:0] be,output wire [2:0] requests_available,output wire [3:0] responses_available,output reg fatal,opened,poison);
wire [255:0] i_lower=i_flit[255:0],i_upper=i_flit[511:256];
wire seq_allowed,unused_taken,unused_rejected;wire [2:0] i_class0,i_class1;
joint_reference admission(i_clk,i_rstn,taken,i_auth,i_lower,i_msg,i_lower[7:0],i_upper[7:0],seq_allowed,unused_taken,unused_rejected,i_class0,i_class1,pending,be,requests_available,responses_available);
wire [3:0] i_tags;wire [1:0] unused_status;wire [31:0] unused_counts;wire [7:0] unused_be;
tl_control_tenure certified_tags(i_lower,unused_status,i_tags,unused_counts,unused_be);
wire d0=(i_class0==3'd1)||(i_class0==3'd5),d1=(i_class1==3'd1)||(i_class1==3'd5);
wire p0=(i_class0==3'd5),p1=(i_class1==3'd5);
wire middle_open=opened^d0;
wire middle_poison=d0 ? (opened ? 1'b0 : p0) : poison;
wire next_open=opened^d0^d1;
wire next_poison=d1 ? (middle_open ? 1'b0 : p1) : middle_poison;
wire [9:0] shift_bits={i_tags,6'd0};
wire bad_tag0=(i_class0==3'd6)&&((i_tags<4'd1)||(i_tags>4'd4)||((i_lower>>shift_bits)!=256'd0));
wire bad_tag1=(i_class1==3'd6)&&((i_tags<4'd1)||(i_tags>4'd4)||((i_upper>>shift_bits)!=256'd0));
wire bad_nop=((i_class0==3'd3)&&(i_lower!=256'd0))||((i_class1==3'd3)&&(i_upper!=256'd0));
wire bad_pair=(d0&&opened&&(poison!=p0))||(d1&&middle_open&&(middle_poison!=p1));
wire bad_be=((i_class0==3'd2)&&opened)||((i_class1==3'd2)&&middle_open);
wire bad=bad_tag0||bad_tag1||bad_nop||bad_pair||bad_be;
assign allowed=seq_allowed&&!fatal&&!bad;
assign taken=i_commit&&allowed;assign rejected=i_rstn&&i_commit&&!allowed;
assign lower=allowed?i_class0:3'd7;assign upper=allowed?i_class1:3'd7;
always @(posedge i_clk)begin
 if(!i_rstn)begin fatal<=0;opened<=0;poison<=0;end
 else begin
  fatal<=fatal||(i_commit&&!allowed);
  if(taken)begin opened<=next_open;poison<=next_poison;end
 end
end
endmodule
module proof(input wire i_clk,i_rstn,i_commit,i_auth,input wire [511:0] i_flit,input wire [1:0] i_msg,output wire same_state,outputs_equal);
wire [98:0] actual,reference;
tl_full_flit dut(i_clk,i_rstn,i_commit,i_auth,i_flit,i_msg,actual[98],actual[97],actual[96],actual[95:93],actual[92:90],actual[89:83],actual[82:10],actual[9:7],actual[6:3],actual[2],actual[1],actual[0]);
full_reference ref_impl(i_clk,i_rstn,i_commit,i_auth,i_flit,i_msg,reference[98],reference[97],reference[96],reference[95:93],reference[92:90],reference[89:83],reference[82:10],reference[9:7],reference[6:3],reference[2],reference[1],reference[0]);
assign same_state=actual[89:0]==reference[89:0];assign outputs_equal=actual==reference;
endmodule
