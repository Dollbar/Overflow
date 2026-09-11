`timescale 1ns/1ps
module tb;
 parameter CAPACITY=4;
 localparam ROWS=@@COUNT@@,LEGAL=@@LEGAL@@,BEATS=@@BEATS@@;
 reg clk=0,rstn=0,rv=0,mready=0,mrv=0,captured=0;reg [1:0] accepted=0,slot=0;
 reg [56:0] address=0;reg [5:0] length=0;reg [7:0] attr=0,meta=0;reg [1:0] asi=0,vc=0;reg pool=0;
 reg [10:0] tag=0;reg [9:0] src=0,dst=10'h3a5;reg [2047:0] result_data=0;reg [3:0] status=0;
 wire ready,mvalid,mrready,sv,error;wire [1:0] mslot,dvalid;wire [56:0] maddr;wire [5:0] mlen;wire [7:0] mattr,mmeta,count;wire [1:0] masi;wire [255:0] mbe,control;wire [511:0] data;
 endpoint_read_completer #(.CAPACITY(CAPACITY),.SLOT_WIDTH(2),.FULL_READ_ENABLE(1)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_local_id(10'h3a5),.i_request_valid(rv),.o_request_ready(ready),.i_request_tag(tag),.i_request_src(src),.i_request_dst(dst),.i_request_address(address),.i_request_length(length),.i_request_attr(attr),.i_request_vc(vc),.i_request_pool(pool),.i_request_asi(asi),.i_request_metadata(meta),
 .o_mem_valid(mvalid),.i_mem_ready(mready),.o_mem_slot(mslot),.o_mem_address(maddr),.o_mem_length(mlen),.o_mem_attr(mattr),.o_mem_asi(masi),.o_mem_metadata(mmeta),.o_mem_be(mbe),
 .i_mem_result_valid(mrv),.o_mem_result_ready(mrready),.i_mem_result_slot(slot),.i_mem_result_data(512'hbad),.i_mem_result_data_full(result_data),.i_mem_result_status(status),
 .o_source_valid(sv),.o_source_control(control),.i_source_captured(captured),.o_data_valid(dvalid),.o_data(data),.i_data_accepted(accepted),.o_error(error),.o_count(count));
 reg valid[0:ROWS-1];reg [56:0] va[0:ROWS-1];reg [5:0] vl[0:ROWS-1];reg [7:0] vat[0:ROWS-1],vm[0:ROWS-1];reg [1:0] vas[0:ROWS-1];reg [10:0] vt[0:ROWS-1];reg [9:0] vsrc[0:ROWS-1];reg [3:0] vst[0:ROWS-1];integer vn[0:ROWS-1];reg [255:0] vbe[0:ROWS-1],vh[0:ROWS-1];reg [2047:0] vd[0:ROWS-1],ve[0:ROWS-1];
 reg [7:0] memory[0:4095];integer ids[0:ROWS-1],pending[0:CAPACITY-1],due[0:CAPACITY-1];reg finished[0:ROWS-1];
 integer row=0,sent=0,issued=0,retired=0,cycle=0,headbeat=0,halves=0;reg headheader=0;
 integer results=0,headers=0,totalhalves=0,rejected=0,zero_be=0,highaddr=0,ooo=0,fullstalls=0,partial=0,doubletake=0,headerfirst=0,datafirst=0,errors=0;
 integer fd,rc,j,k,b,id,base,chosen,return_id,return_kind,duplicate=-1,duplicate_done=0,reserved_done=0,seed=195241,maxcount=0;
 reg tracking=1;reg expecting_error=0;reg hold_mem=0;reg [338:0] mem_snapshot;reg [1:0] slot_snapshot;
 reg ev=0,elast=0,epool=0;reg [3:0] est=0;reg [1:0] eoff=0,en=0,evc=0;
 wire efv,efe,elv,ele;wire [255:0] efc,elc;reg [63:0] ew;reg fl,lg;
 integer e0,e1,e2,e3,e4,e5,e6,encoder_cases=0;
 endpoint_response_encode #(.FULL_READ_ENABLE(1)) full_encoder(.i_valid(ev),.i_tag(11'd1969),.i_src(10'd766),.i_dst(10'd769),.i_status(est),.i_num_beats(en),.i_offset(eoff),.i_last(elast),.i_vc(evc),.i_pool(epool),.o_valid(efv),.o_error(efe),.o_control(efc));
 endpoint_response_encode legacy_encoder(.i_valid(ev),.i_tag(11'd1969),.i_src(10'd766),.i_dst(10'd769),.i_status(est),.i_num_beats(en),.i_offset(eoff),.i_last(elast),.i_vc(evc),.i_pool(epool),.o_valid(elv),.o_error(ele),.o_control(elc));
 task step;
 integer t,cur;
 begin
  #2;
  if(rstn)begin
   if(tracking&&((sv!==1'b0)||(dvalid!==2'd0))&&(retired>=sent||!finished[retired]))$fatal(1,"READ_CAUSAL unknown_or_early_response");
   if(error!==expecting_error)$fatal(1,"READ_ERROR cycle=%0d got=%b expected=%b",cycle,error,expecting_error);
   if(error)errors=errors+1;
   if(mrv&&!mrready)$fatal(1,"READ_RESULT_READY");
   if(tracking)begin
    if(sv||dvalid!=0)begin
     if(retired>=sent||!finished[retired])$fatal(1,"READ_CAUSAL retired=%0d",retired);
     cur=ids[retired];
     if(sv&&(headheader||control!=={192'd0,vh[cur][headbeat*64+:64]}))$fatal(1,"READ_HEADER row=%0d beat=%0d got=%h expected=%h",cur,headbeat,control,vh[cur][headbeat*64+:64]);
     if(dvalid!==2-halves)$fatal(1,"READ_DATA_COUNT row=%0d beat=%0d got=%0d expected=%0d",cur,headbeat,dvalid,2-halves);
     if(dvalid!=0&&data[255:0]!==ve[cur][headbeat*512+halves*256+:256])$fatal(1,"READ_DATA_LOW row=%0d beat=%0d half=%0d",cur,headbeat,halves);
     if(dvalid==2&&data[511:256]!==ve[cur][headbeat*512+256+:256])$fatal(1,"READ_DATA_HIGH");
    end
    if(hold_mem&&(!mvalid||mslot!==slot_snapshot||{maddr,mlen,mattr,masi,mmeta,mbe}!==mem_snapshot))$fatal(1,"READ_MEM_HOLD");
    hold_mem=mvalid&&!mready;slot_snapshot=mslot;mem_snapshot={maddr,mlen,mattr,masi,mmeta,mbe};
    if(mvalid&&mready)begin
     if(issued>=sent||mslot>=CAPACITY||pending[mslot]>=0)$fatal(1,"READ_MEM_CAUSAL");
     cur=ids[issued];if({maddr,mlen,mattr,masi,mmeta}!=={va[cur],vl[cur],vat[cur],vas[cur],vm[cur]})$fatal(1,"READ_MEM_FIELDS row=%0d",cur);
     if(mbe!==vbe[cur])$fatal(1,"READ_BE row=%0d got=%h expected=%h",cur,mbe,vbe[cur]);
     if(mbe==0)zero_be=zero_be+1;if(maddr[56])highaddr=highaddr+1;
     pending[mslot]=issued;due[mslot]=cycle+2+$unsigned($random(seed))%19;issued=issued+1;
    end
    if(mrv&&return_kind==1)begin
     if(pending[slot]!=return_id||finished[return_id])$fatal(1,"READ_RESULT_CAUSAL");
     for(t=0;t<return_id;t=t+1)if(!finished[t])ooo=ooo+1;
     finished[return_id]=1;pending[slot]=-1;results=results+1;duplicate=slot;
    end
    if(captured&&!headheader&&halves==0&&accepted==0)headerfirst=headerfirst+1;
    if(accepted!=0&&!headheader&&!captured)datafirst=datafirst+1;
    if(captured)begin headheader=1;headers=headers+1;end
    if(accepted==1)partial=partial+1;if(accepted==2)doubletake=doubletake+1;
    totalhalves=totalhalves+accepted;halves=halves+accepted;
    if(retired<sent&&headheader&&halves==2)begin
     headheader=0;halves=0;headbeat=headbeat+1;
     if(headbeat==vn[ids[retired]])begin retired=retired+1;headbeat=0;end
    end
    if(rv)begin
     if(valid[row])begin if(ready)begin ids[sent]=row;sent=sent+1;row=row+1;end else if(count==CAPACITY)fullstalls=fullstalls+1;end
     else begin if(ready)$fatal(1,"READ_INVALID_ACCEPT row=%0d",row);rejected=rejected+1;row=row+1;end
    end
    if(count>maxcount)maxcount=count;
   end
  end
  clk=1;#2;clk=0;cycle=cycle+1;
  if(tracking&&rstn&&count!==sent-retired)$fatal(1,"READ_LIFETIME got=%0d expected=%0d",count,sent-retired);
 end
 endtask
 initial begin
  for(e0=0;e0<16;e0=e0+1)for(e1=0;e1<4;e1=e1+1)for(e2=0;e2<2;e2=e2+1)for(e3=0;e3<4;e3=e3+1)for(e4=0;e4<4;e4=e4+1)for(e5=0;e5<2;e5=e5+1)for(e6=0;e6<2;e6=e6+1)begin
   est=e0;eoff=e1;elast=e2;en=e3;evc=e4;epool=e5;ev=e6;
   fl=(e0==0||e0==2||e0==3||e0==6||e0==8)&&e3==0&&e4==0&&e5==0;
   lg=(e0==0||e0==3)&&e1==0&&e2==1&&e3==0&&e4==0&&e5==0;
   ew=64'h2000002000000000|(64'd1969<<47)|(64'd766<<26)|(64'd769<<16)|({60'd0,est}<<38)|({62'd0,eoff}<<42)|({63'd0,elast}<<36);
   #1;if(efv!==(ev&&fl)||efe!==(ev&&!fl)||efc!==(ev&&fl?{192'd0,ew}:256'd0)||elv!==(ev&&lg)||ele!==(ev&&!lg)||elc!==(ev&&lg?{192'd0,ew}:256'd0))$fatal(1,"READ_ENCODER_PROFILE");
   encoder_cases=encoder_cases+1;
  end
  ev=0;
  $readmemh("memory.hex",memory);fd=$fopen("vectors.txt","r");
  for(j=0;j<ROWS;j=j+1)begin rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",valid[j],va[j],vl[j],vat[j],vas[j],vm[j],vt[j],vsrc[j],vst[j],vn[j],vbe[j],vd[j],ve[j],vh[j]);if(rc!=14)$fatal(1,"READ_VECTOR_PARSE");finished[j]=0;end
  $fclose(fd);for(j=0;j<CAPACITY;j=j+1)pending[j]=-1;
  step();rstn=1;tracking=0;expecting_error=1;mrv=1;slot=3;step();mrv=0;captured=1;step();captured=0;accepted=3;step();accepted=0;
  rv=1;dst=0;step();dst=10'h3a5;vc=1;step();vc=0;pool=1;step();pool=0;rv=0;expecting_error=0;tracking=1;
  while(cycle<150000&&retired<LEGAL)begin
   rv=row<ROWS;if(rv)begin address=va[row];length=vl[row];attr=vat[row];asi=vas[row];meta=vm[row];tag=vt[row];src=vsrc[row];end
   mready=cycle>16&&$unsigned($random(seed))%4!=0;mrv=0;return_kind=0;expecting_error=rv&&!valid[row];chosen=-1;
   for(j=CAPACITY-1;j>=0;j=j-1)if(pending[j]>=0&&due[j]<=cycle&&chosen<0)chosen=j;
   if(cycle==10)begin mrv=1;slot=0;status=0;return_kind=2;expecting_error=1;end
   else if(cycle==11&&CAPACITY<4)begin mrv=1;slot=CAPACITY;status=0;return_kind=2;expecting_error=1;end
   else if(chosen>=0&&reserved_done<16)begin
    if(reserved_done==0||reserved_done==2||reserved_done==3||reserved_done==6||reserved_done==8)reserved_done=reserved_done+1;
    else begin mrv=1;slot=chosen;status=reserved_done;return_kind=2;expecting_error=1;reserved_done=reserved_done+1;end
   end
   else if(duplicate>=0&&!duplicate_done)begin mrv=1;slot=duplicate;status=0;result_data={2048{1'b1}};return_kind=2;expecting_error=1;duplicate_done=1;end
   else if(chosen>=0)begin
    return_id=pending[chosen];id=ids[return_id];mrv=1;slot=chosen;status=vst[id];return_kind=1;result_data=0;base=(va[id]&4095)/64*64;
    for(b=0;b<256;b=b+1)result_data[b*8+:8]=memory[base+b];
    if(result_data!==vd[id])$fatal(1,"READ_BFM_ORACLE");
   end
   #1;captured=sv&&cycle>90&&$unsigned($random(seed))%4!=0;accepted=0;
   if(cycle>70&&dvalid!=0&&!(retired%3==1&&!headheader))begin accepted=$unsigned($random(seed))%3;if(accepted>dvalid)accepted=dvalid;if(retired%3==0&&halves==0)accepted=1;end
   step();
  end
  rv=0;mrv=0;captured=0;accepted=0;expecting_error=0;step();
  if(row!=ROWS||sent!=LEGAL||retired!=LEGAL||issued!=LEGAL||results!=LEGAL||headers!=BEATS||totalhalves!=2*BEATS||rejected!=ROWS-LEGAL||maxcount!=CAPACITY||zero_be==0||highaddr==0||partial==0||doubletake==0||headerfirst==0||datafirst==0||(CAPACITY>1&&ooo==0)||reserved_done!=16||!duplicate_done)$fatal(1,"READ_COVERAGE row=%0d sent=%0d retired=%0d headers=%0d wanted=%0d",row,sent,retired,headers,BEATS);
  tracking=0;rv=1;address=0;length=63;attr=255;asi=3;meta=8'hff;tag=11'h7ff;src=10'h3ff;mready=0;step();rv=0;#1;slot=mslot;mready=1;step();mready=0;mrv=1;status=0;result_data={2048{1'b1}};step();mrv=0;captured=1;accepted=1;step();captured=0;accepted=0;
  if(count!=1)$fatal(1,"READ_RESET_SETUP");rstn=0;step();rstn=1;#1;if(count!=0||sv||dvalid!=0||mvalid)$fatal(1,"READ_RESET_STATE");mrv=1;expecting_error=1;step();mrv=0;expecting_error=0;step();
  $display("READ_COMPLETER_PASS capacity=%0d rows=%0d requests=%0d memory=%0d results=%0d responses=%0d beats=%0d halves=%0d rejected=%0d zero_be=%0d high_addresses=%0d partial=%0d double=%0d header_first=%0d data_first=%0d out_of_order=%0d full_stalls=%0d errors=%0d cycles=%0d encoder_cases=%0d",CAPACITY,ROWS,sent,issued,results,retired,headers,totalhalves,rejected,zero_be,highaddr,partial,doubletake,headerfirst,datafirst,ooo,fullstalls,errors,cycle,encoder_cases);$finish;
 end
endmodule
