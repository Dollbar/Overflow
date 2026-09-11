`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0;
reg valid=0,full=0;wire ready,source_valid,error,pending,sent_event,done;
reg [10:0] tag=0;reg [56:0] address=0;reg [5:0] length=0;reg [7:0] attr=8'ha5,metadata=8'h96;reg [1:0] asi=2'd3;
reg [2047:0] data=0;reg [255:0] be=0;wire [255:0] control;wire [1:0] data_valid;wire [511:0] data_out;
reg captured=0,taken=0;reg [1:0] accepted=0;
endpoint_write_originator dut(.i_clk(clk),.i_rstn(rstn),.i_local_id(10'd1023),.i_request_valid(valid),.o_request_ready(ready),
 .i_request_full(full),.i_request_tag(tag),.i_request_address(address),.i_request_dst(10'd1022),.i_request_length(length),
 .i_request_attr(attr),.i_request_asi(asi),.i_request_metadata(metadata),.i_request_data(data),.i_request_be(be),
 .o_source_valid(source_valid),.o_source_control(control),.i_source_captured(captured),.i_header_taken(taken),
 .o_data_valid(data_valid),.o_data(data_out),.i_data_accepted(accepted),.o_pending(pending),.o_sent(sent_event),.o_done(done),.o_error(error));
integer good=0,bad=0,cycles=0,pos,size,n,index,mode,q,total,cursor,tick_number,amount;
reg [255:0] expected_header,halves[0:8],mask;
reg [2047:0] fixture;
task tick;begin @(posedge clk);#1;@(negedge clk);cycles=cycles+1;if(cycles>200000)$fatal(1,"WRITE_TIMEOUT");end endtask
task check_bad;begin valid=1;#1;if(ready!==0||error!==1)$fatal(1,"WRITE_BAD_ACCEPTED address=%h length=%d full=%b",address,length,full);tick;valid=0;#1;if(error!==0)$fatal(1,"WRITE_IDLE_ERROR");bad=bad+1;end endtask
task send_and_drain;
 begin
  n=((address%64)+4*(length+1)+63)/64;total=2*n+(!full);mode=good%3;
  mask=0;for(q=0;q<256;q=q+1)if(q>=(address%256)&&q<(address%256)+4*(length+1))mask[q]=1;
  be=(good%5==0)?256'd0:(mask&{16{16'ha55a}});
  if(full)be=~mask; // Input BE is deliberately wrong and must be ignored for WriteFull.
  fixture=0;for(q=0;q<8;q=q+1)begin halves[q]={8{32'h91827364}}^(256'hf01e2d3c4b5a6978*(q+1))^(good*17);fixture[q*256+:256]=halves[q];end
  halves[2*n]=be;data=fixture;
  expected_header={128'd0,4'h1,(full?6'h29:6'h28),2'd0,asi,tag,1'b0,attr,length,metadata,address[56:2],10'd1023,10'd1022,3'd0,2'(n-1)};
  valid=1;#1;if(ready!==1||error!==0)$fatal(1,"WRITE_LEGAL_REJECTED address=%h length=%d",address,length);tick;valid=0;
  // Change every source payload after the handshake: the serializer must use saved ownership.
  data=~fixture;be=~be;tag=~tag;address=~address;length=~length;attr=~attr;metadata=~metadata;asi=~asi;
  cursor=0;tick_number=0;
  while(pending)begin
   #1;
   if(source_valid&&control!==expected_header)$fatal(1,"WRITE_SERIAL_HEADER");
   if(data_valid!==((total-cursor>=2)?2'd2:(total-cursor==1)?2'd1:2'd0))$fatal(1,"WRITE_SERIAL_COUNT");
   if(data_valid!=0&&data_out[255:0]!==halves[cursor])$fatal(1,"WRITE_SERIAL_DATA low good=%0d cursor=%0d",good,cursor);
   if(data_valid==2&&data_out[511:256]!==halves[cursor+1])$fatal(1,"WRITE_SERIAL_DATA high good=%0d cursor=%0d",good,cursor);
   if(data_valid<2&&data_out[511:256]!==0)$fatal(1,"WRITE_UNUSED_LANE");
   captured=source_valid&&(tick_number==(mode==2?3:1));
   taken=(mode==0)?tick_number==3:(mode==1)?cursor==total&&tick_number>2:tick_number==5;
   // Header before Data, Header after Data, and overlap with partial acceptance.
   amount=((mode==0&&tick_number<5)||tick_number%4==0)?0:((tick_number%3==0)?2:1);
   if(amount>total-cursor)amount=total-cursor;
   accepted=amount;#1;if(error)$fatal(1,"WRITE_FEEDBACK_ERROR good=%0d tick=%0d",good,tick_number);
   cursor=cursor+amount;tick;captured=0;taken=0;accepted=0;tick_number=tick_number+1;
   if(tick_number>30)$fatal(1,"WRITE_PENDING_STUCK");
  end
  if(cursor!=total||source_valid||data_valid)$fatal(1,"WRITE_OWNERSHIP_RELEASE");
  good=good+1;attr=8'ha5;metadata=8'h96;asi=3;
 end
endtask
initial begin
 repeat(2)tick;rstn=1;
 // Exhaust all DWORD positions and lengths; overflow combinations must not become ready.
 for(pos=0;pos<64;pos=pos+1)for(size=1;size<=64;size=size+1)begin
  full=0;address=57'h100000000000000+pos*4;length=size-1;tag=(pos*67+size)&2047;be=0;
  if(pos+size<=64)send_and_drain;else check_bad;
 end
 for(pos=0;pos<4;pos=pos+1)for(size=1;size<=4;size=size+1)begin
  full=1;address=pos*64;length=size*16-1;tag=2047;be=0;
  if(pos+size<=4)send_and_drain;else check_bad;
 end
 full=0;address=0;length=0;be=256'h10;check_bad;
 address=1;be=0;check_bad;full=1;address=4;length=15;check_bad;address=0;length=14;check_bad;
 // Invalid feedback must preserve the saved first half and Header ownership.
 full=1;address=0;length=63;be=0;valid=1;#1;if(!ready)$fatal(1,"WRITE_FEEDBACK_RESERVE");tick;valid=0;
 fixture=data;accepted=3;taken=1;#1;if(error!==1||sent_event!==0)$fatal(1,"WRITE_BAD_FEEDBACK_ACCEPTED");tick;accepted=0;taken=0;#1;
 if(data_out[255:0]!==fixture[255:0]||!source_valid)$fatal(1,"WRITE_BAD_FEEDBACK_ADVANCED");
 captured=1;taken=1;accepted=2;#1;if(error||!sent_event)$fatal(1,"WRITE_CONCURRENT_FEEDBACK");tick;captured=0;taken=0;accepted=0;
 rstn=0;tick;rstn=1;
 // Reset while held cancels all pending Data and Header work.
 full=0;address=60;length=1;be=0;valid=1;#1;if(!ready)$fatal(1,"WRITE_RESET_RESERVE");tick;valid=0;rstn=0;tick;rstn=1;#1;
 if(pending||source_valid||data_valid||error)$fatal(1,"WRITE_RESET_LEAK");
 if(good!=2090||bad!=2026)$fatal(1,"WRITE_GEOMETRY_COVERAGE good=%0d bad=%0d",good,bad);
 $display("WRITE_TEST_PASS serializer legal=%0d illegal=%0d cycles=%0d",good,bad,cycles);$finish;
end
endmodule
