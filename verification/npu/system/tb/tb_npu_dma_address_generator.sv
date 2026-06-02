`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_address_generator;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic command_valid_i;
    logic command_ready_o;
    logic [npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0] command_i;
    npu_dma_pkg::npu_dma_command_t command_fields;
    logic beat_valid_o;
    logic beat_ready_i;
    logic [1:0] beat_operation_o;
    logic [15:0] beat_command_id_o;
    logic [34:0] beat_hbm_address_o;
    logic [23:0] beat_sram_address_o;
    logic [1:0] beat_qos_o;
    logic beat_first_o;
    logic beat_last_o;
    logic sequence_done_valid_o;
    logic sequence_done_ready_i;
    logic [15:0] sequence_done_command_id_o;
    logic sequence_done_error_o;
    logic [2:0] sequence_done_error_code_o;
    logic [17:0] sequence_done_beats_o;
    logic busy_o;
    logic protocol_error_o;
    integer checked_beats;
    integer checked_commands;

    assign command_i = command_fields;

    npu_dma_address_generator dut (
        .clk_i,
        .rst_i,
        .clear_i,
        .command_valid_i,
        .command_ready_o,
        .command_i,
        .beat_valid_o,
        .beat_ready_i,
        .beat_operation_o,
        .beat_command_id_o,
        .beat_hbm_address_o,
        .beat_sram_address_o,
        .beat_qos_o,
        .beat_first_o,
        .beat_last_o,
        .sequence_done_valid_o,
        .sequence_done_ready_i,
        .sequence_done_command_id_o,
        .sequence_done_error_o,
        .sequence_done_error_code_o,
        .sequence_done_beats_o,
        .busy_o,
        .protocol_error_o
    );

    always #0.5 clk_i = ~clk_i;

    task automatic submit_command;
        input logic [3:0] version;
        input logic [1:0] operation;
        input logic [15:0] command_id;
        input logic [34:0] hbm_base;
        input logic [23:0] sram_base;
        input logic [17:0] x_count;
        input logic [15:0] y_count;
        input logic [15:0] z_count;
        input logic [34:0] hbm_y_stride;
        input logic [34:0] hbm_z_stride;
        input logic [23:0] sram_y_stride;
        input logic [23:0] sram_z_stride;
        input logic [1:0] qos;
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
            command_fields.z_count = z_count;
            command_fields.hbm_y_stride = hbm_y_stride;
            command_fields.hbm_z_stride = hbm_z_stride;
            command_fields.sram_y_stride = sram_y_stride;
            command_fields.sram_z_stride = sram_z_stride;
            command_fields.qos = qos;
            command_valid_i = 1'b1;
            while (!command_ready_o) begin
                @(negedge clk_i);
            end
            @(posedge clk_i);
            @(negedge clk_i);
            command_valid_i = 1'b0;
        end
    endtask

    task automatic consume_done;
        input logic [15:0] expected_command_id;
        input logic expected_error;
        input logic [2:0] expected_error_code;
        input logic [17:0] expected_beats;
        logic [15:0] held_command_id;
        logic held_error;
        logic [2:0] held_error_code;
        logic [17:0] held_beats;
        begin
            while (!sequence_done_valid_o) begin
                @(negedge clk_i);
            end
            if ((sequence_done_command_id_o != expected_command_id) ||
                (sequence_done_error_o != expected_error) ||
                (sequence_done_error_code_o != expected_error_code) ||
                (sequence_done_beats_o != expected_beats)) begin
                $fatal(1, "completion mismatch id=%0d error=%0b code=%0d beats=%0d",
                       sequence_done_command_id_o, sequence_done_error_o,
                       sequence_done_error_code_o, sequence_done_beats_o);
            end
            held_command_id = sequence_done_command_id_o;
            held_error = sequence_done_error_o;
            held_error_code = sequence_done_error_code_o;
            held_beats = sequence_done_beats_o;
            sequence_done_ready_i = 1'b0;
            repeat (3) begin
                @(posedge clk_i);
                @(negedge clk_i);
                if (!sequence_done_valid_o ||
                    (sequence_done_command_id_o != held_command_id) ||
                    (sequence_done_error_o != held_error) ||
                    (sequence_done_error_code_o != held_error_code) ||
                    (sequence_done_beats_o != held_beats)) begin
                    $fatal(1, "completion changed under backpressure");
                end
            end
            sequence_done_ready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            sequence_done_ready_i = 1'b0;
            if (sequence_done_valid_o) begin
                $fatal(1, "completion did not retire");
            end
            checked_commands = checked_commands + 1;
        end
    endtask

    task automatic run_sequence;
        input logic [1:0] operation;
        input logic [15:0] command_id;
        input logic [34:0] hbm_base;
        input logic [23:0] sram_base;
        input logic [17:0] x_count;
        input logic [15:0] y_count;
        input logic [15:0] z_count;
        input logic [34:0] hbm_y_stride;
        input logic [34:0] hbm_z_stride;
        input logic [23:0] sram_y_stride;
        input logic [23:0] sram_z_stride;
        input logic [1:0] qos;
        integer x_index;
        integer y_index;
        integer z_index;
        integer accepted;
        logic [31:0] random_state;
        logic held_valid;
        logic [34:0] held_hbm_address;
        logic [23:0] held_sram_address;
        logic held_first;
        logic held_last;
        logic [34:0] expected_hbm_address;
        logic [23:0] expected_sram_address;
        begin
            submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION, operation,
                command_id, hbm_base, sram_base, x_count, y_count, z_count,
                hbm_y_stride, hbm_z_stride, sram_y_stride, sram_z_stride,
                qos);
            x_index = 0;
            y_index = 0;
            z_index = 0;
            accepted = 0;
            random_state = 32'h3d72_a591 ^ {16'd0, command_id};
            held_valid = 1'b0;
            while (!sequence_done_valid_o) begin
                @(negedge clk_i);
                random_state = {random_state[30:0],
                    random_state[31] ^ random_state[21] ^
                    random_state[1] ^ random_state[0]};
                beat_ready_i = random_state[0] | random_state[3];
                if (beat_valid_o) begin
                    if ((beat_operation_o != operation) ||
                        (beat_command_id_o != command_id) ||
                        (beat_qos_o != qos)) begin
                        $fatal(1, "beat metadata mismatch");
                    end
                    expected_hbm_address = 35'(
                        64'(hbm_base) + 64'(z_index)*64'(hbm_z_stride) +
                        64'(y_index)*64'(hbm_y_stride) +
                        64'(x_index)*64'd128);
                    expected_sram_address = 24'(
                        64'(sram_base) + 64'(z_index)*64'(sram_z_stride) +
                        64'(y_index)*64'(sram_y_stride) +
                        64'(x_index)*64'd128);
                    if ((beat_hbm_address_o != expected_hbm_address) ||
                        (beat_sram_address_o != expected_sram_address) ||
                        (beat_first_o != (accepted == 0)) ||
                        (beat_last_o != ((x_index == int'(x_count)-1) &&
                         (y_index == int'(y_count)-1) &&
                         (z_index == int'(z_count)-1)))) begin
                        $fatal(1, "beat sequence mismatch command=%0d beat=%0d",
                               command_id, accepted);
                    end
                    if (held_valid &&
                        ((beat_hbm_address_o != held_hbm_address) ||
                         (beat_sram_address_o != held_sram_address) ||
                         (beat_first_o != held_first) ||
                         (beat_last_o != held_last))) begin
                        $fatal(1, "beat changed under backpressure");
                    end
                    if (beat_ready_i) begin
                        held_valid = 1'b0;
                        accepted = accepted + 1;
                        checked_beats = checked_beats + 1;
                        if (x_index == int'(x_count)-1) begin
                            x_index = 0;
                            if (y_index == int'(y_count)-1) begin
                                y_index = 0;
                                z_index = z_index + 1;
                            end else begin
                                y_index = y_index + 1;
                            end
                        end else begin
                            x_index = x_index + 1;
                        end
                    end else begin
                        held_valid = 1'b1;
                        held_hbm_address = beat_hbm_address_o;
                        held_sram_address = beat_sram_address_o;
                        held_first = beat_first_o;
                        held_last = beat_last_o;
                    end
                end
                @(posedge clk_i);
            end
            beat_ready_i = 1'b0;
            if (accepted != x_count*y_count*z_count) begin
                $fatal(1, "accepted beat count mismatch command=%0d got=%0d",
                       command_id, accepted);
            end
            consume_done(command_id, 1'b0,
                npu_dma_pkg::NPU_DMA_ERROR_OK, 18'(accepted));
        end
    endtask

    initial begin
        integer trial;
        logic [17:0] trial_x_count;
        logic [15:0] trial_y_count;
        logic [15:0] trial_z_count;
        logic [34:0] trial_hbm_y_stride;
        logic [34:0] trial_hbm_z_stride;
        logic [23:0] trial_sram_y_stride;
        logic [23:0] trial_sram_z_stride;
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        command_valid_i = 1'b0;
        command_fields = '0;
        beat_ready_i = 1'b0;
        sequence_done_ready_i = 1'b0;
        checked_beats = 0;
        checked_commands = 0;

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        run_sequence(npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h1001,
            35'h0000_1000, 24'h002000, 18'd7, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd3);
        run_sequence(npu_dma_pkg::NPU_DMA_SRAM_TO_HBM, 16'h1002,
            35'h0000_8000, 24'h010000, 18'd3, 16'd4, 16'd1,
            35'd1024, 35'd0, 24'd2048, 24'd0, 2'd1);
        run_sequence(npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h1003,
            35'h0002_0000, 24'h080000, 18'd2, 16'd3, 16'd2,
            35'd512, 35'd4096, 24'd1024, 24'd8192, 2'd2);
        run_sequence(npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h1004,
            35'h0004_0000, 24'h100000, 18'd1, 16'd2, 16'd2,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);

        for (trial = 0; trial < 8; trial++) begin
            trial_x_count = 18'((trial % 4) + 1);
            trial_y_count = 16'((trial % 3) + 1);
            trial_z_count = 16'((trial % 2) + 1);
            trial_hbm_y_stride =
                (35'(trial_x_count) + 35'd1) * 35'd128;
            trial_hbm_z_stride =
                trial_hbm_y_stride * 35'(trial_y_count) + 35'd256;
            trial_sram_y_stride =
                (24'(trial_x_count) + 24'd2) * 24'd128;
            trial_sram_z_stride =
                trial_sram_y_stride * 24'(trial_y_count) + 24'd384;
            run_sequence(2'(trial & 1), 16'(16'h1100 + trial),
                35'(35'h0010_0000 + trial*35'h0001_0000),
                24'(24'h200000 + trial*24'h010000),
                trial_x_count, trial_y_count, trial_z_count,
                trial_hbm_y_stride, trial_hbm_z_stride,
                trial_sram_y_stride, trial_sram_z_stride, 2'(trial));
        end

        submit_command(4'd0, npu_dma_pkg::NPU_DMA_HBM_TO_SRAM,
            16'h2001, 35'h1000, 24'h2000, 18'd1, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2001, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR, 18'd0);

        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION, 2'd2,
            16'h2002, 35'h1000, 24'h2000, 18'd1, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2002, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR, 18'd0);
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2003,
            35'h1000, 24'h2000, 18'd0, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2003, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR, 18'd0);
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2004,
            35'h1000, 24'h2000, 18'd1, 16'd0, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2004, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR, 18'd0);
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2005,
            35'h1000, 24'h2000, 18'd1, 16'd1, 16'd0,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2005, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR, 18'd0);
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2006,
            35'h1000, 24'h2000, 18'd131073, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2006, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR, 18'd0);

        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;
        if (protocol_error_o || busy_o) begin
            $fatal(1, "clear did not reset diagnostic state");
        end

        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2101,
            35'h1081, 24'h2000, 18'd1, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2101, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_ADDRESS, 18'd0);

        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2102,
            35'h1000, 24'h2001, 18'd1, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2102, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_ADDRESS, 18'd0);
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2103,
            35'h1000, 24'h2000, 18'd1, 16'd1, 16'd1,
            35'd129, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2103, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_ADDRESS, 18'd0);
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2104,
            35'h1000, 24'h2000, 18'd1, 16'd1, 16'd1,
            35'd0, 35'd129, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2104, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_ADDRESS, 18'd0);
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2105,
            35'h1000, 24'h2000, 18'd1, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd129, 24'd0, 2'd0);
        consume_done(16'h2105, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_ADDRESS, 18'd0);
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2106,
            35'h1000, 24'h2000, 18'd1, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd129, 2'd0);
        consume_done(16'h2106, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_ADDRESS, 18'd0);
        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2107,
            35'd24000000000, 24'h2000, 18'd1, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        consume_done(16'h2107, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_ADDRESS, 18'd0);

        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;

        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2201,
            35'd23999999872, 24'h000000, 18'd2, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        @(negedge clk_i);
        beat_ready_i = 1'b1;
        if (!beat_valid_o || beat_last_o) begin
            $fatal(1, "capacity test first-beat state is invalid");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        beat_ready_i = 1'b0;
        checked_beats = checked_beats + 1;
        consume_done(16'h2201, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_ADDRESS, 18'd1);

        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;

        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2202,
            35'h0000_0000, 24'hffff80, 18'd2, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        @(negedge clk_i);
        beat_ready_i = 1'b1;
        if (!beat_valid_o || beat_last_o) begin
            $fatal(1, "SRAM capacity test first-beat state is invalid");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        beat_ready_i = 1'b0;
        checked_beats = checked_beats + 1;
        consume_done(16'h2202, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_ADDRESS, 18'd1);

        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;

        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2203,
            35'h0000_0000, 24'h000000, 18'd65536, 16'd3, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        @(negedge clk_i);
        beat_ready_i = 1'b1;
        wait (sequence_done_valid_o);
        @(negedge clk_i);
        beat_ready_i = 1'b0;
        checked_beats = checked_beats + 131072;
        consume_done(16'h2203, 1'b1,
            npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR, 18'd131072);

        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;

        run_sequence(npu_dma_pkg::NPU_DMA_HBM_TO_SRAM, 16'h2204,
            35'h0000_0000, 24'h000000, 18'd131072, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);

        submit_command(npu_dma_pkg::NPU_DMA_COMMAND_VERSION,
            npu_dma_pkg::NPU_DMA_SRAM_TO_HBM, 16'h3001,
            35'h8000, 24'h10000, 18'd16, 16'd1, 16'd1,
            35'd0, 35'd0, 24'd0, 24'd0, 2'd0);
        @(negedge clk_i);
        beat_ready_i = 1'b1;
        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;
        beat_ready_i = 1'b0;
        if (busy_o || sequence_done_valid_o || protocol_error_o) begin
            $fatal(1, "clear did not remove an active sequence");
        end

        if (checked_commands != 29 || checked_beats != 262240) begin
            $fatal(1, "test accounting mismatch commands=%0d beats=%0d",
                   checked_commands, checked_beats);
        end
        $display("[RTL_SIM PASS] npu_dma_address_generator commands=%0d beats=%0d",
                 checked_commands, checked_beats);
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "npu_dma_address_generator timeout");
    end

endmodule

`default_nettype wire
