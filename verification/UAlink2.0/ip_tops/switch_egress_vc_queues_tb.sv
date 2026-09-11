`timescale 1ns/1ps
module tb;
parameter integer P=4,V=4,W=4,D=544,T=8,BAD=0;
localparam integer N=2*V*P;
parameter [N*W-1:0] CAPS={N{4'd3}};
reg clk=0,rstn=0;always #5 clk=~clk;
reg [P-1:0] hv=0,hr=0,bv=0,bl=0;
reg [P*P-1:0] route=0;
reg [P*W-1:0] units=0;
reg [P*T-1:0] ht=0,bt=0;
reg [P*2-1:0] vc=0;
reg [P*D-1:0] bd=0;
reg [N-1:0] ready=0;
wire [P-1:0] hready,bready,herror,berror,source_busy,source_sticky;
wire [N-1:0] valid,last,qerror,qsticky,release_valid;
wire [N*D-1:0] data;
wire [N*T-1:0] token;
wire [N*W-1:0] available,reserved,qr,stored,complete,release_units;
wire error;
switch_egress_vc_queues #(.PORTS(P),.VCS(V),.DATA_WIDTH(D),.TOKEN_WIDTH(T),.UNIT_WIDTH(W),.CAPACITIES(CAPS)) dut(
.i_clk(clk),.i_rstn(rstn),.i_header_valid(hv),.i_route_match(route),.i_header_units(units),.i_header_token(ht),.i_header_vc(vc),.i_header_response(hr),.o_header_ready(hready),
.i_body_valid(bv),.i_body_data(bd),.i_body_last(bl),.i_body_token(bt),.o_body_ready(bready),
.i_ready(ready),.o_valid(valid),.o_data(data),.o_last(last),.o_token(token),.o_release_valid(release_valid),.o_release_units(release_units),
.o_available(available),.o_reserved(reserved),.o_queue_reserved(qr),.o_stored(stored),.o_completed(complete),.o_source_busy(source_busy),
.o_header_error(herror),.o_body_error(berror),.o_source_error_sticky(source_sticky),.o_queue_error_now(qerror),.o_queue_error_sticky(qsticky),.o_error(error));
integer seq[0:P-1],left[0:P-1],tag[0:P-1],index[0:P-1];
integer c,s,e,k,dom,slot,cap,n,b,fd,injected=0,accepted=0;
reg [31:0] rng=32'h7649a3cf;
reg [D-1:0] word_value;
initial begin
fd=$fopen("trace.txt","w");for(s=0;s<P;s=s+1)begin seq[s]=0;left[s]=0;tag[s]=0;index[s]=0;end
for(c=0;c<2300;c=c+1)begin
 @(negedge clk);rstn=c>=3&&c!=1150&&c!=1151;
 hv=0;hr=0;route=0;units=0;ht=0;vc=0;bv=0;bl=0;bt=0;bd=0;ready=0;
 rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
 for(slot=0;slot<N;slot=slot+1)begin
  ready[slot]=(c>=1900)||((c>=350||(c>=270&&slot>=P)||slot>=V*P)&&c%29>7&&rng[slot%32]);
 end
 for(s=0;s<P;s=s+1)begin
  if(c<180)begin e=s;dom=0;end
  else if(c<270)begin e=s;dom=V;end
  else if(c<350&&V>1)begin e=s;dom=1;end
  else begin e=(seq[s]/(2*V)+s)%P;dom=(seq[s]+s*3)%(2*V);end
  slot=dom*P+e;cap=(CAPS>>(slot*W))&((1<<W)-1);
  for(k=0;k<N;k=k+1)if(cap==0)begin slot=(slot+1)%N;dom=slot/P;e=slot%P;cap=(CAPS>>(slot*W))&((1<<W)-1);end
  // Change current candidate even while a body is owned; the saved destination must win.
  hr[s]=dom>=V;vc[s*2+:2]=dom%V;route[s*P+e]=1;ht[s*T+:T]=(seq[s]*P+s);units[s*W+:W]=c<270?cap:(1+(seq[s]+s)%cap);
  if(c<1850)hv[s]=1;
  if(left[s]>0&&(c%5!=0||c>=1900))begin
   bv[s]=1;bl[s]=left[s]==1;bt[s*T+:T]=tag[s];word_value=0;
   for(b=0;b<D;b=b+1)word_value[b]=((tag[s]*71+index[s]*37+b*19+b/5)%29)<14;
   bd[s*D+:D]=word_value;
  end
 end
 if(BAD&&!injected&&c>500&&c<1000)for(s=0;s<P;s=s+1)begin
  if(!injected&&BAD==1&&bv[s])begin bt[s*T+:T]=bt[s*T+:T]^1;injected=1;end
  if(!injected&&BAD>=2&&left[s]==0&&hv[s])begin
   if(BAD==2)vc[s*2+:2]=3;
   if(BAD==3)begin bv[s]=1;bt[s*T+:T]=8'hb7;bl[s]=1;end
   if(BAD==4)route[s*P+:P]=0;
   if(BAD==5)units[s*W+:W]=0;
   if(BAD==6)units[s*W+:W]=(1<<W)-1;
   injected=1;
  end
 end
 @(posedge clk);
 $fdisplay(fd,"%0d %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",c,rstn,hv,route,units,ht,vc,hr,bv,bd,bl,bt,ready,hready,bready,valid,data,last,token,release_valid,release_units,available,reserved,qr,stored,complete,source_busy,herror,berror,source_sticky,qerror,qsticky,error,0);
 if(rstn)begin
  for(s=0;s<P;s=s+1)begin
   if(bv[s]&&bready[s])begin left[s]<=left[s]-1;index[s]<=index[s]+1;end
   if(hready[s])begin left[s]<=units[s*W+:W];tag[s]<=ht[s*T+:T];index[s]<=0;seq[s]<=seq[s]+1;accepted=accepted+1;end
  end
 end else for(s=0;s<P;s=s+1)begin left[s]<=0;seq[s]<=0;index[s]<=0;end
 #1;
end
$fclose(fd);$display("VC_QUEUE_RUN_DONE accepted=%0d",accepted);$finish;
end
endmodule
