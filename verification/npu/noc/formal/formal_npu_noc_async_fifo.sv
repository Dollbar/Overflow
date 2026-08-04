`timescale 1ns/1ps
`default_nettype none

// The equal-clock case is a formal subset of the asynchronous FIFO contract.
// Multi-clock phase behavior remains covered by the dedicated RTL regression.
module formal_npu_noc_async_fifo;

    localparam int unsigned WIDTH = 8;
    localparam int unsigned DEPTH = 4;

    wire clk = $global_clock;
    (* anyseq *) logic rst;
    (* anyseq *) logic write_valid;
    (* anyseq *) logic [WIDTH-1:0] write_data;
    (* anyseq *) logic read_ready;
    logic write_ready;
    logic write_full;
    logic write_empty;
    logic read_valid;
    logic [WIDTH-1:0] read_data;
    logic read_empty;
    logic configuration_error;
    logic past_valid_q;
    logic [WIDTH-1:0] ghost_storage_q [0:DEPTH-1];
    logic [1:0] ghost_write_pointer_q;
    logic [1:0] ghost_read_pointer_q;
    logic [2:0] ghost_count_q;
    logic write_fire;
    logic read_fire;

    initial past_valid_q = 1'b0;

    assign write_fire = write_valid && write_ready;
    assign read_fire = read_valid && read_ready;

    npu_noc_async_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .write_clk_i(clk),
        .write_rst_i(rst),
        .write_valid_i(write_valid),
        .write_ready_o(write_ready),
        .write_data_i(write_data),
        .write_full_o(write_full),
        .write_empty_o(write_empty),
        .read_clk_i(clk),
        .read_rst_i(rst),
        .read_valid_o(read_valid),
        .read_ready_i(read_ready),
        .read_data_o(read_data),
        .read_empty_o(read_empty),
        .configuration_error_o(configuration_error)
    );

    always_ff @(posedge clk) begin
        past_valid_q <= 1'b1;
        if (!past_valid_q) begin
            assume (rst);
        end else begin
            assume (!rst);
        end
        if (past_valid_q && $past(write_valid && !write_ready)) begin
            assume (write_valid);
            assume (write_data == $past(write_data));
        end

        if (rst) begin
            ghost_write_pointer_q <= '0;
            ghost_read_pointer_q <= '0;
            ghost_count_q <= '0;
        end else begin
            assert (!configuration_error);
            assert (ghost_count_q <= DEPTH);
            if (read_fire) begin
                assert (ghost_count_q != 0);
                assert (read_data == ghost_storage_q[ghost_read_pointer_q]);
                ghost_read_pointer_q <= ghost_read_pointer_q + 1'b1;
            end
            if (write_fire) begin
                assert (ghost_count_q != DEPTH || read_fire);
                ghost_storage_q[ghost_write_pointer_q] <= write_data;
                ghost_write_pointer_q <= ghost_write_pointer_q + 1'b1;
            end
            case ({write_fire, read_fire})
                2'b10: ghost_count_q <= ghost_count_q + 1'b1;
                2'b01: ghost_count_q <= ghost_count_q - 1'b1;
                default: ghost_count_q <= ghost_count_q;
            endcase
        end
    end

    wire _unused_status = &{1'b0, write_full, write_empty, read_empty};

endmodule

`default_nettype wire
