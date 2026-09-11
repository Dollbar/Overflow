`timescale 1ns/1ps
module write_response_tb;
reg [107:0] stimulus;
reg [109:0] expected;
wire [109:0] observed;
reg i_rstn,i_valid;
wire [1:0] i_type_info,o_type_info;
wire [10:0] i_tag,o_tag;
wire [3:0] i_status,o_status;
wire [9:0] i_src,o_src;
wire [9:0] i_dst,o_dst;
wire [1:0] i_port,o_port;
wire [1:0] i_vc,o_vc;
wire [0:0] i_pool,o_pool;
wire [63:0] i_auth_tag,o_auth_tag;
wire o_valid,o_valid_parity,o_auth_tag_parity,o_control_parity;
integer fd,fields_read,rows,wanted;
reg [4095:0] path;
assign {i_rstn,i_valid,i_type_info,i_tag,i_status,i_src,i_dst,i_port,i_vc,i_pool,i_auth_tag} = stimulus;
assign observed={o_valid,o_type_info,o_tag,o_status,o_src,o_dst,o_port,o_vc,o_pool,o_auth_tag,o_valid_parity,o_auth_tag_parity,o_control_parity};
upli_write_response_channel dut(.i_rstn(i_rstn),.i_valid(i_valid),.o_valid(o_valid),.i_type_info(i_type_info),.o_type_info(o_type_info),.i_tag(i_tag),.o_tag(o_tag),.i_status(i_status),.o_status(o_status),.i_src(i_src),.o_src(o_src),.i_dst(i_dst),.o_dst(o_dst),.i_port(i_port),.o_port(o_port),.i_vc(i_vc),.o_vc(o_vc),.i_pool(i_pool),.o_pool(o_pool),.i_auth_tag(i_auth_tag),.o_auth_tag(o_auth_tag),.o_valid_parity(o_valid_parity),.o_auth_tag_parity(o_auth_tag_parity),.o_control_parity(o_control_parity));
initial begin
 stimulus=0; rows=0;
 if(!$value$plusargs("VECTORS=%s",path) || !$value$plusargs("ROWS=%d",wanted)) $fatal(1,"WRITE_RESPONSE_ARGS");
 fd=$fopen(path,"r"); if(!fd) $fatal(1,"WRITE_RESPONSE_OPEN");
 fields_read=$fscanf(fd,"%h %h\n",stimulus,expected);
 while(fields_read==2) begin
  #1; if(observed !== expected) $fatal(1,"WRITE_RESPONSE_COMPARE row=%0d actual=%h expected=%h",rows,observed,expected);
  rows=rows+1; fields_read=$fscanf(fd,"%h %h\n",stimulus,expected);
 end
 if(rows!=wanted || rows<3000 || fields_read!=-1 || !$feof(fd)) $fatal(1,"WRITE_RESPONSE_COUNT actual=%0d wanted=%0d",rows,wanted);
 $fclose(fd); $display("WRITE_RESPONSE_PASS rows=%0d",rows); $finish;
end
endmodule
