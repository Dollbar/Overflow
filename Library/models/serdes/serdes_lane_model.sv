`timescale 1ns/1ps
module serdes_lane_model #(
    parameter integer BLOCK_WIDTH = 66,
    parameter integer PROPAGATION_CYCLES = 3,
    parameter integer STATIC_SKEW_CYCLES = 0,
    parameter integer CDR_LOCK_CYCLES = 8,
    parameter integer BLOCK_LOCK_CYCLES = 8,
    parameter integer JITTER_PERIOD_BLOCKS = 0,
    parameter integer JITTER_EXTRA_CYCLES = 0,
    parameter integer BURST_ERROR_LENGTH_BLOCKS = 4,
    parameter integer ELASTIC_DEPTH = 64,
    parameter [BLOCK_WIDTH-1:0] CORRUPTION_MASK = {{(BLOCK_WIDTH-2){1'b0}},2'b11}
) (
    input wire clk_i,input wire rst_n_i,input wire admin_up_i,input wire signal_detect_i,
    input wire force_loss_of_lock_i,input wire tx_block_valid_i,output wire tx_block_ready_o,
    input wire [BLOCK_WIDTH-1:0] tx_block_i,input wire inject_drop_i,input wire inject_corrupt_i,
    input wire inject_burst_i,input wire [31:0] error_period_blocks_i,
    output wire rx_block_valid_o,input wire rx_block_ready_i,output wire [BLOCK_WIDTH-1:0] rx_block_o,
    output wire cdr_locked_o,output wire block_locked_o,output wire lane_ready_o,output wire [2:0] lane_state_o,
    output reg [31:0] offered_blocks_o,output reg [31:0] delivered_blocks_o,
    output reg [31:0] dropped_blocks_o,output reg [31:0] corrupted_blocks_o,
    output reg [31:0] overflow_blocks_o,output reg [31:0] retrain_events_o
);
    localparam [2:0] LANE_DOWN=3'd0,LANE_CDR_LOCK=3'd1,LANE_BLOCK_LOCK=3'd2,LANE_READY=3'd3,LANE_FAULT=3'd4;
    localparam integer BASE_LATENCY=PROPAGATION_CYCLES+STATIC_SKEW_CYCLES;
    localparam integer POINTER_WIDTH=(ELASTIC_DEPTH<=2)?1:$clog2(ELASTIC_DEPTH);
    localparam integer JITTER_DIVISOR=(JITTER_PERIOD_BLOCKS>0)?JITTER_PERIOD_BLOCKS:1;
    localparam [POINTER_WIDTH:0] ELASTIC_DEPTH_COUNT=ELASTIC_DEPTH[POINTER_WIDTH:0];
    localparam integer LAST_POINTER_INTEGER=ELASTIC_DEPTH-1;
    localparam [POINTER_WIDTH-1:0] LAST_POINTER=LAST_POINTER_INTEGER[POINTER_WIDTH-1:0];
    reg [2:0] lane_state_q;reg [31:0] lock_count_q,offered_sequence_q,periodic_error_count_q;
    reg [31:0] burst_remaining_q,cycle_count_q,last_due_cycle_q;
    reg [BLOCK_WIDTH-1:0] block_fifo[0:ELASTIC_DEPTH-1];reg [31:0]due_fifo[0:ELASTIC_DEPTH-1];
    reg [POINTER_WIDTH-1:0]read_pointer_q,write_pointer_q;reg [POINTER_WIDTH:0]fifo_count_q;integer queue_index;
    wire fifo_full=(fifo_count_q==ELASTIC_DEPTH_COUNT);
    wire output_due=(fifo_count_q!=0)&&(due_fifo[read_pointer_q]<=cycle_count_q);
    wire output_fire=rx_block_valid_o&&rx_block_ready_i;
    wire input_fire=tx_block_valid_i&&tx_block_ready_o;
    wire explicit_drop=input_fire&&inject_drop_i;
    wire periodic_error=input_fire&&(error_period_blocks_i!=0)&&(periodic_error_count_q>=error_period_blocks_i-1'b1);
    wire burst_error=input_fire&&((burst_remaining_q!=0)||inject_burst_i);
    wire corrupt_block=input_fire&&!inject_drop_i&&(inject_corrupt_i||periodic_error||burst_error);
    wire store_block=input_fire&&!explicit_drop;
    wire jitter_event=input_fire&&(JITTER_PERIOD_BLOCKS>0)&&((offered_sequence_q%JITTER_DIVISOR)==JITTER_DIVISOR-1);
    wire [31:0]requested_due_cycle=cycle_count_q+BASE_LATENCY+(jitter_event?JITTER_EXTRA_CYCLES:0);
    wire [31:0]ordered_due_cycle=((fifo_count_q==0)||((fifo_count_q==1)&&output_fire)||requested_due_cycle>last_due_cycle_q)?requested_due_cycle:last_due_cycle_q+1'b1;
    assign lane_ready_o=(lane_state_q==LANE_READY);assign lane_state_o=lane_state_q;
    assign cdr_locked_o=(lane_state_q==LANE_BLOCK_LOCK)||(lane_state_q==LANE_READY);
    assign block_locked_o=lane_ready_o;
    assign rx_block_valid_o=lane_ready_o&&output_due;assign rx_block_o=block_fifo[read_pointer_q];
    assign tx_block_ready_o=lane_ready_o&&(!fifo_full||output_fire||inject_drop_i);
    initial begin
        if(BLOCK_WIDTH<2||PROPAGATION_CYCLES<1||STATIC_SKEW_CYCLES<0)$fatal(1,"illegal SerDes width/latency");
        if(CDR_LOCK_CYCLES<1||BLOCK_LOCK_CYCLES<1||BURST_ERROR_LENGTH_BLOCKS<1||ELASTIC_DEPTH<2)$fatal(1,"illegal SerDes training/buffer parameter");
        if(JITTER_PERIOD_BLOCKS<0||JITTER_EXTRA_CYCLES<0)$fatal(1,"illegal SerDes jitter parameter");
    end
    always @(posedge clk_i or negedge rst_n_i)begin
        if(!rst_n_i)begin
            lane_state_q<=LANE_DOWN;lock_count_q<=0;offered_sequence_q<=0;periodic_error_count_q<=0;burst_remaining_q<=0;cycle_count_q<=0;last_due_cycle_q<=0;read_pointer_q<=0;write_pointer_q<=0;fifo_count_q<=0;
            offered_blocks_o<=0;delivered_blocks_o<=0;dropped_blocks_o<=0;corrupted_blocks_o<=0;overflow_blocks_o<=0;retrain_events_o<=0;
            for(queue_index=0;queue_index<ELASTIC_DEPTH;queue_index=queue_index+1)begin block_fifo[queue_index]<=0;due_fifo[queue_index]<=0;end
        end else begin
            cycle_count_q<=cycle_count_q+1'b1;
            if(!admin_up_i||!signal_detect_i||force_loss_of_lock_i)begin
                if(lane_state_q==LANE_READY)retrain_events_o<=retrain_events_o+1'b1;
                if(fifo_count_q!=0)dropped_blocks_o<=dropped_blocks_o+{{(32-POINTER_WIDTH-1){1'b0}},fifo_count_q};
                lane_state_q<=force_loss_of_lock_i?LANE_FAULT:LANE_DOWN;lock_count_q<=0;offered_sequence_q<=0;periodic_error_count_q<=0;burst_remaining_q<=0;last_due_cycle_q<=cycle_count_q;read_pointer_q<=0;write_pointer_q<=0;fifo_count_q<=0;
            end else begin
                case(lane_state_q)
                    LANE_DOWN,LANE_FAULT:begin lane_state_q<=LANE_CDR_LOCK;lock_count_q<=1;end
                    LANE_CDR_LOCK:if(lock_count_q>=CDR_LOCK_CYCLES)begin lane_state_q<=LANE_BLOCK_LOCK;lock_count_q<=1;end else lock_count_q<=lock_count_q+1'b1;
                    LANE_BLOCK_LOCK:if(lock_count_q>=BLOCK_LOCK_CYCLES)begin lane_state_q<=LANE_READY;end else lock_count_q<=lock_count_q+1'b1;
                    default:lane_state_q<=LANE_READY;
                endcase
                if(output_fire)begin delivered_blocks_o<=delivered_blocks_o+1'b1;read_pointer_q<=(read_pointer_q==LAST_POINTER)?0:read_pointer_q+1'b1;end
                if(input_fire)begin
                    offered_blocks_o<=offered_blocks_o+1'b1;offered_sequence_q<=offered_sequence_q+1'b1;
                    periodic_error_count_q<=periodic_error?0:periodic_error_count_q+1'b1;
                    if(inject_burst_i&&(burst_remaining_q==0))burst_remaining_q<=BURST_ERROR_LENGTH_BLOCKS-1;
                    else if(burst_remaining_q!=0)burst_remaining_q<=burst_remaining_q-1'b1;
                    if(explicit_drop)dropped_blocks_o<=dropped_blocks_o+1'b1;
                    else if(fifo_full&&!output_fire)begin overflow_blocks_o<=overflow_blocks_o+1'b1;dropped_blocks_o<=dropped_blocks_o+1'b1;end
                    else begin block_fifo[write_pointer_q]<=corrupt_block?(tx_block_i^CORRUPTION_MASK):tx_block_i;due_fifo[write_pointer_q]<=ordered_due_cycle;last_due_cycle_q<=ordered_due_cycle;write_pointer_q<=(write_pointer_q==LAST_POINTER)?0:write_pointer_q+1'b1;if(corrupt_block)corrupted_blocks_o<=corrupted_blocks_o+1'b1;end
                end
                case({store_block&&(!fifo_full||output_fire),output_fire})2'b10:fifo_count_q<=fifo_count_q+1'b1;2'b01:fifo_count_q<=fifo_count_q-1'b1;default:fifo_count_q<=fifo_count_q;endcase
            end
        end
    end
endmodule
