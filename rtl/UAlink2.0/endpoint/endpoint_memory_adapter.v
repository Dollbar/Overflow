`timescale 1ns/1ps // 后端命令、结果和最终响应退休共享同一时钟域。
`default_nettype none // 上下文token及完整数据字段不得由隐式网络连接。
module endpoint_memory_adapter #( // 单在途加速器后端适配器；多事务容量仍由外部context拥有。
 parameter integer TOKEN_WIDTH=10, // 本地context token宽度，不替换原网络Tag。
 parameter integer STATION_WIDTH=8 // 本地station身份宽度。
)(
 input wire i_clk,i_rstn, // 共同同步低有效reset取消本地未完成生命周期。
 input wire i_issue_valid,output wire o_issue_ready, // context仅在此握手后标记issued。
 input wire [TOKEN_WIDTH-1:0] i_issue_token,input wire [STATION_WIDTH-1:0] i_issue_station,
 input wire [1:0] i_issue_port,input wire [1:0] i_issue_vc,input wire i_issue_pool,
 input wire [183:0] i_issue_payload,input wire [2047:0] i_issue_data,input wire [255:0] i_issue_be,
 input wire [3:0] i_issue_poison,input wire [3:0] i_issue_data_pools,
 output wire o_backend_valid,input wire i_backend_ready, // 命令在真实后端接纳前完整保持。
 output wire [TOKEN_WIDTH-1:0] o_backend_token,output wire [STATION_WIDTH-1:0] o_backend_station,
 output wire [1:0] o_backend_port,output wire [1:0] o_backend_vc,output wire o_backend_pool,
 output wire [183:0] o_backend_payload,output wire [2047:0] o_backend_data,output wire [255:0] o_backend_be,
 output wire [3:0] o_backend_poison,output wire [3:0] o_backend_data_pools,
 input wire i_result_valid,output wire o_result_ready,input wire [TOKEN_WIDTH-1:0] i_result_token,
 input wire [3:0] i_result_status,input wire [2047:0] i_result_data,input wire [3:0] i_result_poison,
 output wire o_completion_valid,input wire i_completion_ready, // formatter取得完整结果但不释放context。
 output wire [TOKEN_WIDTH-1:0] o_completion_token,output wire [3:0] o_completion_status,
 output wire [2047:0] o_completion_data,output wire [3:0] o_completion_poison,
 input wire i_final_valid,output wire o_final_ready,input wire [TOKEN_WIDTH-1:0] i_final_token, // 最终响应退休确认。
 output wire o_release_valid,input wire i_release_ready,output wire [TOKEN_WIDTH-1:0] o_release_token, // 唯一context release交接。
 output wire o_busy,output wire o_error,output wire o_error_sticky // 乱序/重复/未知完成只诊断并丢弃。
);
 localparam [2:0] S_IDLE=3'd0,S_COMMAND=3'd1,S_RESULT_WAIT=3'd2,S_COMPLETION=3'd3,S_FINAL_WAIT=3'd4,S_RELEASE=3'd5;
 reg [2:0] r_state; // 单槽生命周期明确区分五个所有权转移。
 reg [TOKEN_WIDTH-1:0] r_token;reg [STATION_WIDTH-1:0] r_station;reg [1:0] r_port,r_vc;reg r_pool;
 reg [183:0] r_payload;reg [2047:0] r_issue_data;reg [255:0] r_be;reg [3:0] r_issue_poison,r_data_pools;
 reg [3:0] r_status,r_result_poison;reg [2047:0] r_result_data;reg r_error,r_error_sticky;
 wire issue_fire,backend_fire,completion_fire,release_fire; // 每级只由真实ready/valid推进。
 assign o_issue_ready=i_rstn&&(r_state==S_IDLE);assign issue_fire=i_issue_valid&&o_issue_ready;
 assign o_backend_valid=i_rstn&&(r_state==S_COMMAND);assign backend_fire=o_backend_valid&&i_backend_ready;
 assign o_backend_token=o_backend_valid?r_token:{TOKEN_WIDTH{1'b0}};assign o_backend_station=o_backend_valid?r_station:{STATION_WIDTH{1'b0}};
 assign o_backend_port=o_backend_valid?r_port:2'd0;assign o_backend_vc=o_backend_valid?r_vc:2'd0;assign o_backend_pool=o_backend_valid&&r_pool;
 assign o_backend_payload=o_backend_valid?r_payload:184'd0;assign o_backend_data=o_backend_valid?r_issue_data:2048'd0;
 assign o_backend_be=o_backend_valid?r_be:256'd0;assign o_backend_poison=o_backend_valid?r_issue_poison:4'd0;assign o_backend_data_pools=o_backend_valid?r_data_pools:4'd0;
 assign o_result_ready=i_rstn; // 未期待或token不符的结果也消费并诊断，不能堵塞共享后端返回口。
 assign o_completion_valid=i_rstn&&(r_state==S_COMPLETION);assign completion_fire=o_completion_valid&&i_completion_ready;
 assign o_completion_token=o_completion_valid?r_token:{TOKEN_WIDTH{1'b0}};assign o_completion_status=o_completion_valid?r_status:4'd0;
 assign o_completion_data=o_completion_valid?r_result_data:2048'd0;assign o_completion_poison=o_completion_valid?r_result_poison:4'd0;
 assign o_final_ready=i_rstn; // 早到、重复或token不符的退休事件均被消费并诊断。
 assign o_release_valid=i_rstn&&(r_state==S_RELEASE);assign release_fire=o_release_valid&&i_release_ready;
 assign o_release_token=o_release_valid?r_token:{TOKEN_WIDTH{1'b0}};assign o_busy=i_rstn&&(r_state!=S_IDLE);
 assign o_error=i_rstn&&r_error;assign o_error_sticky=i_rstn&&r_error_sticky;
 always @(posedge i_clk)begin
  if(!i_rstn)begin
   r_state<=S_IDLE;r_token<={TOKEN_WIDTH{1'b0}};r_station<={STATION_WIDTH{1'b0}};r_port<=2'd0;r_vc<=2'd0;r_pool<=1'b0;
   r_payload<=184'd0;r_issue_data<=2048'd0;r_be<=256'd0;r_issue_poison<=4'd0;r_data_pools<=4'd0;
   r_status<=4'd0;r_result_data<=2048'd0;r_result_poison<=4'd0;r_error<=1'b0;r_error_sticky<=1'b0;
  end else begin
   r_error<=1'b0;
   if(issue_fire)begin
    r_state<=S_COMMAND;r_token<=i_issue_token;r_station<=i_issue_station;r_port<=i_issue_port;r_vc<=i_issue_vc;r_pool<=i_issue_pool;
    r_payload<=i_issue_payload;r_issue_data<=i_issue_data;r_be<=i_issue_be;r_issue_poison<=i_issue_poison;r_data_pools<=i_issue_data_pools;
   end
   if(backend_fire)r_state<=S_RESULT_WAIT; // 同沿零延迟result不属于此接口契约。
   if(i_result_valid&&o_result_ready)begin
    if((r_state==S_RESULT_WAIT)&&(i_result_token==r_token))begin
     r_status<=i_result_status;r_result_data<=i_result_data;r_result_poison<=i_result_poison;r_state<=S_COMPLETION;
    end else begin r_error<=1'b1;r_error_sticky<=1'b1;end
   end
   if(completion_fire)r_state<=S_FINAL_WAIT; // formatter接纳后仍等待真实最终响应退休。
   if(i_final_valid&&o_final_ready)begin
    if((r_state==S_FINAL_WAIT)&&(i_final_token==r_token))r_state<=S_RELEASE;
    else begin r_error<=1'b1;r_error_sticky<=1'b1;end
   end
   if(release_fire)r_state<=S_IDLE; // context实际接纳release后才允许下一个issue。
  end
 end
 generate if((TOKEN_WIDTH<1)||(TOKEN_WIDTH>32)||(STATION_WIDTH<1)||(STATION_WIDTH>32))begin:gen_invalid
  endpoint_memory_adapter_parameters_invalid u_invalid();
 end endgenerate
endmodule
`default_nettype wire
