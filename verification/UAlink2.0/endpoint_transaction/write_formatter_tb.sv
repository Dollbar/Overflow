`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0;
reg request_valid=0,is_write=0,full=0;wire request_ready;
reg [10:0] tag=0;reg [56:0] address=0;reg [5:0] length=15;reg [7:0] attr=255,metadata=0;reg [1:0] asi=0;
reg [2047:0] data=0;reg [255:0] be=0;
wire source_valid;wire [255:0] control;wire [1:0] data_valid;wire [511:0] data_out;reg captured=0,taken=0;reg [1:0] accepted=0;
reg response_valid=0,response_write=0;wire response_ready;reg [1:0] response_port=0,response_offset=0,response_beats=0;
reg [10:0] response_tag=0;reg [9:0] response_dst=17;reg [3:0] response_status=0;reg response_last=1,response_data_error=0;
reg [511:0] response_data=512'hf0123456789abcde;wire complete_valid,complete_write,complete_data_valid;reg complete_ready=0;
wire [1:0] complete_port;wire [10:0] complete_tag;wire [3:0] complete_status;wire [511:0] complete_data;wire error;wire [7:0] count;
endpoint_request_formatter dut(.i_clk(clk),.i_rstn(rstn),.i_local_id(10'd17),
 .i_request_valid(request_valid),.o_request_ready(request_ready),.i_request_is_write(is_write),.i_request_full(full),
 .i_request_port(2'd0),.i_request_tag(tag),.i_request_address(address),.i_request_dst(10'd513),.i_request_length(length),.i_request_attr(attr),
 .i_request_asi(asi),.i_request_metadata(metadata),.i_request_data(data),.i_request_be(be),
 .o_source_valid(source_valid),.o_source_control(control),.i_source_captured(captured),.i_header_taken(taken),
 .o_data_valid(data_valid),.o_data(data_out),.i_data_accepted(accepted),
 .i_response_valid(response_valid),.o_response_ready(response_ready),.i_response_is_write(response_write),.i_response_port(response_port),.i_response_tag(response_tag),
 .i_response_dst(response_dst),.i_response_status(response_status),.i_response_offset(response_offset),.i_response_last(response_last),.i_response_num_beats(response_beats),
 .i_response_data(response_data),.i_response_data_error(response_data_error),
 .o_complete_valid(complete_valid),.i_complete_ready(complete_ready),.o_complete_is_write(complete_write),.o_complete_port(complete_port),.o_complete_tag(complete_tag),
 .o_complete_status(complete_status),.o_complete_data(complete_data),.o_complete_data_valid(complete_data_valid),.o_error(error),.o_count(count));
integer cycles=0,reservations=0,retired=0,bad_responses=0,q,save_count;
reg [531:0] held_value;
task tick;begin @(posedge clk);#1;@(negedge clk);cycles=cycles+1;if(cycles>2000)$fatal(1,"WRITE_FORMATTER_TIMEOUT");end endtask
task fields;
 input kind;input [10:0] new_tag;
 begin
  is_write=kind;tag=new_tag;full=0;address=kind?57'd60:57'd0;length=kind?6'd1:6'd15;
  attr=kind?8'h81:8'hff;asi=kind?2'd2:2'd0;metadata=kind?8'h5a:8'd0;
  data={8{256'hfedcba98765432100123456789abcdef}};be=256'hff000000000000000;
 end
endtask
task reserve;
 input kind;input [10:0] new_tag;
 begin
  fields(kind,new_tag);request_valid=1;#1;
  if(!request_ready||error)$fatal(1,"WRITE_RESERVATION_REJECTED tag=%d",new_tag);
  tick;request_valid=0;reservations=reservations+1;
  if(!source_valid||count==0)$fatal(1,"WRITE_NO_SAVED_REQUEST");
  if(kind&&new_tag==1024&&control!==256'h1a0a0020415a0000000000001e08c021)$fatal(1,"WRITE_FIXED_CONTROL");
 end
endtask
task send_pending;
 begin
  repeat(2)tick;
  captured=1;tick;captured=0;#1;
  if(source_valid)$fatal(1,"WRITE_CAPTURE_DUPLICATED");
  // Header is acknowledged before draining Data; next app request must remain blocked.
  taken=1;#1;if(error)$fatal(1,"WRITE_SENT_ERROR");tick;taken=0;
  while(data_valid!=0)begin
   #1;if(request_ready)$fatal(1,"WRITE_DATA_ORDER_BYPASSED");
   accepted=(data_valid==2)?2'd1:data_valid;tick;accepted=0;
  end
  tick;#1;if(error)$fatal(1,"WRITE_IDLE_AFTER_SEND");
 end
endtask
task bad_response;
 input kind;input [10:0] bad_tag;input [3:0] status;
 begin
  response_write=kind;response_tag=bad_tag;response_status=status;response_valid=1;save_count=count;#1;
  if(!response_ready||!error)$fatal(1,"WRITE_KIND_MISMATCH_ACCEPTED tag=%d kind=%b",bad_tag,kind);
  tick;response_valid=0;repeat(3)tick;
  if(count!=save_count||complete_valid)$fatal(1,"WRITE_BAD_RESPONSE_CHANGED_OWNERSHIP");
  bad_responses=bad_responses+1;
 end
endtask
task finish_response;
 input kind;input [10:0] expected_tag;input [3:0] status;
 begin
  response_write=kind;response_tag=expected_tag;response_status=status;
  response_offset=kind?2'd3:2'd0;response_last=!kind;response_valid=1;#1;
  if(!response_ready||error)$fatal(1,"WRITE_VALID_RESPONSE_REJECTED tag=%d status=%d",expected_tag,status);
  tick;response_valid=0;while(!complete_valid)tick;
  if(complete_write!==kind||complete_tag!==expected_tag||complete_port!==0||complete_status!==status||complete_data_valid!==(!kind&&status==0)||complete_data!==((!kind&&status==0)?response_data:512'd0))$fatal(1,"WRITE_COMPLETION_FIELDS");
  held_value={complete_valid,complete_write,complete_port,complete_tag,complete_status,complete_data_valid,complete_data};
  repeat(5)begin tick;if(held_value!=={complete_valid,complete_write,complete_port,complete_tag,complete_status,complete_data_valid,complete_data})$fatal(1,"WRITE_COMPLETION_UNSTABLE");end
  complete_ready=1;tick;complete_ready=0;retired=retired+1;tick;
 end
endtask
initial begin
 repeat(2)tick;rstn=1;
 reserve(1,1024);
 captured=1;tick;captured=0;
 // A captured, unsent request must not accept even a correctly typed response.
 bad_response(1,1024,0);
 taken=1;tick;taken=0;while(data_valid!=0)begin accepted=data_valid;tick;accepted=0;end;tick;
 reserve(0,0);send_pending;
 reserve(1,2047);send_pending;
 reserve(0,4);send_pending;
 if(count!=4)$fatal(1,"WRITE_SHARED_CAPACITY");
 fields(1,0);request_valid=1;#1;if(request_ready||!error)$fatal(1,"WRITE_CROSS_KIND_TAG_COLLISION");tick;request_valid=0;
 fields(1,7);request_valid=1;#1;if(request_ready||error)$fatal(1,"WRITE_FULL_IS_NOT_ERROR");tick;request_valid=0;
 bad_response(0,1024,0);bad_response(1,0,0);bad_response(1,1025,0);bad_response(1,1024,1);
 response_dst=18;bad_response(1,1024,0);response_dst=17;
 response_beats=1;bad_response(1,1024,0);response_beats=0;
 response_data_error=1;bad_response(1,1024,0);response_data_error=0;
 response_port=1;bad_response(1,1024,0);response_port=0;
 // Return out of request order, retain full Tag and exact request kind.
 finish_response(1,2047,6);finish_response(0,4,3);finish_response(1,1024,0);finish_response(0,0,0);
 bad_response(1,1024,0);
 if(count!=0)$fatal(1,"WRITE_SHARED_DRAIN");
 for(q=0;q<5;q=q+1)begin
  reserve(1,1024+q);send_pending;
  case(q)
   0:finish_response(1,1024+q,0);
   1:finish_response(1,1024+q,2);
   2:finish_response(1,1024+q,3);
   3:finish_response(1,1024+q,6);
   4:finish_response(1,1024+q,8);
  endcase
 end
 reserve(1,1024);captured=1;tick;captured=0;accepted=1;tick;accepted=0;
 rstn=0;tick;rstn=1;#1;if(count||source_valid||data_valid||complete_valid||error)$fatal(1,"WRITE_FORMATTER_RESET");
 reserve(0,1024);send_pending;finish_response(0,1024,0);
 if(count!=0||reservations!=11||retired!=10||bad_responses!=10)$fatal(1,"WRITE_FORMATTER_COVERAGE reservations=%d retired=%d bad=%d",reservations,retired,bad_responses);
 $display("WRITE_TEST_PASS formatter reservations=%0d retired=%0d rejected=%0d cycles=%0d",reservations,retired,bad_responses,cycles);$finish;
end
endmodule
