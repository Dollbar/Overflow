module kdlink_v2_reverse_channel_model #(
    parameter integer PROPAGATION_CYCLES = 4
) (
    input logic clk_i,
    input logic rst_n_i,
    input logic a_tx_valid_i,
    input logic [127:0] a_tx_word_i,
    input logic b_tx_valid_i,
    input logic [127:0] b_tx_word_i,
    input logic inject_a_to_b_corrupt_i,
    input logic inject_b_to_a_corrupt_i,
    input logic inject_a_to_b_drop_i,
    input logic inject_b_to_a_drop_i,
    output logic a_rx_valid_o,
    output logic [127:0] a_rx_word_o,
    output logic b_rx_valid_o,
    output logic [127:0] b_rx_word_o
);
    logic [PROPAGATION_CYCLES:0] a_valid_pipe_q;
    logic [PROPAGATION_CYCLES:0] b_valid_pipe_q;
    logic [127:0] a_word_pipe_q [0:PROPAGATION_CYCLES];
    logic [127:0] b_word_pipe_q [0:PROPAGATION_CYCLES];
    integer stage_index;

    assign b_rx_valid_o = a_valid_pipe_q[PROPAGATION_CYCLES];
    assign b_rx_word_o = a_word_pipe_q[PROPAGATION_CYCLES];
    assign a_rx_valid_o = b_valid_pipe_q[PROPAGATION_CYCLES];
    assign a_rx_word_o = b_word_pipe_q[PROPAGATION_CYCLES];

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            a_valid_pipe_q <= '0;
            b_valid_pipe_q <= '0;
            for (stage_index = 0; stage_index <= PROPAGATION_CYCLES;
                 stage_index = stage_index + 1) begin
                a_word_pipe_q[stage_index] <= '0;
                b_word_pipe_q[stage_index] <= '0;
            end
        end else begin
            a_valid_pipe_q[0] <= a_tx_valid_i && !inject_a_to_b_drop_i;
            b_valid_pipe_q[0] <= b_tx_valid_i && !inject_b_to_a_drop_i;
            a_word_pipe_q[0] <= inject_a_to_b_corrupt_i ?
                (a_tx_word_i ^ 128'd1) : a_tx_word_i;
            b_word_pipe_q[0] <= inject_b_to_a_corrupt_i ?
                (b_tx_word_i ^ 128'd1) : b_tx_word_i;
            for (stage_index = 0; stage_index < PROPAGATION_CYCLES;
                 stage_index = stage_index + 1) begin
                a_valid_pipe_q[stage_index+1] <= a_valid_pipe_q[stage_index];
                b_valid_pipe_q[stage_index+1] <= b_valid_pipe_q[stage_index];
                a_word_pipe_q[stage_index+1] <= a_word_pipe_q[stage_index];
                b_word_pipe_q[stage_index+1] <= b_word_pipe_q[stage_index];
            end
        end
    end
endmodule
