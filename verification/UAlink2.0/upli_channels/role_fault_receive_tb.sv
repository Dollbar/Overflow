`timescale 1ns/1ps
module role_fault_receive_tb;
parameter PORTS=1,ROLES=2,IS_TL=0;
reg clk=0;always #5 clk=~clk;
reg rstn=0,connected=0;
reg [3:0] valid=0,ready=0,credit_flip=0;
reg [51:0] parity_in=0;
reg [ROLES-1:0] ack=0;
wire [ROLES-1:0] drop_roles,notify_roles,ack_accepted,reset_required,init_incomplete,init_roles;
wire [ROLES*PORTS-1:0] drop_ports;
wire [31:0] reasons;
wire [3:0] control_error,credit_error,auth_error,profile_error,metadata_error,order_error,storage_error,data_error,data_observed;
wire [3:0] accepted,head_valid,consume_valid;
wire [618:0] heads[0:3];
wire [PORTS*20-1:0] counts[0:3];
wire [3:0] cv[0:3],cp[0:3],done[0:3];
wire [7:0] cvc[0:3],cn[0:3];
wire [11:0] pending[0:3];
wire [3:0] credit_valid_parity,credit_fields_parity;
wire all_init;
assign all_init=(&done[0][PORTS-1:0])&&(&done[1][PORTS-1:0])&&(&done[2][PORTS-1:0])&&(&done[3][PORTS-1:0]);
generate
 if(ROLES==1)begin assign init_roles[0]=all_init;end
 else begin
  assign init_roles[0]=(&done[1][PORTS-1:0])&&(&done[2][PORTS-1:0]);
  assign init_roles[1]=(&done[0][PORTS-1:0])&&(&done[3][PORTS-1:0]);
 end
 for(genvar ch=0;ch<4;ch=ch+1)begin:channels
  localparam W=(ch==0)?184:(ch==1)?619:(ch==2)?101:580;
  localparam ROLE=(ROLES==1||ch==1||ch==2)?0:1;
  wire [W-1:0] head;
  wire [2:0] diagnostic;
  wire [PORTS-1:0] oe,os;
  assign heads[ch]={{(619-W){1'b0}},head};
  assign order_error[ch]=(|oe)||(|os);
  assign storage_error[ch]=|diagnostic;
  upli_native_rx_channel #(.CHANNEL_KIND(ch),.C_NUM_PORTS(PORTS)) rx(
   .i_clk(clk),.i_rstn(rstn),.i_credit_connected(connected),.i_beats_connected(connected),.i_drop(drop_roles[ROLE]),.i_auth_enabled(1'b0),
   .i_valid(valid[ch]),.i_port(2'd0),.i_vc(2'd0),.i_pool(1'b0),.i_payload({W{1'b0}}),.i_received_parity(parity_in[ch*13+:13]),
   .i_consumer_port(2'd0),.i_consumer_ready(ready[ch]),.o_head_payload(head),.o_head_parity(),.o_ingress_errors(),.o_head_errors(),
   .o_control_error(control_error[ch]),.o_data_error(data_error[ch]),.o_auth_error(auth_error[ch]),.o_auth_profile_error(profile_error[ch]),.o_metadata_error(metadata_error[ch]),.o_fault_stop_request(),
   .o_head_vc(),.o_head_pool(),.o_head_account(),.o_head_valid(head_valid[ch]),.o_consume_valid(consume_valid[ch]),.o_receive_accepted(accepted[ch]),
   .o_storage_diagnostic(diagnostic),.o_counts(counts[ch]),.o_pending_count(pending[ch]),.o_order_counts(),.o_order_error(oe),.o_order_error_sticky(os),
   .o_credit_valid(cv[ch]),.o_credit_pool(cp[ch]),.o_credit_vc(cvc[ch]),.o_credit_num(cn[ch]),.o_credit_init_done(done[ch]),.o_credit_valid_parity(credit_valid_parity[ch]),.o_credit_parity(credit_fields_parity[ch]));
  upli_credit_guard credit_guard(.i_check_enable(rstn),.i_credit_valid(4'd0),.i_credit_pool(4'd0),.i_credit_vc(8'd0),.i_credit_num(8'd0),.i_credit_valid_parity(credit_flip[ch]),.i_credit_parity(1'b0),.o_valid_error(),.o_control_error(),.o_error(credit_error[ch]),.o_integrity_ok());
 end
endgenerate
upli_rx_role_fault_controller #(.C_NUM_PORTS(PORTS),.C_NUM_ROLES(ROLES),.C_IS_TL(IS_TL)) controller(
 .i_clk(clk),.i_rstn(rstn),.i_fault_ack(ack),.i_init_done_roles(init_roles),.i_control_error(control_error),.i_credit_control_error(credit_error),
 .i_auth_error(auth_error),.i_auth_profile_error(profile_error),.i_metadata_error(metadata_error),.i_order_error(order_error),.i_storage_error(storage_error),.i_tdm_error(4'd0),.i_data_error(data_error),
 .o_drop_roles(drop_roles),.o_drop_ports(drop_ports),.o_notify_roles(notify_roles),.o_ack_accepted(ack_accepted),.o_reset_required(reset_required),.o_reason_sticky(reasons),.o_init_incomplete(init_incomplete),.o_data_error_observed(data_observed));
integer published[0:3][0:3][0:4],retired[0:3];
integer cycle=0,c,p,a,n;
reg [ROLES-1:0] expected_drop;
initial begin for(integer cc=0;cc<4;cc=cc+1)begin retired[cc]=0;for(integer pp=0;pp<4;pp=pp+1)for(integer aa=0;aa<5;aa=aa+1)published[cc][pp][aa]=0;end end
always @(posedge clk)begin
 cycle=cycle+1;
 if(!rstn)begin
  for(c=0;c<4;c=c+1)begin retired[c]=0;for(p=0;p<4;p=p+1)for(a=0;a<5;a=a+1)published[c][p][a]=0;end
 end else begin
  for(c=0;c<4;c=c+1)begin
   if(credit_valid_parity[c] !== (^cv[c]) || credit_fields_parity[c] !== (^{cp[c],cvc[c],cn[c]}))$fatal(1,"ROLE_RX_CREDIT_PARITY");
   for(p=0;p<4;p=p+1)if(cv[c][p])begin
    a=cp[c][p]?4:cvc[c][p*2+:2];published[c][p][a]=published[c][p][a]+cn[c][p*2+:2]+1;
    if(p>=PORTS||published[c][p][a]>3+((p==0&&a==0)?retired[c]:0))$fatal(1,"ROLE_RX_UNTRUSTED_RETURN");
   end
  end
 end
 if(cycle>3000)$fatal(1,"ROLE_RX_TIMEOUT");
end
initial begin
 repeat(3)@(negedge clk);rstn=1;connected=1;
 wait(all_init);repeat(3)@(negedge clk);
 // Actual OrigData parity error poisons one stored beat and never requests role Drop.
 valid=4'b1000;parity_in[39+:13]=13'h11;
 #1;if(drop_roles||data_observed!=8)$fatal(1,"ROLE_RX_DATA_DROPPED");
 @(posedge clk);#1;if(accepted!=8)$fatal(1,"ROLE_RX_POISON_NOT_STORED");
 @(negedge clk);valid=0;parity_in=0;
 wait(head_valid[3]);@(negedge clk);#1;if(heads[3]!==619'd1||drop_roles)$fatal(1,"ROLE_RX_POISON_PAYLOAD");
 ready=8;@(posedge clk);retired[3]=retired[3]+1;
 @(negedge clk);ready=0;
 repeat(6)@(negedge clk);
 // Queue one Request and two Read responses; retire one trustworthy Read before the fault.
 valid=3;parity_in[0+:13]=13'd1;parity_in[13+:13]=13'd1;
 @(posedge clk);#1;if(accepted!=3)$fatal(1,"ROLE_RX_SETUP_FIRST");
 @(negedge clk);valid=2;parity_in[0+:13]=0;
 @(posedge clk);#1;if(accepted!=2)$fatal(1,"ROLE_RX_SETUP_SECOND");
 @(negedge clk);valid=0;parity_in=0;
 wait(head_valid[0]&&head_valid[1]);@(negedge clk);ready=2;
 @(posedge clk);retired[1]=retired[1]+1;
 @(negedge clk);ready=0;
 // Bad Write response must block the still-owned Read head on this same input cycle.
 // The simultaneous good Request is allowed only in the other non-TL role.
 valid=5;parity_in[0+:13]=13'd1;parity_in[26+:13]=13'd3;ready=2;ack={ROLES{1'b1}};
 expected_drop=(ROLES==2&&!IS_TL)?1:{ROLES{1'b1}};
 #1;if(drop_roles!==expected_drop||consume_valid[1]||ack_accepted)$fatal(1,"ROLE_RX_SAME_EDGE_SCOPE");
 @(posedge clk);#1;
 if(accepted!==((ROLES==2&&!IS_TL)?4'b0001:4'b0000))$fatal(1,"ROLE_RX_CROSS_ACCEPT");
 if(counts[1][3:0]!=1||counts[2]!=0)$fatal(1,"ROLE_RX_BAD_RETIRE_OR_STORE");
 @(negedge clk);valid=0;parity_in=0;ready=0;
 repeat(8)@(negedge clk);
 if(drop_roles!==expected_drop||reset_required!==expected_drop||notify_roles)$fatal(1,"ROLE_RX_ACK_RECOVERED");
 if(published[1][0][0]!=4||pending[1]!=0)$fatal(1,"ROLE_RX_TRUSTED_CREDIT_LOST");
 if(ROLES==2&&!IS_TL)begin
  for(n=0;n<2;n=n+1)begin
   wait(consume_valid[0]);@(negedge clk);ready=1;
   @(posedge clk);retired[0]=retired[0]+1;
   @(negedge clk);ready=0;
  end
  repeat(6)@(negedge clk);if(counts[0]||published[0][0][0]!=5)$fatal(1,"ROLE_RX_UNAFFECTED_ROLE");
 end
 // Shared reset is the only recovery qualification; old payload/credits cannot survive.
 rstn=0;connected=0;ack=0;repeat(3)@(negedge clk);
 if(drop_roles||reasons||counts[0]||counts[1]||counts[2]||counts[3])$fatal(1,"ROLE_RX_RESET");
 // Real reverse-credit guard error belongs to Originator for Request credit, not Completer.
 rstn=1;connected=1;credit_flip=1;
 #1;if(drop_roles!==expected_drop)$fatal(1,"ROLE_RX_CREDIT_DIRECTION");
 @(posedge clk);#1;if(init_incomplete!==expected_drop)$fatal(1,"ROLE_RX_INIT_BOUNDARY");
 @(negedge clk);credit_flip=0;ack={ROLES{1'b1}};
 wait(all_init);repeat(5)@(negedge clk);
 if(drop_roles!==expected_drop||init_incomplete!==expected_drop||notify_roles)$fatal(1,"ROLE_RX_INIT_RECOVERY");
 $display("ROLE_RX_PASS ports=%0d roles=%0d tl=%0d cycles=%0d poison=1 good_retire_before_drop=1",PORTS,ROLES,IS_TL,cycle);$finish;
end
endmodule
