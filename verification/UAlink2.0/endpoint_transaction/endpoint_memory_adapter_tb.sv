`timescale 1ns/1ps
module endpoint_memory_adapter_tb;
localparam TW=10;
reg clk=0,rstn=0,issue_valid=0,backend_ready=0,result_valid=0,completion_ready=0,final_valid=0,release_ready=0;
reg [TW-1:0] issue_token=0,result_token=0,final_token=0;
reg [7:0] station=0; reg [1:0] port=0,vc=0; reg pool=0;
reg [183:0] payload=0; reg [2047:0] issue_data=0,result_data=0; reg [255:0] be=0; reg [3:0] poison=0,data_pools=0,status=0,result_poison=0;
wire issue_ready,backend_valid,result_ready,completion_valid,final_ready,release_valid,busy,error,error_sticky;
wire [TW-1:0] backend_token,completion_token,release_token; wire [7:0] backend_station; wire [1:0] backend_port,backend_vc; wire backend_pool;
wire [183:0] backend_payload; wire [2047:0] backend_data,completion_data; wire [255:0] backend_be; wire [3:0] backend_poison,backend_data_pools,completion_status,completion_poison;
endpoint_memory_adapter #(.TOKEN_WIDTH(TW)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_issue_valid(issue_valid),.o_issue_ready(issue_ready),.i_issue_token(issue_token),.i_issue_station(station),.i_issue_port(port),.i_issue_vc(vc),.i_issue_pool(pool),.i_issue_payload(payload),.i_issue_data(issue_data),.i_issue_be(be),.i_issue_poison(poison),.i_issue_data_pools(data_pools),
 .o_backend_valid(backend_valid),.i_backend_ready(backend_ready),.o_backend_token(backend_token),.o_backend_station(backend_station),.o_backend_port(backend_port),.o_backend_vc(backend_vc),.o_backend_pool(backend_pool),.o_backend_payload(backend_payload),.o_backend_data(backend_data),.o_backend_be(backend_be),.o_backend_poison(backend_poison),.o_backend_data_pools(backend_data_pools),
 .i_result_valid(result_valid),.o_result_ready(result_ready),.i_result_token(result_token),.i_result_status(status),.i_result_data(result_data),.i_result_poison(result_poison),
 .o_completion_valid(completion_valid),.i_completion_ready(completion_ready),.o_completion_token(completion_token),.o_completion_status(completion_status),.o_completion_data(completion_data),.o_completion_poison(completion_poison),
 .i_final_valid(final_valid),.o_final_ready(final_ready),.i_final_token(final_token),.o_release_valid(release_valid),.i_release_ready(release_ready),.o_release_token(release_token),.o_busy(busy),.o_error(error),.o_error_sticky(error_sticky));
always #5 clk=~clk;
task tick; begin @(negedge clk); #1; end endtask
task need; input ok; input [255:0] why; begin if(!ok) begin $display("FAIL %0s",why); $fatal; end end endtask
initial begin
 repeat(2) tick; rstn=1; tick; need(issue_ready&&!busy,"idle ready");
 issue_token=10'h155;station=8'ha6;port=2;vc=1;pool=1;payload=184'h123456789abcdef;issue_data[2047:1984]=64'hfedcba9876543210;issue_data[63:0]=64'h0123456789abcdef;be=256'h8000000000000000000000000000000000000000000000000000000000000001;poison=4'ha;data_pools=4'h5;issue_valid=1;tick;issue_valid=0;
 need(backend_valid&&busy,"command held");need(backend_token==10'h155&&backend_station==8'ha6&&backend_port==2&&backend_vc==1&&backend_pool,"command identity");
 need(backend_payload==184'h123456789abcdef&&backend_data[2047:1984]==64'hfedcba9876543210&&backend_data[63:0]==64'h0123456789abcdef&&backend_be==be&&backend_poison==4'ha&&backend_data_pools==4'h5,"command fields");
 issue_token=3;station=1;payload=7;tick;need(backend_token==10'h155&&backend_station==8'ha6&&backend_payload==184'h123456789abcdef,"backpressure stable");
 final_token=10'h155;final_valid=1;tick;final_valid=0;need(error&&error_sticky&&!release_valid,"early final rejected");
 backend_ready=1;tick;backend_ready=0;need(!backend_valid&&busy,"wait result");
 result_token=10'h2aa;result_valid=1;tick;result_valid=0;need(error&&error_sticky&&!completion_valid,"wrong result rejected");
 result_token=10'h155;status=4'h6;result_data[2047:1984]=64'h1122334455667788;result_data[63:0]=64'h8877665544332211;result_poison=4'h9;result_valid=1;tick;result_valid=0;
 need(completion_valid&&completion_token==10'h155&&completion_status==6&&completion_poison==9,"completion held");need(completion_data[2047:1984]==64'h1122334455667788&&completion_data[63:0]==64'h8877665544332211,"completion data");
 result_data=0;status=0;tick;need(completion_valid&&completion_status==6&&completion_data[2047:1984]==64'h1122334455667788,"completion stable");
 completion_ready=1;tick;completion_ready=0;need(!completion_valid&&busy,"wait final");
 final_token=10'h2aa;final_valid=1;tick;final_valid=0;need(error&&!release_valid,"wrong final rejected");
 final_token=10'h155;final_valid=1;tick;final_valid=0;need(release_valid&&release_token==10'h155&&busy,"release held");
 tick;need(release_valid&&release_token==10'h155,"release backpressure");release_ready=1;tick;release_ready=0;need(!busy&&issue_ready&&!release_valid,"retired");
 // Reset cancels an accepted command without fabricating release.
 issue_token=10'h31;issue_valid=1;tick;issue_valid=0;need(backend_valid,"second command");rstn=0;tick;need(!busy&&!backend_valid&&!release_valid&&!error_sticky,"reset cancel");rstn=1;tick;need(issue_ready,"new epoch ready");
 $display("MEMORY_ADAPTER_PASS checks=22");$finish;
end
endmodule
