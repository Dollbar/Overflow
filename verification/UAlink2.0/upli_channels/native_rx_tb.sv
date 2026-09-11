`timescale 1ns/1ps
module native_rx_tb;
parameter KIND=0,PORTS=1;
localparam W=(KIND==0)?184:(KIND==1)?619:(KIND==2)?101:580;
reg clk=0;always #5 clk=~clk;
reg auth_enabled=0;
reg rstn=0,connected=0,drop=0,valid=0,pool=0,ready=0;
reg [1:0] port=0,vc=0,consumer=0;
reg [W-1:0] payload=0;
reg [12:0] parity_in=0;
wire [W-1:0] head_payload;
wire [12:0] ingress_errors,head_errors,head_parity;
wire control_error,data_error,auth_error,profile_error,metadata_error,fault_stop;
wire accepted,head_valid,consume_valid,head_pool;
wire [1:0] head_vc;
wire [2:0] head_account,diagnostic;
wire [PORTS*20-1:0] counts;
wire [11:0] pending;
wire [PORTS*7-1:0] order_counts;
wire [PORTS-1:0] order_error,order_sticky;
wire [3:0] cv,cp,done;
wire [7:0] cvc,cn;
wire cvp,cfp;
upli_native_rx_channel #(.CHANNEL_KIND(KIND),.C_NUM_PORTS(PORTS)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_credit_connected(connected),.i_beats_connected(connected),.i_drop(drop),
 .i_auth_enabled(auth_enabled),.i_valid(valid),.i_port(port),.i_vc(vc),.i_pool(pool),.i_payload(payload),.i_received_parity(parity_in),
 .i_consumer_port(consumer),.i_consumer_ready(ready),.o_head_payload(head_payload),.o_head_parity(head_parity),
 .o_head_vc(head_vc),.o_head_pool(head_pool),.o_head_account(head_account),.o_head_valid(head_valid),.o_consume_valid(consume_valid),
 .o_ingress_errors(ingress_errors),.o_head_errors(head_errors),.o_control_error(control_error),.o_data_error(data_error),
 .o_auth_error(auth_error),.o_auth_profile_error(profile_error),.o_metadata_error(metadata_error),.o_fault_stop_request(fault_stop),
 .o_receive_accepted(accepted),.o_storage_diagnostic(diagnostic),.o_counts(counts),.o_pending_count(pending),.o_order_counts(order_counts),.o_order_error(order_error),.o_order_error_sticky(order_sticky),
 .o_credit_valid(cv),.o_credit_pool(cp),.o_credit_vc(cvc),.o_credit_num(cn),.o_credit_init_done(done),.o_credit_valid_parity(cvp),.o_credit_parity(cfp));
integer returned[0:3][0:4],retired[0:3][0:4];
integer cycle=0,fd,rc,rows,index,wait_cycles,account,accepted_count=0,consumed_count=0;
integer pp,aa,n;
reg [1023:0] file_name;
reg [12:0] exp_errors,exp_parity;
reg exp_control,exp_data,exp_auth,exp_profile,exp_accept;
reg [W-1:0] exp_payload;
reg [W+17:0] injected_envelope;
reg [W-1:0] injected_payload;
initial begin for(integer p=0;p<4;p=p+1)for(integer a=0;a<5;a=a+1)begin returned[p][a]=0;retired[p][a]=0;end end
always @(posedge clk)begin
 cycle=cycle+1;
 if(rstn)begin
  if(cvp !== (^cv)||cfp !== (^{cp,cvc,cn}))$fatal(1,"RX_CREDIT_PARITY");
  for(integer p=0;p<4;p=p+1)if(cv[p])begin
   if(p>=PORTS)$fatal(1,"RX_CREDIT_PORT");
   if(cp[p])aa=4;else aa=cvc[p*2+:2];
   returned[p][aa]=returned[p][aa]+cn[p*2+:2]+1;
   if(returned[p][aa]>3+retired[p][aa])$fatal(1,"RX_CREDIT_FABRICATED port=%0d account=%0d",p,aa);
  end
 end
 if(cycle>200000)$fatal(1,"RX_TIMEOUT");
end
initial begin
 if(!$value$plusargs("VECTORS=%s",file_name)||!$value$plusargs("ROWS=%d",rows))$fatal(1,"args");
 fd=$fopen(file_name,"r");if(!fd)$fatal(1,"vectors");
 repeat(3)@(negedge clk);rstn=1;connected=1;
 wait(&done[PORTS-1:0]);repeat(3)@(negedge clk);
 for(pp=0;pp<PORTS;pp=pp+1)for(n=0;n<5;n=n+1)if(returned[pp][n]!=3)$fatal(1,"RX_INITIAL_CREDIT");
 for(index=0;index<rows;index=index+1)begin
  @(negedge clk);ready=0;
  rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",auth_enabled,valid,drop,port,vc,pool,payload,parity_in,exp_errors,exp_control,exp_data,exp_auth,exp_profile,exp_payload,exp_parity,exp_accept);
  if(rc!=16)$fatal(1,"parse %0d",index);
  consumer=port;account=pool?4:vc;
  #1;
  if({ingress_errors,control_error,data_error,auth_error,profile_error}!=={exp_errors,exp_control,exp_data,exp_auth,exp_profile})$fatal(1,"RX_INGRESS row=%0d got=%h expected=%h",index,{ingress_errors,control_error,data_error,auth_error,profile_error},{exp_errors,exp_control,exp_data,exp_auth,exp_profile});
  @(posedge clk);#1;if(accepted!==exp_accept)$fatal(1,"RX_ACCEPT row=%0d got=%b expected=%b",index,accepted,exp_accept);
  if(exp_accept)accepted_count=accepted_count+1;
  @(negedge clk);valid=0;parity_in=0;drop=0;
  if(exp_accept)begin
   wait_cycles=0;while(!head_valid&&wait_cycles<20)begin @(negedge clk);wait_cycles=wait_cycles+1;end
   if(!head_valid)$fatal(1,"RX_MISSING_HEAD row=%0d",index);
   repeat(3)begin
    #1;if({head_payload,head_parity,head_vc,head_pool,head_account}!=={exp_payload,exp_parity,vc,pool,account[2:0]})$fatal(1,"RX_HEAD row=%0d",index);
    if(head_errors||fault_stop||metadata_error)$fatal(1,"RX_PROTECTED_HEAD row=%0d",index);
    @(negedge clk);
   end
   ready=1;#1;if(!consume_valid)$fatal(1,"RX_NOT_CONSUMABLE");
   @(posedge clk);retired[port][account]=retired[port][account]+1;consumed_count=consumed_count+1;
   @(negedge clk);ready=0;
  end
  repeat(7)@(negedge clk);
  if(counts!=0||order_counts!=0)$fatal(1,"RX_COUNT row=%0d",index);
  for(pp=0;pp<PORTS;pp=pp+1)for(n=0;n<5;n=n+1)if(returned[pp][n]!=3+retired[pp][n])$fatal(1,"RX_CREDIT_LOST row=%0d",index);
 end
 // True account saturation: exactly three protected entries fit; an illegal fourth native event cannot create storage or credit.
 @(negedge clk);auth_enabled=0;port=0;vc=0;pool=0;consumer=0;ready=0;drop=0;
 for(n=0;n<3;n=n+1)begin
  payload=n;parity_in=(n==0)?13'd1:13'd3;valid=1;
  @(posedge clk);#1;if(!accepted)$fatal(1,"RX_CAPACITY_EARLY_REJECT item=%0d",n);
  @(negedge clk);
 end
 payload=0;parity_in=13'd1;valid=1;
 @(posedge clk);#1;if(accepted||diagnostic==0||counts[3:0]!=3)$fatal(1,"RX_CAPACITY_OVERFLOW");
 @(negedge clk);valid=0;parity_in=0;
 repeat(5)@(negedge clk);
 for(n=0;n<3;n=n+1)begin
  wait_cycles=0;while(!consume_valid&&wait_cycles<20)begin @(negedge clk);wait_cycles=wait_cycles+1;end
  if(!consume_valid||head_payload!==W'(n))$fatal(1,"RX_CAPACITY_ORDER item=%0d",n);
  ready=1;@(posedge clk);retired[0][0]=retired[0][0]+1;
  @(negedge clk);ready=0;
 end
 repeat(8)@(negedge clk);
 if(counts||returned[0][0]!=3+retired[0][0])$fatal(1,"RX_CAPACITY_CREDIT");
 if(PORTS<4)begin
  port=3;valid=1;payload=0;parity_in=13'd1;
  @(posedge clk);#1;if(accepted||diagnostic==0)$fatal(1,"RX_INVALID_PORT");
  @(negedge clk);valid=0;parity_in=0;port=0;
  repeat(3)@(negedge clk);
 end
 // Inject transient SRAM-read-path corruption into an actual queued envelope.
 // Values are built from the known external zero record; never derive the oracle from DUT memory.
 @(negedge clk);auth_enabled=0;port=0;vc=0;pool=0;payload=0;parity_in=13'd1;valid=1;consumer=0;
 @(posedge clk);#1;if(!accepted)$fatal(1,"RX_HEAD_SETUP");
 @(negedge clk);valid=0;parity_in=0;
 repeat(5)@(negedge clk);if(!head_valid)$fatal(1,"RX_HEAD_SETUP_MISSING");
 injected_envelope=0;injected_envelope[W+:13]=13'd1;injected_envelope[0]=1;
 force dut.saved_envelope=injected_envelope;
 #1;ready=1;
 if(!control_error||!fault_stop||consume_valid||head_valid)$fatal(1,"RX_HEAD_CONTROL_GATE");
 repeat(3)@(negedge clk);if(counts[3:0]!=1)$fatal(1,"RX_BAD_HEAD_RETIRED");
 ready=0;release dut.saved_envelope;
 @(negedge clk);
 if(KIND!=3)begin
  injected_envelope=0;injected_envelope[W+:13]=13'd1;
  injected_envelope[(KIND==0)?118:(KIND==1)?555:37]=1;
  force dut.saved_envelope=injected_envelope;
  #1;if(!auth_error||control_error||!profile_error||consume_valid||head_valid)$fatal(1,"RX_HEAD_AUTH_GATE");
  @(negedge clk);release dut.saved_envelope;
 end
 // Saved port is changed together with its control parity: account consistency must still reject.
 @(negedge clk);injected_envelope=0;injected_envelope[W+:13]=13'd3;injected_envelope[W+16]=1;
 force dut.saved_envelope=injected_envelope;
 #1;if(!metadata_error||head_errors||consume_valid||head_valid)$fatal(1,"RX_HEAD_METADATA_GATE");
 @(negedge clk);release dut.saved_envelope;
 if(KIND==1||KIND==3)begin
  @(negedge clk);injected_envelope=0;injected_envelope[W+:13]=13'd1;
  injected_envelope[(KIND==1)?10:68]=1;
  injected_payload=0;injected_payload[(KIND==1)?10:68]=1;injected_payload[(KIND==1)?2:0]=1;
  force dut.saved_envelope=injected_envelope;
  #1;if(!data_error||fault_stop||!head_valid||head_payload!==injected_payload||head_parity!==13'h13)$fatal(1,"RX_HEAD_DATA_POISON");
  @(negedge clk);release dut.saved_envelope;
  if(KIND==3)begin
   @(negedge clk);injected_envelope=0;injected_envelope[W+:13]=13'd1;injected_envelope[4]=1;
   injected_payload=0;injected_payload[4]=1;injected_payload[0]=1;
   force dut.saved_envelope=injected_envelope;
   #1;if(!data_error||fault_stop||!head_valid||head_payload!==injected_payload||head_parity!==13'h1003)$fatal(1,"RX_HEAD_BE_POISON");
   @(negedge clk);release dut.saved_envelope;
  end
 end
 // Drop cannot retire the trusted head or accept even an otherwise good new beat.
 @(negedge clk);drop=1;ready=1;valid=1;parity_in=13'd1;
 #1;if(head_valid||consume_valid||fault_stop)$fatal(1,"RX_DROP_HEAD");
 @(posedge clk);#1;if(accepted||counts[3:0]!=1)$fatal(1,"RX_DROP_ACCEPT");
 @(negedge clk);valid=0;parity_in=0;ready=0;
 repeat(3)@(negedge clk);if(returned[0][0]!=3+retired[0][0])$fatal(1,"RX_DROP_FAKE_CREDIT");
 // One trusted retirement predates Drop; its registered return must naturally drain.
 drop=0;ready=1;
 @(posedge clk);retired[0][0]=retired[0][0]+1;
 @(negedge clk);drop=1;ready=0;
 repeat(8)@(negedge clk);
 if(returned[0][0]!=3+retired[0][0]||counts||pending)$fatal(1,"RX_DROP_TRUSTED_RETURN_LOST");
 drop=0;
 // Cancel a real protected queued item and its journal ownership with common reset.
 @(negedge clk);port=0;vc=0;pool=0;payload=0;parity_in=13'd1;valid=1;consumer=0;
 @(posedge clk);#1;if(!accepted)$fatal(1,"RX_RESET_SETUP");
 @(negedge clk);valid=0;parity_in=0;
 repeat(5)@(negedge clk);if(!head_valid)$fatal(1,"RX_RESET_NO_HEAD");
 rstn=0;connected=0;
 repeat(3)@(negedge clk);if(counts||head_valid||consume_valid||accepted||cv||pending||order_counts)$fatal(1,"RX_RESET_OWNERSHIP");
 $display("NATIVE_RX_PASS kind=%0d ports=%0d rows=%0d cycles=%0d accepted_vectors=%0d consumed_vectors=%0d accepted_directed=5 retired_directed=4 cancelled=1",KIND,PORTS,rows,cycle,accepted_count,consumed_count);$finish;
end
endmodule
