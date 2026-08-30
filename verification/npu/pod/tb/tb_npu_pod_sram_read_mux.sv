`timescale 1ns/1ps
`default_nettype none

module tb_npu_pod_sram_read_mux;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic dma_request_valid_i;
    logic dma_request_ready_o;
    logic [23:0] dma_request_address_i;
    logic dma_response_valid_o;
    logic dma_response_ready_i;
    logic [1023:0] dma_response_data_o;
    logic loader_request_valid_i;
    logic loader_request_ready_o;
    logic [23:0] loader_request_address_i;
    logic loader_response_valid_o;
    logic loader_response_ready_i;
    logic [1023:0] loader_response_data_o;
    logic downstream_request_valid_o;
    logic downstream_request_ready_i;
    logic [23:0] downstream_request_address_o;
    logic downstream_response_valid_i;
    logic downstream_response_ready_o;
    logic [1023:0] downstream_response_data_i;
    logic busy_o;
    logic protocol_error_o;
    logic [1023:0] response_pattern;

    npu_pod_sram_read_mux dut (.*);

    always #0.5 clk_i = ~clk_i;

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        dma_request_valid_i = 1'b0;
        dma_request_address_i = 24'h000100;
        dma_response_ready_i = 1'b0;
        loader_request_valid_i = 1'b0;
        loader_request_address_i = 24'h000200;
        loader_response_ready_i = 1'b0;
        downstream_request_ready_i = 1'b1;
        downstream_response_valid_i = 1'b0;
        downstream_response_data_i = '0;
        response_pattern = {128{8'h5a}};

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        dma_request_valid_i = 1'b1;
        loader_request_valid_i = 1'b1;
        #0.01;
        if (!downstream_request_valid_o || !dma_request_ready_o ||
            loader_request_ready_o ||
            (downstream_request_address_o != 24'h000100)) begin
            $fatal(1, "initial DMA arbitration mismatch");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        dma_request_valid_i = 1'b0;
        if (!busy_o || loader_request_ready_o) begin
            $fatal(1, "outstanding request ownership mismatch");
        end

        downstream_response_data_i = response_pattern;
        downstream_response_valid_i = 1'b1;
        repeat (2) begin
            @(posedge clk_i);
            @(negedge clk_i);
            if (!dma_response_valid_o || loader_response_valid_o ||
                (dma_response_data_o != response_pattern) ||
                downstream_response_ready_o) begin
                $fatal(1, "DMA response backpressure mismatch");
            end
        end
        dma_response_ready_i = 1'b1;
        #0.01;
        if (!downstream_response_ready_o ||
            !downstream_request_valid_o || !loader_request_ready_o ||
            (downstream_request_address_o != 24'h000200)) begin
            $fatal(1, "same-cycle response/request turnover mismatch");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        dma_response_ready_i = 1'b0;
        downstream_response_valid_i = 1'b0;
        loader_request_valid_i = 1'b0;

        downstream_response_data_i = ~response_pattern;
        downstream_response_valid_i = 1'b1;
        loader_response_ready_i = 1'b1;
        #0.01;
        if (!loader_response_valid_o || dma_response_valid_o ||
            (loader_response_data_o != ~response_pattern)) begin
            $fatal(1, "loader response routing mismatch");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        downstream_response_valid_i = 1'b0;
        loader_response_ready_i = 1'b0;
        if (busy_o || protocol_error_o) begin
            $fatal(1, "read mux failed to drain cleanly");
        end

        dma_request_valid_i = 1'b1;
        loader_request_valid_i = 1'b1;
        #0.01;
        if (!downstream_request_valid_o || !dma_request_ready_o ||
            loader_request_ready_o ||
            (downstream_request_address_o != 24'h000100)) begin
            $fatal(1, "round-robin DMA priority mismatch");
        end

        $display("[RTL_SIM PASS] npu_pod_sram_read_mux");
        $finish;
    end

    initial begin
        #200;
        $fatal(1, "npu_pod_sram_read_mux timeout");
    end

endmodule

`default_nettype wire
