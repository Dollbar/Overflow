`timescale 1ns/1ps
module orig_data_tb;
reg [0:0] i_valid;
reg [1:0] i_port_id;
reg [511:0] i_data;
reg [63:0] i_byte_en;
reg [1:0] i_offset;
reg [0:0] i_last;
reg [0:0] i_error;
reg [1:0] i_vc;
reg [0:0] i_pool;
wire [0:0] o_orig_data_valid;
wire [1:0] o_orig_data_port_id;
wire [511:0] o_orig_data;
wire [63:0] o_orig_data_byte_en;
wire [1:0] o_orig_data_offset;
wire [0:0] o_orig_data_last;
wire [0:0] o_orig_data_error;
wire [1:0] o_orig_data_vc;
wire [0:0] o_orig_data_pool;
wire [0:0] o_orig_data_valid_parity;
wire [7:0] o_orig_data_parity;
wire [0:0] o_orig_data_byte_en_parity;
wire [0:0] o_orig_data_fields_parity;
reg [585:0] stimulus;
reg [596:0] expected;
wire [596:0] observed;
integer fd, fields, rows;
reg [4095:0] path;
assign {i_valid, i_port_id, i_data, i_byte_en, i_offset, i_last, i_error, i_vc, i_pool} = stimulus;
assign observed = {o_orig_data_valid, o_orig_data_port_id, o_orig_data, o_orig_data_byte_en, o_orig_data_offset, o_orig_data_last, o_orig_data_error, o_orig_data_vc, o_orig_data_pool, o_orig_data_valid_parity, o_orig_data_parity, o_orig_data_byte_en_parity, o_orig_data_fields_parity};
upli_orig_data_channel dut(.i_valid(i_valid),.i_port_id(i_port_id),.i_data(i_data),.i_byte_en(i_byte_en),.i_offset(i_offset),.i_last(i_last),.i_error(i_error),.i_vc(i_vc),.i_pool(i_pool),.o_orig_data_valid(o_orig_data_valid),.o_orig_data_port_id(o_orig_data_port_id),.o_orig_data(o_orig_data),.o_orig_data_byte_en(o_orig_data_byte_en),.o_orig_data_offset(o_orig_data_offset),.o_orig_data_last(o_orig_data_last),.o_orig_data_error(o_orig_data_error),.o_orig_data_vc(o_orig_data_vc),.o_orig_data_pool(o_orig_data_pool),.o_orig_data_valid_parity(o_orig_data_valid_parity),.o_orig_data_parity(o_orig_data_parity),.o_orig_data_byte_en_parity(o_orig_data_byte_en_parity),.o_orig_data_fields_parity(o_orig_data_fields_parity));
initial begin
 rows=0; stimulus=0;
 if (!$value$plusargs("VECTORS=%s",path)) $fatal(1,"ORIG_NO_VECTOR");
 fd=$fopen(path,"r"); if(!fd) $fatal(1,"ORIG_OPEN");
 fields=$fscanf(fd,"%h %h\n",stimulus,expected);
 while(fields==2) begin
  #1; if(observed !== expected) $fatal(1,"ORIG_COMPARE row=%0d actual=%h expected=%h",rows,observed,expected);
  rows=rows+1; fields=$fscanf(fd,"%h %h\n",stimulus,expected);
 end
 if(rows!=3688 || fields!=-1 || !$feof(fd)) $fatal(1,"ORIG_EMPTY %0d",rows);
 $display("ORIG_DATA_PASS rows=%0d",rows); $finish;
end
endmodule
