module sequence_reference(input wire i_clk,i_rstn,i_commit,i_auth,input wire [255:0] i_lower,input wire [1:0] i_msg,input wire [7:0] i_type0,i_type1,output wire allowed,taken,rejected,output wire [2:0] lower,upper,output wire [6:0] pending,output wire [72:0] be);
wire [45:0] desc;tl_control_tenure certified_fields(i_lower,desc[45:44],desc[43:40],desc[39:8],desc[7:0]);
reg [6:0] count;reg [72:0] bits;
assign pending=count;assign be=bits;
wire control_slot=(count<=7'd1);
wire control=control_slot && !i_msg[0];
wire [6:0] offset0=7'd0;
wire [6:0] offset1=offset0+{3'd0,desc[8 +: 4]}+{6'd0,desc[0]};
wire [72:0] tail0=desc[0] ? (73'd1 << (offset0+{3'd0,desc[8 +: 4]})) : 73'd0;
wire [6:0] offset2=offset1+{3'd0,desc[12 +: 4]}+{6'd0,desc[1]};
wire [72:0] tail1=desc[1] ? (73'd1 << (offset1+{3'd0,desc[12 +: 4]})) : 73'd0;
wire [6:0] offset3=offset2+{3'd0,desc[16 +: 4]}+{6'd0,desc[2]};
wire [72:0] tail2=desc[2] ? (73'd1 << (offset2+{3'd0,desc[16 +: 4]})) : 73'd0;
wire [6:0] offset4=offset3+{3'd0,desc[20 +: 4]}+{6'd0,desc[3]};
wire [72:0] tail3=desc[3] ? (73'd1 << (offset3+{3'd0,desc[20 +: 4]})) : 73'd0;
wire [6:0] offset5=offset4+{3'd0,desc[24 +: 4]}+{6'd0,desc[4]};
wire [72:0] tail4=desc[4] ? (73'd1 << (offset4+{3'd0,desc[24 +: 4]})) : 73'd0;
wire [6:0] offset6=offset5+{3'd0,desc[28 +: 4]}+{6'd0,desc[5]};
wire [72:0] tail5=desc[5] ? (73'd1 << (offset5+{3'd0,desc[28 +: 4]})) : 73'd0;
wire [6:0] offset7=offset6+{3'd0,desc[32 +: 4]}+{6'd0,desc[6]};
wire [72:0] tail6=desc[6] ? (73'd1 << (offset6+{3'd0,desc[32 +: 4]})) : 73'd0;
wire [6:0] offset8=offset7+{3'd0,desc[36 +: 4]}+{6'd0,desc[7]};
wire [72:0] tail7=desc[7] ? (73'd1 << (offset7+{3'd0,desc[36 +: 4]})) : 73'd0;
wire [72:0] fresh_bits=tail0 | tail1 | tail2 | tail3 | tail4 | tail5 | tail6 | tail7;
wire [6:0] extended_count=count+(control?offset8:7'd0);
wire [72:0] extended_bits=bits|(control?(fresh_bits<<count):73'd0);
wire ordinary0=i_msg[0] && i_type0!=8'd32;
wire ordinary1=i_msg[1] && i_type1!=8'd32;
wire consume0=!control_slot && !ordinary0;
wire [2:0] expected0=control_slot?3'd0:(bits[0]?3'd2:3'd1);
wire [2:0] expected1=control_slot?
 ((count==7'd1)?(bits[0]?3'd2:3'd1):
 (control && i_auth && desc[43:40]!=0)?3'd6:
 (extended_count!=0)?(extended_bits[0]?3'd2:3'd1):3'd3):
 (bits[consume0]?3'd2:3'd1);
wire consume1=((expected1==3'd1)||(expected1==3'd2)) && !ordinary1;
wire [1:0] consumed={1'b0,consume0}+{1'b0,consume1};
wire msg0_legal=!i_msg[0] || i_type0==8'd0 || i_type0==8'd1 || i_type0==8'd32;
wire msg1_legal=!i_msg[1] || i_type1==8'd0 || i_type1==8'd1 || i_type1==8'd32;
wire poison0_legal=!(i_msg[0] && i_type0==8'd32) || expected0==3'd1;
wire poison1_legal=!(i_msg[1] && i_type1==8'd32) || expected1==3'd1;
wire auth_legal=!control || !i_auth || (desc[43:40]<=4'd4 && !(count==7'd1 && desc[43:40]!=0));
wire structural=!control || desc[45:44]==0;
wire tag_legal=expected1!=3'd6 || !i_msg[1];
wire valid=msg0_legal && msg1_legal && poison0_legal && poison1_legal && auth_legal && structural && tag_legal;
assign allowed=i_rstn && valid;
assign taken=i_commit && allowed;
assign rejected=i_rstn && i_commit && !valid;
assign lower=!allowed?3'd7 : i_msg[0]?(i_type0==8'd32 ? 3'd5 : 3'd4):expected0;
assign upper=!allowed?3'd7 : i_msg[1]?(i_type1==8'd32 ? 3'd5 : 3'd4):expected1;
always @(posedge i_clk)begin
 if(!i_rstn)begin count<=7'd0;bits<=73'd0;end
 else if(taken)begin count<=extended_count-{5'd0,consumed};bits<=extended_bits>>consumed;end
end
endmodule
