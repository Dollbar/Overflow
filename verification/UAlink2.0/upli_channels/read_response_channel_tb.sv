`timescale 1ns/1ps
module tb;
reg rstn,valid;reg [623:0] fields;
wire out_valid,vp,ap,cp;wire [7:0] dp;wire [623:0] out_fields;
reg ev,evp,eap,ecp;reg [7:0] edp;reg [623:0] ef;integer fd,n,checks=0;
wire [1:0] i_port,o_port;
wire [63:0] i_auth_tag,o_auth_tag;
wire [9:0] i_src,o_src;
wire [9:0] i_dst,o_dst;
wire [10:0] i_tag,o_tag;
wire [1:0] i_num_beats,o_num_beats;
wire [511:0] i_data,o_data;
wire [3:0] i_status,o_status;
wire [1:0] i_offset,o_offset;
wire [0:0] i_last,o_last;
wire [0:0] i_data_error,o_data_error;
wire [1:0] i_type_info,o_type_info;
wire [1:0] i_vc,o_vc;
wire [0:0] i_pool,o_pool;
assign {i_port,i_auth_tag,i_src,i_dst,i_tag,i_num_beats,i_data,i_status,i_offset,i_last,i_data_error,i_type_info,i_vc,i_pool}=fields;
assign out_fields={o_port,o_auth_tag,o_src,o_dst,o_tag,o_num_beats,o_data,o_status,o_offset,o_last,o_data_error,o_type_info,o_vc,o_pool};
upli_read_response_channel dut(.i_rstn(rstn),.i_valid(valid),.o_valid(out_valid),.o_valid_parity(vp),.o_auth_tag_parity(ap),.o_data_parity(dp),.o_control_parity(cp),.i_port(i_port),.o_port(o_port),.i_auth_tag(i_auth_tag),.o_auth_tag(o_auth_tag),.i_src(i_src),.o_src(o_src),.i_dst(i_dst),.o_dst(o_dst),.i_tag(i_tag),.o_tag(o_tag),.i_num_beats(i_num_beats),.o_num_beats(o_num_beats),.i_data(i_data),.o_data(o_data),.i_status(i_status),.o_status(o_status),.i_offset(i_offset),.o_offset(o_offset),.i_last(i_last),.o_last(o_last),.i_data_error(i_data_error),.o_data_error(o_data_error),.i_type_info(i_type_info),.o_type_info(o_type_info),.i_vc(i_vc),.o_vc(o_vc),.i_pool(i_pool),.o_pool(o_pool));
initial begin
fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"NO_VECTORS");
while(!$feof(fd))begin
n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h\n",rstn,valid,fields,ev,ef,evp,eap,edp,ecp);
if(n==9)begin #1;checks=checks+1;if({out_valid,out_fields,vp,ap,dp,cp}!=={ev,ef,evp,eap,edp,ecp})$fatal(1,"READ_RESPONSE_MISMATCH vector=%0d got=%h expected=%h",checks,{out_valid,out_fields,vp,ap,dp,cp},{ev,ef,evp,eap,edp,ecp});end
end
$display("READ_RESPONSE_PASS checks=%0d",checks);$finish;end
endmodule
