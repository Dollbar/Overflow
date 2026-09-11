`timescale 1ns/1ps
module tb;
parameter PORTS=1,CAP=4;
localparam C_STATION_WIDTH=8,C_GENERATION_WIDTH=8,C_SLOT_WIDTH=(CAP<=2)?1:(CAP<=4)?2:(CAP<=8)?3:4;
localparam C_COUNT_WIDTH=(CAP<=1)?1:(CAP<=3)?2:(CAP<=7)?3:(CAP<=15)?4:5;
reg i_clk=0;always #5 i_clk=~i_clk;
reg  i_rstn=0;
reg  i_request_valid=0;
reg  i_issue_ready=0;
reg  i_release_valid=0;
reg [C_STATION_WIDTH-1:0] i_request_station=0;
reg [2-1:0] i_request_port=0;
reg [2-1:0] i_request_vc=0;
reg  i_request_pool=0;
reg [184-1:0] i_request_payload=0;
reg [2048-1:0] i_request_data=0;
reg [256-1:0] i_request_be=0;
reg [4-1:0] i_request_poison=0;
reg [4-1:0] i_request_data_pools=0;
reg [C_SLOT_WIDTH+C_GENERATION_WIDTH-1:0] i_release_token=0;
wire  o_request_ready;
wire  o_issue_valid;
wire  o_release_ready;
wire  o_error;
wire [C_SLOT_WIDTH+C_GENERATION_WIDTH-1:0] o_request_token;
wire [C_SLOT_WIDTH+C_GENERATION_WIDTH-1:0] o_issue_token;
wire [C_STATION_WIDTH-1:0] o_issue_station;
wire [2-1:0] o_issue_port;
wire [2-1:0] o_issue_vc;
wire  o_issue_pool;
wire [184-1:0] o_issue_payload;
wire [2048-1:0] o_issue_data;
wire [256-1:0] o_issue_be;
wire [4-1:0] o_issue_poison;
wire [4-1:0] o_issue_data_pools;
wire [C_COUNT_WIDTH-1:0] o_count;
reg  expected_o_request_ready;
reg  expected_o_issue_valid;
reg  expected_o_release_ready;
reg  expected_o_error;
reg [C_SLOT_WIDTH+C_GENERATION_WIDTH-1:0] expected_o_request_token;
reg [C_SLOT_WIDTH+C_GENERATION_WIDTH-1:0] expected_o_issue_token;
reg [C_STATION_WIDTH-1:0] expected_o_issue_station;
reg [2-1:0] expected_o_issue_port;
reg [2-1:0] expected_o_issue_vc;
reg  expected_o_issue_pool;
reg [184-1:0] expected_o_issue_payload;
reg [2048-1:0] expected_o_issue_data;
reg [256-1:0] expected_o_issue_be;
reg [4-1:0] expected_o_issue_poison;
reg [4-1:0] expected_o_issue_data_pools;
reg [C_COUNT_WIDTH-1:0] expected_o_count;
upli_endpoint_request_context #(.CAPACITY(CAP),.C_NUM_PORTS(PORTS)) dut(
.i_clk(i_clk),
.i_rstn(i_rstn),
.i_request_valid(i_request_valid),
.i_issue_ready(i_issue_ready),
.i_release_valid(i_release_valid),
.i_request_station(i_request_station),
.i_request_port(i_request_port),
.i_request_vc(i_request_vc),
.i_request_pool(i_request_pool),
.i_request_payload(i_request_payload),
.i_request_data(i_request_data),
.i_request_be(i_request_be),
.i_request_poison(i_request_poison),
.i_request_data_pools(i_request_data_pools),
.i_release_token(i_release_token),
.o_request_ready(o_request_ready),
.o_issue_valid(o_issue_valid),
.o_release_ready(o_release_ready),
.o_error(o_error),
.o_request_token(o_request_token),
.o_issue_token(o_issue_token),
.o_issue_station(o_issue_station),
.o_issue_port(o_issue_port),
.o_issue_vc(o_issue_vc),
.o_issue_pool(o_issue_pool),
.o_issue_payload(o_issue_payload),
.o_issue_data(o_issue_data),
.o_issue_be(o_issue_be),
.o_issue_poison(o_issue_poison),
.o_issue_data_pools(o_issue_data_pools),
.o_count(o_count)
);
integer fd,n,row=0,checks=0;reg [4095:0] file_name;
initial begin
 if(!$value$plusargs("VECTORS=%s",file_name))$fatal(1,"CONTEXT_MISMATCH missing vectors");
 fd=$fopen(file_name,"r");if(!fd)$fatal(1,"CONTEXT_MISMATCH missing file");
 while(!$feof(fd))begin
  @(negedge i_clk);#1;
  n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",i_rstn,i_request_valid,i_request_station,i_request_port,i_request_vc,i_request_pool,i_request_payload,i_request_data,i_request_be,i_request_poison,i_request_data_pools,i_issue_ready,i_release_valid,i_release_token,expected_o_request_ready,expected_o_request_token,expected_o_issue_valid,expected_o_issue_token,expected_o_issue_station,expected_o_issue_port,expected_o_issue_vc,expected_o_issue_pool,expected_o_issue_payload,expected_o_issue_data,expected_o_issue_be,expected_o_issue_poison,expected_o_issue_data_pools,expected_o_release_ready,expected_o_count,expected_o_error);
  if(n!=30)$fatal(1,"CONTEXT_MISMATCH parse row=%0d n=%0d",row,n);
  #1;
  checks=checks+1;if(o_request_ready!==expected_o_request_ready)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_request_ready got=%h expected=%h",row,o_request_ready,expected_o_request_ready);
  checks=checks+1;if(o_request_token!==expected_o_request_token)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_request_token got=%h expected=%h",row,o_request_token,expected_o_request_token);
  checks=checks+1;if(o_issue_valid!==expected_o_issue_valid)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_valid got=%h expected=%h",row,o_issue_valid,expected_o_issue_valid);
  checks=checks+1;if(o_issue_token!==expected_o_issue_token)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_token got=%h expected=%h",row,o_issue_token,expected_o_issue_token);
  checks=checks+1;if(o_issue_station!==expected_o_issue_station)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_station got=%h expected=%h",row,o_issue_station,expected_o_issue_station);
  checks=checks+1;if(o_issue_port!==expected_o_issue_port)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_port got=%h expected=%h",row,o_issue_port,expected_o_issue_port);
  checks=checks+1;if(o_issue_vc!==expected_o_issue_vc)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_vc got=%h expected=%h",row,o_issue_vc,expected_o_issue_vc);
  checks=checks+1;if(o_issue_pool!==expected_o_issue_pool)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_pool got=%h expected=%h",row,o_issue_pool,expected_o_issue_pool);
  checks=checks+1;if(o_issue_payload!==expected_o_issue_payload)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_payload got=%h expected=%h",row,o_issue_payload,expected_o_issue_payload);
  checks=checks+1;if(o_issue_data!==expected_o_issue_data)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_data got=%h expected=%h",row,o_issue_data,expected_o_issue_data);
  checks=checks+1;if(o_issue_be!==expected_o_issue_be)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_be got=%h expected=%h",row,o_issue_be,expected_o_issue_be);
  checks=checks+1;if(o_issue_poison!==expected_o_issue_poison)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_poison got=%h expected=%h",row,o_issue_poison,expected_o_issue_poison);
  checks=checks+1;if(o_issue_data_pools!==expected_o_issue_data_pools)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_issue_data_pools got=%h expected=%h",row,o_issue_data_pools,expected_o_issue_data_pools);
  checks=checks+1;if(o_release_ready!==expected_o_release_ready)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_release_ready got=%h expected=%h",row,o_release_ready,expected_o_release_ready);
  checks=checks+1;if(o_count!==expected_o_count)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_count got=%h expected=%h",row,o_count,expected_o_count);
  checks=checks+1;if(o_error!==expected_o_error)$fatal(1,"CONTEXT_MISMATCH row=%0d signal=o_error got=%h expected=%h",row,o_error,expected_o_error);
  @(posedge i_clk);#1;row=row+1;
 end
 $display("CONTEXT_PASS ports=%0d capacity=%0d rows=%0d checks=%0d",PORTS,CAP,row,checks);$finish;
end
endmodule
