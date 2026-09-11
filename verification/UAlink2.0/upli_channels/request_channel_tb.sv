`timescale 1ns/1ps
module tb;
reg rstn,valid;
reg [188:0] fields;
wire out_valid,vp,ap,dp,cp;
wire [188:0] out_fields;
reg ev,evp,eap,edp,ecp;reg [188:0] ef;
integer fd,n,checks=0;
wire [1:0] i_asi,o_asi;
wire [63:0] i_auth_tag,o_auth_tag;
wire [9:0] i_src,o_src;
wire [9:0] i_dst,o_dst;
wire [10:0] i_tag,o_tag;
wire [1:0] i_num_beats,o_num_beats;
wire [56:0] i_address,o_address;
wire [5:0] i_command,o_command;
wire [5:0] i_length,o_length;
wire [7:0] i_attr,o_attr;
wire [7:0] i_metadata,o_metadata;
wire [1:0] i_port,o_port;
wire [1:0] i_vc,o_vc;
wire [0:0] i_pool,o_pool;
assign {i_asi,i_auth_tag,i_src,i_dst,i_tag,i_num_beats,i_address,i_command,i_length,i_attr,i_metadata,i_port,i_vc,i_pool}=fields;
assign out_fields={o_asi,o_auth_tag,o_src,o_dst,o_tag,o_num_beats,o_address,o_command,o_length,o_attr,o_metadata,o_port,o_vc,o_pool};
upli_request_channel dut(.i_rstn(rstn),.i_valid(valid),.o_valid(out_valid),.o_valid_parity(vp),.o_auth_tag_parity(ap),.o_address_parity(dp),.o_control_parity(cp),.i_asi(i_asi),.o_asi(o_asi),.i_auth_tag(i_auth_tag),.o_auth_tag(o_auth_tag),.i_src(i_src),.o_src(o_src),.i_dst(i_dst),.o_dst(o_dst),.i_tag(i_tag),.o_tag(o_tag),.i_num_beats(i_num_beats),.o_num_beats(o_num_beats),.i_address(i_address),.o_address(o_address),.i_command(i_command),.o_command(o_command),.i_length(i_length),.o_length(o_length),.i_attr(i_attr),.o_attr(o_attr),.i_metadata(i_metadata),.o_metadata(o_metadata),.i_port(i_port),.o_port(o_port),.i_vc(i_vc),.o_vc(o_vc),.i_pool(i_pool),.o_pool(o_pool));
initial begin
fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"NO_VECTORS");
while(!$feof(fd))begin
n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h\n",rstn,valid,fields,ev,ef,evp,eap,edp,ecp);
if(n==9)begin #1;checks=checks+1;if({out_valid,out_fields,vp,ap,dp,cp}!=={ev,ef,evp,eap,edp,ecp})$fatal(1,"REQUEST_MISMATCH vector=%0d got=%h expected=%h",checks,{out_valid,out_fields,vp,ap,dp,cp},{ev,ef,evp,eap,edp,ecp});end
end
$display("REQUEST_PASS checks=%0d",checks);$finish;end
endmodule
