`timescale 1ns/1ps
module tb;
parameter integer P=4,W=4,D=544,T=8,BAD=0;
parameter [P*W-1:0] CAPS={P{4'd7}};
reg clk=0,rstn=0;always #5 clk=~clk;
reg [P-1:0] request_valid=0,write_valid=0,write_last=0,read_ready=0;
reg [P*P-1:0] routes=0;
reg [P*W-1:0] request_units=0;
reg [P*D-1:0] write_data=0;
reg [P*T-1:0] write_token=0,reserve_token=0;
wire [P-1:0] request_ready,admit_ready,reserve_valid,write_ready,out_valid,out_last,release_valid,release_accepted;
wire [P*P-1:0] grant;
wire [P*W-1:0] grant_units,release_units,available,reserved,qr,stored,completed;
wire [P*D-1:0] out_data;
wire [P*T-1:0] out_token;
wire [P-1:0] req_error,rel_error,busy,error_now,error_sticky;
wire reserr,qerr;
switch_credit_reservation #(.PORTS(P),.UNIT_WIDTH(W),.CAPACITIES(CAPS)) reservation(
.i_clk(clk),.i_rstn(rstn),.i_request_valid(request_valid),.i_route_match(routes),.i_request_units(request_units),.i_admit_ready(admit_ready),
.i_release_valid(release_valid),.i_release_units(release_units),.o_request_ready(request_ready),.o_grant(grant),.o_grant_units(grant_units),
.o_release_accepted(release_accepted),.o_available(available),.o_reserved(reserved),.o_request_error(req_error),.o_release_error(rel_error),.o_error(reserr));
genvar g;generate for(g=0;g<P;g=g+1)begin
assign reserve_valid[g]=|grant[g*P+:P];
end endgenerate
switch_egress_packet_queue #(.PORTS(P),.DATA_WIDTH(D),.TOKEN_WIDTH(T),.UNIT_WIDTH(W),.CAPACITIES(CAPS)) dut(
.i_clk(clk),.i_rstn(rstn),.i_reserve_valid(reserve_valid),.i_reserve_units(grant_units),.i_reserve_token(reserve_token),.o_reserve_ready(admit_ready),
.i_write_valid(write_valid),.i_write_data(write_data),.i_write_last(write_last),.i_write_token(write_token),.o_write_ready(write_ready),
.i_ready(read_ready),.o_valid(out_valid),.o_data(out_data),.o_last(out_last),.o_token(out_token),.o_release_valid(release_valid),.o_release_units(release_units),
.o_reserved(qr),.o_stored(stored),.o_completed(completed),.o_busy(busy),.o_error_now(error_now),.o_error_sticky(error_sticky),.o_error(qerr));
integer cycle=0,seq[0:P-1],left[0:P-1],length[0:P-1],owner[0:P-1],tag[0:P-1],index[0:P-1];
integer s,e,k,dest,n,cap,b,fd,accepted=0,retired=0,injected=0;
reg [31:0] lfsr=32'h315efa09;
reg [D-1:0] word_value;
always @* begin
reserve_token=0;
for(integer a=0;a<P;a=a+1)for(integer z=0;z<P;z=z+1)
 if(grant[a*P+z])reserve_token[a*T+:T]=(seq[z]*P+z);
end
initial begin
fd=$fopen("trace.txt","w");
for(s=0;s<P;s=s+1)begin seq[s]=0;left[s]=0;length[s]=0;owner[s]=0;tag[s]=0;index[s]=0;end
for(cycle=0;cycle<1900;cycle=cycle+1)begin
 @(negedge clk);
 rstn=(cycle>=3)&&(cycle!=811)&&(cycle!=812);
 request_valid=0;request_units=0;routes=0;write_valid=0;write_data=0;write_last=0;write_token=0;read_ready=0;
 lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
 for(e=0;e<P;e=e+1)begin
  read_ready[e]=(cycle>1700)||((cycle%29)>8 && lfsr[e]);
  if(left[e]>0 && ((cycle%5)!=0 || cycle>1700))begin
   write_valid[e]=1;write_last[e]=(left[e]==1);write_token[e*T+:T]=tag[e];
   word_value=0;
   for(b=0;b<D;b=b+1)word_value[b]=((tag[e]*97+index[e]*41+b*13+(b/7)*19)%31)<15;
   write_data[e*D+:D]=word_value;
  end
 end
 if(cycle<1600)for(s=0;s<P;s=s+1)begin
  n=0;for(e=0;e<P;e=e+1)if(left[e]>0&&owner[e]==s)n=1;
  dest=(seq[s]+s)%P;cap=(CAPS>>(dest*W))&((1<<W)-1);
  for(k=0;k<P;k=k+1)if(cap==0)begin dest=(dest+1)%P;cap=(CAPS>>(dest*W))&((1<<W)-1);end
  if(n==0&&cap>0)begin request_valid[s]=1;routes[s*P+dest]=1;request_units[s*W+:W]=1+((seq[s]*3+s)%cap);end
 end
 if(!injected&&cycle>100&&cycle<700)for(e=0;e<P;e=e+1)begin
  if(!injected&&write_valid[e])begin
   if(BAD==1)begin write_token[e*T+:T]=write_token[e*T+:T]^1;injected=1;end
   if(BAD==2&&left[e]>1)begin write_last[e]=1;injected=1;end
   if(BAD==3&&left[e]==1)begin write_last[e]=0;injected=1;end
  end
 end
 @(posedge clk);
 $fdisplay(fd,"%0d %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",cycle,rstn,request_valid,routes,request_units,read_ready,write_valid,write_data,write_last,write_token,reserve_token,request_ready,grant,grant_units,admit_ready,write_ready,out_valid,out_data,out_last,out_token,release_valid,release_units,release_accepted,available,reserved,qr,stored,completed,busy,error_now,error_sticky,reserr,qerr);
 if(rstn)begin
  for(e=0;e<P;e=e+1)begin
   if(write_valid[e]&&write_ready[e])begin left[e]<=left[e]-1;index[e]<=index[e]+1;end
   if(release_valid[e])retired=retired+1;
   for(s=0;s<P;s=s+1)if(grant[e*P+s])begin
    left[e]<=(grant_units>>(e*W))&((1<<W)-1);length[e]<=(grant_units>>(e*W))&((1<<W)-1);owner[e]<=s;tag[e]<=(seq[s]*P+s)&((1<<T)-1);index[e]<=0;seq[s]<=seq[s]+1;accepted=accepted+1;
   end
  end
 end else for(e=0;e<P;e=e+1)begin left[e]<=0;index[e]<=0;seq[e]<=0;end
 // All driver state changes above only affect inputs recomputed next negedge, except reserve_token.
 #1;
end
$fclose(fd);$display("QUEUE_RUN_DONE accepted=%0d retired=%0d",accepted,retired);$finish;
end
endmodule
