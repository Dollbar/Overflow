// Two actual mixed cores. This bridge models prepared feedback/records, not TL transport.
`timescale 1ns/1ps
module write_core_bridge(
 input wire clk,rstn,input wire [1:0] source_valid,input wire [511:0] source_control,
 input wire [3:0] data_valid,input wire [511:0] data0,
 output reg [1:0] captured,output wire header_taken,output reg [3:0] accepted,
 output wire rx_valid,input wire rx_ready,output wire [511:0] rx_flit,output wire [5:0] rx_classes
);
 reg [1:0] state; reg owner,prefer;reg [255:0] header,half;
 integer remaining,tick;reg be_last;
 wire choice=source_valid[prefer]?prefer:!prefer;
 assign rx_valid=rstn&&((state==1)||(state==3));
 assign rx_flit={256'd0,(state==1?header:half)};
 assign rx_classes={3'd3,(state==1?3'd0:((be_last&&(remaining==1))?3'd2:3'd1))};
 assign header_taken=(state==1)&&rx_ready&&rx_valid&&!owner;
 always @* begin
  captured=0;accepted=0;
  if(rstn&&(state==0)&&(tick%7!=0)&&source_valid[choice])captured[choice]=1;
  if(rstn&&(state==2)&&(tick%5!=0)&&(data_valid[owner*2+:2]!=0))accepted[owner*2+:2]=1;
 end
 always @(posedge clk) begin
  if(!rstn)begin state<=0;owner<=0;prefer<=0;header<=0;half<=0;remaining<=0;be_last<=0;tick<=0;end
  else begin
   tick<=tick+1;
   if(state==0&&captured!=0)begin
    owner<=choice;header<=source_control[choice*256+:256];state<=1;be_last<=0;
    if(source_control[choice*256+124+:4]==4'd1)begin
     if(source_control[choice*256+118+:6]==6'h28)begin remaining<=2*(source_control[choice*256+:2]+1)+1;be_last<=1;end
     else if(source_control[choice*256+118+:6]==6'h29)remaining<=2*(source_control[choice*256+:2]+1);
     else remaining<=0;
    end else if(source_control[choice*256+60+:4]==4'd2)remaining<=source_control[choice*256+37]?2:0;
    else $fatal(1,"MIXED_HEADER_TYPE");
   end
   if(state==1&&rx_ready)begin if(remaining==0)begin state<=0;prefer<=!owner;end else state<=2;end
   if(state==2&&accepted!=0)begin half<=data0[owner*256+:256];state<=3;end
   if(state==3&&rx_ready)begin remaining<=remaining-1;if(remaining==1)begin state<=0;prefer<=!owner;end else state<=2;end
  end
 end
endmodule
module tb;
 parameter integer CAPACITY=4;
 localparam integer N=@@COUNT@@;
 reg clk=0;always #5 clk=~clk;
 reg rstn=0;
 reg req_valid[0:1],req_write[0:1],req_full[0:1],complete_ready[0:1];
 reg [10:0] req_tag[0:1];reg [56:0] req_address[0:1];reg [5:0] req_length[0:1];reg [7:0] req_attr[0:1],req_meta[0:1];reg [1:0] req_asi[0:1];reg [2047:0] req_data[0:1];reg [255:0] req_be[0:1];
 wire req_ready[0:1],complete_valid[0:1],complete_write[0:1],complete_dv[0:1];
 wire [1:0] complete_port[0:1];wire [10:0] complete_tag[0:1];wire [3:0] complete_status[0:1];wire [511:0] complete_data[0:1];
 wire mem_valid[0:1],write_valid[0:1],result_ready[0:1],write_result_ready[0:1];
 reg mem_ready[0:1],write_ready[0:1],result_valid[0:1],write_result_valid[0:1];
 wire [1:0] mem_slot[0:1],write_slot[0:1];reg [1:0] result_slot[0:1];
 wire [56:0] mem_address[0:1],write_address[0:1];wire [5:0] mem_length[0:1],write_length[0:1];wire [7:0] mem_attr[0:1],write_attr[0:1],mem_meta[0:1],write_meta[0:1];wire [1:0] mem_asi[0:1],write_asi[0:1];
 wire [2047:0] write_data[0:1];wire [255:0] write_be[0:1];reg [511:0] result_data[0:1];reg [3:0] result_status[0:1];
 wire [1:0] source_valid[0:1],captured[0:1];wire [511:0] source_control[0:1],data0[0:1],data1[0:1];wire [3:0] data_valid[0:1],accepted[0:1];wire taken[0:1],rx_valid[0:1],rx_ready[0:1];wire [511:0] rx_flit[0:1];wire [5:0] rx_classes[0:1];
 wire [7:0] outstanding[0:1],read_count[0:1],write_count[0:1];wire error[0:1];
 genvar g;generate for(g=0;g<2;g=g+1)begin:cores
 endpoint_transaction_core #(.WRITE_ENABLE(1),.ORIGINATOR_CAPACITY(CAPACITY),.COMPLETER_CAPACITY(CAPACITY)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_port(2'd0),.i_local_id(g==0?10'h301:10'h2fe),
 .i_request_valid(req_valid[g]),.o_request_ready(req_ready[g]),.i_request_port(2'd0),.i_request_tag(req_tag[g]),.i_request_address(req_address[g]),.i_request_dst(g==0?10'h2fe:10'h301),.i_request_length(req_length[g]),.i_request_attr(req_attr[g]),
 .i_request_is_write(req_write[g]),.i_request_full(req_full[g]),.i_request_asi(req_asi[g]),.i_request_metadata(req_meta[g]),.i_request_data(req_data[g]),.i_request_be(req_be[g]),
 .o_complete_valid(complete_valid[g]),.i_complete_ready(complete_ready[g]),.o_complete_port(complete_port[g]),.o_complete_tag(complete_tag[g]),.o_complete_status(complete_status[g]),.o_complete_data(complete_data[g]),.o_complete_data_valid(complete_dv[g]),.o_complete_is_write(complete_write[g]),
 .o_mem_valid(mem_valid[g]),.i_mem_ready(mem_ready[g]),.o_mem_slot(mem_slot[g]),.o_mem_address(mem_address[g]),.o_mem_length(mem_length[g]),.o_mem_attr(mem_attr[g]),.o_mem_asi(mem_asi[g]),.o_mem_metadata(mem_meta[g]),
 .i_mem_result_valid(result_valid[g]),.o_mem_result_ready(result_ready[g]),.i_mem_result_slot(result_slot[g]),.i_mem_result_data(result_data[g]),.i_mem_result_status(result_status[g]),
 .o_write_mem_valid(write_valid[g]),.i_write_mem_ready(write_ready[g]),.o_write_mem_slot(write_slot[g]),.o_write_mem_address(write_address[g]),.o_write_mem_length(write_length[g]),.o_write_mem_attr(write_attr[g]),.o_write_mem_asi(write_asi[g]),.o_write_mem_metadata(write_meta[g]),.o_write_mem_data(write_data[g]),.o_write_mem_be(write_be[g]),
 .i_write_mem_result_valid(write_result_valid[g]),.o_write_mem_result_ready(write_result_ready[g]),.i_write_mem_result_slot(result_slot[g]),.i_write_mem_result_status(result_status[g]),
 .o_source_valid(source_valid[g]),.o_source_control(source_control[g]),.i_source_captured(captured[g]),.i_request_header_taken(taken[g]),.o_data_valid(data_valid[g]),.o_data0(data0[g]),.o_data1(data1[g]),.i_data_accepted(accepted[g]),
 .i_read_valid(rx_valid[1-g]),.o_read_ready(rx_ready[1-g]),.i_read_flit(rx_flit[1-g]),.i_read_msg(2'd0),.i_read_classes(rx_classes[1-g]),.i_read_releases(80'd0),
 .o_outstanding_count(outstanding[g]),.o_completer_count(read_count[g]),.o_write_completer_count(write_count[g]),.o_error(error[g]));
 write_core_bridge bridge(.clk(clk),.rstn(rstn),.source_valid(source_valid[g]),.source_control(source_control[g]),.data_valid(data_valid[g]),.data0(data0[g]),.captured(captured[g]),.header_taken(taken[g]),.accepted(accepted[g]),.rx_valid(rx_valid[g]),.rx_ready(rx_ready[g]),.rx_flit(rx_flit[g]),.rx_classes(rx_classes[g]));
 end endgenerate
 reg vw[0:2*N-1],vf[0:2*N-1];reg [10:0] vt[0:2*N-1];reg [56:0] va[0:2*N-1];reg [5:0] vl[0:2*N-1];reg [7:0] vattr[0:2*N-1],vmeta[0:2*N-1];reg [1:0] vasi[0:2*N-1];reg [2047:0] vd[0:2*N-1];reg [255:0] vbe[0:2*N-1],vebe[0:2*N-1];reg [3:0] vs[0:2*N-1];reg [511:0] vr[0:2*N-1];
 reg [7:0] memory0[0:4095],memory1[0:4095],final0[0:4095],final1[0:4095];
 integer requested[0:1],commands[0:1],completed[0:1],results[0:1],maximum[0:1],deadline[0:1],active_idx[0:1];reg pending[0:1];
 reg [1:0] active_slot[0:1];reg [2047:0] active_data[0:1];reg [255:0] active_be[0:1];reg [56:0] active_address[0:1];
 reg seen[0:2*N-1],executed[0:2*N-1];
 reg rqfire[0:1],cmdfire[0:1],resfire[0:1],cmpfire[0:1];
 reg stalled[0:1];reg [531:0] stalled_value[0:1];
 integer fd,rc,i,s,k,j,b,cycle,index,base,relative,drain,write_exec,read_exec,zero_exec,high_exec,partial_halves,app_stalls;
 initial begin
  fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"MIXED_VECTOR_OPEN");
  for(i=0;i<2*N;i=i+1)begin rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h\n",vw[i],vf[i],vt[i],va[i],vl[i],vattr[i],vasi[i],vmeta[i],vd[i],vbe[i],vebe[i],vs[i],vr[i]);if(rc!=13)$fatal(1,"MIXED_VECTOR_PARSE");seen[i]=0;executed[i]=0;end
  $fclose(fd);$readmemh("initial0.hex",memory0);$readmemh("initial1.hex",memory1);$readmemh("final0.hex",final0);$readmemh("final1.hex",final1);
  write_exec=0;read_exec=0;zero_exec=0;high_exec=0;partial_halves=0;app_stalls=0;drain=0;
  for(s=0;s<2;s=s+1)begin requested[s]=0;commands[s]=0;completed[s]=0;results[s]=0;maximum[s]=0;pending[s]=0;stalled[s]=0;req_valid[s]=0;complete_ready[s]=0;mem_ready[s]=0;write_ready[s]=0;result_valid[s]=0;write_result_valid[s]=0;result_slot[s]=0;result_data[s]=0;result_status[s]=0;end
  repeat(4)@(negedge clk);rstn=1;
  for(cycle=0;cycle<20000;cycle=cycle+1)begin
   @(negedge clk);
   for(s=0;s<2;s=s+1)begin
    index=s*N+(requested[s]<N?requested[s]:N-1);
    req_valid[s]=requested[s]<N;req_write[s]=vw[index];req_full[s]=vf[index];req_tag[s]=vt[index];req_address[s]=va[index];req_length[s]=vl[index];req_attr[s]=vattr[index];req_asi[s]=vasi[index];req_meta[s]=vmeta[index];req_data[s]=vd[index];req_be[s]=vbe[index];
    complete_ready[s]=(cycle>500)&&(cycle%13>4);mem_ready[s]=(cycle%7>1);write_ready[s]=(cycle%11>2);
    result_valid[s]=0;write_result_valid[s]=0;result_data[s]=0;
    if(pending[s])begin
     index=active_idx[s];result_slot[s]=active_slot[s];result_status[s]=vs[index];
     if(!vw[index]&&vs[index]==0)for(b=0;b<64;b=b+1)result_data[s][b*8+:8]=(s==0?memory0[va[index]+b]:memory1[va[index]+b]);
     if(cycle>=deadline[s])begin if(vw[index])write_result_valid[s]=1;else result_valid[s]=1;end
    end
   end
   #1;
   for(s=0;s<2;s=s+1)begin
    if(error[s]!==0)$fatal(1,"MIXED_CORE_ERROR side=%0d cycle=%0d req=%0d cmd=%0d",s,cycle,requested[s],commands[s]);
    rqfire[s]=req_valid[s]&&req_ready[s];cmdfire[s]=(mem_valid[s]&&mem_ready[s])||(write_valid[s]&&write_ready[s]);resfire[s]=(result_valid[s]&&result_ready[s])||(write_result_valid[s]&&write_result_ready[s]);cmpfire[s]=complete_valid[s]&&complete_ready[s];
    if(outstanding[s]>maximum[s])maximum[s]=outstanding[s];
    if(pending[s]&&(mem_valid[s]||write_valid[s]))$fatal(1,"MIXED_DISPATCH_EARLY side=%0d cycle=%0d",s,cycle);
    if(mem_valid[s]&&write_valid[s])$fatal(1,"MIXED_BACKEND_REORDER simultaneous");
    if(cmdfire[s])begin
     index=(1-s)*N+commands[s];if(commands[s]>=N||commands[s]>=requested[1-s])$fatal(1,"MIXED_BACKEND_UNREQUESTED");
     if(write_valid[s]!==vw[index])$fatal(1,"MIXED_BACKEND_REORDER side=%0d command=%0d",s,commands[s]);
     if(vw[index])begin
      if(write_address[s]!==va[index]||write_length[s]!==vl[index]||write_attr[s]!==vattr[index]||write_asi[s]!==vasi[index]||write_meta[s]!==vmeta[index])$fatal(1,"MIXED_BACKEND_FIELDS write side=%0d command=%0d",s,commands[s]);
      if(write_data[s]!==vd[index])$fatal(1,"MIXED_BACKEND_DATA side=%0d command=%0d",s,commands[s]);
      if(write_be[s]!==vebe[index])$fatal(1,"MIXED_BACKEND_BE side=%0d command=%0d",s,commands[s]);
      active_slot[s]=write_slot[s];active_data[s]=write_data[s];active_be[s]=write_be[s];active_address[s]=write_address[s];
     end else begin
      if(mem_address[s]!==va[index]||mem_length[s]!==vl[index]||mem_attr[s]!==vattr[index]||mem_asi[s]!==vasi[index]||mem_meta[s]!==vmeta[index])$fatal(1,"MIXED_BACKEND_FIELDS read");
      active_slot[s]=mem_slot[s];active_address[s]=mem_address[s];
     end
     if(active_slot[s]>=CAPACITY)$fatal(1,"MIXED_BACKEND_SLOT");
    end
    if(stalled[s]&&({complete_valid[s],complete_write[s],complete_dv[s],complete_port[s],complete_tag[s],complete_status[s],complete_data[s]}!==stalled_value[s]))$fatal(1,"MIXED_COMPLETE_STABILITY");
    stalled[s]=complete_valid[s]&&!complete_ready[s];stalled_value[s]={complete_valid[s],complete_write[s],complete_dv[s],complete_port[s],complete_tag[s],complete_status[s],complete_data[s]};if(stalled[s])app_stalls=app_stalls+1;
    if(complete_valid[s])begin
     k=-1;for(j=0;j<N;j=j+1)if(complete_tag[s]===vt[s*N+j])k=s*N+j;
     if(k<0)$fatal(1,"MIXED_COMPLETE_TAG");
     if(!executed[k]||seen[k]||complete_port[s]!==0||complete_status[s]!==vs[k]||complete_write[s]!==vw[k]||complete_dv[s]!==(!vw[k]&&vs[k]==0))$fatal(1,"MIXED_COMPLETE_CAUSAL side=%0d vector=%0d",s,k);
     if(complete_data[s]!==vr[k])$fatal(1,"MIXED_READ_ORACLE side=%0d vector=%0d",s,k);
    end
    if(accepted[s][1:0]==1)partial_halves=partial_halves+1;if(accepted[s][3:2]==1)partial_halves=partial_halves+1;
   end
   @(posedge clk);#1;
   for(s=0;s<2;s=s+1)begin
    if(rqfire[s])requested[s]=requested[s]+1;
    if(cmdfire[s])begin active_idx[s]=(1-s)*N+commands[s];commands[s]=commands[s]+1;pending[s]=1;deadline[s]=cycle+40+(commands[s]*17+s*11)%37;end
    if(resfire[s])begin
     index=active_idx[s];if(!pending[s]||executed[index])$fatal(1,"MIXED_EXECUTION_DUPLICATE");
     if(vw[index])begin
      write_exec=write_exec+1;if(active_be[s]==0)zero_exec=zero_exec+1;
      if(vs[index]==0)begin
       base=active_address[s]&57'h1ffffffffffff00;
       for(j=0;j<(active_address[s][5:0]+4*(vl[index]+1)+63)/64;j=j+1)for(b=0;b<64;b=b+1)begin
        relative=active_address[s][7:6]*64+j*64+b;
        if(active_be[s][relative])begin if(s==0)memory0[base+relative]=active_data[s][(j*64+b)*8+:8];else memory1[base+relative]=active_data[s][(j*64+b)*8+:8];end
       end
      end
     end else read_exec=read_exec+1;
     if(va[index][56])high_exec=high_exec+1;executed[index]=1;results[s]=results[s]+1;pending[s]=0;
    end
    if(cmpfire[s])begin
     // The pre-edge tag remains owned until this handshake; derive it from held snapshot.
     k=-1;for(j=0;j<N;j=j+1)if(stalled_value[s][526:516]===vt[s*N+j])k=s*N+j;
     if(k<0)$fatal(1,"MIXED_COMPLETION_SNAPSHOT");seen[k]=1;completed[s]=completed[s]+1;
    end
   end
   if(completed[0]==N&&completed[1]==N)begin
    drain=drain+1;
    if(drain==10)begin
     for(s=0;s<2;s=s+1)if(requested[s]!=N||commands[s]!=N||results[s]!=N||pending[s]||outstanding[s]!=0||read_count[s]!=0||write_count[s]!=0||maximum[s]!=CAPACITY)$fatal(1,"MIXED_DRAIN_OR_CAPACITY side=%0d max=%0d",s,maximum[s]);
     for(i=0;i<4096;i=i+1)if(memory0[i]!==final0[i]||memory1[i]!==final1[i])$fatal(1,"MIXED_FINAL_MEMORY byte=%0d",i);
     for(i=0;i<2*N;i=i+1)if(!seen[i]||!executed[i])$fatal(1,"MIXED_MISSING");
     rstn=0;repeat(3)@(negedge clk);if(outstanding[0]!=0||outstanding[1]!=0||complete_valid[0]||complete_valid[1])$fatal(1,"MIXED_RESET");
     $display("MIXED_CORE_PASS capacity=%0d requests=%0d completions=%0d write_executions=%0d read_executions=%0d zero_be_executions=%0d high_address_executions=%0d partial_halves=%0d app_stalls=%0d cycles=%0d",CAPACITY,2*N,completed[0]+completed[1],write_exec,read_exec,zero_exec,high_exec,partial_halves,app_stalls,cycle);$finish;
    end
   end
  end
  $fatal(1,"MIXED_TIMEOUT requests=%0d,%0d commands=%0d,%0d completions=%0d,%0d",requested[0],requested[1],commands[0],commands[1],completed[0],completed[1]);
 end
endmodule
