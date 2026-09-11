`timescale 1ns/1ps
module tb;
localparam CAPACITY=@@CAPACITY@@,SW=@@SLOT_WIDTH@@,MAXV=4200;
reg clk=0,rstn=0,rv=0,full=0,pool=0,mready=0,result_valid=0,captured=0;
reg [10:0] tag=0;reg [9:0] src=0,dst=10'h3a5;reg [56:0] address=0;
reg [5:0] length=0;reg [7:0] attr=0,metadata=0;reg [1:0] asi=0,vc=0;
reg [2047:0] payload=0;reg [255:0] be=0;reg [SW-1:0] result_slot=0;reg [3:0] status=0;
wire ready,mvalid,rready,sv,error;wire [7:0] count;wire [SW-1:0] mslot;
wire [56:0] maddr;wire [5:0] mlen;wire [7:0] mattr,mmeta;wire [1:0] masi;
wire [2047:0] mdata;wire [255:0] mbe,control;
endpoint_write_completer @@PARAMETERS@@ dut(
 .i_clk(clk),.i_rstn(rstn),.i_local_id(10'h3a5),
 .i_request_valid(rv),.o_request_ready(ready),.i_request_tag(tag),.i_request_src(src),.i_request_dst(dst),
 .i_request_full(full),.i_request_address(address),.i_request_length(length),.i_request_attr(attr),
 .i_request_vc(vc),.i_request_pool(pool),.i_request_asi(asi),.i_request_metadata(metadata),.i_request_data(payload),.i_request_be(be),
 .o_mem_valid(mvalid),.i_mem_ready(mready),.o_mem_slot(mslot),.o_mem_address(maddr),.o_mem_length(mlen),.o_mem_attr(mattr),
 .o_mem_asi(masi),.o_mem_metadata(mmeta),.o_mem_data(mdata),.o_mem_be(mbe),
 .i_mem_result_valid(result_valid),.o_mem_result_ready(rready),.i_mem_result_slot(result_slot),.i_mem_result_status(status),
 .o_source_valid(sv),.o_source_control(control),.i_source_captured(captured),.o_error(error),.o_count(count));
integer legal[0:MAXV-1],vfull[0:MAXV-1],vpool[0:MAXV-1];
reg [56:0] va[0:MAXV-1];reg [5:0] vl[0:MAXV-1];reg [7:0] vat[0:MAXV-1],vm[0:MAXV-1];
reg [1:0] vas[0:MAXV-1],vvc[0:MAXV-1];reg [10:0] vt[0:MAXV-1];reg [9:0] vs[0:MAXV-1],vd[0:MAXV-1];
reg [2047:0] vdata[0:MAXV-1];reg [255:0] vbe[0:MAXV-1],expected_be[0:MAXV-1];
reg [3:0] vstatus[0:MAXV-1];reg [63:0] expected_control[0:MAXV-1];
reg [7:0] memory[0:8191],expected_memory[0:8191];
integer order[0:MAXV-1],returned[0:MAXV-1],responded[0:MAXV-1],executed[0:MAXV-1];
integer pending[0:CAPACITY-1],due[0:CAPACITY-1];
reg [56:0] backend_address[0:CAPACITY-1];reg [2047:0] backend_data[0:CAPACITY-1];reg [255:0] backend_be[0:CAPACITY-1];
integer total=0,next_vector=0,accepted=0,issued=0,results=0,responses=0,rejected=0,executions=0,cycle=0,seed=19731;
integer fd,scan,n,j,k,chosen,return_kind=0,duplicate_slot=-1,duplicate_done=0,bad_status_done=0,expected_error=0,tracking=0;
integer max_count=0,full_wait=0,memory_wait=0,response_wait=0,out_of_order=0,expected_accepted=0,saved_slot;
reg holding=0;reg [2400:0] held_command;
task drive_request;
input integer index;
begin
 full=vfull[index];tag=vt[index];src=vs[index];dst=vd[index];address=va[index];length=vl[index];attr=vat[index];
 asi=vas[index];metadata=vm[index];vc=vvc[index];pool=vpool[index];payload=vdata[index];be=vbe[index];
end
endtask
task step;
integer id,slot,beat,lane,region_bit,absolute_byte,q;
begin
 #2;
 if(rstn)begin
  if(tracking&&sv&&(responses>=accepted||!returned[order[responses]]))$fatal(1,"WRITE_EARLY_RESPONSE");
  if(error!==(expected_error!=0))$fatal(1,"WRITE_DIAGNOSTIC cycle=%0d got=%b expected=%0d",cycle,error,expected_error);
  if(result_valid&&!rready)$fatal(1,"WRITE_RESULT_NOT_CONSUMED");
  if(tracking)begin
   if(holding&&(!mvalid||{mslot,maddr,mlen,mattr,masi,mmeta,mdata,mbe}!==held_command))$fatal(1,"WRITE_MEMORY_HOLD");
   holding=mvalid&&!mready;held_command={mslot,maddr,mlen,mattr,masi,mmeta,mdata,mbe};
   if(mvalid&&!mready)memory_wait=memory_wait+1;
   if(sv&&!captured)response_wait=response_wait+1;
   if(count>max_count)max_count=count;
   if(count>CAPACITY)$fatal(1,"WRITE_CAPACITY");
   if(mvalid&&mready)begin
    if(issued>=accepted||mslot>=CAPACITY)$fatal(1,"WRITE_WITHOUT_REQUEST");
    id=order[issued];slot=mslot;
    if(pending[slot]>=0)$fatal(1,"WRITE_DUPLICATE_ISSUE");
    if(maddr!==va[id]||mlen!==vl[id]||mattr!==vat[id]||masi!==vas[id]||mmeta!==vm[id])$fatal(1,"WRITE_MEMORY_FIELDS id=%0d",id);
    if(mbe!==expected_be[id])$fatal(1,"WRITE_MEMORY_BE id=%0d",id);
    if(mdata!==vdata[id])$fatal(1,"WRITE_MEMORY_DATA id=%0d",id);
    backend_address[slot]=maddr;backend_data[slot]=mdata;backend_be[slot]=mbe;
    // This backend applies commands in accepted order and independently delays completion notifications.
    if(executed[id])$fatal(1,"WRITE_DUPLICATE_EXECUTION");
    if(vstatus[id]==0)for(beat=0;beat<4;beat=beat+1)for(lane=0;lane<64;lane=lane+1)begin
     region_bit=(maddr[7:6]+beat)*64+lane;
     absolute_byte=(maddr[56]?4096:0)+(maddr[11:6]*64)+beat*64+lane;
     if(region_bit<256&&mbe[region_bit])memory[absolute_byte]=mdata[(beat*64+lane)*8+:8];
    end
    executed[id]=1;executions=executions+1;
    pending[slot]=id;due[slot]=cycle+2+($unsigned($random(seed))%17)+(slot==0?15:0);issued=issued+1;
   end
   if(result_valid&&rready&&return_kind==1)begin
    slot=result_slot;id=pending[slot];
    if(id<0||returned[id]||!executed[id])$fatal(1,"WRITE_DUPLICATE_RESULT");
    for(q=0;q<issued;q=q+1)if(order[q]<id&&!returned[order[q]])out_of_order=out_of_order+1;
    returned[id]=1;results=results+1;pending[slot]=-1;duplicate_slot=slot;
   end
   if(sv)begin
    id=order[responses];
    if(responded[id]||control!=={192'd0,expected_control[id]})$fatal(1,"WRITE_RESPONSE_FIELDS id=%0d got=%h",id,control);
    if(captured)begin responded[id]=1;responses=responses+1;end
   end
   if(rv)begin
    if(!legal[next_vector])begin
     if(ready)$fatal(1,"WRITE_INVALID_ACCEPTED id=%0d",next_vector);
     rejected=rejected+1;next_vector=next_vector+1;
    end else if(ready)begin order[accepted]=next_vector;accepted=accepted+1;next_vector=next_vector+1;end
    else if(count==CAPACITY)full_wait=full_wait+1;
   end
  end
 end
 clk=1;#2;clk=0;cycle=cycle+1;
 if(rstn&&tracking&&count!==(accepted-responses))$fatal(1,"WRITE_SLOT_LIFETIME");
end
endtask
initial begin
 $readmemh("initial.hex",memory);$readmemh("final.hex",expected_memory);fd=$fopen("vectors.txt","r");
 while(!$feof(fd))begin
  scan=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",legal[total],vfull[total],va[total],vl[total],vat[total],vas[total],vm[total],vt[total],vs[total],vd[total],vvc[total],vpool[total],vdata[total],vbe[total],expected_be[total],vstatus[total],expected_control[total]);
  if(scan!=17)$fatal(1,"WRITE_VECTOR_INPUT");
  returned[total]=0;responded[total]=0;executed[total]=0;if(legal[total])expected_accepted=expected_accepted+1;total=total+1;
 end
 $fclose(fd);for(j=0;j<CAPACITY;j=j+1)pending[j]=-1;
 step();rstn=1;result_valid=1;result_slot=0;expected_error=1;step();
 for(j=CAPACITY;j<(1<<SW);j=j+1)begin result_slot=j;step();end
 result_valid=0;captured=1;step();captured=0;expected_error=0;tracking=1;
 for(n=0;n<180000&&responses<expected_accepted;n=n+1)begin
  rv=next_vector<total;if(rv)drive_request(next_vector);
  expected_error=rv&&!legal[next_vector];mready=n>=20&&($unsigned($random(seed))%5!=0);
  chosen=-1;result_valid=0;return_kind=0;
  for(j=CAPACITY-1;j>=0;j=j-1)if(chosen<0&&pending[j]>=0&&due[j]<=cycle)chosen=j;
  if(n==6)begin result_valid=1;result_slot=0;status=0;return_kind=2;expected_error=1;end
  else if(n>=7&&n<7+(1<<SW)-CAPACITY)begin result_valid=1;result_slot=CAPACITY+n-7;status=0;return_kind=2;expected_error=1;end
  else if(chosen>=0&&bad_status_done<11)begin
   result_valid=1;result_slot=chosen;return_kind=2;expected_error=1;
   case(bad_status_done)
    0:status=1;1:status=4;2:status=5;3:status=7;4:status=9;5:status=10;6:status=11;7:status=12;8:status=13;9:status=14;default:status=15;
   endcase
   bad_status_done=bad_status_done+1;
  end
  else if(duplicate_slot>=0&&!duplicate_done)begin result_valid=1;result_slot=duplicate_slot;status=8;return_kind=2;expected_error=1;duplicate_done=1;end
  else if(chosen>=0)begin result_valid=1;result_slot=chosen;status=vstatus[pending[chosen]];return_kind=1;end
  #1;captured=sv&&n>=200&&($unsigned($random(seed))%5!=0);step();
 end
 rv=0;result_valid=0;captured=0;expected_error=0;step();
 if(next_vector!=total||accepted!=expected_accepted||issued!=accepted||results!=accepted||responses!=accepted||executions!=accepted||count!=0)$fatal(1,"WRITE_DRAIN");
 if(max_count!=CAPACITY||full_wait==0||memory_wait==0||response_wait<100||(CAPACITY>1&&out_of_order==0))$fatal(1,"WRITE_COVERAGE");
 for(j=0;j<8192;j=j+1)if(memory[j]!==expected_memory[j])$fatal(1,"WRITE_FINAL_BYTE address=%0d got=%h expected=%h",j,memory[j],expected_memory[j]);
 // Reset cancels an issued command's local ownership; external memory must separately cancel its old epoch.
 tracking=0;drive_request(0);rv=1;mready=0;step();rv=0;#1;saved_slot=mslot;mready=1;step();mready=0;
 rstn=0;step();rstn=1;result_valid=1;result_slot=saved_slot;status=0;expected_error=1;step();
 if(count!=0||sv||mvalid)$fatal(1,"WRITE_RESET");
 $display("WRITE_COMPLETER_PASS capacity=%0d slot_width=%0d vectors=%0d accepted=%0d rejected=%0d memory=%0d executions=%0d responses=%0d max_count=%0d full_wait=%0d memory_wait=%0d response_wait=%0d out_of_order=%0d cycles=%0d",CAPACITY,SW,total,accepted,rejected,issued,executions,responses,max_count,full_wait,memory_wait,response_wait,out_of_order,cycle);
 $finish;
end
endmodule
