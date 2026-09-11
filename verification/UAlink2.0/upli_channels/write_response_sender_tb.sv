`timescale 1ns/1ps
module write_response_sender_tb;
parameter integer PORTS=1,WIDTH=4,INIT_CYCLES=2;
parameter [PORTS*5*WIDTH-1:0] CAPACITIES={PORTS*5{4'd4}};
localparam BANK_BITS=PORTS*5*WIDTH;
reg clk;
reg [137:0] stimulus;
reg [110:0] expected;
reg [BANK_BITS+8:0] before_state,after_state;
wire rstn,credit_connected,beats_connected,cvld,cpool;
wire [1:0] cport,cvc;
wire [100:0] payload;
wire [3:0] return_valid,return_pool,done;
wire [7:0] return_vc,return_num;
wire accepted,valid,pool,valid_parity,auth_parity,control_parity,credit_error,sticky,known;
wire [1:0] typ,port,vc,phase;
wire [10:0] tag;
wire [3:0] status,init;
wire [9:0] src,dst;
wire [63:0] auth;
wire [BANK_BITS-1:0] balances;
wire [110:0] observed;
wire [BANK_BITS+8:0] state;
reg [4095:0] path;
integer fd,read_fields,rows,wanted,sends,held,account,p,a,grant;
integer journal[0:PORTS*5-1];
integer tentative[0:PORTS*5-1];
reg journal_error,waiting;
reg [105:0] waiting_tuple;
assign {rstn,credit_connected,beats_connected,cvld,cport,cvc,cpool,payload,return_valid,return_pool,return_vc,return_num,done}=stimulus;
assign observed={accepted,valid,typ,tag,status,src,dst,port,vc,pool,auth,valid_parity,auth_parity,control_parity};
assign state={balances,init,known,phase,credit_error,sticky};
upli_write_response_sender #(.C_NUM_PORTS(PORTS),.C_CREDIT_WIDTH(WIDTH),.C_CAPACITIES(CAPACITIES),.C_INIT_CYCLES(INIT_CYCLES)) dut(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(credit_connected),.i_beats_connected(beats_connected),
.i_candidate_valid(cvld),.i_candidate_port(cport),.i_candidate_vc(cvc),.i_candidate_pool(cpool),.i_candidate_payload(payload),
.i_credit_valid(return_valid),.i_credit_pool(return_pool),.i_credit_vc(return_vc),.i_credit_num(return_num),.i_credit_init_done(done),
.o_candidate_accepted(accepted),.o_valid(valid),.o_type_info(typ),.o_tag(tag),.o_status(status),.o_src(src),.o_dst(dst),.o_port(port),.o_vc(vc),.o_pool(pool),.o_auth_tag(auth),
.o_valid_parity(valid_parity),.o_auth_tag_parity(auth_parity),.o_control_parity(control_parity),
.o_balances(balances),.o_init_confirmed(init),.o_credit_error(credit_error),.o_credit_error_sticky(sticky),.o_tdm_known(known),.o_tdm_port(phase));
initial begin
 clk=0;stimulus=0;rows=0;sends=0;held=0;waiting=0;waiting_tuple=0;
 for(account=0;account<PORTS*5;account=account+1) journal[account]=0;
 if(!$value$plusargs("VECTORS=%s",path)||!$value$plusargs("ROWS=%d",wanted)) $fatal(1,"WR_SENDER_ARGS");
 fd=$fopen(path,"r");if(!fd)$fatal(1,"WR_SENDER_OPEN");
 read_fields=$fscanf(fd,"%h %h %h %h\n",stimulus,expected,before_state,after_state);
 while(read_fields==4) begin
  #4;
  if(rows>0 && (observed!==expected || state!==before_state)) $fatal(1,"WR_SENDER_PRE row=%0d got=%h wanted=%h state=%h before=%h",rows,observed,expected,state,before_state);
  if(accepted!==valid) $fatal(1,"WR_SENDER_ACCEPT row=%0d",rows);
  if(rstn && waiting && (!cvld || {cport,cvc,cpool,payload}!==waiting_tuple)) $fatal(1,"WR_SENDER_STIMULUS_HOLD row=%0d",rows);
  waiting=rstn&&cvld&&!accepted;waiting_tuple={cport,cvc,cpool,payload};if(waiting)held=held+1;
  // Independent integral journal debits actual native output events, not model send flags.
  journal_error=0;
  for(account=0;account<PORTS*5;account=account+1)tentative[account]=journal[account];
  for(p=0;p<4;p=p+1) begin
   if(p>=PORTS)begin if(return_valid[p]||done[p])journal_error=1;end
   else begin
    if(return_valid[p]) begin
     if(!credit_connected)journal_error=1;
     a=return_pool[p]?4:((return_vc>>(p*2))&3);grant=((return_num>>(p*2))&3)+1;
     tentative[p*5+a]=tentative[p*5+a]+grant;
    end
    if(!init[p] && done[p] && !credit_connected)journal_error=1;
   end
  end
  if(valid) begin
   if(!rstn||!credit_connected||!beats_connected||port>=PORTS||!init[port])$fatal(1,"WR_SENDER_ILLEGAL_SEND row=%0d",rows);
   account=port*5+(pool?4:vc);
   if(journal[account]<=0)$fatal(1,"WR_SENDER_CREDIT_UNDERFLOW row=%0d",rows);
   tentative[account]=tentative[account]-1;sends=sends+1;
  end
  for(account=0;account<PORTS*5;account=account+1)if(tentative[account]<0 || tentative[account]>((CAPACITIES>>(account*WIDTH))&((1<<WIDTH)-1)))journal_error=1;
  if(!rstn)begin for(account=0;account<PORTS*5;account=account+1)journal[account]=0;end
  else if(!journal_error)begin for(account=0;account<PORTS*5;account=account+1)journal[account]=tentative[account];end
  #1 clk=1;#1;
  if(state!==after_state)$fatal(1,"WR_SENDER_POST row=%0d got=%h wanted=%h",rows,state,after_state);
  for(account=0;account<PORTS*5;account=account+1)if(balances[account*WIDTH +: WIDTH]!==journal[account][WIDTH-1:0])$fatal(1,"WR_SENDER_JOURNAL row=%0d account=%0d",rows,account);
  #4 clk=0;rows=rows+1;
  read_fields=$fscanf(fd,"%h %h %h %h\n",stimulus,expected,before_state,after_state);
 end
 if(rows!=wanted||rows<1000||sends<200||held<10||read_fields!=-1||!$feof(fd))$fatal(1,"WR_SENDER_COUNT rows=%0d wanted=%0d sends=%0d held=%0d",rows,wanted,sends,held);
 $display("WR_SENDER_PASS rows=%0d sends=%0d held=%0d ports=%0d width=%0d init_cycles=%0d",rows,sends,held,PORTS,WIDTH,INIT_CYCLES);$finish;
end
initial begin #10000000;$fatal(1,"WR_SENDER_TIMEOUT");end
endmodule
