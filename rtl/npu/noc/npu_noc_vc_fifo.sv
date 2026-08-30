`timescale 1ns/1ps
`default_nettype none

module npu_noc_vc_fifo #(
    parameter int unsigned WIDTH = 32,
    parameter int unsigned DEPTH = 8,
    parameter int unsigned POINTER_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int unsigned COUNT_WIDTH = $clog2(DEPTH + 1)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic push_valid_i,
    output logic push_ready_o,
    input  logic [WIDTH-1:0] push_data_i,

    output logic pop_valid_o,
    input  logic pop_ready_i,
    output logic [WIDTH-1:0] pop_data_o,

    output logic [COUNT_WIDTH-1:0] level_o
);

    logic [WIDTH-1:0] storage_q [0:DEPTH-1];
    logic [POINTER_WIDTH-1:0] write_pointer_q;
    logic [POINTER_WIDTH-1:0] read_pointer_q;
    logic [COUNT_WIDTH-1:0] count_q;
    logic push_fire;
    logic pop_fire;
    localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = COUNT_WIDTH'(DEPTH);
    localparam logic [POINTER_WIDTH-1:0] LAST_POINTER =
        POINTER_WIDTH'(DEPTH - 1);

    assign pop_valid_o = (count_q != '0);
    assign pop_data_o = storage_q[read_pointer_q];
    assign pop_fire = pop_valid_o && pop_ready_i;
    assign push_ready_o = (count_q < DEPTH_COUNT) || pop_fire;
    assign push_fire = push_valid_i && push_ready_o;
    assign level_o = count_q;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            write_pointer_q <= '0;
            read_pointer_q <= '0;
            count_q <= '0;
        end else begin
            if (push_fire) begin
                storage_q[write_pointer_q] <= push_data_i;
                if (write_pointer_q == LAST_POINTER) begin
                    write_pointer_q <= '0;
                end else begin
                    write_pointer_q <= write_pointer_q + 1'b1;
                end
            end
            if (pop_fire) begin
                if (read_pointer_q == LAST_POINTER) begin
                    read_pointer_q <= '0;
                end else begin
                    read_pointer_q <= read_pointer_q + 1'b1;
                end
            end
            case ({push_fire, pop_fire})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: count_q <= count_q;
            endcase
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk_i) begin
        if (!rst_i && !clear_i) begin
            assert (count_q <= DEPTH_COUNT);
            assert (write_pointer_q <= LAST_POINTER);
            assert (read_pointer_q <= LAST_POINTER);
            if (count_q == '0) begin
                assert (!pop_valid_o);
            end
            if (count_q == DEPTH_COUNT && !pop_fire) begin
                assert (!push_ready_o);
            end
        end
    end
`endif

`ifndef SYNTHESIS
    initial begin
        assert (WIDTH > 0 && DEPTH >= 2)
            else $error("npu_noc_vc_fifo requires WIDTH > 0 and DEPTH >= 2");
        assert ((1 << POINTER_WIDTH) >= DEPTH)
            else $error("npu_noc_vc_fifo pointer width is insufficient");
    end
`endif

endmodule

`default_nettype wire
