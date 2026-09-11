`timescale 1ns/1ps
module receive_tdm_station_tb;
parameter PORTS=4;
// Existing complete station bench drives the actual three senders and four SRAM receivers.
tb #(.PORTS(PORTS)) env();
wire [3:0] errors,sticky;
wire [2:0] known;
wire [5:0] expected_ports;
wire [3:0] valid={env.o_wr_valid,env.o_rd_valid,env.o_data_valid,env.o_req_valid};
wire [7:0] actual_ports={env.o_wr_port,env.o_rd_port,env.o_data_port,env.o_req_port};
upli_receive_tdm_monitor #(.C_NUM_PORTS(PORTS)) monitor(
 .i_clk(env.clk),.i_rstn(env.rstn),.i_req_valid(valid[0]),.i_req_port(actual_ports[1:0]),
 .i_data_valid(valid[1]),.i_data_port(actual_ports[3:2]),.i_rd_valid(valid[2]),.i_rd_port(actual_ports[5:4]),
 .i_wr_valid(valid[3]),.i_wr_port(actual_ports[7:6]),.o_error(errors),.o_error_sticky(sticky),
 .o_phase_known(known),.o_expected_port(expected_ports));
integer cycle=0;
integer epoch[0:2];integer first_port[0:2];integer events[0:3];
integer ch,group_id,port_id,g,slots=0,idle_slots=0;
reg [2:0] expected_known;
reg [5:0] expected_phase;
initial begin
 for(integer n=0;n<3;n=n+1)begin epoch[n]=-1;first_port[n]=0;end
 for(integer n=0;n<4;n=n+1)events[n]=0;
end
always @(posedge env.clk)begin
 if(errors!==4'd0)$fatal(1,"TDM_STATION_ERROR cycle=%0d errors=%h",cycle,errors);
 if(!env.rstn)begin
  for(g=0;g<3;g=g+1)begin epoch[g]=-1;first_port[g]=0;end
 end else begin
  slots=slots+1;if(valid==0)idle_slots=idle_slots+1;
  // Absolute first-event cycle and port form the oracle; no sender/monitor phase is read.
  for(ch=0;ch<4;ch=ch+1)if(valid[ch])begin
   group_id=(ch<2)?0:ch-1;port_id=(actual_ports>>(ch*2))&3;
   if(epoch[group_id]<0)begin
    if(ch==1)$fatal(1,"TDM_STATION_ORPHAN_DATA");
    epoch[group_id]=cycle;first_port[group_id]=port_id;
   end
   if(port_id>=PORTS||port_id!=((cycle-epoch[group_id]+first_port[group_id])%PORTS))
    $fatal(1,"TDM_STATION_ORACLE cycle=%0d channel=%0d port=%0d",cycle,ch,port_id);
   events[ch]=events[ch]+1;
  end
 end
 expected_known=0;expected_phase=0;
 for(g=0;g<3;g=g+1)if(epoch[g]>=0)begin
  expected_known[g]=1;expected_phase[g*2+:2]=(cycle+1-epoch[g]+first_port[g])%PORTS;
 end
 #1;
 if({known,expected_ports,sticky}!=={expected_known,expected_phase,4'd0})
  $fatal(1,"TDM_STATION_POST cycle=%0d got=%h expected=%h",cycle,{known,expected_ports,sticky},{expected_known,expected_phase,4'd0});
 cycle=cycle+1;
end
final begin
 if(events[0]<48||events[1]<48||events[2]<120||events[3]<48||idle_slots==0)
  $error("TDM_STATION_COVERAGE req=%0d data=%0d rd=%0d wr=%0d idle=%0d",events[0],events[1],events[2],events[3],idle_slots);
 else $display("TDM_STATION_PASS ports=%0d slots=%0d idle=%0d req=%0d data=%0d rd=%0d wr=%0d",PORTS,slots,idle_slots,events[0],events[1],events[2],events[3]);
end
endmodule
