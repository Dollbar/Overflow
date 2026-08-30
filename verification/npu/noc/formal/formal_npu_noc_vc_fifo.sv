`timescale 1ns/1ps
`default_nettype none

module formal_npu_noc_vc_fifo;

    wire clk = $global_clock;
    (* anyseq *) logic rst;
    (* anyseq *) logic push_valid;
    (* anyseq *) logic [7:0] push_data;
    (* anyseq *) logic pop_ready;
    logic push_ready;
    logic pop_valid;
    logic [7:0] pop_data;
    logic [2:0] level;
    logic past_valid_q;

    initial past_valid_q = 1'b0;

    npu_noc_vc_fifo #(
        .WIDTH(8),
        .DEPTH(4)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(1'b0),
        .push_valid_i(push_valid),
        .push_ready_o(push_ready),
        .push_data_i(push_data),
        .pop_valid_o(pop_valid),
        .pop_ready_i(pop_ready),
        .pop_data_o(pop_data),
        .level_o(level)
    );

    always_ff @(posedge clk) begin
        past_valid_q <= 1'b1;
        if (!past_valid_q) begin
            assume (rst);
        end else begin
            assume (!rst);
        end
        assert (level <= 3'd4);
        assert (pop_valid == (level != 0));
        if (past_valid_q && $past(push_valid && !push_ready)) begin
            assume (push_valid);
            assume (push_data == $past(push_data));
        end
        if (past_valid_q && $past(pop_valid && !pop_ready)) begin
            assert (pop_valid);
            assert (pop_data == $past(pop_data));
        end
    end

endmodule

`default_nettype wire
