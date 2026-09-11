`timescale 1ns/1ps
module isolation_tb;
parameter P=1,C=1,SW=0,E=2;
reg clk=0;always #5 clk=~clk;
reg rstn=0,quiet,tv,read,cv,dr,dv,rv;
reg [P-1:0] iso,down,up,init,drop;
reg [1:0] ts,tp,cs,ds;
reg [E-1:0] te,ce,de,re;
reg [10:0] tag;
reg [2:0] beats;
wire [P-1:0] isolated,forward;
wire [E-1:0] epoch,qe;
wire [7:0] count;
wire tr,cr,discard,qv,qr,done_ready,recover_ready,recovered;
wire [1:0] qs,qp;
wire [10:0] qt;
wire [2:0] qb;
wire [3:0] status,error;
ras_originator_isolation #(.PORTS(P),.CAPACITY(C),.IS_SWITCH(SW),.EPOCH_WIDTH(E)) dut(
.i_clk(clk),.i_rstn(rstn),.i_isolate(iso),.i_link_down(down),.i_link_up(up),.i_init_done(init),.i_drop(drop),.i_quiescent(quiet),
.i_track_valid(tv),.i_track_slot(ts),.i_track_epoch(te),.i_track_port(tp),.i_track_tag(tag),.i_track_read(read),.i_track_beats(beats),.o_track_ready(tr),
.i_complete_valid(cv),.i_complete_slot(cs),.i_complete_epoch(ce),.o_complete_ready(cr),.o_complete_discard(discard),
.o_dummy_valid(qv),.i_dummy_ready(dr),.o_dummy_slot(qs),.o_dummy_epoch(qe),.o_dummy_port(qp),.o_dummy_tag(qt),.o_dummy_read(qr),.o_dummy_beats(qb),.o_dummy_status(status),
.i_dummy_done_valid(dv),.i_dummy_done_slot(ds),.i_dummy_done_epoch(de),.o_dummy_done_ready(done_ready),
.i_recover_valid(rv),.i_recover_epoch(re),.o_recover_ready(recover_ready),.o_recovered(recovered),.o_isolated(isolated),.o_forward_allowed(forward),.o_epoch(epoch),.o_count(count),.o_error(error));
reg [P-1:0] ei,ef;
reg [E-1:0] ee,eqe;
reg [7:0] ec;
reg etr,ecr,edisc,eqv,eqr,edr,err,era;
reg [1:0] eqs,eqp;
reg [10:0] eqt;
reg [2:0] eqb;
reg [3:0] estat,eerr;
integer fd,rows,n,rc;
reg [2047:0] filename;
initial begin
 iso=0;down=0;up=0;init=0;drop=0;quiet=0;tv=0;ts=0;te=0;tp=0;tag=0;read=0;beats=0;cv=0;cs=0;ce=0;dr=0;dv=0;ds=0;de=0;rv=0;re=0;
 if(!$value$plusargs("VECTORS=%s",filename)||!$value$plusargs("ROWS=%d",rows))$fatal(1,"args");fd=$fopen(filename,"r");if(!fd)$fatal(1,"file");@(posedge clk);#1;
 for(n=0;n<rows;n=n+1)begin
  @(negedge clk);rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",rstn,iso,down,up,init,drop,quiet,tv,ts,te,tp,tag,read,beats,cv,cs,ce,dr,dv,ds,de,rv,re,ei,ef,ee,ec,etr,ecr,edisc,eqv,eqs,eqe,eqp,eqt,eqr,eqb,estat,edr,err,era,eerr);
  if(rc!=42)$fatal(1,"parse %0d",rc);#1;
  if({isolated,forward,epoch,count,tr,cr,discard,qv,qs,qe,qp,qt,qr,qb,status,done_ready,recover_ready,recovered,error}!=={ei,ef,ee,ec,etr,ecr,edisc,eqv,eqs,eqe,eqp,eqt,eqr,eqb,estat,edr,err,era,eerr})$fatal(1,"ISOLATION_CHECK row=%0d mask=%h/%h count=%h/%h epoch=%h/%h error=%h/%h",n,isolated,ei,count,ec,epoch,ee,error,eerr);
  @(posedge clk);#1;
 end
 $display("ISOLATION_PASS ports=%0d capacity=%0d switch=%0d rows=%0d",P,C,SW,rows);$finish;
end
endmodule
