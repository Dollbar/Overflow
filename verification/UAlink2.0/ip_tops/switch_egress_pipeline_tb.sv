`timescale 1ns/1ps
module switch_egress_pipeline_tb;
parameter P=1,V=1,D=544,T=8,U=4;
localparam N=2*V*P;
reg clk=0;always #5 clk=~clk;
reg rstn=0;
reg [P-1:0] hv=0,response=0,bv=0,bl=0,ready=0;
reg [P*P-1:0] route=0;
reg [P*U-1:0] units=0;
reg [P*T-1:0] ht=0,bt=0;
reg [P*2-1:0] vc=0;
reg [P*D-1:0] bd=0;
wire [P-1:0] hr,br,valid,last,kind,owned,source_busy,source_sticky,he,be;
wire [P*D-1:0] data;
wire [P*T-1:0] token;
wire [P*2-1:0] out_vc;
wire [N-1:0] selected,release_valid,qe,qs;
wire [N*U-1:0] release_units,available,reserved,queue_reserved,stored,completed;
wire [2*V-1:0] re;
wire error;
switch_egress_pipeline #(.PORTS(P),.VCS(V),.DATA_WIDTH(D),.TOKEN_WIDTH(T),.UNIT_WIDTH(U)) dut(
.i_clk(clk),.i_rstn(rstn),.i_header_valid(hv),.i_route_match(route),.i_header_units(units),.i_header_token(ht),.i_header_vc(vc),.i_header_response(response),.o_header_ready(hr),
.i_body_valid(bv),.i_body_data(bd),.i_body_last(bl),.i_body_token(bt),.o_body_ready(br),.i_ready(ready),
.o_valid(valid),.o_data(data),.o_last(last),.o_token(token),.o_vc(out_vc),.o_response(kind),.o_selected(selected),.o_owned(owned),
.o_release_valid(release_valid),.o_release_units(release_units),.o_available(available),.o_reserved(reserved),.o_queue_reserved(queue_reserved),.o_stored(stored),.o_completed(completed),
.o_source_busy(source_busy),.o_source_error_sticky(source_sticky),.o_header_error(he),.o_body_error(be),.o_queue_error_now(qe),.o_queue_error_sticky(qs),.o_reservation_error(re),.o_error(error));
integer packet_slot[0:255],packet_units[0:255],packet_position[0:255],body_written[0:255];
integer slot_tokens[0:N-1][0:63],slot_push[0:N-1],slot_pop[0:N-1];
integer account_reserved[0:N-1],account_stored[0:N-1],account_completed[0:N-1];
integer owner_token[0:P-1],source_token[0:P-1];
reg [D-1:0] held_data[0:P-1];
reg [P-1:0] held=0;
integer cycles=0,admissions=0,finishes=0,words=0,releases=0,stall_edges=0;
integer s,e,d,tagno=0,length,n,roundno,ticks,target,pending;
function automatic [D-1:0] pattern(input integer id,input integer index);
 reg [D-1:0] x;
 begin
  for(integer bitno=0;bitno<D;bitno=bitno+1)x[bitno]=((id*71+index*37+bitno*19+bitno/5)%29)<14;
  pattern=x;
 end
endfunction
always @(posedge clk)begin:oracle
 integer src,eg,sl,id,count,rlen;
 reg [N-1:0] expected_release;
 cycles=cycles+1;if(cycles>14000)$fatal(1,"PIPELINE_TIMEOUT");
 if(rstn)begin
  if(error||he||be||source_sticky||qe||qs||re)$fatal(1,"PIPELINE_UNEXPECTED_ERROR");
  for(sl=0;sl<N;sl=sl+1)begin
   if(available[sl*U+:U]!==U'(4-account_reserved[sl])||reserved[sl*U+:U]!==U'(account_reserved[sl])||queue_reserved[sl*U+:U]!==U'(account_reserved[sl]))$fatal(1,"PIPELINE_RESERVATION sl=%0d got=%h expected=%0d",sl,reserved[sl*U+:U],account_reserved[sl]);
   if(stored[sl*U+:U]!==U'(account_stored[sl])||completed[sl*U+:U]!==U'(account_completed[sl]))$fatal(1,"PIPELINE_STORAGE_ACCOUNT");
  end
  expected_release=0;
  for(src=0;src<P;src=src+1)begin
   if(hv[src]&&hr[src])begin
    eg=-1;for(sl=0;sl<P;sl=sl+1)if(route[src*P+sl])eg=sl;
    id=ht[src*T+:T];sl=(response[src]*V+vc[src*2+:2])*P+eg;
    if(source_token[src]!=-1||eg<0||packet_units[id]!=0)$fatal(1,"PIPELINE_DOUBLE_ADMISSION");
    source_token[src]=id;packet_slot[id]=sl;packet_units[id]=units[src*U+:U];packet_position[id]=0;body_written[id]=0;
    slot_tokens[sl][slot_push[sl]]=id;slot_push[sl]=slot_push[sl]+1;account_reserved[sl]=account_reserved[sl]+units[src*U+:U];admissions=admissions+1;
   end
   if(bv[src]&&br[src])begin
    id=source_token[src];if(id<0||bt[src*T+:T]!==T'(id))$fatal(1,"PIPELINE_BODY_OWNER");
    if(bd[src*D+:D]!==pattern(id,body_written[id])||bl[src]!=(body_written[id]==packet_units[id]-1))$fatal(1,"PIPELINE_BODY_FORMAT");
    body_written[id]=body_written[id]+1;sl=packet_slot[id];account_stored[sl]=account_stored[sl]+1;
    if(bl[src])begin account_completed[sl]=account_completed[sl]+1;source_token[src]=-1;end
   end
  end
  for(eg=0;eg<P;eg=eg+1)begin
   count=0;for(sl=eg;sl<N;sl=sl+P)if(selected[sl])count=count+1;
   if(count>1)$fatal(1,"PIPELINE_MULTI_SELECTED");
   if(held[eg]&&valid[eg]&&data[eg*D+:D]!==held_data[eg])$fatal(1,"PIPELINE_STALL_DATA");
   if(valid[eg])begin
    id=token[eg*T+:T];sl=(kind[eg]*V+out_vc[eg*2+:2])*P+eg;
    if(sl>=N||packet_units[id]==0||packet_slot[id]!=sl||slot_pop[sl]>=slot_push[sl]||slot_tokens[sl][slot_pop[sl]]!=id)$fatal(1,"PIPELINE_CLASS_VC_TOKEN");
    if(owner_token[eg]!=-1&&owner_token[eg]!=id)$fatal(1,"PIPELINE_OWNER_INTERLEAVE");
    if(!selected[sl]||count!=1)$fatal(1,"PIPELINE_SELECTED_IDENTITY");
    if(body_written[id]!=packet_units[id])$fatal(1,"PIPELINE_PREMATURE_OUTPUT");
    if(data[eg*D+:D]!==pattern(id,packet_position[id])||last[eg]!=(packet_position[id]==packet_units[id]-1))$fatal(1,"PIPELINE_PAYLOAD_LAST");
    owner_token[eg]=id;
    if(ready[eg])begin
     account_stored[sl]=account_stored[sl]-1;words=words+1;packet_position[id]=packet_position[id]+1;held[eg]=0;
     if(last[eg])begin
      expected_release[sl]=1;rlen=packet_units[id];
      if(release_units[sl*U+:U]!==U'(rlen))$fatal(1,"PIPELINE_RELEASE_UNITS");
      account_reserved[sl]=account_reserved[sl]-rlen;account_completed[sl]=account_completed[sl]-1;slot_pop[sl]=slot_pop[sl]+1;owner_token[eg]=-1;finishes=finishes+1;
     end
    end else begin held[eg]=1;held_data[eg]=data[eg*D+:D];stall_edges=stall_edges+1;end
   end
  end
  if(release_valid!==expected_release)$fatal(1,"PIPELINE_RELEASE_ONCE actual=%h expected=%h",release_valid,expected_release);
  for(sl=0;sl<N;sl=sl+1)if(release_valid[sl])releases=releases+1;
 end
end
task send_packet(input integer src,input integer eg,input integer domain,input integer id,input integer len);
 integer k,w;
 begin
  @(negedge clk);hv=0;bv=0;route=0;hv[src]=1;route[src*P+eg]=1;units[src*U+:U]=U'(len);ht[src*T+:T]=T'(id);vc[src*2+:2]=2'(domain%V);response[src]=(domain>=V);
  #1;w=0;while(!hr[src]&&w<30)begin @(negedge clk);w=w+1;end
  if(!hr[src])$fatal(1,"PIPELINE_HEADER_TIMEOUT");
  @(posedge clk);@(negedge clk);hv=0;
  // Input classification/route noise after admission must not affect the saved body owner.
  route=~route;vc=~vc;response=~response;ht=~ht;
  for(k=0;k<len;k=k+1)begin
   repeat(k%2)@(negedge clk);
   bv[src]=1;bl[src]=(k==len-1);bt[src*T+:T]=T'(id);bd[src*D+:D]=pattern(id,k);
   @(posedge clk);if(!br[src])$fatal(1,"PIPELINE_BODY_NOT_RESERVED");
   @(negedge clk);bv=0;
  end
 end
endtask
initial begin
 for(s=0;s<256;s=s+1)begin packet_units[s]=0;packet_position[s]=0;body_written[s]=0;end
 for(s=0;s<N;s=s+1)begin slot_push[s]=0;slot_pop[s]=0;account_reserved[s]=0;account_stored[s]=0;account_completed[s]=0;end
 for(s=0;s<P;s=s+1)begin source_token[s]=-1;owner_token[s]=-1;end
 repeat(3)@(negedge clk);rstn=1;
 for(roundno=0;roundno<3;roundno=roundno+1)begin
  ready=0;
  for(d=0;d<2*V;d=d+1)for(e=0;e<P;e=e+1)begin
   length=1+(d+e+roundno)%4;send_packet((e+d)%P,e,d,tagno,length);tagno=tagno+1;
  end
  repeat(7)@(negedge clk);target=admissions;ticks=0;
  while(finishes<target&&ticks<1000)begin
   @(negedge clk);for(e=0;e<P;e=e+1)ready[e]=(ticks>e*7)&&(ticks%11<6);ticks=ticks+1;
  end
  if(finishes!=target)$fatal(1,"PIPELINE_DRAIN_TIMEOUT");
  @(negedge clk);ready=0;repeat(4)@(negedge clk);
  if(reserved||queue_reserved||stored||completed)$fatal(1,"PIPELINE_RESIDUAL");
 end
 if(releases!=admissions||finishes!=admissions||stall_edges==0)$fatal(1,"PIPELINE_COVERAGE");
 // A real complete held packet is cancelled by the common queue/scheduler reset.
 send_packet(0,0,0,tagno,3);repeat(6)@(negedge clk);if(!owned[0]||!valid[0])$fatal(1,"PIPELINE_RESET_OWNER_SETUP");
 rstn=0;repeat(3)@(negedge clk);if(valid||owned||release_valid||reserved||source_busy)$fatal(1,"PIPELINE_RESET_CANCEL");
 $display("PIPELINE_PASS ports=%0d vcs=%0d cycles=%0d admissions=%0d completed=%0d releases=%0d words=%0d stalls=%0d reset_cancel=1",P,V,cycles,admissions,finishes,releases,words,stall_edges);$finish;
end
endmodule
