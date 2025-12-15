`timescale 1ns/1ps
module tb_overflow_hbm_beat_bfm;
    localparam integer DATA_BYTES = 16;
    logic clk;
    logic rst_n;
    logic req_valid;
    wire req_ready;
    wire req_error;
    logic req_write;
    logic [0:0] req_partition;
    logic [11:0] req_address;
    logic [7:0] req_tag;
    logic [DATA_BYTES*8-1:0] req_write_data;
    logic [DATA_BYTES-1:0] req_byte_enable;
    logic inject_correctable;
    logic inject_uncorrectable;
    wire rsp_valid;
    logic rsp_ready;
    wire rsp_write;
    wire [0:0] rsp_partition;
    wire [7:0] rsp_tag;
    wire [DATA_BYTES*8-1:0] rsp_read_data;
    wire [1:0] rsp_status;
    wire [63:0] accepted_beats;
    wire [63:0] completed_beats;
    wire [63:0] backpressure_cycles;
    logic [DATA_BYTES*8-1:0] full_data;
    logic [DATA_BYTES*8-1:0] partial_data;
    logic [DATA_BYTES*8-1:0] expected_partial;
    logic [DATA_BYTES*8-1:0] stalled_data;
    logic [7:0] stalled_tag;
    integer stall_cycle;

    overflow_hbm_beat_bfm #(
        .PARTITIONS(2),
        .PARTITION_BITS(1),
        .ADDR_WIDTH(12),
        .TAG_WIDTH(8),
        .DATA_BYTES(DATA_BYTES),
        .READ_LATENCY_CYCLES(3),
        .WRITE_LATENCY_CYCLES(3),
        .PAYLOAD_BYTES_PER_CYCLE_PER_PARTITION(DATA_BYTES),
        .MAX_OUTSTANDING_PER_PARTITION(8),
        .QUEUE_DEPTH(16),
        .CAPACITY_BYTES_PER_PARTITION(64'd4096)
    ) u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .req_valid_i(req_valid), .req_ready_o(req_ready), .req_error_o(req_error),
        .req_write_i(req_write), .req_partition_i(req_partition),
        .req_address_i(req_address), .req_tag_i(req_tag),
        .req_write_data_i(req_write_data), .req_byte_enable_i(req_byte_enable),
        .inject_correctable_i(inject_correctable),
        .inject_uncorrectable_i(inject_uncorrectable),
        .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready), .rsp_write_o(rsp_write),
        .rsp_partition_o(rsp_partition), .rsp_tag_o(rsp_tag),
        .rsp_read_data_o(rsp_read_data), .rsp_status_o(rsp_status),
        .accepted_beats_o(accepted_beats), .completed_beats_o(completed_beats),
        .backpressure_cycles_o(backpressure_cycles)
    );

    always #0.5 clk = ~clk;

    task automatic send_request(
        input logic write_value,
        input logic [0:0] partition_value,
        input logic [11:0] address_value,
        input logic [7:0] tag_value,
        input logic [DATA_BYTES*8-1:0] data_value,
        input logic [DATA_BYTES-1:0] enable_value,
        input logic correctable_value,
        input logic uncorrectable_value
    );
        begin
            @(negedge clk);
            req_write = write_value;
            req_partition = partition_value;
            req_address = address_value;
            req_tag = tag_value;
            req_write_data = data_value;
            req_byte_enable = enable_value;
            inject_correctable = correctable_value;
            inject_uncorrectable = uncorrectable_value;
            req_valid = 1'b1;
            while (!req_ready) @(negedge clk);
            @(negedge clk);
            req_valid = 1'b0;
            inject_correctable = 1'b0;
            inject_uncorrectable = 1'b0;
        end
    endtask

    task automatic expect_response(
        input logic expected_write,
        input logic [7:0] expected_tag,
        input logic [1:0] expected_status,
        input logic [DATA_BYTES*8-1:0] expected_data
    );
        begin
            rsp_ready = 1'b1;
            while (!rsp_valid) @(posedge clk);
            #0.01;
            if (rsp_write !== expected_write || rsp_tag !== expected_tag ||
                rsp_status !== expected_status) begin
                $fatal(1, "HBM BFM response metadata mismatch write=%b tag=%0d status=%0d",
                    rsp_write, rsp_tag, rsp_status);
            end
            if (!expected_write && rsp_read_data !== expected_data) begin
                $fatal(1, "HBM BFM response data mismatch tag=%0d expected=%h observed=%h",
                    expected_tag, expected_data, rsp_read_data);
            end
            @(negedge clk);
            rsp_ready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_partition = 1'b0;
        req_address = 12'd0;
        req_tag = 8'd0;
        req_write_data = 128'd0;
        req_byte_enable = 16'd0;
        inject_correctable = 1'b0;
        inject_uncorrectable = 1'b0;
        rsp_ready = 1'b0;
        full_data = 128'hffeeddccbbaa99887766554433221100;
        partial_data = 128'h55555555555555555555555555555555;
        expected_partial = 128'hffeeddccbbaa99885555555555555555;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        send_request(1'b1, 1'b0, 12'h000, 8'd1, full_data, 16'hffff, 1'b0, 1'b0);
        expect_response(1'b1, 8'd1, 2'd0, 128'd0);
        send_request(1'b0, 1'b0, 12'h000, 8'd2, 128'd0, 16'd0, 1'b0, 1'b0);
        expect_response(1'b0, 8'd2, 2'd0, full_data);

        send_request(1'b1, 1'b0, 12'h000, 8'd3, partial_data, 16'h00ff, 1'b0, 1'b0);
        expect_response(1'b1, 8'd3, 2'd0, 128'd0);
        send_request(1'b0, 1'b0, 12'h000, 8'd4, 128'd0, 16'd0, 1'b0, 1'b0);
        expect_response(1'b0, 8'd4, 2'd0, expected_partial);

        send_request(1'b0, 1'b0, 12'h000, 8'd5, 128'd0, 16'd0, 1'b1, 1'b0);
        expect_response(1'b0, 8'd5, 2'd1, expected_partial);
        send_request(1'b0, 1'b0, 12'h000, 8'd6, 128'd0, 16'd0, 1'b0, 1'b1);
        expect_response(1'b0, 8'd6, 2'd2, expected_partial ^ 128'd3);

        send_request(1'b0, 1'b1, 12'h010, 8'd7, 128'd0, 16'd0, 1'b0, 1'b0);
        while (!rsp_valid) @(posedge clk);
        #0.01;
        stalled_data = rsp_read_data;
        stalled_tag = rsp_tag;
        for (stall_cycle = 0; stall_cycle < 3; stall_cycle = stall_cycle + 1) begin
            @(posedge clk); #0.01;
            if (!rsp_valid || rsp_read_data !== stalled_data || rsp_tag !== stalled_tag) begin
                $fatal(1, "HBM BFM response changed under backpressure");
            end
        end
        rsp_ready = 1'b1;
        @(posedge clk); #0.01;
        rsp_ready = 1'b0;

        @(negedge clk);
        req_valid = 1'b1;
        req_address = 12'h001;
        #0.01;
        if (!req_error || req_ready) $fatal(1, "HBM BFM accepted a misaligned request");
        @(negedge clk); req_valid = 1'b0;

        repeat (2) @(posedge clk); #0.01;
        if (accepted_beats != 64'd7 || completed_beats != 64'd7) begin
            $fatal(1, "HBM BFM counters mismatch accepted=%0d completed=%0d",
                accepted_beats, completed_beats);
        end
        if (backpressure_cycles == 64'd0) $fatal(1, "HBM BFM did not count invalid-request backpressure");
        $display("TB_OVERFLOW_HBM_BEAT_BFM_PASS beats=7 partial_write=1 corrected=1 uncorrectable=1 response_stall=3");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "HBM BFM timeout");
    end
endmodule
