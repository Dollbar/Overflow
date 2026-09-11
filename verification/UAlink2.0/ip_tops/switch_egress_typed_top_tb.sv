`timescale 1ns/1ps
module tb;
parameter P=1,V=1,D=544,T=8,U=4;
localparam IW=(P<=2)?1:2;
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
wire [P-1:0] typed_valid,typed_last,typed_kind,repack_error;
wire [P*544-1:0] typed_data;
wire [P*T-1:0] typed_token;
wire [P*2-1:0] typed_vc,typed_msg;
wire [P*24-1:0] typed_header;
wire [P*6-1:0] typed_aux;
wire [P*512-1:0] typed_flit;
wire [P-1:0] capture_ready=dut.gen_buffered.u_egress.pipeline_ready;
assign valid=dut.gen_buffered.u_egress.pipeline_valid;assign data=dut.gen_buffered.u_egress.pipeline_data;assign last=dut.gen_buffered.u_egress.pipeline_last;
assign token=dut.gen_buffered.u_egress.pipeline_token;assign out_vc=dut.gen_buffered.u_egress.pipeline_vc;assign kind=dut.gen_buffered.u_egress.pipeline_response;
reg [P-1:0] expected_valid=0,expected_last=0,expected_kind=0;
reg [P*544-1:0] expected_data=0;
reg [P*T-1:0] expected_token=0;
reg [P*2-1:0] expected_vc=0;
reg [543:0] supplied_word[0:255][0:3];
integer typed_words=0,typed_packets=0,early_release=0,typed_stalls=0,reset_typed_cancel=0;

reg [P*10-1:0] route_ids=0,dst;
reg cfg_write=0,cfg_commit=0;reg [IW-1:0] cfg_index=0;reg [9:0] cfg_id=0;
wire cfg_accepted,cfg_committed,cfg_pending,cfg_error,quiescent,fabric_error;
wire [P-1:0] route_error;
integer map_s,map_e;
always @* begin
 dst=0;
 for(map_s=0;map_s<P;map_s=map_s+1)for(map_e=0;map_e<P;map_e=map_e+1)
  if(route[map_s*P+map_e])dst[map_s*10+:10]=10'(256+map_e);
end
ualink_switch_top #(.PORTS(P),.DATA_WIDTH(544),.BUFFERED_EGRESS_ENABLE(1),.PACKET_VCS(V),.PACKET_TOKEN_WIDTH(T),.PACKET_UNIT_WIDTH(U),.ROUTE_CONFIG_ENABLE(1),.ROUTE_INDEX_WIDTH(IW)) dut(
.clk(clk),.rstn(rstn),.i_route_ids(route_ids),.i_port_enable({P{1'b1}}),.i_valid(bv),.o_ready(br),.i_data(bd),.i_dst(dst),.i_last(bl),.o_valid(typed_valid),.i_ready(ready),.o_data(typed_data),.o_last(typed_last),.o_route_error(route_error),.o_pending_features(),
.i_packet_header_valid(hv),.o_packet_header_ready(hr),.i_packet_units(units),.i_packet_token(ht),.i_packet_body_token(bt),.i_packet_vc(vc),.i_packet_response(response),
.o_typed_local_dl_header(typed_header),.o_typed_record_aux(typed_aux),.o_typed_tl_msg(typed_msg),.o_typed_tl_flit(typed_flit),.o_packet_token(typed_token),.o_packet_vc(typed_vc),.o_packet_response(typed_kind),.o_queue_release_valid(release_valid),.o_queue_release_units(release_units),.o_egress_error(error),
.i_route_write_valid(cfg_write),.i_route_write_index(cfg_index),.i_route_write_id(cfg_id),.i_route_write_enable(1'b1),.i_route_commit(cfg_commit),.o_route_write_accepted(cfg_accepted),.o_route_commit_accepted(cfg_committed),.o_route_config_pending(cfg_pending),.o_route_config_error(cfg_error),.o_route_quiescent(quiescent),.o_fabric_error(fabric_error));
assign available=dut.gen_buffered.u_egress.o_available;
assign reserved=dut.gen_buffered.u_egress.o_reserved;
assign queue_reserved=dut.gen_buffered.u_egress.o_queue_reserved;
assign stored=dut.gen_buffered.u_egress.o_stored;
assign completed=dut.gen_buffered.u_egress.o_completed;
assign source_busy=dut.gen_buffered.u_egress.o_source_busy;
assign source_sticky=dut.gen_buffered.u_egress.o_source_error_sticky;
assign he=dut.gen_buffered.u_egress.o_header_error;
assign be=dut.gen_buffered.u_egress.o_body_error;
assign qe=dut.gen_buffered.u_egress.o_queue_error_now;
assign qs=dut.gen_buffered.u_egress.o_queue_error_sticky;
assign re=dut.gen_buffered.u_egress.o_reservation_error;
assign repack_error=dut.gen_buffered.u_egress.o_repack_input_error;
assign selected=dut.gen_buffered.u_egress.o_selected;
assign owned=dut.gen_buffered.u_egress.o_owned;
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
  pending=0;for(sl=0;sl<N;sl=sl+1)pending=pending+account_reserved[sl];
  if(quiescent!==(!hv&&!bv&&!pending&&!expected_valid))$fatal(1,"TOP_QUIESCENT");
  if(route_error||fabric_error)$fatal(1,"TOP_ROUTE_ERROR");
  if(typed_valid!==expected_valid)$fatal(1,"TYPED_VALID");
  for(eg=0;eg<P;eg=eg+1)begin
   if(typed_valid[eg])begin
    if({typed_header[eg*24+:24],typed_aux[eg*6+:6],typed_msg[eg*2+:2],typed_flit[eg*512+:512]}!==expected_data[eg*544+:544]||typed_data[eg*544+:544]!==expected_data[eg*544+:544])$fatal(1,"TYPED_FULL_FIELDS");
    if({typed_token[eg*T+:T],typed_vc[eg*2+:2],typed_last[eg],typed_kind[eg]}!=={expected_token[eg*T+:T],expected_vc[eg*2+:2],expected_last[eg],expected_kind[eg]})$fatal(1,"TYPED_METADATA");
    if(ready[eg])begin typed_words=typed_words+1;if(typed_last[eg])typed_packets=typed_packets+1;end
    else typed_stalls=typed_stalls+1;
   end
   if(typed_valid[eg]&&ready[eg])expected_valid[eg]=0;
   if(valid[eg]&&capture_ready[eg])begin
    id=token[eg*T+:T];
    expected_valid[eg]=1;expected_data[eg*544+:544]=supplied_word[id][packet_position[id]];
    expected_token[eg*T+:T]=T'(id);expected_vc[eg*2+:2]=2'((packet_slot[id]/P)%V);
    expected_kind[eg]=(packet_slot[id]/P)>=V;expected_last[eg]=(packet_position[id]==packet_units[id]-1);
   end
  end
  if(repack_error)$fatal(1,"TYPED_REPACK_ERROR");
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
    supplied_word[id][body_written[id]]=bd[src*D+:D];
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
    if(data[eg*D+:D]!==supplied_word[id][packet_position[id]]||last[eg]!=(packet_position[id]==packet_units[id]-1))$fatal(1,"PIPELINE_PAYLOAD_LAST");
    owner_token[eg]=id;
    if(capture_ready[eg])begin
     account_stored[sl]=account_stored[sl]-1;words=words+1;packet_position[id]=packet_position[id]+1;held[eg]=0;
     if(last[eg])begin
      if(!ready[eg])early_release=early_release+1;
      expected_release[sl]=1;rlen=packet_units[id];
      if(release_units[sl*U+:U]!==U'(rlen))$fatal(1,"PIPELINE_RELEASE_UNITS");
      account_reserved[sl]=account_reserved[sl]-rlen;account_completed[sl]=account_completed[sl]-1;slot_pop[sl]=slot_pop[sl]+1;owner_token[eg]=-1;finishes=finishes+1;
     end
    end else begin held[eg]=1;held_data[eg]=data[eg*D+:D];stall_edges=stall_edges+1;end
   end
  end
  if(release_valid!==expected_release)$fatal(1,"PIPELINE_RELEASE_ONCE actual=%h expected=%h",release_valid,expected_release);
  for(sl=0;sl<N;sl=sl+1)if(release_valid[sl])releases=releases+1;
 end else begin expected_valid=0;expected_data=0;expected_token=0;expected_vc=0;expected_last=0;expected_kind=0;end
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
 for(e=0;e<P;e=e+1)begin
  @(negedge clk);cfg_write=1;cfg_index=IW'(e);cfg_id=10'(256+e);#1;if(!cfg_accepted)$fatal(1,"TOP_CONFIG_WRITE");
 end
 @(negedge clk);cfg_write=0;cfg_commit=1;#1;if(!cfg_committed)$fatal(1,"TOP_CONFIG_COMMIT");
 @(negedge clk);cfg_commit=0;
 for(roundno=0;roundno<3;roundno=roundno+1)begin
  ready=0;
  for(d=0;d<2*V;d=d+1)for(e=0;e<P;e=e+1)begin
   length=1+(d+e+roundno)%4;send_packet((e+d)%P,e,d,tagno,length);tagno=tagno+1;
  end
  repeat(7)@(negedge clk);target=admissions;ticks=0;
  while((finishes<target||typed_packets<target)&&ticks<1000)begin
   @(negedge clk);for(e=0;e<P;e=e+1)ready[e]=(ticks>e*7)&&(ticks%11<6);ticks=ticks+1;
  end
  if(finishes!=target||typed_packets!=target)$fatal(1,"PIPELINE_DRAIN_TIMEOUT");
  @(negedge clk);ready=0;repeat(4)@(negedge clk);
  if(reserved||queue_reserved||stored||completed)$fatal(1,"PIPELINE_RESIDUAL");
 end
 if(releases!=admissions||finishes!=admissions||typed_packets!=admissions||words!=typed_words||typed_stalls==0||early_release==0||stall_edges==0)$fatal(1,"PIPELINE_COVERAGE");
 // After queue released a single word, repack alone still blocks routing commit.
 send_packet(0,0,0,tagno,1);tagno=tagno+1;repeat(6)@(negedge clk);
 if(reserved||!typed_valid[0]||owned[0])$fatal(1,"TOP_REPACK_ONLY_SETUP");
 cfg_commit=1;#1;if(quiescent||cfg_committed||!cfg_error)$fatal(1,"TOP_REPACK_COMMIT");
 @(negedge clk);cfg_commit=0;ready={P{1'b1}};repeat(5)@(negedge clk);ready=0;
 if(typed_packets!=admissions||typed_words!=words)$fatal(1,"TOP_TYPED_FINAL_DRAIN");
 // A real complete held packet is cancelled by the common queue/scheduler reset.
 send_packet(0,0,0,tagno,3);repeat(6)@(negedge clk);if(!owned[0]||!valid[0]||!typed_valid[0])$fatal(1,"PIPELINE_RESET_OWNER_SETUP");
 reset_typed_cancel=typed_valid[0];rstn=0;repeat(3)@(negedge clk);if(valid||typed_valid||owned||release_valid||reserved||source_busy)$fatal(1,"PIPELINE_RESET_CANCEL");
 $display("TYPED_COUNTS words=%0d packets=%0d stalls=%0d early_release=%0d reset_cancel=%0d",typed_words,typed_packets,typed_stalls,early_release,reset_typed_cancel);
 $display("TOP_TYPED_PASS ports=%0d vcs=%0d cycles=%0d admissions=%0d completed=%0d releases=%0d words=%0d stalls=%0d reset_cancel=1",P,V,cycles,admissions,finishes,releases,words,stall_edges);$finish;
end
endmodule
