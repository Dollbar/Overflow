`timescale 1ns/1ps
module receive_tdm_tb;
parameter PORTS=4;
reg clk=0; always #5 clk=~clk;
reg rstn=0;
reg [3:0] valid=0;
reg [7:0] ports=0;
wire [3:0] error_bits,sticky;
wire [2:0] known;
wire [5:0] phase;
upli_receive_tdm_monitor #(.C_NUM_PORTS(PORTS)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_req_valid(valid[0]),.i_req_port(ports[1:0]),
 .i_data_valid(valid[1]),.i_data_port(ports[3:2]),.i_rd_valid(valid[2]),.i_rd_port(ports[5:4]),
 .i_wr_valid(valid[3]),.i_wr_port(ports[7:6]),.o_error(error_bits),.o_error_sticky(sticky),
 .o_phase_known(known),.o_expected_port(phase));
integer fd,rc,rows,index;
reg [1023:0] filename;
reg [3:0] ee,es,ps;
reg [2:0] ek,pk;
reg [5:0] ep,pp;
initial begin
 if(!$value$plusargs("VECTORS=%s",filename))$fatal(1,"missing vectors");
 if(!$value$plusargs("ROWS=%d",rows))$fatal(1,"missing rows");
 fd=$fopen(filename,"r");if(!fd)$fatal(1,"cannot open vectors");
 // Establish synchronous reset before reference row zero.
 @(posedge clk);#1;
 for(index=0;index<rows;index=index+1)begin
  @(negedge clk);
  rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h\n",rstn,valid,ports,ee,ek,ep,es,pk,pp,ps);
  if(rc!=10)$fatal(1,"vector parse row %0d",index);
  #1;if({error_bits,known,phase,sticky}!=={ee,ek,ep,es})
   $fatal(1,"TDM_PRE row=%0d valid=%h ports=%h got=%h expected=%h",index,valid,ports,{error_bits,known,phase,sticky},{ee,ek,ep,es});
  @(posedge clk);#1;
  if({known,phase,sticky}!=={pk,pp,ps})$fatal(1,"TDM_POST row=%0d got=%h expected=%h",index,{known,phase,sticky},{pk,pp,ps});
 end
 $fclose(fd);$display("TDM_PASS ports=%0d rows=%0d",PORTS,rows);$finish;
end
endmodule
