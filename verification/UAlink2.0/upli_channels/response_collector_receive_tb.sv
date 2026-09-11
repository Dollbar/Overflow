`timescale 1ns/1ps
module response_collector_receive_tb;
parameter PORTS=1;
reg clk=0;always #5 clk=~clk;
reg rstn=0,connected=0,stop=0;
reg [1:0] iv=0,ipool=0,sv=0,ready=0;
reg [3:0] ip=0,ivc=0,sp=0;
reg [618:0] incoming[0:1];
reg [25:0] parity=0;
wire [3:0] cp,rp,rvc,hvc;
wire [1:0] cr,rv,rpool,hpool,hv,cv,accepted,rx_fault,errors,retired;
wire [5:0] racc,hacc;
wire [618:0] head_rd,out_rd;
wire [100:0] head_wr,out_wr;
wire fault;
wire [7:0] credit_valid,credit_pool,done;
wire [15:0] credit_vc,credit_num;
wire [1:0] credit_vp,credit_fp;
wire [PORTS*20-1:0] counts[0:1];
wire [PORTS*7-1:0] orders[0:1];
genvar g;
generate for(g=0;g<2;g=g+1)begin:rx
 localparam W=(g==0)?619:101;
 wire [W-1:0] head;
 upli_native_rx_channel #(.CHANNEL_KIND(g+1),.C_NUM_PORTS(PORTS)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_credit_connected(connected),.i_beats_connected(connected),.i_drop(stop),.i_auth_enabled(1'b1),
 .i_valid(iv[g]),.i_port(ip[g*2+:2]),.i_vc(ivc[g*2+:2]),.i_pool(ipool[g]),.i_payload(incoming[g][W-1:0]),.i_received_parity(parity[g*13+:13]),
 .i_consumer_port(cp[g*2+:2]),.i_consumer_ready(cr[g]),.o_head_payload(head),.o_head_parity(),.o_ingress_errors(),.o_head_errors(),
 .o_control_error(),.o_data_error(),.o_auth_error(),.o_auth_profile_error(),.o_metadata_error(),.o_fault_stop_request(rx_fault[g]),
 .o_head_vc(hvc[g*2+:2]),.o_head_pool(hpool[g]),.o_head_account(hacc[g*3+:3]),.o_head_valid(hv[g]),.o_consume_valid(cv[g]),.o_receive_accepted(accepted[g]),
 .o_storage_diagnostic(),.o_counts(counts[g]),.o_pending_count(),.o_order_counts(orders[g]),.o_order_error(),.o_order_error_sticky(),
 .o_credit_valid(credit_valid[g*4+:4]),.o_credit_pool(credit_pool[g*4+:4]),.o_credit_init_done(done[g*4+:4]),
 .o_credit_vc(credit_vc[g*8+:8]),.o_credit_num(credit_num[g*8+:8]),.o_credit_valid_parity(credit_vp[g]),.o_credit_parity(credit_fp[g]));
 if(g==0)assign head_rd=head;else assign head_wr=head;
end endgenerate
upli_endpoint_response_collector #(.C_NUM_PORTS(PORTS)) dut(
.i_clk(clk),.i_rstn(rstn),.i_stop(stop),.i_select_valid(sv),.i_select_port(sp),.i_head_valid(hv),.i_consume_valid(cv),.i_head_vc(hvc),.i_head_pool(hpool),.i_head_account(hacc),
.i_read_payload(head_rd),.i_write_payload(head_wr),.i_retire_ready(ready),.o_consumer_port(cp),.o_consumer_ready(cr),.o_response_valid(rv),.o_response_port(rp),
.o_response_vc(rvc),.o_response_pool(rpool),.o_response_account(racc),.o_read_payload(out_rd),.o_write_payload(out_wr),.o_retired(retired),.o_metadata_error(errors),.o_fault_stop_request(fault));
reg [618:0] expected[0:1][0:3][0:255];
integer expected_vc[0:1][0:3][0:255],expected_pool[0:1][0:3][0:255];
integer pushed[0:1][0:3],popped[0:1][0:3];
integer returned[0:1][0:3][0:4],retire_ledger[0:1][0:3][0:4];
integer credit_written[0:1][0:3],credit_read[0:1][0:3];
reg [2:0] credit_expected[0:1][0:3][0:255];
reg normal_credits=0;
integer cycles=0,total_retired=0,total_accepted=0;
integer c,p,a,q,j,roundno,b,waits,target,tick;
reg [618:0] payload;
reg [1:0] held=0;
reg [1:0] held_port[0:1];
reg [618:0] held_payload[0:1];
reg [31:0] prng=32'h52789a;
function automatic [12:0] protection(input integer ch,input [618:0] data,input [1:0] port,input [1:0] vc,input pool);
 reg [12:0] code;
 begin
  code=13'd1;
  if(ch==0)begin
   code[1]=^{data[554:522],data[9:0],port,vc,pool};code[3]=^data[618:555];
   for(integer lane=0;lane<8;lane=lane+1)code[4+lane]=^data[10+lane*64+:64];
  end else begin code[1]=^{data[36:0],port,vc,pool};code[3]=^data[100:37];end
  protection=code;
 end
endfunction
always @(posedge clk)begin:journal
 integer ch,port,acc,pos,item;
 cycles=cycles+1;
 if(cycles>15000)$fatal(1,"COLLECTOR_RX_TIMEOUT");
 if(rstn)begin
  if(fault||rx_fault||errors)$fatal(1,"COLLECTOR_RX_UNEXPECTED_FAULT");
  if(stop&&(cr||rv||retired))$fatal(1,"COLLECTOR_RX_STOP");
  if(cr!==(rv&ready)||retired!==cr)$fatal(1,"COLLECTOR_RX_RETIRE_CAUSALITY");
  for(ch=0;ch<2;ch=ch+1)begin
   if(credit_vp[ch]!==^credit_valid[ch*4+:4]||credit_fp[ch]!==^{credit_pool[ch*4+:4],credit_vc[ch*8+:8],credit_num[ch*8+:8]})$fatal(1,"COLLECTOR_RX_CREDIT_PARITY");
   for(port=0;port<4;port=port+1)if(credit_valid[ch*4+port])begin
    if(port>=PORTS)$fatal(1,"COLLECTOR_RX_CREDIT_PORT");
    acc=credit_pool[ch*4+port]?4:credit_vc[ch*8+port*2+:2];
    if(normal_credits)begin
     for(item=0;item<=credit_num[ch*8+port*2+:2];item=item+1)begin
      if(credit_read[ch][port]>=credit_written[ch][port])$fatal(1,"COLLECTOR_RX_CREDIT_UNOWNED");
      if({credit_pool[ch*4+port],credit_vc[ch*8+port*2+:2]}!==credit_expected[ch][port][credit_read[ch][port]])$fatal(1,"COLLECTOR_RX_ORIGINAL_CREDIT_METADATA");
      credit_read[ch][port]=credit_read[ch][port]+1;
     end
    end
    returned[ch][port][acc]=returned[ch][port][acc]+credit_num[ch*8+port*2+:2]+1;
    if(returned[ch][port][acc]>3+retire_ledger[ch][port][acc])$fatal(1,"COLLECTOR_RX_FABRICATED_CREDIT");
   end
   if(held[ch] && cp[ch*2+:2]!==held_port[ch])$fatal(1,"COLLECTOR_RX_HOLD_PORT");
   if(rv[ch])begin
    if(held[ch] && (ch==0?out_rd:{{518{1'b0}},out_wr})!==held_payload[ch])$fatal(1,"COLLECTOR_RX_HOLD_PAYLOAD");
    if(cr[ch])held[ch]=0;
    else begin held[ch]=1;held_port[ch]=cp[ch*2+:2];held_payload[ch]=(ch==0?out_rd:{{518{1'b0}},out_wr});end
    port=rp[ch*2+:2];pos=popped[ch][port];
    if(pos>=pushed[ch][port])$fatal(1,"COLLECTOR_RX_UNOWNED");
    if((ch==0?out_rd:{{518{1'b0}},out_wr})!==expected[ch][port][pos])$fatal(1,"COLLECTOR_RX_PAYLOAD ch=%0d port=%0d pos=%0d",ch,port,pos);
    if(rvc[ch*2+:2]!==2'(expected_vc[ch][port][pos])||rpool[ch]!==1'(expected_pool[ch][port][pos]))$fatal(1,"COLLECTOR_RX_ACCOUNT");
    acc=expected_pool[ch][port][pos]?4:expected_vc[ch][port][pos];
    if(racc[ch*3+:3]!==3'(acc))$fatal(1,"COLLECTOR_RX_ACCOUNT_INDEX");
    if(cr[ch])begin
     credit_expected[ch][port][credit_written[ch][port]]={rpool[ch],rvc[ch*2+:2]};credit_written[ch][port]=credit_written[ch][port]+1;
     retire_ledger[ch][port][acc]=retire_ledger[ch][port][acc]+1;
     popped[ch][port]=pos+1;total_retired=total_retired+1;
    end
   end
  end
 end
end
initial begin
 incoming[0]=0;incoming[1]=0;
 for(c=0;c<2;c=c+1)for(p=0;p<4;p=p+1)begin
  pushed[c][p]=0;popped[c][p]=0;credit_written[c][p]=0;credit_read[c][p]=0;
  for(a=0;a<5;a=a+1)begin returned[c][p][a]=0;retire_ledger[c][p][a]=0;end
 end
 repeat(3)@(negedge clk);rstn=1;connected=1;
 waits=0;while(((done[3:0]&((1<<PORTS)-1))!=((1<<PORTS)-1)||(done[7:4]&((1<<PORTS)-1))!=((1<<PORTS)-1))&&waits<100)begin @(negedge clk);waits=waits+1;end
 repeat(4)@(negedge clk);
 for(c=0;c<2;c=c+1)for(p=0;p<PORTS;p=p+1)for(a=0;a<5;a=a+1)if(returned[c][p][a]!=3)$fatal(1,"COLLECTOR_RX_INIT");
 normal_credits=1;
 for(roundno=0;roundno<3;roundno=roundno+1)begin
  sv=0;ready=0;
  // Populate every actual SRAM account to capacity before any application retirement.
  for(p=0;p<PORTS;p=p+1)for(q=0;q<3;q=q+1)for(a=0;a<5;a=a+1)begin
   @(negedge clk);
   for(c=0;c<2;c=c+1)begin
    payload=0;
    for(b=0;b<(c==0?619:101);b=b+1)begin prng={prng[30:0],prng[31]^prng[21]^prng[1]^prng[0]};payload[b]=prng[7];end
    incoming[c]=payload;ip[c*2+:2]=2'(p);ivc[c*2+:2]=a==4?2'(q+roundno):2'(a);ipool[c]=(a==4);iv[c]=1;
    parity[c*13+:13]=protection(c,payload,ip[c*2+:2],ivc[c*2+:2],ipool[c]);
   end
   @(posedge clk);#1;if(accepted!==2'b11)$fatal(1,"COLLECTOR_RX_ACCEPT");
   for(c=0;c<2;c=c+1)begin
    j=pushed[c][p];expected[c][p][j]=incoming[c];expected_vc[c][p][j]=ivc[c*2+:2];expected_pool[c][p][j]=ipool[c];pushed[c][p]=j+1;total_accepted=total_accepted+1;
   end
   @(negedge clk);iv=0;parity=0;
  end
  repeat(3)@(negedge clk);
  for(c=0;c<2;c=c+1)for(p=0;p<PORTS;p=p+1)for(a=0;a<5;a=a+1)if(counts[c][(p*5+a)*4+:4]!==4'd3)$fatal(1,"COLLECTOR_RX_SATURATION");
  target=total_accepted;tick=0;sv=3;
  while(total_retired<target&&tick<3000)begin
   @(negedge clk);sp={2'((tick/3)%PORTS),2'((tick/2)%PORTS)};
   ready[0]=(tick>25)&&(tick%7<4);ready[1]=(tick%5<3);stop=(tick%43>=38);tick=tick+1;
  end
  if(total_retired!=target)$fatal(1,"COLLECTOR_RX_LOST");
  @(negedge clk);ready=0;sv=0;stop=0;repeat(12)@(negedge clk);
  for(c=0;c<2;c=c+1)begin
   if(counts[c]||orders[c])$fatal(1,"COLLECTOR_RX_OCCUPANCY");
   for(p=0;p<PORTS;p=p+1)for(a=0;a<5;a=a+1)if(returned[c][p][a]!=3+retire_ledger[c][p][a])$fatal(1,"COLLECTOR_RX_MISSING_CREDIT");
  end
 end
 // Cancel queued ownership with a common reset; no old epoch may retire after restart.
 @(negedge clk);incoming[0]=619'd0;ip=0;ivc=0;ipool=0;parity=26'd1;iv=1;
 @(posedge clk);#1;if(!accepted[0])$fatal(1,"COLLECTOR_RX_RESET_SETUP");
 j=pushed[0][0];expected[0][0][j]=0;expected_vc[0][0][j]=0;expected_pool[0][0][j]=0;pushed[0][0]=j+1;total_accepted=total_accepted+1;
 @(negedge clk);iv=0;parity=0;sv=1;sp=0;ready=0;
 repeat(5)@(negedge clk);rstn=0;connected=0;
 repeat(3)@(negedge clk);if(rv||retired||counts[0]||counts[1])$fatal(1,"COLLECTOR_RX_RESET");
 $display("COLLECTOR_RX_PASS ports=%0d cycles=%0d accepted=%0d retired=%0d reset_cancel=1",PORTS,cycles,total_accepted,total_retired);$finish;
end
endmodule
