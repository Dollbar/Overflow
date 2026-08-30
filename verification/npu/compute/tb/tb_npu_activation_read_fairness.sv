`timescale 1ns/1ps
`default_nettype none

module tb_npu_activation_read_fairness;
    localparam int unsigned DATA_WIDTH = 32;
    localparam int unsigned BUFFER_ID_WIDTH = 4;
    localparam int unsigned OFFSET_WIDTH = 32;
    localparam int unsigned CONTENTION_CYCLES = 32;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic gemm_valid;
    logic gemm_ready;
    logic [BUFFER_ID_WIDTH-1:0] gemm_buffer_id;
    logic [OFFSET_WIDTH-1:0] gemm_offset;
    logic gemm_response_valid;
    logic [DATA_WIDTH-1:0] gemm_response_data;
    logic [DATA_WIDTH-1:0] gemm_response_scale;
    logic vector_valid;
    logic vector_ready;
    logic [BUFFER_ID_WIDTH-1:0] vector_buffer_id;
    logic [OFFSET_WIDTH-1:0] vector_offset;
    logic vector_response_valid;
    logic [DATA_WIDTH-1:0] vector_response_data;
    logic [DATA_WIDTH-1:0] vector_response_scale;
    logic sram_read_enable;
    logic [BUFFER_ID_WIDTH-1:0] sram_read_buffer_id;
    logic [OFFSET_WIDTH-1:0] sram_read_offset;
    logic sram_read_valid;
    logic [DATA_WIDTH-1:0] sram_read_data;
    logic [DATA_WIDTH-1:0] sram_read_scale;
    logic protocol_error;
    logic previous_grant_valid;
    logic previous_grant_vector;
    integer gemm_grants;
    integer vector_grants;
    integer gemm_responses;
    integer vector_responses;
    integer checks;

    npu_local_activation_read_arbiter #(
        .DATA_WIDTH(DATA_WIDTH),
        .BUFFER_ID_WIDTH(BUFFER_ID_WIDTH),
        .OFFSET_WIDTH(OFFSET_WIDTH)
    ) u_dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .gemm_valid_i(gemm_valid),
        .gemm_ready_o(gemm_ready),
        .gemm_buffer_id_i(gemm_buffer_id),
        .gemm_offset_i(gemm_offset),
        .gemm_response_valid_o(gemm_response_valid),
        .gemm_response_data_o(gemm_response_data),
        .gemm_response_scale_o(gemm_response_scale),
        .vector_valid_i(vector_valid),
        .vector_ready_o(vector_ready),
        .vector_buffer_id_i(vector_buffer_id),
        .vector_offset_i(vector_offset),
        .vector_response_valid_o(vector_response_valid),
        .vector_response_data_o(vector_response_data),
        .vector_response_scale_o(vector_response_scale),
        .sram_read_enable_o(sram_read_enable),
        .sram_read_buffer_id_o(sram_read_buffer_id),
        .sram_read_offset_o(sram_read_offset),
        .sram_read_valid_i(sram_read_valid),
        .sram_read_data_i(sram_read_data),
        .sram_read_scale_i(sram_read_scale),
        .protocol_error_o(protocol_error)
    );

    always #2 clk_i = ~clk_i;

    // One-cycle registered SRAM contract used by the production tensor buffer.
    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            sram_read_valid <= 1'b0;
            sram_read_data <= '0;
            sram_read_scale <= '0;
        end else begin
            sram_read_valid <= sram_read_enable;
            if (sram_read_enable) begin
                sram_read_data <= sram_read_offset ^
                    {{(DATA_WIDTH-BUFFER_ID_WIDTH){1'b0}}, sram_read_buffer_id};
                sram_read_scale <= ~(sram_read_offset ^
                    {{(DATA_WIDTH-BUFFER_ID_WIDTH){1'b0}}, sram_read_buffer_id});
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            previous_grant_valid <= 1'b0;
            previous_grant_vector <= 1'b0;
            gemm_grants <= 0;
            vector_grants <= 0;
            gemm_responses <= 0;
            vector_responses <= 0;
        end else begin
            if (gemm_valid && vector_valid && sram_read_enable) begin
                if (previous_grant_valid &&
                    (previous_grant_vector == vector_ready)) begin
                    $fatal(1, "FAIL: round-robin repeated one client under contention");
                end
                previous_grant_valid <= 1'b1;
                previous_grant_vector <= vector_ready;
            end else begin
                previous_grant_valid <= 1'b0;
            end

            if (gemm_valid && gemm_ready) begin
                gemm_grants <= gemm_grants + 1;
            end
            if (vector_valid && vector_ready) begin
                vector_grants <= vector_grants + 1;
            end
            if (gemm_response_valid) begin
                if ((gemm_response_data != (gemm_offset ^
                     {{(DATA_WIDTH-BUFFER_ID_WIDTH){1'b0}}, gemm_buffer_id})) ||
                    (gemm_response_scale != ~(gemm_offset ^
                     {{(DATA_WIDTH-BUFFER_ID_WIDTH){1'b0}}, gemm_buffer_id}))) begin
                    $fatal(1, "FAIL: GEMM response payload was misrouted");
                end
                gemm_responses <= gemm_responses + 1;
            end
            if (vector_response_valid) begin
                if ((vector_response_data != (vector_offset ^
                     {{(DATA_WIDTH-BUFFER_ID_WIDTH){1'b0}}, vector_buffer_id})) ||
                    (vector_response_scale != ~(vector_offset ^
                     {{(DATA_WIDTH-BUFFER_ID_WIDTH){1'b0}}, vector_buffer_id}))) begin
                    $fatal(1, "FAIL: Vector response payload was misrouted");
                end
                vector_responses <= vector_responses + 1;
            end
            if (gemm_response_valid && vector_response_valid) begin
                $fatal(1, "FAIL: one SRAM response reached both clients");
            end
        end
    end

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        gemm_valid = 1'b0;
        gemm_buffer_id = 4'ha;
        gemm_offset = 32'h0123_4560;
        vector_valid = 1'b0;
        vector_buffer_id = 4'h5;
        vector_offset = 32'h0765_4320;
        checks = 0;

        repeat (4) @(negedge clk_i);
        rst_i = 1'b0;
        gemm_valid = 1'b1;
        vector_valid = 1'b1;

        repeat (CONTENTION_CYCLES) @(negedge clk_i);
        gemm_valid = 1'b0;
        vector_valid = 1'b0;
        repeat (3) @(negedge clk_i);

        if ((gemm_grants != CONTENTION_CYCLES / 2) ||
            (vector_grants != CONTENTION_CYCLES / 2) ||
            (gemm_responses != gemm_grants) ||
            (vector_responses != vector_grants)) begin
            $fatal(1, "FAIL: fairness counts gemm=%0d/%0d vector=%0d/%0d",
                   gemm_responses, gemm_grants,
                   vector_responses, vector_grants);
        end
        checks = checks + 1;

        gemm_valid = 1'b1;
        repeat (4) @(negedge clk_i);
        gemm_valid = 1'b0;
        repeat (2) @(negedge clk_i);
        if ((gemm_grants != CONTENTION_CYCLES / 2 + 4) ||
            (gemm_responses != gemm_grants) || protocol_error) begin
            $fatal(1, "FAIL: uncontended GEMM service or protocol closure");
        end
        checks = checks + 1;

        $display("[RTL_SIM PASS] activation_read_fairness grants=%0d/%0d checks=%0d",
                 gemm_grants, vector_grants, checks);
        $finish;
    end

    initial begin
        repeat (200) @(posedge clk_i);
        $fatal(1, "FAIL: Activation read fairness timeout");
    end

endmodule

`default_nettype wire
