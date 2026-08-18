`timescale 1ns/1ps
`default_nettype none

// 根分发器与(0,0) Router之间的两项寄存缓冲。输入ready只由占用寄存器
// 决定，满状态恢复时允许一个气泡，以切断Router ready的组合反压路径。
module gemm_root_dispatcher_egress_fifo (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         clear_i,
    input  logic         in_valid_i,
    output logic         in_ready_o,
    input  logic         in_vc_i,
    input  logic [159:0] in_flit_i,
    output logic         out_valid_o,
    input  logic         out_ready_i,
    output logic         out_vc_o,
    output logic [159:0] out_flit_o
);

    logic [159:0] head_flit_q;
    logic [159:0] tail_flit_q;
    logic head_vc_q;
    logic tail_vc_q;
    logic [1:0] count_q;
    logic push;
    logic pop;
    logic head_load_input;
    logic head_load_tail;
    logic tail_load_input;

    assign in_ready_o = count_q != 2'd2;
    assign out_valid_o = count_q != 2'd0;
    assign out_flit_o = head_flit_q;
    assign out_vc_o = head_vc_q;
    assign push = in_valid_i && in_ready_o;
    assign pop = out_valid_o && out_ready_i;
    assign head_load_input = push &&
        ((count_q == 2'd0) || ((count_q == 2'd1) && pop));
    assign head_load_tail = (count_q == 2'd2) && pop;
    assign tail_load_input = push && (count_q == 2'd1) && !pop;

    // 160-bit head/tail数据按16-bit切片建立本地写使能，避免FIFO状态位
    // 或读指针直接驱动整条flit总线的160个选择器。
    for (genvar data_slice = 0; data_slice < 10;
         data_slice = data_slice + 1) begin : gen_data_slice
        logic head_input_load_inverted;
        logic head_input_load_buffered;
        logic head_tail_load_inverted;
        logic head_tail_load_buffered;
        logic tail_input_load_inverted;
        logic tail_input_load_buffered;

        gemm_root_dispatcher_control_inverter u_head_input_load_inverter (
            .data_i (head_load_input),
            .data_o (head_input_load_inverted)
        );
        gemm_root_dispatcher_control_inverter u_head_input_load_restore (
            .data_i (head_input_load_inverted),
            .data_o (head_input_load_buffered)
        );
        gemm_root_dispatcher_control_inverter u_head_tail_load_inverter (
            .data_i (head_load_tail),
            .data_o (head_tail_load_inverted)
        );
        gemm_root_dispatcher_control_inverter u_head_tail_load_restore (
            .data_i (head_tail_load_inverted),
            .data_o (head_tail_load_buffered)
        );
        gemm_root_dispatcher_control_inverter u_tail_input_load_inverter (
            .data_i (tail_load_input),
            .data_o (tail_input_load_inverted)
        );
        gemm_root_dispatcher_control_inverter u_tail_input_load_restore (
            .data_i (tail_input_load_inverted),
            .data_o (tail_input_load_buffered)
        );

        always_ff @(posedge clk_i) begin
            if (head_input_load_buffered) begin
                head_flit_q[data_slice*16 +: 16] <=
                    in_flit_i[data_slice*16 +: 16];
            end
            if (head_tail_load_buffered) begin
                head_flit_q[data_slice*16 +: 16] <=
                    tail_flit_q[data_slice*16 +: 16];
            end
            if (tail_input_load_buffered) begin
                tail_flit_q[data_slice*16 +: 16] <=
                    in_flit_i[data_slice*16 +: 16];
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            count_q <= 2'd0;
        end else begin
            if (head_load_input) begin
                head_vc_q <= in_vc_i;
            end
            if (head_load_tail) begin
                head_vc_q <= tail_vc_q;
            end
            if (tail_load_input) begin
                tail_vc_q <= in_vc_i;
            end
            case ({push, pop})
                2'b10: count_q <= count_q + 2'd1;
                2'b01: count_q <= count_q - 2'd1;
                default: count_q <= count_q;
            endcase
        end
    end

endmodule

`default_nettype wire
