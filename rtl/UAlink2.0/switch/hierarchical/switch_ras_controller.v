`default_nettype none
// RAS 事件收集：每一位独立 sticky、独立饱和计数，clear 不影响同周期新事件。
// 位映射0..18：CRC、FEC、replay、replay timeout、credit underflow/overflow/duplicate、
// queue overflow/underflow、illegal route、inactive destination、illegal bifurcation、
// illegal PortID/VC、stuck owner、fabric timeout、bank conflict、drop、link state change。
module switch_ras_controller #(
    parameter integer C_NUM_EVENTS = 19,
    parameter integer C_COUNTER_WIDTH = 16
) (
    input wire i_clk, input wire i_rstn,
    input wire [C_NUM_EVENTS-1:0] i_event,
    input wire [C_NUM_EVENTS-1:0] i_clear,
    output reg [C_NUM_EVENTS-1:0] o_sticky,
    output reg [C_NUM_EVENTS*C_COUNTER_WIDTH-1:0] o_counters,
    output wire o_serious_error
);
    reg [C_COUNTER_WIDTH-1:0] counter_q [0:C_NUM_EVENTS-1];
    integer event_index;
    localparam [C_COUNTER_WIDTH-1:0] C_COUNTER_MAX = {C_COUNTER_WIDTH{1'b1}};
    // 本叶模块把所有事件统一上报；系统级 RAS 策略可在上层决定中断严重度。
    assign o_serious_error = |o_sticky;

    always @(*) begin
        o_counters = {(C_NUM_EVENTS*C_COUNTER_WIDTH){1'b0}};
        for (event_index=0; event_index<C_NUM_EVENTS; event_index=event_index+1)
            o_counters[event_index*C_COUNTER_WIDTH +: C_COUNTER_WIDTH] = counter_q[event_index];
    end

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            o_sticky <= {C_NUM_EVENTS{1'b0}};
            for (event_index=0; event_index<C_NUM_EVENTS; event_index=event_index+1)
                counter_q[event_index] <= {C_COUNTER_WIDTH{1'b0}};
        end else begin
            o_sticky <= (o_sticky & ~i_clear) | i_event;
            for (event_index=0; event_index<C_NUM_EVENTS; event_index=event_index+1)
                if (i_event[event_index] && counter_q[event_index] != C_COUNTER_MAX)
                    counter_q[event_index] <= counter_q[event_index]+1'b1;
        end
    end
endmodule
`default_nettype wire
