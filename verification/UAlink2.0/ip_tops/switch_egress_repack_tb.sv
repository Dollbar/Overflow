`timescale 1ns/1ps
module switch_egress_repack_tb;
parameter P=1,V=1;
reg clk=0;always #5 clk=~clk;
reg rstn=0;
reg [P-1:0] valid,last,kind,ready;
reg [P*544-1:0] data;
reg [P*8-1:0] token;
reg [P*2-1:0] vc;
wire [P-1:0] ir,ov,ol,ok,error;
wire [P*24-1:0] header;
wire [P*6-1:0] aux;
wire [P*2-1:0] msg,oc;
wire [P*512-1:0] flit;
wire [P*8-1:0] ot;
switch_egress_repack #(.PORTS(P),.VCS(V)) dut(.i_clk(clk),.i_rstn(rstn),.i_valid(valid),.i_data(data),.i_last(last),.i_token(token),.i_vc(vc),.i_response(kind),.o_ready(ir),.i_ready(ready),.o_valid(ov),.o_local_dl_header(header),.o_record_aux(aux),.o_tl_msg(msg),.o_tl_flit(flit),.o_last(ol),.o_token(ot),.o_vc(oc),.o_response(ok),.o_input_error(error));
integer fd,rows,n,rc;
reg [2047:0] filename;
reg [P-1:0] eir,eov,eol,eok,ee;
reg [P*24-1:0] eh;
reg [P*6-1:0] ea;
reg [P*2-1:0] em,evc;
reg [P*512-1:0] ef;
reg [P*8-1:0] et;
initial begin
 if(!$value$plusargs("VECTORS=%s",filename)||!$value$plusargs("ROWS=%d",rows))$fatal(1,"args");fd=$fopen(filename,"r");if(!fd)$fatal(1,"file");
 @(posedge clk);#1;
 for(n=0;n<rows;n=n+1)begin
  @(negedge clk);rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",rstn,valid,data,last,token,vc,kind,ready,eir,eov,eh,ea,em,ef,eol,et,evc,eok,ee);
  if(rc!=19)$fatal(1,"parse");#1;
  if({ir,ov,header,aux,msg,flit,ol,ot,oc,ok,error}!=={eir,eov,eh,ea,em,ef,eol,et,evc,eok,ee})$fatal(1,"REPACK_CHECK row=%0d ready=%h/%h valid=%h/%h err=%h/%h",n,ir,eir,ov,eov,error,ee);
  @(posedge clk);#1;
 end
 $display("REPACK_PASS ports=%0d vcs=%0d rows=%0d",P,V,rows);$finish;
end
endmodule
