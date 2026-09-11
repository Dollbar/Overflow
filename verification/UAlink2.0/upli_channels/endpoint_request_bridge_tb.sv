`timescale 1ps/1ps
module tb;
parameter PORTS=1,CASES=138;
reg clk=0;always #500 clk=~clk;
reg rstn=0,peer_ready=0;reg reset_fault_enable=0;
wire oq,oa,cq,ca,otx,orx,ob,ctx,crx,cb;
upli_connection_side oconn(.i_clk(clk),.i_rstn(rstn),.i_ready(1'b1),.i_peer_req(cq),.i_peer_ack(ca),.o_req(oq),.o_ack(oa),.o_tx_connected(otx),.o_rx_connected(orx),.o_beats_connected(ob));
upli_connection_side #(.C_IS_COMPLETER(1'b1)) cconn(.i_clk(clk),.i_rstn(rstn),.i_ready(peer_ready),.i_peer_req(oq),.i_peer_ack(oa),.o_req(cq),.o_ack(ca),.o_tx_connected(ctx),.o_rx_connected(crx),.o_beats_connected(cb));
reg [1:0] native_valid=0;
reg [1:0] native_port[0:1],native_vc[0:1];reg native_pool[0:1];reg [579:0] native_payload[0:1];
wire [579:0] heads[0:1];wire [1:0] head_vc[0:1];wire head_pool[0:1];wire [1:0] head_valid,consume_valid,consume_ready,accepted,bank_error;
wire [1:0] consume_port[0:1];wire [3:0] cv[0:1],cp[0:1],done[0:1],confirmed[0:1];wire [7:0] cvc[0:1],cn[0:1];
wire [PORTS*20-1:0] counts[0:1],balances[0:1];wire [2:0] diagnostics[0:1];wire [PORTS-1:0] order_error[0:1];
genvar g;generate for(g=0;g<2;g=g+1)begin:channels
 localparam W=(g==0)?184:580;wire [W-1:0] raw_head;
 assign heads[g]={{(580-W){1'b0}},raw_head};
 upli_ordered_receive_channel #(.C_NUM_PORTS(PORTS),.C_PAYLOAD_WIDTH(W),.C_DEFAULT_CAPACITY(4'd4),.C_RETURN_DEPTH(1)) receiver(
 .i_clk(clk),.i_rstn(rstn),.i_credit_connected(ctx),.i_beats_connected(cb),.i_receive_valid(native_valid[g]),.i_receive_port(native_port[g]),.i_receive_vc(native_vc[g]),.i_receive_pool(native_pool[g]),.i_receive_payload(native_payload[g][W-1:0]),
 .i_consumer_port(consume_port[g]),.i_consumer_ready(consume_ready[g]),.o_head_payload(raw_head),.o_head_vc(head_vc[g]),.o_head_pool(head_pool[g]),.o_head_valid(head_valid[g]),.o_consume_valid(consume_valid[g]),.o_receive_accepted(accepted[g]),.o_diagnostic(diagnostics[g]),.o_counts(counts[g]),.o_order_error_sticky(order_error[g]),
 .o_credit_valid(cv[g]),.o_credit_pool(cp[g]),.o_credit_vc(cvc[g]),.o_credit_num(cn[g]),.o_credit_init_done(done[g]));
 upli_credit_bank #(.C_NUM_PORTS(PORTS),.C_DEFAULT_CAPACITY(4'd4)) sender_bank(.i_clk(clk),.i_rstn(rstn),.i_credit_connected(orx),.i_beats_connected(ob),.i_credit_valid(cv[g]),.i_credit_pool(cp[g]),.i_credit_vc(cvc[g]),.i_credit_num(cn[g]),.i_credit_init_done(done[g]),.i_send_valid(native_valid[g]),.i_send_port(native_port[g]),.i_send_vc(native_vc[g]),.i_send_pool(native_pool[g]),.o_balances(balances[g]),.o_init_confirmed(confirmed[g]),.o_error(bank_error[g]));
end endgenerate
reg [1:0] selected_port=0;reg request_ready=0;wire request_valid,busy,error;
wire [1:0] request_port,request_vc;wire request_pool;wire [183:0] request_payload;wire [2047:0] request_data;wire [255:0] request_be;wire [3:0] request_poison,request_pools;
upli_endpoint_request_bridge #(.C_NUM_PORTS(PORTS)) dut(.i_clk(clk),.i_rstn(rstn),.i_select_port(selected_port),
 .o_req_consumer_port(consume_port[0]),.i_req_head_valid(head_valid[0]),.i_req_consume_valid(consume_valid[0]),.i_req_payload(heads[0][183:0]),.i_req_vc(head_vc[0]),.i_req_pool(head_pool[0]),.o_req_consumer_ready(consume_ready[0]),
 .o_data_consumer_port(consume_port[1]),.i_data_head_valid(head_valid[1]),.i_data_consume_valid(consume_valid[1]),.i_data_payload(heads[1]),.i_data_vc(head_vc[1]),.i_data_pool(head_pool[1]),.o_data_consumer_ready(consume_ready[1]),
 .o_request_valid(request_valid),.i_request_ready(request_ready),.o_request_port(request_port),.o_request_vc(request_vc),.o_request_pool(request_pool),.o_request_payload(request_payload),.o_request_data(request_data),.o_request_be(request_be),.o_request_poison(request_poison),.o_request_data_pools(request_pools),.o_busy(busy),.o_error(error));
reg [183:0] reqs[0:CASES-1];reg [2:0] ns[0:CASES-1];reg [579:0] origs[0:CASES*4-1];reg [2047:0] expected_data[0:CASES-1];reg [255:0] expected_be[0:CASES-1];reg [3:0] expected_poison[0:CASES-1],expected_pools[0:CASES-1];
reg [582:0] native_journal[0:1][0:3][0:2047];integer nw[0:1][0:3],nr[0:1][0:3];
reg [2:0] credits[0:1][0:3][0:2047];integer cw[0:1][0:3],rr[0:1][0:3],ledger[0:1][0:3][0:4];
integer cycles=0,checks=0,total_requests=0,total_heads=0,total_returns=0,stalled_cycles=0,resets=0;
integer epoch_heads[0:1],epoch_outputs=0,expected_index=0,expected_port=0,expected_req_vc=0,expected_req_pool=0,base_req=0,base_data=0;
reg expect_output=0,allow_error=0;integer c,p,a,j,amount;
task ck(input bit ok,input integer code);begin checks=checks+1;if(!ok)$fatal(1,"BRIDGE_MISMATCH id=%0d cycle=%0d ports=%0d case=%0d",code,cycles,PORTS,expected_index);end endtask
always @(posedge clk)begin
 cycles<=cycles+1;
 if(!rstn)begin
  epoch_outputs=0;epoch_heads[0]=0;epoch_heads[1]=0;
  for(c=0;c<2;c=c+1)for(p=0;p<4;p=p+1)begin nw[c][p]=0;nr[c][p]=0;cw[c][p]=0;rr[c][p]=0;for(a=0;a<5;a=a+1)ledger[c][p][a]=0;end
 end else begin
  ck(!error||allow_error,1);ck(bank_error==0,2);ck(diagnostics[0]==0&&diagnostics[1]==0&&order_error[0]==0&&order_error[1]==0,3);
  for(c=0;c<2;c=c+1)begin
   for(p=0;p<PORTS;p=p+1)if(cv[c][p])begin
    a=cp[c][p]?4:cvc[c][p*2+:2];amount=cn[c][p*2+:2]+1;
    if(done[c][p])begin
     // Only prior actual head transfers can earn normal return credits.
     for(j=0;j<amount;j=j+1)begin ck(rr[c][p]<cw[c][p],10);ck(credits[c][p][rr[c][p]]==={cp[c][p],cvc[c][p*2+:2]},11);rr[c][p]=rr[c][p]+1;total_returns=total_returns+1;end
    end
    ledger[c][p][a]=ledger[c][p][a]+amount;ck(ledger[c][p][a]<=4,12);
   end
   if(native_valid[c])begin
    p=native_port[c];a=native_pool[c]?4:native_vc[c];ck(ledger[c][p][a]>0,13);ledger[c][p][a]=ledger[c][p][a]-1;
    native_journal[c][p][nw[c][p]]={native_pool[c],native_vc[c],native_payload[c]};nw[c][p]=nw[c][p]+1;
   end
   if(consume_valid[c]&&consume_ready[c])begin
    p=consume_port[c];ck(nr[c][p]<nw[c][p],14);ck({head_pool[c],head_vc[c],heads[c]}===native_journal[c][p][nr[c][p]],15);
    nr[c][p]=nr[c][p]+1;credits[c][p][cw[c][p]]={head_pool[c],head_vc[c]};cw[c][p]=cw[c][p]+1;epoch_heads[c]=epoch_heads[c]+1;total_heads=total_heads+1;
   end
  end
  if(request_valid)begin
   ck(expect_output,20);ck(epoch_heads[0]==base_req+1&&epoch_heads[1]==base_data+ns[expected_index],21);
   ck(request_payload===reqs[expected_index]&&request_port==expected_port&&request_vc==expected_req_vc&&request_pool==expected_req_pool,22);
   ck(request_data===expected_data[expected_index]&&request_be===expected_be[expected_index]&&request_poison===expected_poison[expected_index]&&request_pools===expected_pools[expected_index],23);
   ck(!consume_ready[0]&&!consume_ready[1],24);
   if(request_ready)begin epoch_outputs=epoch_outputs+1;total_requests=total_requests+1;end else stalled_cycles=stalled_cycles+1;
  end
 end
 if(cycles>150000)$fatal(1,"BRIDGE_TIMEOUT");
end
// Every driver change occurs on a falling edge; counters never feed DUT combinationally at a sampling edge.
task start_epoch;begin
 @(negedge clk);#1;rstn=0;peer_ready=0;native_valid=0;request_ready=0;expect_output=0;selected_port=0;allow_error=0;
 repeat(4)@(negedge clk);#1;rstn=1;
 repeat(3)@(negedge clk);#1;ck(!busy&&!request_valid,30);peer_ready=1;
 wait((confirmed[0]&((1<<PORTS)-1))==((1<<PORTS)-1)&&(confirmed[1]&((1<<PORTS)-1))==((1<<PORTS)-1));
 repeat(2)@(negedge clk);#1;resets=resets+1;
end endtask
task send_case(input integer idx,input integer port,input integer beat_limit);integer b,n;begin
 n=ns[idx];
 @(negedge clk);#1;selected_port=port;expected_index=idx;expected_port=port;expected_req_vc=idx%4;expected_req_pool=(idx/4)%2;base_req=epoch_heads[0];base_data=epoch_heads[1];expect_output=1;
 for(b=0;b<((n==0)?1:beat_limit);b=b+1)begin
  @(negedge clk);#1;while(cycles%PORTS!=port)begin @(negedge clk);#1;end
  native_valid=(b==0)?((n==0)?2'b01:2'b11):2'b10;
  native_port[0]=port;native_port[1]=port;native_vc[0]=idx%4;native_vc[1]=idx%4;native_pool[0]=(idx/4)%2;native_pool[1]=(idx+b)%2;
  native_payload[0]={396'd0,reqs[idx]};native_payload[1]=origs[idx*4+b];
  @(negedge clk);#1;native_valid=0;native_payload[0]=~native_payload[0];native_payload[1]=~native_payload[1];
 end
end endtask
task finish_case;integer oldout,timeout;begin
 timeout=0;while(!request_valid&&timeout<200)begin @(negedge clk);#1;timeout=timeout+1;end
 ck(request_valid,40);oldout=epoch_outputs;
 // Changing selected port while occupied must not redirect Data or corrupt saved identity.
 repeat(31)begin @(negedge clk);#1;selected_port=(selected_port+1)%PORTS;end
 request_ready=1;
 @(negedge clk);#1;request_ready=0;expect_output=0;ck(epoch_outputs==oldout+1,41);
 repeat(12)@(negedge clk);#1;
 ck(!busy&&!request_valid&&counts[0]==0&&counts[1]==0,42);
 for(integer ch=0;ch<2;ch=ch+1)for(integer port=0;port<PORTS;port=port+1)begin ck(nr[ch][port]==nw[ch][port]&&rr[ch][port]==cw[ch][port],43);for(integer acc=0;acc<5;acc=acc+1)ck(ledger[ch][port][acc]==4,44);end
end endtask
task overlay_case;integer b,oldout,timeout;begin
 @(negedge clk);#1;selected_port=0;expected_index=127;expected_port=0;expected_req_vc=3;expected_req_pool=1;base_req=epoch_heads[0];base_data=epoch_heads[1];expect_output=1;
 for(b=0;b<4;b=b+1)begin
  @(negedge clk);#1;while(cycles%PORTS!=0)begin @(negedge clk);#1;end
  native_valid=(b<2)?2'b11:2'b10;native_port[0]=0;native_port[1]=0;
  native_vc[0]=(b==0)?3:2;native_pool[0]=(b==0);native_payload[0]={396'd0,reqs[(b==0)?127:0]};
  native_vc[1]=3;native_pool[1]=(127+b)%2;native_payload[1]=origs[127*4+b];
  @(negedge clk);#1;native_valid=0;native_payload[0]=~native_payload[0];native_payload[1]=~native_payload[1];
 end
 timeout=0;while(!request_valid&&timeout<200)begin @(negedge clk);#1;timeout=timeout+1;end
 ck(request_valid,60);oldout=epoch_outputs;
 repeat(41)begin @(negedge clk);#1;selected_port=(selected_port+1)%PORTS;end
 ck(epoch_heads[0]==base_req+1,61); // Read remains in actual Request SRAM while the complete older Write is held.
 request_ready=1;@(negedge clk);#1;request_ready=0;ck(epoch_outputs==oldout+1,62);
 expected_index=0;expected_req_vc=2;expected_req_pool=0;selected_port=0;base_req=epoch_heads[0];base_data=epoch_heads[1];
 finish_case();
end endtask
initial begin
 $readmemh("request.hex",reqs);$readmemh("n.hex",ns);$readmemh("orig.hex",origs);$readmemh("data.hex",expected_data);$readmemh("be.hex",expected_be);$readmemh("poison.hex",expected_poison);$readmemh("pools.hex",expected_pools);
 for(integer ch=0;ch<2;ch=ch+1)begin native_port[ch]=0;native_vc[ch]=0;native_pool[ch]=0;native_payload[ch]=0;end
 start_epoch();
 for(integer idx=0;idx<CASES;idx=idx+1)for(integer port=0;port<PORTS;port=port+1)begin send_case(idx,port,ns[idx]);finish_case();end
 overlay_case();
 // Actual SRAM heads transferred, but no complete 4-Beat Write exists yet; reset cancels it.
 send_case(127,PORTS-1,2);repeat(20)@(negedge clk);#1;ck(busy&&!request_valid&&epoch_heads[1]==base_data+2,50);
 start_epoch();repeat(15)@(negedge clk);#1;ck(!busy&&!request_valid&&counts[0]==0&&counts[1]==0,51);
 send_case(127,PORTS-1,4);finish_case();
 // Complete descriptor is held under downstream backpressure then cancelled, no old commit.
 send_case(127,0,4);wait(request_valid);repeat(5)@(negedge clk);#1;ck(busy&&request_valid,52);reset_fault_enable=1;
 start_epoch();repeat(15)@(negedge clk);#1;ck(!busy&&!request_valid,53);
 send_case(127,0,4);finish_case();
 // A malformed descriptor stays unconsumed; no fabricated credit or successful request.
 start_epoch();@(negedge clk);#1;allow_error=1;reqs[0][28]=1'b1;
 send_case(0,0,0);repeat(25)@(negedge clk);#1;
 ck(error&&!request_valid&&epoch_heads[0]==0&&counts[0]!=0&&!consume_ready[0],70);reqs[0][28]=1'b0;
 start_epoch();
 // A duplicate Data offset after one copied beat must not overwrite holding or consume the bad head.
 @(negedge clk);#1;allow_error=1;origs[127*4+1][3:2]=2'd0;
 send_case(127,0,4);repeat(25)@(negedge clk);#1;
 ck(error&&busy&&!request_valid&&epoch_heads[1]==1&&!consume_ready[1],71);origs[127*4+1][3:2]=2'd1;
 start_epoch();send_case(127,0,4);finish_case();
 $display("BRIDGE_PASS ports=%0d requests=%0d heads=%0d returned=%0d resets=%0d stalls=%0d checks=%0d cycles=%0d",PORTS,total_requests,total_heads,total_returns,resets,stalled_cycles,checks,cycles);$finish;
end
endmodule
