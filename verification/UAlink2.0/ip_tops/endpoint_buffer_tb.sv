`timescale 1ns/1ps
module endpoint_buffer_tb;
reg clk=0;always #5 clk=~clk;
reg rstn=0,clear=0,ready=0;
wire valid,rxready,payload,replayed,error;
wire [543:0] word;
wire [8:0] seq_out;
ualink_endpoint_top dut(
 .i_clk(clk),.i_rstn(rstn),.i_link_reset(clear),.i_start(1'b0),.i_auth(1'b0),.i_shared(1'b0),
 .i_capacities({20{8'd1}}),.i_source_valid(2'd0),.i_source_control(512'd0),
 .i_source_tags_valid(2'd0),.i_source_tags(1024'd0),.i_data_valid(4'd0),.i_data0(512'd0),.i_data1(512'd0),
 .i_read_ready(1'b0),.i_link_ready(ready),.o_link_valid(valid),.o_link_data(word),
 .o_link_payload(payload),.o_link_replay(replayed),.o_link_sequence(seq_out),
 .i_link_valid(1'b0),.i_link_data(544'd0),.i_link_crc_ok(1'b1),.o_link_ready(rxready),
 .i_rx_replay_limit(8'd50),.o_error(error));
task tick;begin @(posedge clk);#1;end endtask
initial begin
 force dut.dl_issue_accept=1'b0;
 force dut.dl_valid=1'b0;
 force dut.dl_header=24'habcdef;
 force dut.dl_data=520'h123456789abcdef;
 force dut.dl_payload=1'b1;
 force dut.dl_replay=1'b1;
 force dut.dl_sequence=9'd257;
 tick;@(negedge clk);rstn=1;
 if(valid!==0)$fatal(1,"reset leaked holding");
 force dut.dl_issue_accept=1'b1;tick;
 if(!dut.inflight||dut.reserve)$fatal(1,"reservation not exclusively retained");
 @(negedge clk);force dut.dl_issue_accept=1'b0;force dut.dl_valid=1'b1;tick;
 if(!valid||word!=={24'habcdef,520'h123456789abcdef}||!payload||!replayed||seq_out!==9'd257)
   $fatal(1,"return word and metadata were not captured together");
 @(negedge clk);force dut.dl_valid=1'b0;
 force dut.dl_header=24'hfedcba;force dut.dl_data=520'hdeadbeef;
 force dut.dl_payload=1'b0;force dut.dl_replay=1'b0;force dut.dl_sequence=9'd3;
 repeat(5)begin tick;if(!valid||word!=={24'habcdef,520'h123456789abcdef}||!payload||!replayed||seq_out!==9'd257||dut.reserve)
   $fatal(1,"holding changed while downstream stalled");end
 @(negedge clk);ready=1;tick;if(valid)$fatal(1,"retirement did not clear holding");
 @(negedge clk);ready=0;force dut.dl_issue_accept=1'b1;tick;
 @(negedge clk);force dut.dl_issue_accept=1'b0;clear=1;tick;
 if(valid||dut.inflight||rxready)$fatal(1,"link reset retained reservation");
 @(negedge clk);clear=0;tick;
 if(valid)$fatal(1,"cancelled slot reappeared");
 $display("PASS endpoint holding: reservation, full-word metadata stall, retirement, reset");$finish;
end
endmodule
