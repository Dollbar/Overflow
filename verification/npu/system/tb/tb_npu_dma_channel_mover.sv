`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_channel_mover;

    localparam int unsigned QUEUE_DEPTH = 256;
    localparam int unsigned SRAM_WORDS = 512;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic command_valid_i;
    logic command_ready_o;
    logic [npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0] command_i;
    npu_dma_pkg::npu_dma_command_t command_fields;
    logic hbm_request_valid_o;
    logic hbm_request_ready_i;
    logic hbm_request_write_o;
    logic [34:0] hbm_request_address_o;
    logic [1023:0] hbm_request_write_data_o;
    logic [127:0] hbm_request_byte_enable_o;
    logic [1:0] hbm_request_qos_o;
    logic [7:0] hbm_request_local_tag_i;
    logic hbm_response_valid_i;
    logic hbm_response_ready_o;
    logic hbm_response_write_i;
    logic [7:0] hbm_response_local_tag_i;
    logic [1023:0] hbm_response_read_data_i;
    logic [1:0] hbm_response_status_i;
    logic sram_read_request_valid_o;
    logic sram_read_request_ready_i;
    logic [23:0] sram_read_request_address_o;
    logic sram_read_response_valid_i;
    logic sram_read_response_ready_o;
    logic [1023:0] sram_read_response_data_i;
    logic sram_write_valid_o;
    logic sram_write_ready_i;
    logic [23:0] sram_write_address_o;
    logic [1023:0] sram_write_data_o;
    logic [127:0] sram_write_byte_enable_o;
    logic completion_valid_o;
    logic completion_ready_i;
    logic [npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH-1:0] completion_o;
    npu_dma_pkg::npu_dma_completion_t completion_fields;
    logic busy_o;
    logic [8:0] outstanding_o;
    logic protocol_error_o;

    logic [1023:0] sram_memory [0:SRAM_WORDS-1];
    logic sram_response_valid_q;
    logic [1023:0] sram_response_data_q;
    logic [31:0] lfsr_q;
    logic [7:0] next_tag_q;
    logic response_present_q;
    integer response_head_q;
    integer response_tail_q;
    integer response_count_q;
    logic response_write_queue [0:QUEUE_DEPTH-1];
    logic [7:0] response_tag_queue [0:QUEUE_DEPTH-1];
    logic [1023:0] response_data_queue [0:QUEUE_DEPTH-1];
    logic [1:0] response_status_queue [0:QUEUE_DEPTH-1];
    integer command_request_index_q;
    integer inject_status_index;
    logic [1:0] inject_status_code;
    logic [1023:0] expected_write_data [0:63];
    integer expected_write_count;
    integer hbm_request_count;
    integer hbm_response_count;
    integer sram_read_count;
    integer sram_write_count;
    logic held_request_q;
    logic held_request_write_q;
    logic [34:0] held_request_address_q;
    logic [1023:0] held_request_data_q;
    logic [127:0] held_request_enable_q;
    logic [1:0] held_request_qos_q;

    assign command_i = command_fields;
    assign completion_fields = completion_o;
    assign hbm_request_local_tag_i = next_tag_q;
    assign hbm_response_valid_i = response_present_q;
    assign hbm_response_write_i =
        response_write_queue[response_head_q];
    assign hbm_response_local_tag_i =
        response_tag_queue[response_head_q];
    assign hbm_response_read_data_i =
        response_data_queue[response_head_q];
    assign hbm_response_status_i =
        response_status_queue[response_head_q];
    assign sram_read_request_ready_i =
        (!sram_response_valid_q || sram_read_response_ready_o) && lfsr_q[3];
    assign sram_read_response_valid_i = sram_response_valid_q;
    assign sram_read_response_data_i = sram_response_data_q;
    assign sram_write_ready_i = lfsr_q[5] | lfsr_q[9];

    npu_dma_channel_mover dut (
        .clk_i,
        .rst_i,
        .clear_i,
        .command_valid_i,
        .command_ready_o,
        .command_i,
        .hbm_request_valid_o,
        .hbm_request_ready_i,
        .hbm_request_write_o,
        .hbm_request_address_o,
        .hbm_request_write_data_o,
        .hbm_request_byte_enable_o,
        .hbm_request_qos_o,
        .hbm_request_local_tag_i,
        .hbm_response_valid_i,
        .hbm_response_ready_o,
        .hbm_response_write_i,
        .hbm_response_local_tag_i,
        .hbm_response_read_data_i,
        .hbm_response_status_i,
        .sram_read_request_valid_o,
        .sram_read_request_ready_i,
        .sram_read_request_address_o,
        .sram_read_response_valid_i,
        .sram_read_response_ready_o,
        .sram_read_response_data_i,
        .sram_write_valid_o,
        .sram_write_ready_i,
        .sram_write_address_o,
        .sram_write_data_o,
        .sram_write_byte_enable_o,
        .completion_valid_o,
        .completion_ready_i,
        .completion_o,
        .busy_o,
        .outstanding_o,
        .protocol_error_o
    );

    always #0.5 clk_i = ~clk_i;

    always_ff @(posedge clk_i) begin
        logic request_fire;
        logic response_fire;
        logic sram_read_fire;
        logic sram_response_fire;
        logic sram_write_fire;
        logic [31:0] read_pattern;
        integer word_index;
        request_fire = hbm_request_valid_o && hbm_request_ready_i;
        response_fire = hbm_response_valid_i && hbm_response_ready_o;
        sram_read_fire = sram_read_request_valid_o &&
                         sram_read_request_ready_i;
        sram_response_fire = sram_read_response_valid_i &&
                             sram_read_response_ready_o;
        sram_write_fire = sram_write_valid_o && sram_write_ready_i;
        if (rst_i || clear_i) begin
            lfsr_q <= 32'h6d3a_91c7;
            hbm_request_ready_i <= 1'b0;
            next_tag_q <= 8'd0;
            response_present_q <= 1'b0;
            response_head_q <= 0;
            response_tail_q <= 0;
            response_count_q <= 0;
            command_request_index_q <= 0;
            sram_response_valid_q <= 1'b0;
            sram_response_data_q <= '0;
            hbm_request_count <= 0;
            hbm_response_count <= 0;
            sram_read_count <= 0;
            sram_write_count <= 0;
            held_request_q <= 1'b0;
            held_request_write_q <= 1'b0;
            held_request_address_q <= '0;
            held_request_data_q <= '0;
            held_request_enable_q <= '0;
            held_request_qos_q <= '0;
        end else begin
            lfsr_q <= {lfsr_q[30:0],
                lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
            hbm_request_ready_i <= lfsr_q[0] | lfsr_q[7];

            if (hbm_request_valid_o && !hbm_request_ready_i) begin
                if (held_request_q &&
                    ((hbm_request_write_o != held_request_write_q) ||
                     (hbm_request_address_o != held_request_address_q) ||
                     (hbm_request_write_data_o != held_request_data_q) ||
                     (hbm_request_byte_enable_o != held_request_enable_q) ||
                     (hbm_request_qos_o != held_request_qos_q))) begin
                    $fatal(1, "HBM request changed under backpressure");
                end
                held_request_q <= 1'b1;
                held_request_write_q <= hbm_request_write_o;
                held_request_address_q <= hbm_request_address_o;
                held_request_data_q <= hbm_request_write_data_o;
                held_request_enable_q <= hbm_request_byte_enable_o;
                held_request_qos_q <= hbm_request_qos_o;
            end else begin
                held_request_q <= 1'b0;
            end

            if (request_fire) begin
                if (hbm_request_byte_enable_o != {128{1'b1}}) begin
                    $fatal(1, "HBM request byte enable is not full-beat");
                end
                if (hbm_request_write_o) begin
                    if ((command_request_index_q >= expected_write_count) ||
                        (hbm_request_write_data_o !=
                         expected_write_data[command_request_index_q])) begin
                        $fatal(1, "HBM write data mismatch beat=%0d",
                               command_request_index_q);
                    end
                end
                response_write_queue[response_tail_q] <=
                    hbm_request_write_o;
                response_tag_queue[response_tail_q] <= next_tag_q;
                read_pattern = hbm_request_address_o[31:0] ^ 32'h5a93_c17e;
                response_data_queue[response_tail_q] <= {32{read_pattern}};
                response_status_queue[response_tail_q] <=
                    (command_request_index_q == inject_status_index) ?
                    inject_status_code : 2'd0;
                response_tail_q <= (response_tail_q + 1) % QUEUE_DEPTH;
                next_tag_q <= next_tag_q + 8'd1;
                command_request_index_q <= command_request_index_q + 1;
                hbm_request_count <= hbm_request_count + 1;
            end

            if (response_fire) begin
                response_present_q <= 1'b0;
                response_head_q <= (response_head_q + 1) % QUEUE_DEPTH;
                hbm_response_count <= hbm_response_count + 1;
            end else if (!response_present_q && (response_count_q != 0) &&
                         (lfsr_q[2] || lfsr_q[11])) begin
                response_present_q <= 1'b1;
            end

            case ({request_fire, response_fire})
                2'b10: response_count_q <= response_count_q + 1;
                2'b01: response_count_q <= response_count_q - 1;
                default: response_count_q <= response_count_q;
            endcase

            if (sram_response_fire) begin
                sram_response_valid_q <= 1'b0;
            end
            if (sram_read_fire) begin
                if (sram_read_request_address_o[6:0] != 7'd0) begin
                    $fatal(1, "SRAM read address is misaligned");
                end
                word_index = int'(sram_read_request_address_o) >> 7;
                if (word_index >= SRAM_WORDS) begin
                    $fatal(1, "SRAM read address exceeds test memory");
                end
                sram_response_valid_q <= 1'b1;
                sram_response_data_q <= sram_memory[word_index];
                sram_read_count <= sram_read_count + 1;
            end

            if (sram_write_fire) begin
                if (sram_write_byte_enable_o != {128{1'b1}}) begin
                    $fatal(1, "SRAM write byte enable is not full-beat");
                end
                word_index = int'(sram_write_address_o) >> 7;
                if (word_index >= SRAM_WORDS) begin
                    $fatal(1, "SRAM write address exceeds test memory");
                end
                sram_memory[word_index] <= sram_write_data_o;
                sram_write_count <= sram_write_count + 1;
            end
        end
    end

    task automatic submit_command;
        input logic [3:0] version;
        input logic [1:0] operation;
        input logic [15:0] command_id;
        input logic [34:0] hbm_base;
        input logic [23:0] sram_base;
        input logic [17:0] x_count;
        input logic [15:0] y_count;
        input logic [34:0] hbm_y_stride;
        input logic [23:0] sram_y_stride;
        begin
            @(negedge clk_i);
            command_fields = '0;
            command_fields.version = version;
            command_fields.operation =
                npu_dma_pkg::npu_dma_operation_e'(operation);
            command_fields.command_id = command_id;
            command_fields.hbm_base_address = hbm_base;
            command_fields.sram_base_address = sram_base;
            command_fields.x_beat_count = x_count;
            command_fields.y_count = y_count;
            command_fields.z_count = 16'd1;
            command_fields.hbm_y_stride = hbm_y_stride;
            command_fields.hbm_z_stride = 35'd0;
            command_fields.sram_y_stride = sram_y_stride;
            command_fields.sram_z_stride = 24'd0;
            command_fields.qos = 2'd2;
            command_request_index_q = 0;
            command_valid_i = 1'b1;
            while (!command_ready_o) begin
                @(negedge clk_i);
            end
            @(posedge clk_i);
            @(negedge clk_i);
            command_valid_i = 1'b0;
        end
    endtask

    task automatic check_completion;
        input logic [15:0] expected_id;
        input logic expected_success;
        input logic [2:0] expected_code;
        input logic expected_corrected;
        input logic [17:0] expected_beats;
        logic [npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH-1:0] held_completion;
        begin
            while (!completion_valid_o) begin
                @(negedge clk_i);
            end
            if ((completion_fields.command_id != expected_id) ||
                (completion_fields.success != expected_success) ||
                (completion_fields.error_code != expected_code) ||
                (completion_fields.corrected_ecc_seen != expected_corrected) ||
                (completion_fields.beats_completed != expected_beats)) begin
                $fatal(1, "completion mismatch id=%0d success=%0b code=%0d corrected=%0b beats=%0d",
                       completion_fields.command_id, completion_fields.success,
                       completion_fields.error_code,
                       completion_fields.corrected_ecc_seen,
                       completion_fields.beats_completed);
            end
            held_completion = completion_o;
            completion_ready_i = 1'b0;
            repeat (3) begin
                @(posedge clk_i);
                @(negedge clk_i);
                if (!completion_valid_o || (completion_o != held_completion)) begin
                    $fatal(1, "completion changed under backpressure");
                end
            end
            completion_ready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            completion_ready_i = 1'b0;
            if (completion_valid_o) begin
                $fatal(1, "completion did not retire");
            end
        end
    endtask

    initial begin
        integer index;
        logic [31:0] read_pattern;
        integer request_start;
        integer response_start;
        integer sram_read_start;
        integer sram_write_start;
        integer final_hbm_requests;
        integer final_hbm_responses;
        integer final_sram_reads;
        integer final_sram_writes;
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        command_valid_i = 1'b0;
        command_fields = '0;
        completion_ready_i = 1'b0;
        inject_status_index = -1;
        inject_status_code = 2'd0;
        expected_write_count = 0;
        for (index = 0; index < SRAM_WORDS; index++) begin
            sram_memory[index] = '0;
        end

        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        request_start = hbm_request_count;
        response_start = hbm_response_count;
        sram_read_start = sram_read_count;
        sram_write_start = sram_write_count;
        inject_status_index = 2;
        inject_status_code = 2'd1;
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h4101,
            35'h0001_0000, 24'h000000, 18'd4, 16'd2,
            35'd1024, 24'd1024);
        check_completion(16'h4101, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_OK, 1'b1, 18'd8);
        if (((hbm_request_count-request_start) != 8) ||
            ((hbm_response_count-response_start) != 8) ||
            ((sram_read_count-sram_read_start) != 0) ||
            ((sram_write_count-sram_write_start) != 8)) begin
            $fatal(1, "HBM-to-SRAM traffic accounting mismatch");
        end
        for (index = 0; index < 4; index++) begin
            read_pattern = (32'h0001_0000 + index*128) ^ 32'h5a93_c17e;
            if (sram_memory[index] != {32{read_pattern}}) begin
                $fatal(1, "first read row data mismatch index=%0d", index);
            end
            read_pattern = (32'h0001_0000 + 1024 + index*128) ^
                           32'h5a93_c17e;
            if (sram_memory[8+index] != {32{read_pattern}}) begin
                $fatal(1, "second read row data mismatch index=%0d", index);
            end
        end
        if (protocol_error_o) begin
            $fatal(1, "corrected read raised protocol error");
        end

        for (index = 32; index < 37; index++) begin
            sram_memory[index] = {32{32'hdead_0000 + index}};
        end
        request_start = hbm_request_count;
        response_start = hbm_response_count;
        sram_write_start = sram_write_count;
        inject_status_index = 3;
        inject_status_code = 2'd2;
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h4102,
            35'h0002_0000, 24'h001000, 18'd5, 16'd1,
            35'd0, 24'd0);
        check_completion(16'h4102, 1'b0,
            npu_dma_pkg::NPU_DMA_ERROR_HBM_UNCORRECTABLE, 1'b0, 18'd4);
        if (((hbm_request_count-request_start) != 5) ||
            ((hbm_response_count-response_start) != 5) ||
            ((sram_write_count-sram_write_start) != 4) ||
            (sram_memory[35] != {32{32'hdead_0023}})) begin
            $fatal(1, "uncorrectable read handling mismatch");
        end
        if (protocol_error_o) begin
            $fatal(1, "HBM status error raised protocol error");
        end

        for (index = 0; index < 6; index++) begin
            expected_write_data[index] = {32{32'h7100_0000 + index}};
            sram_memory[64+index] = expected_write_data[index];
        end
        expected_write_count = 6;
        request_start = hbm_request_count;
        response_start = hbm_response_count;
        sram_read_start = sram_read_count;
        sram_write_start = sram_write_count;
        inject_status_index = 4;
        inject_status_code = 2'd3;
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_SRAM_TO_HBM, 16'h4103,
            35'h0003_0000, 24'h002000, 18'd6, 16'd1,
            35'd0, 24'd0);
        check_completion(16'h4103, 1'b0,
            npu_dma_pkg::NPU_DMA_ERROR_HBM_DATA, 1'b0, 18'd5);
        if (((hbm_request_count-request_start) != 6) ||
            ((hbm_response_count-response_start) != 6) ||
            ((sram_read_count-sram_read_start) != 6) ||
            ((sram_write_count-sram_write_start) != 0)) begin
            $fatal(1, "SRAM-to-HBM traffic accounting mismatch");
        end
        if (protocol_error_o) begin
            $fatal(1, "write data status raised protocol error");
        end

        inject_status_index = -1;
        inject_status_code = 2'd0;
        request_start = hbm_request_count;
        submit_command(4'd0, npu_dma_pkg::NPU_DMA_HBM_TO_SRAM,
            16'h41ff, 35'h40000, 24'h4000, 18'd1, 16'd1,
            35'd0, 24'd0);
        check_completion(16'h41ff, 1'b0,
            npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR, 1'b0, 18'd0);
        if ((hbm_request_count != request_start) || !protocol_error_o) begin
            $fatal(1, "malformed command side-effect handling mismatch");
        end

        final_hbm_requests = hbm_request_count;
        final_hbm_responses = hbm_response_count;
        final_sram_reads = sram_read_count;
        final_sram_writes = sram_write_count;

        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;
        if (busy_o || (outstanding_o != 9'd0) || protocol_error_o) begin
            $fatal(1, "clear did not restore mover idle state");
        end

        $display("[RTL_SIM PASS] npu_dma_channel_mover requests=%0d responses=%0d sram_reads=%0d sram_writes=%0d",
                 final_hbm_requests, final_hbm_responses,
                 final_sram_reads, final_sram_writes);
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "npu_dma_channel_mover timeout");
    end

endmodule

`default_nettype wire
