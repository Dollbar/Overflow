`timescale 1ns/1ps
module tb;
 parameter PORTS=4,INDEX_WIDTH=2;
 reg clk=0,rstn=0,wvalid=0,wena=0,commit=0,quiescent=0;reg [INDEX_WIDTH-1:0] index=0;reg [9:0] id=0;
 wire waccepted,caccepted,pending,error;wire [PORTS*10-1:0] active_ids;wire [PORTS-1:0] active_enable;
 switch_route_table @@DUT_PARAMETERS@@ dut(.i_clk(clk),.i_rstn(rstn),.i_write_valid(wvalid),.i_write_index(index),.i_write_route_id(id),.i_write_enable(wena),.i_commit(commit),.i_quiescent(quiescent),.o_write_accepted(waccepted),.o_commit_accepted(caccepted),.o_route_ids(active_ids),.o_port_enable(active_enable),.o_pending(pending),.o_error(error));
 reg [PORTS*10-1:0] query=0;wire [PORTS*PORTS-1:0] match_bits;wire [PORTS-1:0] lookup_errors;
 switch_route_lookup #(.PORTS(PORTS)) lookup(.i_valid({PORTS{1'b1}}),.i_dst(query),.i_route_ids(active_ids),.i_port_enable(active_enable),.o_match(match_bits),.o_error(lookup_errors));
 reg [9:0] shadow_id[0:PORTS-1],active_id[0:PORTS-1];reg shadow_en[0:PORTS-1],active_en[0:PORTS-1];
 reg [1023:0] used_ids;reg duplicate,expect_w,expect_c,expect_e,expect_pending;
 integer cycles=0,writes=0,commits=0,duplicates=0,busy=0,collisions=0,invalid=0,resets=0,lookup_checks=0;
 integer j,k,seed=918241,loopno,target,found;reg [PORTS-1:0] row_match;
 task compare_tables;
 begin
  expect_pending=0;
  for(j=0;j<PORTS;j=j+1)begin
   if(active_ids[j*10+:10]!==active_id[j]||active_enable[j]!==active_en[j])$fatal(1,"ROUTE_ACTIVE cycle=%0d port=%0d",cycles,j);
   if(shadow_id[j]!=active_id[j]||shadow_en[j]!=active_en[j])expect_pending=1;
   row_match=0;found=0;
   for(k=0;k<PORTS;k=k+1)if(active_en[k]&&active_id[k]==query[j*10+:10])begin found=found+1;row_match[k]=1;end
   if(found!=1)row_match=0;
   if(match_bits[j*PORTS+:PORTS]!==row_match||lookup_errors[j]!==(found!=1))$fatal(1,"ROUTE_LOOKUP_LAYOUT");
   lookup_checks=lookup_checks+1;
  end
  if(pending!==expect_pending)$fatal(1,"ROUTE_PENDING cycle=%0d",cycles);
 end
 endtask
 task step;
 begin
  #2;
  if(cycles!=0)compare_tables();
  used_ids=0;duplicate=0;
  for(j=0;j<PORTS;j=j+1)if(shadow_en[j])begin if(used_ids[shadow_id[j]])duplicate=1;used_ids[shadow_id[j]]=1;end
  expect_w=rstn&&wvalid&&!commit&&(index<PORTS);
  expect_c=rstn&&commit&&!wvalid&&quiescent&&!duplicate;
  expect_e=rstn&&((wvalid&&commit)||(wvalid&&index>=PORTS)||(commit&&(!quiescent||duplicate)));
  if(waccepted!==expect_w||caccepted!==expect_c||error!==expect_e)$fatal(1,"ROUTE_ACK cycle=%0d got=%b%b%b expected=%b%b%b",cycles,waccepted,caccepted,error,expect_w,expect_c,expect_e);
  if(!rstn)begin
   for(j=0;j<PORTS;j=j+1)begin shadow_id[j]=0;active_id[j]=0;shadow_en[j]=0;active_en[j]=0;end
   resets=resets+1;
  end else begin
   if(expect_w)begin shadow_id[index]=id;shadow_en[index]=wena;writes=writes+1;end
   if(expect_c)begin for(j=0;j<PORTS;j=j+1)begin active_id[j]=shadow_id[j];active_en[j]=shadow_en[j];end commits=commits+1;end
   if(commit&&!wvalid&&duplicate)duplicates=duplicates+1;
   if(commit&&!wvalid&&!quiescent)busy=busy+1;
   if(commit&&wvalid)collisions=collisions+1;
   if(wvalid&&index>=PORTS)invalid=invalid+1;
  end
  clk=1;#2;clk=0;cycles=cycles+1;#1;compare_tables();
 end
 endtask
 task write_entry(input integer slot,input [9:0] route,input reg enabled);
 begin wvalid=1;commit=0;index=slot;id=route;wena=enabled;step();wvalid=0;end
 endtask
 task publish(input reg idle);
 begin wvalid=0;commit=1;quiescent=idle;step();commit=0;end
 endtask
 initial begin
  for(j=0;j<PORTS;j=j+1)begin shadow_id[j]=0;active_id[j]=0;shadow_en[j]=0;active_en[j]=0;end
  step();rstn=1;step();publish(1); // Legal unchanged commit is an acknowledged no-op.
  for(loopno=0;loopno<PORTS;loopno=loopno+1)begin
   write_entry(loopno,loopno==0?0:loopno==1?1023:512+loopno,1);
   query[loopno*10+:10]=loopno==0?0:loopno==1?1023:512+loopno;
  end
  publish(0);publish(1);
  for(loopno=0;loopno<PORTS;loopno=loopno+1)write_entry(loopno,100+loopno,1);
  publish(1);
  if(PORTS>1)begin
   write_entry(1,100,0);publish(1); // Disabled duplicate is harmless.
   write_entry(1,100,1);publish(1); // Enabled duplicate must preserve active table.
   write_entry(1,777,1);publish(1);
  end
  wvalid=1;commit=1;index=0;id=991;wena=0;quiescent=1;step();wvalid=0;commit=0;
  if((1<<INDEX_WIDTH)>PORTS)write_entry((1<<INDEX_WIDTH)-1,1001,1);
  // Restore content to the active copy: pending must measure actual differences.
  for(loopno=0;loopno<PORTS;loopno=loopno+1)write_entry(loopno,active_id[loopno],active_en[loopno]);
  if(pending)$fatal(1,"ROUTE_PENDING_IDENTICAL");
  for(loopno=0;loopno<250;loopno=loopno+1)begin
   wvalid=$unsigned($random(seed))%2;commit=$unsigned($random(seed))%3==0;quiescent=$unsigned($random(seed))%2;
   index=$unsigned($random(seed))%(1<<INDEX_WIDTH);id=$unsigned($random(seed))%1024;wena=$unsigned($random(seed))%2;
   for(target=0;target<PORTS;target=target+1)query[target*10+:10]=(loopno%2)?active_id[target]:$unsigned($random(seed))%1024;
   step();
  end
  wvalid=0;commit=0;rstn=0;step();rstn=1;step();
  for(loopno=0;loopno<PORTS;loopno=loopno+1)write_entry(loopno,1023-loopno,1);publish(1);
  if(writes<PORTS||commits<4||busy==0||collisions==0||(PORTS>1&&duplicates==0)||((1<<INDEX_WIDTH)>PORTS&&invalid==0)||resets!=2)$fatal(1,"ROUTE_COVERAGE");
  $display("ROUTE_TABLE_PASS ports=%0d index_width=%0d writes=%0d commits=%0d duplicate_rejects=%0d busy_rejects=%0d concurrent_rejects=%0d invalid_indices=%0d resets=%0d lookup_checks=%0d cycles=%0d",PORTS,INDEX_WIDTH,writes,commits,duplicates,busy,collisions,invalid,resets,lookup_checks,cycles);$finish;
 end
endmodule
