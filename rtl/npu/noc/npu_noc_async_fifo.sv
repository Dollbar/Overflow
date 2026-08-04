`timescale 1ns/1ps
`default_nettype none

// Exact-depth dual-clock FIFO. Only Gray-coded pointers cross domains; data is
// held in dual-port storage and addressed by the owning read-domain pointer.
module npu_noc_async_fifo #(
    parameter int unsigned WIDTH = 160,
    parameter int unsigned DEPTH = 8,
    parameter int unsigned ADDRESS_WIDTH = $clog2(DEPTH),
    parameter int unsigned POINTER_WIDTH = ADDRESS_WIDTH + 1
) (
    input  logic write_clk_i,
    input  logic write_rst_i,
    input  logic write_valid_i,
    output logic write_ready_o,
    input  logic [WIDTH-1:0] write_data_i,
    output logic write_full_o,
    output logic write_empty_o,

    input  logic read_clk_i,
    input  logic read_rst_i,
    output logic read_valid_o,
    input  logic read_ready_i,
    output logic [WIDTH-1:0] read_data_o,
    output logic read_empty_o,

    output logic configuration_error_o
);

    logic [WIDTH-1:0] storage_q [0:DEPTH-1];
    logic [POINTER_WIDTH-1:0] write_binary_q;
    logic [POINTER_WIDTH-1:0] write_gray_q;
    logic [POINTER_WIDTH-1:0] read_binary_q;
    logic [POINTER_WIDTH-1:0] read_gray_q;
    (* async_reg = "true" *) logic [POINTER_WIDTH-1:0]
        read_gray_write_sync1_q;
    (* async_reg = "true" *) logic [POINTER_WIDTH-1:0]
        read_gray_write_sync2_q;
    (* async_reg = "true" *) logic [POINTER_WIDTH-1:0]
        write_gray_read_sync1_q;
    (* async_reg = "true" *) logic [POINTER_WIDTH-1:0]
        write_gray_read_sync2_q;
    logic write_full_q;
    logic write_fire;
    logic read_fire;
    logic [POINTER_WIDTH-1:0] write_binary_next;
    logic [POINTER_WIDTH-1:0] write_gray_next;
    logic [POINTER_WIDTH-1:0] read_binary_next;
    logic [POINTER_WIDTH-1:0] read_gray_next;
    logic [POINTER_WIDTH-1:0] full_compare_pointer;
    logic write_full_next;

    assign write_ready_o = !write_full_q;
    assign write_fire = write_valid_i && write_ready_o;
    assign write_binary_next = write_binary_q + POINTER_WIDTH'(write_fire);
    assign write_gray_next = (write_binary_next >> 1) ^ write_binary_next;
    assign full_compare_pointer = {
        ~read_gray_write_sync2_q[POINTER_WIDTH-1:POINTER_WIDTH-2],
        read_gray_write_sync2_q[POINTER_WIDTH-3:0]
    };
    assign write_full_next = (write_gray_next == full_compare_pointer);
    assign write_full_o = write_full_q;
    assign write_empty_o = (write_gray_q == read_gray_write_sync2_q);

    assign read_empty_o = (read_gray_q == write_gray_read_sync2_q);
    assign read_valid_o = !read_empty_o;
    assign read_data_o = storage_q[read_binary_q[ADDRESS_WIDTH-1:0]];
    assign read_fire = read_valid_o && read_ready_i;
    assign read_binary_next = read_binary_q + POINTER_WIDTH'(read_fire);
    assign read_gray_next = (read_binary_next >> 1) ^ read_binary_next;

    always_ff @(posedge write_clk_i or posedge write_rst_i) begin
        if (write_rst_i) begin
            write_binary_q <= '0;
            write_gray_q <= '0;
            write_full_q <= 1'b0;
            read_gray_write_sync1_q <= '0;
            read_gray_write_sync2_q <= '0;
        end else begin
            read_gray_write_sync1_q <= read_gray_q;
            read_gray_write_sync2_q <= read_gray_write_sync1_q;
            if (write_fire) begin
                storage_q[write_binary_q[ADDRESS_WIDTH-1:0]] <= write_data_i;
            end
            write_binary_q <= write_binary_next;
            write_gray_q <= write_gray_next;
            write_full_q <= write_full_next;
        end
    end

    always_ff @(posedge read_clk_i or posedge read_rst_i) begin
        if (read_rst_i) begin
            read_binary_q <= '0;
            read_gray_q <= '0;
            write_gray_read_sync1_q <= '0;
            write_gray_read_sync2_q <= '0;
        end else begin
            write_gray_read_sync1_q <= write_gray_q;
            write_gray_read_sync2_q <= write_gray_read_sync1_q;
            read_binary_q <= read_binary_next;
            read_gray_q <= read_gray_next;
        end
    end

`ifdef FORMAL
    logic formal_write_past_valid_q;
    logic formal_read_past_valid_q;
    initial formal_write_past_valid_q = 1'b0;
    initial formal_read_past_valid_q = 1'b0;

    always_ff @(posedge write_clk_i) begin
        formal_write_past_valid_q <= 1'b1;
        if (!write_rst_i) begin
            assert (write_gray_q ==
                    ((write_binary_q >> 1) ^ write_binary_q));
            assert (write_ready_o == !write_full_o);
            if (formal_write_past_valid_q && !$past(write_rst_i)) begin
                assert ($onehot0(write_gray_q ^ $past(write_gray_q)));
            end
        end
    end

    always_ff @(posedge read_clk_i) begin
        formal_read_past_valid_q <= 1'b1;
        if (!read_rst_i) begin
            assert (read_gray_q ==
                    ((read_binary_q >> 1) ^ read_binary_q));
            assert (read_valid_o == !read_empty_o);
            if (formal_read_past_valid_q && !$past(read_rst_i)) begin
                assert ($onehot0(read_gray_q ^ $past(read_gray_q)));
            end
        end
    end
`endif

    assign configuration_error_o = (WIDTH < 1) || (DEPTH < 4) ||
        ((1 << ADDRESS_WIDTH) != DEPTH) || (POINTER_WIDTH < 3);

endmodule

`default_nettype wire
