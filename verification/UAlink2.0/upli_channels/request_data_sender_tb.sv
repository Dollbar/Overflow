`timescale 1ns/1ps
module tb;
parameter PORTS=1;
localparam CW=4;
reg clk=0;always #5 clk=~clk;
reg rstn=0,comp_ready=0;
wire oq,oa,cq,ca,credit_connected,beats_connected;
upli_connection_side orig(.i_clk(clk),.i_rstn(rstn),.i_ready(1'b1),.i_peer_req(cq),.i_peer_ack(ca),.o_req(oq),.o_ack(oa),.o_tx_connected(),.o_rx_connected(credit_connected),.o_beats_connected(beats_connected));
upli_connection_side #(.C_IS_COMPLETER(1)) comp(.i_clk(clk),.i_rstn(rstn),.i_ready(comp_ready),.i_peer_req(oq),.i_peer_ack(oa),.o_req(cq),.o_ack(ca),.o_tx_connected(),.o_rx_connected(),.o_beats_connected());
reg cv=0,has_data=0,cpool=0;
reg [1:0] port=0,vc=0,num=0;
reg [3:0] pools=0,rv=0,rp=0,ri=0,dv=0,dp=0,di=0;
reg [7:0] rvc=0,rnum=0,dvc=0,dnum=0;
reg [183:0] request=0;reg [5:0] req_length=0;
reg [2047:0] data=0;
reg [255:0] byte_en=0;
wire accepted,qv,qp,ov,op,ol,oe,known,bank_error;
wire [1:0] qport,qvc,oport,ovc,offset,phase;
wire [183:0] qpayload;
wire [511:0] odata;
wire [63:0] obe;
wire [PORTS*5*CW-1:0] rb,db;
wire [3:0] req_init,data_init,busy;
upli_request_data_sender #(.C_NUM_PORTS(PORTS),.C_CREDIT_WIDTH(CW),.C_DEFAULT_CAPACITY(4)) sender(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(credit_connected),.i_beats_connected(beats_connected),
.i_candidate_valid(cv),.i_candidate_port(port),.i_candidate_vc(vc),.i_candidate_pool(cpool),.i_candidate_has_data(has_data),.i_candidate_num_beats(num),.i_candidate_data_pools(pools),.i_candidate_request(request),.i_candidate_data(data),.i_candidate_byte_enable(byte_en),.i_candidate_error(4'd0),
.i_req_credit_valid(rv),.i_req_credit_pool(rp),.i_req_credit_vc(rvc),.i_req_credit_num(rnum),.i_req_credit_init_done(ri),.i_data_credit_valid(dv),.i_data_credit_pool(dp),.i_data_credit_vc(dvc),.i_data_credit_num(dnum),.i_data_credit_init_done(di),
.o_candidate_accepted(accepted),.o_req_valid(qv),.o_req_port(qport),.o_req_vc(qvc),.o_req_pool(qp),.o_req_payload(qpayload),.o_data_valid(ov),.o_data_port(oport),.o_data_vc(ovc),.o_data_pool(op),.o_data_offset(offset),.o_data_last(ol),.o_data_payload(odata),.o_data_byte_enable(obe),.o_data_error(oe),.o_req_balances(rb),.o_data_balances(db),.o_req_init(req_init),.o_data_init(data_init),.o_req_credit_error(),.o_data_credit_error(),.o_credit_error_sticky(bank_error),.o_busy(busy),.o_tdm_known(known),.o_tdm_port(phase),.o_req_asi(out_asi),.o_req_auth_tag(out_auth_tag),.o_req_src(out_src),.o_req_dst(out_dst),.o_req_tag(out_tag),.o_req_num_beats(out_num_beats),.o_req_address(out_address),.o_req_command(out_command),.o_req_length(out_length),.o_req_attr(out_attr),.o_req_metadata(out_metadata),.o_req_valid_parity(vp),.o_req_auth_tag_parity(ap),.o_req_address_parity(adp),.o_req_control_parity(control_parity),.o_data_valid_parity(),.o_data_parity(),.o_data_byte_enable_parity(),.o_data_fields_parity());
wire [1:0] f_asi,out_asi;
wire [63:0] f_auth_tag,out_auth_tag;
wire [9:0] f_src,out_src;
wire [9:0] f_dst,out_dst;
wire [10:0] f_tag,out_tag;
wire [1:0] f_num_beats,out_num_beats;
wire [56:0] f_address,out_address;
wire [5:0] f_command,out_command;
wire [5:0] f_length,out_length;
wire [7:0] f_attr,out_attr;
wire [7:0] f_metadata,out_metadata;
wire [1:0] f_port,out_port;
wire [1:0] f_vc,out_vc;
wire [0:0] f_pool,out_pool;
assign {f_asi,f_auth_tag,f_src,f_dst,f_tag,f_num_beats,f_address,f_command,f_length,f_attr,f_metadata}=qpayload;
assign f_port=qport;assign f_vc=qvc;assign f_pool=qp;
wire native_valid,vp,ap,adp,control_parity;wire [183:0] out_request;
assign out_request={out_asi,out_auth_tag,out_src,out_dst,out_tag,out_num_beats,out_address,out_command,out_length,out_attr,out_metadata};
assign native_valid=qv;assign out_port=qport;assign out_vc=qvc;assign out_pool=qp;
integer expected_req[0:PORTS*5-1],expected_data[0:PORTS*5-1];
integer tail[0:PORTS-1],next_offset[0:PORTS-1],saved_vc[0:PORTS-1];
reg [2047:0] saved_data[0:PORTS-1];reg [255:0] saved_be[0:PORTS-1];reg [3:0] saved_pools[0:PORTS-1];
integer phase_model=-1,requests=0,beats=0,checks=0,j,k,n,watchdog,account;
reg want_data;
task ck;input condition;input integer id;begin checks=checks+1;if(condition!==1'b1)$fatal(1,"SENDER_MISMATCH case=%0d p=%0d req=%0d data=%0d phase=%0d",id,PORTS,requests,beats,phase_model);end endtask
task tick;begin @(posedge clk);#2;@(negedge clk);#1;end endtask
// Oracle journals are independent integers and original tuples, sampled before DUT NBA.
always @(posedge clk)begin
if(!rstn)begin
 phase_model=-1;
 for(k=0;k<PORTS;k=k+1)begin tail[k]=0;next_offset[k]=0;end
 for(k=0;k<PORTS*5;k=k+1)begin expected_req[k]=0;expected_data[k]=0;end
end else begin
 ck(native_valid===accepted&&qv===accepted&&vp===native_valid,1);
 if(native_valid)begin
  ck(beats_connected&&req_init[out_port],2);
  ck(out_request===request&&out_port===port&&out_vc===vc&&out_pool===cpool,3);
  ck(phase_model<0||out_port==phase_model,4);
  ck(ap===(^out_auth_tag)&&adp===(^out_address),5);
  ck(control_parity===(^{out_tag,out_length,out_attr,out_command,out_metadata,out_vc,out_asi,out_src,out_dst,out_port,out_num_beats,out_pool}),6);
  account=out_port*5+(out_pool?4:out_vc);ck(expected_req[account]>0,7);expected_req[account]=expected_req[account]-1;requests=requests+1;
  if(phase_model<0)phase_model=out_port;
  if(has_data)begin
   ck(tail[out_port]==0&&ov,8);tail[out_port]=num+1;next_offset[out_port]=0;saved_vc[out_port]=vc;saved_data[out_port]=data;saved_be[out_port]=byte_en;saved_pools[out_port]=pools;
  end
end
want_data=0;
for(k=0;k<PORTS;k=k+1)if(tail[k]>0&&phase_model==k)begin
 want_data=1;ck(ov&&oport==k&&offset==next_offset[k]&&ovc==saved_vc[k]&&ol==(tail[k]==1),9);
 ck(odata===saved_data[k][next_offset[k]*512+:512]&&obe===saved_be[k][next_offset[k]*64+:64]&&op==saved_pools[k][next_offset[k]]&&!oe,10);
 tail[k]=tail[k]-1;next_offset[k]=next_offset[k]+1;
end
ck(ov===want_data,11);
if(ov)begin account=oport*5+(op?4:ovc);ck(expected_data[account]>0,12);expected_data[account]=expected_data[account]-1;beats=beats+1;end
for(k=0;k<PORTS;k=k+1)begin
 if(rv[k])begin account=k*5+(rp[k]?4:rvc[k*2+:2]);expected_req[account]=expected_req[account]+rnum[k*2+:2]+1;end
 if(dv[k])begin account=k*5+(dp[k]?4:dvc[k*2+:2]);expected_data[account]=expected_data[account]+dnum[k*2+:2]+1;end
end
if(phase_model>=0)phase_model=(phase_model+1)%PORTS;
end
#1;
for(k=0;k<PORTS*5;k=k+1)begin ck(rb[k*CW+:CW]==expected_req[k],13);ck(db[k*CW+:CW]==expected_data[k],14);end
ck(!bank_error,15);
end
initial begin
@(negedge clk);#1;tick;rstn=1;cv=1;port=PORTS-1;
repeat(3)begin #1;ck(!accepted&&!known,20);tick;end
comp_ready=1;repeat(5)begin #1;ck(!accepted&&!known,21);tick;end
ck(beats_connected&&credit_connected,22);cv=0;
for(j=0;j<5;j=j+1)begin
 rv=(1<<PORTS)-1;dv=rv;rp=j==4?rv:0;dp=rp;rvc={4{j[1:0]}};dvc=rvc;rnum=8'hff;dnum=8'hff;tick;
end
rv=0;dv=0;ri=(1<<PORTS)-1;di=ri;tick;ck(!req_init&&!data_init,23);tick;ck(req_init==ri&&data_init==di,24);
for(n=1;n<=4;n=n+1)begin
 has_data=1;num=n-1;vc=n-1;cpool=n%2;pools=4'b1010;port=PORTS-1;
 req_length=n*16-1;request={2'b10,64'h8123456789abcdef,10'h301,10'h2ab,(11'h400+n[10:0]),num,57'h100000000000000,6'h28,req_length,8'hff,8'hc5};
 for(j=0;j<4;j=j+1)begin data[j*512+:512]={16{32'hcdef0123+n+j}};byte_en[j*64+:64]=64'hfedcba9876543210+j;end
 cv=1;#1;watchdog=0;while(!accepted&&watchdog<PORTS+2)begin tick;#1;watchdog=watchdog+1;end
 ck(accepted&&ov,25);tick;
 // A distinct Read overlays this port's first available tail slot; old Data stays owned.
 has_data=0;num=0;vc=n%4;cpool=!(n%2);request={2'b01,64'hfedcba9876543210,10'h201,10'h3fe,(11'h600+n[10:0]),2'd0,57'h100000000000080,6'h03,6'd15,8'hf1,8'h96};
 #1;watchdog=0;while(!accepted&&watchdog<PORTS+2)begin tick;#1;watchdog=watchdog+1;end
 ck(accepted,26);tick;cv=0;
 repeat(PORTS*(n+1))tick;
 ck(!busy,27);
end
ck(requests==8&&beats==10,28);
// Request pool is now exhausted. A returned credit is unavailable on its arrival edge.
has_data=0;num=0;vc=0;cpool=1;request={2'd0,64'd0,10'd1,10'd2,11'h7a0,2'd0,57'd0,6'h03,6'd15,8'hff,8'd0};cv=1;
rv=1<<(PORTS-1);rp=rv;rvc=0;rnum=0;#1;ck(!accepted,32);tick;rv=0;
#1;watchdog=0;while(!accepted&&watchdog<PORTS+2)begin tick;#1;watchdog=watchdog+1;end
ck(accepted,33);tick;cv=0;
// Req credit alone cannot launch a three-beat Write when only two Data credits remain.
has_data=1;num=2;vc=3;cpool=0;pools=0;request={2'd0,64'd0,10'd1,10'd2,11'h777,2'd2,57'd0,6'h28,6'd47,8'hff,8'd0};cv=1;
repeat(PORTS)begin #1;ck(!accepted&&!ov,34);tick;end
// Return one previously consumed Data credit; still no same-edge bypass.
dv=1<<(PORTS-1);dp=0;dvc=8'hff;dnum=0;#1;ck(!accepted,35);tick;dv=0;
// Reset while this real three-beat burst owns its remaining tail.
#1;watchdog=0;while(!accepted&&watchdog<PORTS+2)begin tick;#1;watchdog=watchdog+1;end
ck(accepted&&ov,29);tick;rstn=0;cv=0;#1;ck(!native_valid&&!ov,30);tick;ck(!known&&!busy&&!rb&&!db,31);
$display("SENDER_PASS ports=%0d requests=%0d beats=%0d checks=%0d",PORTS,requests,beats,checks);$finish;
end
initial begin #100000;$fatal(1,"SENDER_TIMEOUT");end
endmodule
