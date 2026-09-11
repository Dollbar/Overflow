`timescale 1ns/1ps
module tb;
parameter integer PORTS=1, WIDTH=184, CW=4, RETURN_DEPTH=2;
parameter [PORTS*5*CW-1:0] CAPS=20'h41302;
localparam PW=(RETURN_DEPTH<=1)?1:(RETURN_DEPTH<=3)?2:(RETURN_DEPTH<=7)?3:(RETURN_DEPTH<=15)?4:5;
reg clk=0,rstn=0,cc=0,bc=0,want=0,inject=0,receive_valid=0,send_actual=0;
reg [1:0] receive_port=0,receive_vc=0,consumer_port=0;
reg receive_pool=0,consumer_ready=0;
reg [WIDTH-1:0] receive_payload=0;
wire [WIDTH-1:0] head;
wire [1:0] head_vc;wire head_pool,head_valid,consume_valid,accepted;
wire [2:0] diagnostic,head_account;
wire [PORTS*5*CW-1:0] counts,balances;
wire [PORTS*(CW+3)-1:0] order_counts;
wire [PORTS-1:0] order_error,order_sticky;
wire [4*PW-1:0] pending;
wire [3:0] credit_valid,credit_pool,credit_done,bank_done;
wire [7:0] credit_vc,credit_num;
wire bank_error;
upli_ordered_receive_channel #(.C_NUM_PORTS(PORTS),.C_PAYLOAD_WIDTH(WIDTH),.C_CREDIT_WIDTH(CW),.C_CAPACITIES(CAPS),.C_RETURN_DEPTH(RETURN_DEPTH)) dut(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(cc),.i_beats_connected(bc),
.i_receive_valid(receive_valid),.i_receive_port(receive_port),.i_receive_vc(receive_vc),.i_receive_pool(receive_pool),.i_receive_payload(receive_payload),
.i_consumer_port(consumer_port),.i_consumer_ready(consumer_ready),
.o_head_payload(head),.o_head_vc(head_vc),.o_head_pool(head_pool),.o_head_valid(head_valid),.o_consume_valid(consume_valid),.o_receive_accepted(accepted),.o_diagnostic(diagnostic),
.o_counts(counts),.o_pending_count(pending),.o_credit_valid(credit_valid),.o_credit_pool(credit_pool),.o_credit_vc(credit_vc),.o_credit_num(credit_num),.o_credit_init_done(credit_done),
.o_head_account(head_account),.o_order_counts(order_counts),.o_order_error(order_error),.o_order_error_sticky(order_sticky));
upli_credit_bank #(.C_NUM_PORTS(PORTS),.C_CREDIT_WIDTH(CW),.C_CAPACITIES(CAPS)) peer(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(cc),.i_beats_connected(bc),
.i_credit_valid(credit_valid),.i_credit_pool(credit_pool),.i_credit_vc(credit_vc),.i_credit_num(credit_num),.i_credit_init_done(credit_done),
.i_send_valid(send_actual),.i_send_port(receive_port),.i_send_vc(receive_vc),.i_send_pool(receive_pool),.o_balances(balances),.o_init_confirmed(bank_done),.o_error(bank_error));
always #5 clk=~clk;
integer fd,n,cycle=0,p,a,ledger[0:PORTS*5-1],init_seen[0:PORTS-1];
reg live=0;
initial begin
for(a=0;a<PORTS*5;a=a+1)ledger[a]=0;
for(p=0;p<PORTS;p=p+1)init_seen[p]=0;
fd=$fopen("stimulus.txt","r");if(!fd)$fatal(1,"NO_STIMULUS");
@(posedge clk);#1;live=1;
while(!$feof(fd))begin
 @(negedge clk);#1;
 n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h\n",rstn,cc,bc,want,receive_port,receive_vc,receive_pool,receive_payload,consumer_port,consumer_ready,inject);
 if(n!=11)$fatal(1,"BAD_STIMULUS %0d",n);
 send_actual=0;
 if(rstn&&cc&&bc&&want&&receive_port<PORTS)
   if(init_seen[receive_port]>=2&&ledger[receive_port*5+(receive_pool?4:receive_vc)]>0)send_actual=1;
 receive_valid=send_actual||inject;
 @(posedge clk);#1;
end
@(negedge clk);live=0;receive_valid=0;send_actual=0;
$display("ORDERED_RECEIVE_RUN_DONE cycles=%0d",cycle);$finish;
end
always @(posedge clk)begin
if(live)begin
 cycle=cycle+1;
 $display("TRACE %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",cycle,rstn,cc,bc,send_actual,receive_valid,receive_port,receive_vc,receive_pool,receive_payload,consumer_port,consumer_ready,accepted,diagnostic,head_valid,consume_valid,head,head_vc,head_pool,head_account,order_counts,order_error,order_sticky,counts,pending,credit_valid,credit_pool,credit_vc,credit_num,credit_done,balances,bank_done,bank_error);
end
if(!rstn)begin
 for(a=0;a<PORTS*5;a=a+1)ledger[a]=0;
 for(p=0;p<PORTS;p=p+1)init_seen[p]=0;
end else begin
 // Only driver-owned ledger changes here; DUT inputs are stable through this edge.
 for(p=0;p<PORTS;p=p+1)begin
  if(credit_valid[p])ledger[p*5+(credit_pool[p]?4:credit_vc[p*2+:2])]=ledger[p*5+(credit_pool[p]?4:credit_vc[p*2+:2])]+{30'd0,credit_num[p*2+:2]}+1;
  if(init_seen[p]<2)begin if(credit_done[p])init_seen[p]=init_seen[p]+1;else init_seen[p]=0;end
 end
 if(send_actual)ledger[receive_port*5+(receive_pool?4:receive_vc)]=ledger[receive_port*5+(receive_pool?4:receive_vc)]-1;
end
end
endmodule
