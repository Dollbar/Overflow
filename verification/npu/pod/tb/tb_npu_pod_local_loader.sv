`timescale 1ns/1ps
`default_nettype none

module tb_npu_pod_local_loader;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic quiesce_i;
    logic command_valid_i;
    logic command_ready_o;
    logic [npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0] command_i;
    npu_pod_pkg::npu_pod_local_transfer_t command_fields;
    logic shared_read_request_valid_o;
    logic shared_read_request_ready_i;
    logic [23:0] shared_read_request_address_o;
    logic shared_read_response_valid_i;
    logic shared_read_response_ready_o;
    logic [1023:0] shared_read_response_data_i;
    logic tensor_write_valid_o;
    logic tensor_write_ready_i;
    logic tensor_write_weight_o;
    logic [3:0] tensor_write_buffer_id_o;
    logic [3:0] tensor_write_bank_o;
    logic [31:0] tensor_write_offset_o;
    logic [127:0] tensor_write_data_o;
    logic [127:0] tensor_write_scale_o;
    logic vector_write_valid_o;
    logic vector_write_ready_i;
    logic vector_write_c_o;
    logic [3:0] vector_write_buffer_id_o;
    logic [3:0] vector_write_bank_o;
    logic [31:0] vector_write_offset_o;
    logic [127:0] vector_write_data_o;
    logic [7:0] vector_write_scale_o;
    logic completion_valid_o;
    logic completion_ready_i;
    logic [npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH-1:0]
          completion_o;
    npu_pod_pkg::npu_pod_local_completion_t completion_fields;
    logic busy_o;
    logic quiesced_o;
    logic protocol_error_o;
    logic [1023:0] test_data;
    logic [1023:0] test_scale;
    integer checked_writes;

    assign command_i = command_fields;
    assign completion_fields = completion_o;

    npu_pod_local_loader dut (
        .clk_i,
        .rst_i,
        .clear_i,
        .quiesce_i,
        .command_valid_i,
        .command_ready_o,
        .command_i,
        .shared_read_request_valid_o,
        .shared_read_request_ready_i,
        .shared_read_request_address_o,
        .shared_read_response_valid_i,
        .shared_read_response_ready_o,
        .shared_read_response_data_i,
        .tensor_write_valid_o,
        .tensor_write_ready_i,
        .tensor_write_weight_o,
        .tensor_write_buffer_id_o,
        .tensor_write_bank_o,
        .tensor_write_offset_o,
        .tensor_write_data_o,
        .tensor_write_scale_o,
        .vector_write_valid_o,
        .vector_write_ready_i,
        .vector_write_c_o,
        .vector_write_buffer_id_o,
        .vector_write_bank_o,
        .vector_write_offset_o,
        .vector_write_data_o,
        .vector_write_scale_o,
        .completion_valid_o,
        .completion_ready_i,
        .completion_o,
        .busy_o,
        .quiesced_o,
        .protocol_error_o
    );

    always #0.5 clk_i = ~clk_i;

    task automatic submit_command;
        input logic [15:0] transfer_id;
        input npu_pod_pkg::npu_pod_local_target_e target;
        input logic [3:0] buffer_id;
        input logic [3:0] bank_start;
        input logic [31:0] local_offset;
        input logic [23:0] data_address;
        input logic [23:0] scale_address;
        input logic [3:0] word_count;
        begin
            @(negedge clk_i);
            command_fields.version =
                npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_VERSION;
            command_fields.transfer_id = transfer_id;
            command_fields.target = target;
            command_fields.buffer_id = buffer_id;
            command_fields.bank_start = bank_start;
            command_fields.local_offset = local_offset;
            command_fields.data_sram_address = data_address;
            command_fields.scale_sram_address = scale_address;
            command_fields.word_count = word_count;
            command_valid_i = 1'b1;
            while (!command_ready_o) begin
                @(negedge clk_i);
            end
            @(posedge clk_i);
            @(negedge clk_i);
            command_valid_i = 1'b0;
        end
    endtask

    task automatic serve_read;
        input logic [23:0] expected_address;
        input logic [1023:0] response_data;
        begin
            while (!shared_read_request_valid_o) begin
                @(negedge clk_i);
            end
            if (shared_read_request_address_o != expected_address) begin
                $fatal(1, "shared SRAM address mismatch");
            end
            repeat (2) @(negedge clk_i);
            shared_read_request_ready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            shared_read_request_ready_i = 1'b0;
            shared_read_response_data_i = response_data;
            shared_read_response_valid_i = 1'b1;
            while (!shared_read_response_ready_o) begin
                @(negedge clk_i);
            end
            @(posedge clk_i);
            @(negedge clk_i);
            shared_read_response_valid_i = 1'b0;
        end
    endtask

    task automatic check_tensor_writes;
        input integer count;
        input logic weight;
        input logic [3:0] buffer_id;
        input logic [3:0] bank_start;
        input logic [31:0] offset;
        begin
            tensor_write_ready_i = 1'b0;
            while (!tensor_write_valid_o) begin
                @(negedge clk_i);
            end
            repeat (3) begin
                logic [127:0] held_data;
                held_data = tensor_write_data_o;
                @(posedge clk_i);
                @(negedge clk_i);
                if (!tensor_write_valid_o ||
                    (tensor_write_data_o != held_data)) begin
                    $fatal(1, "tensor write changed under backpressure");
                end
            end
            tensor_write_ready_i = 1'b1;
            for (integer word_index = 0; word_index < count; word_index++) begin
                if (!tensor_write_valid_o ||
                    (tensor_write_weight_o != weight) ||
                    (tensor_write_buffer_id_o != buffer_id) ||
                    (tensor_write_bank_o !=
                     4'(int'(bank_start) + word_index)) ||
                    (tensor_write_offset_o != offset) ||
                    (tensor_write_data_o !=
                     test_data[word_index*128 +: 128]) ||
                    (tensor_write_scale_o !=
                     test_scale[word_index*128 +: 128])) begin
                    $fatal(1, "tensor write mismatch word=%0d", word_index);
                end
                @(posedge clk_i);
                @(negedge clk_i);
                checked_writes = checked_writes + 1;
            end
            tensor_write_ready_i = 1'b0;
        end
    endtask

    task automatic check_completion;
        input logic [15:0] transfer_id;
        input logic success;
        input npu_pod_pkg::npu_pod_local_error_e error_code;
        begin
            while (!completion_valid_o) begin
                @(negedge clk_i);
            end
            if ((completion_fields.transfer_id != transfer_id) ||
                (completion_fields.success != success) ||
                (completion_fields.error_code != error_code)) begin
                $fatal(1, "local-loader completion mismatch");
            end
            repeat (2) begin
                @(posedge clk_i);
                @(negedge clk_i);
                if (!completion_valid_o ||
                    (completion_fields.transfer_id != transfer_id)) begin
                    $fatal(1, "completion changed under backpressure");
                end
            end
            completion_ready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            completion_ready_i = 1'b0;
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        quiesce_i = 1'b0;
        command_valid_i = 1'b0;
        command_fields = '0;
        shared_read_request_ready_i = 1'b0;
        shared_read_response_valid_i = 1'b0;
        shared_read_response_data_i = '0;
        tensor_write_ready_i = 1'b0;
        vector_write_ready_i = 1'b0;
        completion_ready_i = 1'b0;
        checked_writes = 0;
        for (integer word_index = 0; word_index < 8; word_index++) begin
            test_data[word_index*128 +: 128] =
                {32{4'(word_index + 1)}};
            test_scale[word_index*128 +: 128] =
                {16{8'(8'h80 + word_index)}};
        end

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        submit_command(16'h0101,
            npu_pod_pkg::NPU_POD_TARGET_TENSOR_WEIGHT,
            4'd1, 4'd2, 32'h0000_0040, 24'h000100, 24'h000200, 4'd3);
        serve_read(24'h000100, test_data);
        serve_read(24'h000200, test_scale);
        check_tensor_writes(3, 1'b1, 4'd1, 4'd2, 32'h0000_0040);
        check_completion(16'h0101, 1'b1, npu_pod_pkg::NPU_POD_LOCAL_OK);

        submit_command(16'h0202,
            npu_pod_pkg::NPU_POD_TARGET_VECTOR_C,
            4'd2, 4'd7, 32'h0000_0080, 24'h000300, 24'h000400, 4'd2);
        serve_read(24'h000300, test_data);
        serve_read(24'h000400, test_scale);
        vector_write_ready_i = 1'b1;
        for (integer word_index = 0; word_index < 2; word_index++) begin
            while (!vector_write_valid_o) @(negedge clk_i);
            if (!vector_write_c_o ||
                (vector_write_buffer_id_o != 4'd2) ||
                (vector_write_bank_o != 4'(7 + word_index)) ||
                (vector_write_offset_o != 32'h0000_0080) ||
                (vector_write_data_o != test_data[word_index*128 +: 128]) ||
                (vector_write_scale_o != test_scale[word_index*8 +: 8])) begin
                $fatal(1, "vector write mismatch word=%0d", word_index);
            end
            @(posedge clk_i);
            @(negedge clk_i);
            checked_writes = checked_writes + 1;
        end
        vector_write_ready_i = 1'b0;
        check_completion(16'h0202, 1'b1, npu_pod_pkg::NPU_POD_LOCAL_OK);

        quiesce_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        if (!quiesced_o || command_ready_o || busy_o) begin
            $fatal(1, "loader quiesce mismatch");
        end
        quiesce_i = 1'b0;

        command_fields.version =
            npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_VERSION;
        command_fields.transfer_id = 16'h0bad;
        command_fields.target =
            npu_pod_pkg::NPU_POD_TARGET_TENSOR_ACTIVATION;
        command_fields.buffer_id = 4'd0;
        command_fields.bank_start = 4'd0;
        command_fields.local_offset = 32'd0;
        command_fields.data_sram_address = 24'h000001;
        command_fields.scale_sram_address = 24'h000080;
        command_fields.word_count = 4'd1;
        command_valid_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        command_valid_i = 1'b0;
        if (shared_read_request_valid_o) begin
            $fatal(1, "malformed command issued shared SRAM read");
        end
        check_completion(16'h0bad, 1'b0,
            npu_pod_pkg::NPU_POD_LOCAL_ERROR_ALIGNMENT);
        if (!protocol_error_o) begin
            $fatal(1, "malformed command did not set protocol error");
        end

        $display("[RTL_SIM PASS] npu_pod_local_loader checked_writes=%0d",
                 checked_writes);
        $finish;
    end

endmodule

`default_nettype wire
