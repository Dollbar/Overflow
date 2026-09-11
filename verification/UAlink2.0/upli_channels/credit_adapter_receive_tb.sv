`timescale 1ns/1ps
module credit_adapter_receive_tb;
parameter integer PORTS=4;
localparam integer SLOTS=PORTS*5,TOTAL=SLOTS*3;
localparam [3:0] PORT_MASK=(1<<PORTS)-1;
reg clk=0;always #5 clk=~clk;
reg rstn=0,credit_connected=0,beats_connected=0;
reg send_valid=0;reg [1:0] send_port=0,send_vc=0;reg send_pool=0;reg [31:0] send_payload=0;
reg [1:0] consumer_port=0;reg [2:0] consumer_account=0;reg consumer_ready=0;
wire [31:0] head_payload;wire [1:0] head_vc;wire head_pool,head_valid,consume_valid,receive_accepted;wire [2:0] diagnostic;
wire [SLOTS*4-1:0] counts,balances;wire [11:0] pending;
wire [3:0] raw_valid,raw_pool,raw_init,wire_valid,wire_pool,wire_init,bank_init;
wire [7:0] raw_vc,raw_num,wire_vc,wire_num;
wire valid_parity,control_parity,valid_error,control_error,error,integrity_ok,bank_error;
upli_receive_channel #(.C_NUM_PORTS(PORTS),.C_PAYLOAD_WIDTH(32),.C_CREDIT_WIDTH(4),.C_DEFAULT_CAPACITY(4'd3),.C_RETURN_DEPTH(4)) receiver(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(credit_connected),.i_beats_connected(beats_connected),
.i_receive_valid(send_valid),.i_receive_port(send_port),.i_receive_vc(send_vc),.i_receive_pool(send_pool),.i_receive_payload(send_payload),
.i_consumer_port(consumer_port),.i_consumer_account(consumer_account),.i_consumer_ready(consumer_ready),
.o_head_payload(head_payload),.o_head_vc(head_vc),.o_head_pool(head_pool),.o_head_valid(head_valid),.o_consume_valid(consume_valid),
.o_receive_accepted(receive_accepted),.o_diagnostic(diagnostic),.o_counts(counts),.o_pending_count(pending),
.o_credit_valid(raw_valid),.o_credit_pool(raw_pool),.o_credit_vc(raw_vc),.o_credit_num(raw_num),.o_credit_init_done(raw_init));
upli_credit_return_adapter adapter(.i_credit_valid(raw_valid),.i_credit_pool(raw_pool),.i_credit_vc(raw_vc),.i_credit_num(raw_num),.i_credit_init_done(raw_init),
.o_credit_valid(wire_valid),.o_credit_pool(wire_pool),.o_credit_vc(wire_vc),.o_credit_num(wire_num),.o_credit_init_done(wire_init),.o_credit_valid_parity(valid_parity),.o_credit_parity(control_parity));
upli_credit_guard guard(.i_check_enable(rstn),.i_credit_valid(wire_valid),.i_credit_pool(wire_pool),.i_credit_vc(wire_vc),.i_credit_num(wire_num),
.i_credit_valid_parity(valid_parity),.i_credit_parity(control_parity),.o_valid_error(valid_error),.o_control_error(control_error),.o_error(error),.o_integrity_ok(integrity_ok));
// The real sender bank consumes the adapter bus. Diagnostics do not suppress it.
upli_credit_bank #(.C_NUM_PORTS(PORTS),.C_CREDIT_WIDTH(4),.C_DEFAULT_CAPACITY(4'd3),.C_INIT_CYCLES(2)) bank(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(credit_connected),.i_beats_connected(beats_connected),
.i_credit_valid(wire_valid),.i_credit_pool(wire_pool),.i_credit_vc(wire_vc),.i_credit_num(wire_num),.i_credit_init_done(wire_init),
.i_send_valid(send_valid),.i_send_port(send_port),.i_send_vc(send_vc),.i_send_pool(send_pool),.o_balances(balances),.o_init_confirmed(bank_init),.o_error(bank_error));

integer cycle=0,received=0,consumed=0,normal_returns=0,epoch=0;
integer budget[0:SLOTS-1],initial_count[0:SLOTS-1],written[0:SLOTS-1],read_index[0:SLOTS-1];
reg [31:0] payload_journal[0:SLOTS-1][0:2];reg [1:0] vc_journal[0:SLOTS-1][0:2];reg pool_journal[0:SLOTS-1][0:2];
integer retired_head[0:PORTS-1],retired_tail[0:PORTS-1],last_initial[0:PORTS-1];
reg [1:0] retired_vc[0:PORTS-1][0:TOTAL-1];reg retired_pool[0:PORTS-1][0:TOTAL-1];
reg seen_done[0:PORTS-1];integer p,s,k,n,slot,account,index;
reg sampled_send;
// A procedural population count independently checks the actual registered boundary.
task check_adapter;
integer b,ones_valid,ones_control;
begin
 if({wire_valid,wire_pool,wire_vc,wire_num,wire_init}!=={raw_valid,raw_pool,raw_vc,raw_num,raw_init})$fatal(1,"CREDIT_RETURN_DIRECT cycle=%0d",cycle);
 ones_valid=0;ones_control=0;
 for(b=0;b<4;b=b+1)begin ones_valid=ones_valid+int'(raw_valid[b]);ones_control=ones_control+int'(raw_pool[b]);end
 for(b=0;b<8;b=b+1)begin ones_control=ones_control+int'(raw_vc[b]);ones_control=ones_control+int'(raw_num[b]);end
 if(valid_parity!==((ones_valid%2)!=0)||control_parity!==((ones_control%2)!=0))$fatal(1,"CREDIT_RETURN_PARITY cycle=%0d",cycle);
 if({valid_error,control_error,error,integrity_ok}!==4'b0001)$fatal(1,"CREDIT_RETURN_GUARD cycle=%0d",cycle);
end
endtask

always @(posedge clk)begin
 sampled_send=send_valid;
 if(!rstn)begin
  cycle=0;received=0;consumed=0;normal_returns=0;
  for(s=0;s<SLOTS;s=s+1)begin budget[s]=0;initial_count[s]=0;written[s]=0;read_index[s]=0;end
  for(p=0;p<PORTS;p=p+1)begin retired_head[p]=0;retired_tail[p]=0;last_initial[p]=-1;seen_done[p]=0;end
 end else begin
  cycle=cycle+1;
  check_adapter();
  // Sending is checked against old journal credits, never same-edge returns.
  if(send_valid)begin
   account=send_pool?4:int'(send_vc);slot=int'(send_port)*5+account;
   if(slot>=SLOTS||budget[slot]<=0||!beats_connected||!bank_init[send_port])$fatal(1,"CREDIT_SEND_OWNERSHIP");
   budget[slot]=budget[slot]-1;
   index=written[slot];if(index>=3)$fatal(1,"CREDIT_SEND_CAPACITY");
   payload_journal[slot][index]=send_payload;vc_journal[slot][index]=send_vc;pool_journal[slot][index]=send_pool;
   written[slot]=index+1;received=received+1;
  end
  // Return matching happens before this edge's retirement journal is appended.
  for(p=0;p<PORTS;p=p+1)begin
   if(raw_init[p]&&!seen_done[p])begin
    if(last_initial[p]>=cycle||raw_valid[p])$fatal(1,"CREDIT_INITIAL_DONE_ORDER");
    for(k=0;k<5;k=k+1)if(initial_count[p*5+k]!=3)$fatal(1,"CREDIT_INITIAL_CAPACITY");
    seen_done[p]=1;
   end
   if(wire_valid[p])begin
    n=int'(wire_num[p*2+:2])+1;account=wire_pool[p]?4:int'(wire_vc[p*2+:2]);slot=p*5+account;
    if(!seen_done[p])begin
     initial_count[slot]=initial_count[slot]+n;last_initial[p]=cycle;
     if(initial_count[slot]>3)$fatal(1,"CREDIT_INITIAL_OVERFLOW");
    end else begin
     for(k=0;k<n;k=k+1)begin
      index=retired_head[p];
      if(index>=retired_tail[p])$fatal(1,"CREDIT_RETURN_WITHOUT_PRIOR_RETIRE");
      if(retired_vc[p][index]!==wire_vc[p*2+:2]||retired_pool[p][index]!==wire_pool[p])$fatal(1,"CREDIT_RETURN_ORIGINAL_ACCOUNT");
      retired_head[p]=index+1;normal_returns=normal_returns+1;
     end
    end
    budget[slot]=budget[slot]+n;if(budget[slot]>3)$fatal(1,"CREDIT_BUDGET_OVERFLOW");
   end
  end
  if((wire_valid&~PORT_MASK)!=0||(wire_init&~PORT_MASK)!=0)$fatal(1,"CREDIT_INACTIVE_PORT");
  if(consume_valid&&consumer_ready)begin
   slot=int'(consumer_port)*5+int'(consumer_account);index=read_index[slot];
   if(index>=written[slot])$fatal(1,"CREDIT_CONSUME_WITHOUT_RECEIVE");
   if({head_payload,head_vc,head_pool}!=={payload_journal[slot][index],vc_journal[slot][index],pool_journal[slot][index]})$fatal(1,"CREDIT_SRAM_PAYLOAD_ACCOUNT");
   read_index[slot]=index+1;consumed=consumed+1;
   p=int'(consumer_port);index=retired_tail[p];
   retired_vc[p][index]=head_vc;retired_pool[p][index]=head_pool;retired_tail[p]=index+1;
  end
 end
 #1;
 check_adapter(); // Detect any inserted register or output gating after RX NBA updates.
 if(rstn)begin
  if(receive_accepted!==sampled_send||diagnostic!=0||bank_error)$fatal(1,"CREDIT_RECEIVER_BANK_DIAGNOSTIC");
  for(s=0;s<SLOTS;s=s+1)begin
   if(int'(balances[s*4+:4])!=budget[s])$fatal(1,"CREDIT_BANK_COMPARE slot=%0d",s);
   if(int'(counts[s*4+:4])!=written[s]-read_index[s])$fatal(1,"CREDIT_COUNT_COMPARE slot=%0d",s);
  end
 end else if(wire_valid!=0||wire_init!=0||balances!=0||counts!=0||pending!=0)$fatal(1,"CREDIT_RESET_CLEAR");
end
integer ep,word,port,acct,cursor,timeout,total_receives=0,total_returns=0;
initial begin
 for(ep=1;ep<=2;ep=ep+1)begin
  @(negedge clk);rstn=0;credit_connected=0;beats_connected=0;send_valid=0;consumer_ready=0;epoch=ep;
  repeat(3)@(negedge clk);
  rstn=1;repeat(3)@(negedge clk);credit_connected=1;
  timeout=0;
  while((bank_init&PORT_MASK)!=PORT_MASK)begin @(negedge clk);timeout=timeout+1;if(timeout>100)$fatal(1,"CREDIT_STARTUP_TIMEOUT");end
  beats_connected=1;
  for(word=0;word<3;word=word+1)for(port=0;port<PORTS;port=port+1)for(acct=0;acct<5;acct=acct+1)begin
   @(negedge clk);send_valid=1;send_port=port[1:0];send_pool=(acct==4);send_vc=(acct==4)?word[1:0]:acct[1:0];
   send_payload=32'h90000000|(ep<<20)|(port<<12)|(acct<<8)|word;
  end
  @(negedge clk);send_valid=0;cursor=0;timeout=0;
  while(consumed<TOTAL||normal_returns<TOTAL)begin
   consumer_port=2'((cursor%SLOTS)/5);consumer_account=3'(cursor%5);consumer_ready=(cursor%7!=6);
   cursor=cursor+1;timeout=timeout+1;@(negedge clk);
   if(timeout>3000)$fatal(1,"CREDIT_DRAIN_TIMEOUT consumed=%0d returned=%0d",consumed,normal_returns);
  end
  consumer_ready=0;repeat(12)@(negedge clk);
  if(received!=TOTAL||consumed!=TOTAL||normal_returns!=TOTAL||counts!=0||pending!=0)$fatal(1,"CREDIT_FINAL_COUNTS");
  for(acct=0;acct<SLOTS;acct=acct+1)if(budget[acct]!=3)$fatal(1,"CREDIT_FINAL_BALANCE");
  total_receives=total_receives+received;total_returns=total_returns+normal_returns;
  $display("CREDIT_RETURN_EPOCH ports=%0d epoch=%0d cycles=%0d accepted=%0d consumed=%0d returned=%0d",PORTS,ep,cycle,received,consumed,normal_returns);
 end
 $display("CREDIT_RETURN_PASS ports=%0d epochs=2 accepted=%0d returned=%0d",PORTS,total_receives,total_returns);$finish;
end
initial begin #1000000;$fatal(1,"CREDIT_GLOBAL_TIMEOUT");end
endmodule
