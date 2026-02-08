`timescale 1ns/1ps
`default_nettype none

module tb_vector_engine16;
    import fp8_pkg::*;
    import mxfp_pkg::*;
    import vector_pkg::*;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic request_valid_i;
    logic request_ready_o;
    vector_fp32_data_t data_a_i;
    vector_fp32_data_t data_b_i;
    vector_fp32_data_t data_c_i;
    logic [31:0] scalar_i;
    vector_lane_mask_t invalid_a_i;
    vector_lane_mask_t invalid_b_i;
    vector_lane_mask_t invalid_c_i;
    logic scalar_invalid_i;
    vector_engine_control_t control_i;
    logic response_valid_o;
    logic response_ready_i;
    vector_fp32_data_t fp32_vector_o;
    vector_mx_data_t mx_vector_o;
    mxfp_scale_t mx_scale_o;
    logic [31:0] fp32_scalar_o;
    vector_lane_mask_t invalid_o;
    vector_lane_mask_t overflow_o;
    vector_lane_mask_t inexact_o;
    logic empty_o;
    vector_engine_response_control_t response_control_o;
    logic [7:0] scenario_id;
    mxfp_scale_t expected_mx_scale;
    integer check_count;

    vector_engine16 u_dut (.*);

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/vector_engine16.vcd");
        $dumpvars(1, tb_vector_engine16);
    end
`endif

    function automatic logic [31:0] small_integer_to_fp32(input integer value);
        integer magnitude;
        integer highest_bit;
        logic sign;
        logic [7:0] exponent;
        logic [22:0] fraction;
        begin
            if (value == 0) begin
                small_integer_to_fp32 = 32'd0;
            end else begin
                sign = value < 0;
                magnitude = sign ? -value : value;
                highest_bit = 0;
                for (integer bit_index = 0; bit_index < 31; bit_index++) begin
                    if ((magnitude >> bit_index) != 0) highest_bit = bit_index;
                end
                exponent = 8'(127 + highest_bit);
                fraction = 23'(magnitude << (23 - highest_bit));
                small_integer_to_fp32 = {sign, exponent, fraction};
            end
        end
    endfunction

    function automatic vector_engine_op_e stress_operation(
        input integer request_index
    );
        begin
            case (request_index % 7)
                0: stress_operation = VECTOR_ENGINE_OP_PASS;
                1: stress_operation = VECTOR_ENGINE_OP_EPILOGUE;
                2: stress_operation = VECTOR_ENGINE_OP_REDUCE_SUM;
                3: stress_operation = VECTOR_ENGINE_OP_SOFTMAX;
                4: stress_operation = VECTOR_ENGINE_OP_LAYERNORM;
                5: stress_operation = VECTOR_ENGINE_OP_GELU;
                default: stress_operation = VECTOR_ENGINE_OP_SILU;
            endcase
        end
    endfunction

    task automatic set_uniform_inputs(
        input integer value_a,
        input integer value_b,
        input integer value_c
    );
        begin
            for (integer lane = 0; lane < VECTOR_LANES; lane++) begin
                data_a_i[lane*32 +: 32] = small_integer_to_fp32(value_a);
                data_b_i[lane*32 +: 32] = small_integer_to_fp32(value_b);
                data_c_i[lane*32 +: 32] = small_integer_to_fp32(value_c);
            end
        end
    endtask

    task automatic start_request(
        input vector_engine_op_e operation,
        input vector_lane_mask_t lane_mask,
        input logic [7:0] tag,
        input logic last
    );
        begin
            while (!request_ready_o) @(negedge clk_i);
            control_i.operation = operation;
            control_i.lane_mask = lane_mask;
            control_i.tag = tag;
            control_i.last = last;
            request_valid_i = 1'b1;
            @(negedge clk_i);
            request_valid_i = 1'b0;
        end
    endtask

    task automatic expect_response(
        input vector_engine_op_e operation,
        input vector_engine_result_kind_e result_kind,
        input vector_lane_mask_t lane_mask,
        input logic [7:0] tag,
        input logic last,
        input vector_fp32_data_t expected_fp32,
        input vector_mx_data_t expected_mx,
        input logic [31:0] expected_scalar,
        input vector_lane_mask_t expected_invalid,
        input vector_lane_mask_t expected_overflow,
        input vector_lane_mask_t expected_inexact,
        input logic expected_empty
    );
        begin
            while (!response_valid_o) @(negedge clk_i);
            if ((fp32_vector_o !== expected_fp32) ||
                (mx_vector_o !== expected_mx) ||
                ((result_kind == VECTOR_ENGINE_RESULT_MX_VECTOR) &&
                 (mx_scale_o !== expected_mx_scale)) ||
                (fp32_scalar_o !== expected_scalar) ||
                (invalid_o !== expected_invalid) ||
                (overflow_o !== expected_overflow) ||
                (inexact_o !== expected_inexact) ||
                (empty_o !== expected_empty) ||
                (response_control_o.operation !== operation) ||
                (response_control_o.result_kind !== result_kind) ||
                (response_control_o.lane_mask !== lane_mask) ||
                (response_control_o.tag !== tag) ||
                (response_control_o.last !== last)) begin
                $fatal(1,
                    "FAIL: vector_engine scenario=%0d op=%0d tag=%h got_kind=%0d expected_kind=%0d fp32_lane0=%h/%h scalar=%h/%h invalid=%h/%h empty=%b/%b",
                    scenario_id, operation, tag, response_control_o.result_kind,
                    result_kind, fp32_vector_o[31:0], expected_fp32[31:0],
                    fp32_scalar_o, expected_scalar, invalid_o,
                    expected_invalid, empty_o, expected_empty);
            end
            check_count = check_count + 1;
            @(negedge clk_i);
        end
    endtask

    initial begin
        vector_fp32_data_t expected_fp32;
        vector_mx_data_t expected_mx;
        vector_fp32_data_t held_fp32;
        vector_mx_data_t held_mx;
        vector_engine_response_control_t held_control;
        logic [111:0] stress_seen;

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        request_valid_i = 1'b0;
        response_ready_i = 1'b1;
        data_a_i = '0;
        data_b_i = '0;
        data_c_i = '0;
        scalar_i = '0;
        invalid_a_i = '0;
        invalid_b_i = '0;
        invalid_c_i = '0;
        scalar_invalid_i = 1'b0;
        control_i = '0;
        control_i.operand_b_source = VECTOR_SRC_VECTOR;
        scenario_id = 8'd0;
        expected_mx_scale = '0;
        check_count = 0;
        repeat (3) @(negedge clk_i);
        rst_i = 1'b0;

        scenario_id = 8'd1;
        set_uniform_inputs(1, 2, 0);
        expected_fp32 = data_a_i;
        start_request(VECTOR_ENGINE_OP_PASS, 16'hffff, 8'h10, 1'b0);
        expect_response(VECTOR_ENGINE_OP_PASS,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h10, 1'b0, expected_fp32, '0, '0,
                        '0, '0, '0, 1'b0);

        scenario_id = 8'd2;
        set_uniform_inputs(1, 2, 0);
        invalid_a_i = 16'h0001;
        expected_fp32 = '0;
        for (integer lane = 0; lane < VECTOR_LANES; lane++) begin
            expected_fp32[lane*32 +: 32] = small_integer_to_fp32(3);
        end
        start_request(VECTOR_ENGINE_OP_ADD, 16'hffff, 8'h11, 1'b0);
        expect_response(VECTOR_ENGINE_OP_ADD,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h11, 1'b0, expected_fp32, '0, '0,
                        16'h0001, '0, '0, 1'b0);
        invalid_a_i = '0;

        scenario_id = 8'd3;
        set_uniform_inputs(2, 0, 0);
        scalar_i = small_integer_to_fp32(3);
        control_i.operand_b_source = VECTOR_SRC_SCALAR;
        expected_fp32 = '0;
        for (integer lane = 0; lane < VECTOR_LANES; lane++) begin
            expected_fp32[lane*32 +: 32] = small_integer_to_fp32(6);
        end
        start_request(VECTOR_ENGINE_OP_MUL, 16'hffff, 8'h12, 1'b0);
        expect_response(VECTOR_ENGINE_OP_MUL,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h12, 1'b0, expected_fp32, '0, '0,
                        '0, '0, '0, 1'b0);
        control_i.operand_b_source = VECTOR_SRC_VECTOR;

        scenario_id = 8'd4;
        set_uniform_inputs(4, 2, 0);
        expected_fp32 = '0;
        for (integer lane = 0; lane < VECTOR_LANES; lane++) begin
            expected_fp32[lane*32 +: 32] =
                small_integer_to_fp32((lane < 8) ? 2 : 4);
        end
        start_request(VECTOR_ENGINE_OP_MIN, 16'h00ff, 8'h13, 1'b0);
        expect_response(VECTOR_ENGINE_OP_MIN,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'h00ff, 8'h13, 1'b0, expected_fp32, '0, '0,
                        '0, '0, '0, 1'b0);

        scenario_id = 8'd5;
        set_uniform_inputs(1, 2, 1);
        control_i.bias_enable = 1'b1;
        control_i.residual_enable = 1'b1;
        control_i.output_format = EPILOGUE_OUT_FP32;
        expected_fp32 = '0;
        for (integer lane = 0; lane < VECTOR_LANES; lane++) begin
            expected_fp32[lane*32 +: 32] = small_integer_to_fp32(4);
        end
        start_request(VECTOR_ENGINE_OP_EPILOGUE, 16'hffff, 8'h20, 1'b0);
        expect_response(VECTOR_ENGINE_OP_EPILOGUE,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h20, 1'b0, expected_fp32, '0,
                        '0, '0, '0, '0, 1'b0);

        scenario_id = 8'd6;
        set_uniform_inputs(1, 0, 0);
        expected_fp32 = data_a_i;
        control_i.bias_enable = 1'b0;
        control_i.residual_enable = 1'b0;
        control_i.output_format = EPILOGUE_OUT_MX;
        control_i.mx_format = MXFP8_E4M3;
        expected_mx_scale = 8'd119;
        expected_mx = {16{8'h78}};
        start_request(VECTOR_ENGINE_OP_EPILOGUE, 16'hffff, 8'h21, 1'b0);
        start_request(VECTOR_ENGINE_OP_EPILOGUE, 16'hffff, 8'h22, 1'b1);
        expect_response(VECTOR_ENGINE_OP_EPILOGUE,
                        VECTOR_ENGINE_RESULT_MX_VECTOR,
                        16'hffff, 8'h21, 1'b0, expected_fp32, expected_mx,
                        '0, '0, '0, '0, 1'b0);
        expect_response(VECTOR_ENGINE_OP_EPILOGUE,
                        VECTOR_ENGINE_RESULT_MX_VECTOR,
                        16'hffff, 8'h22, 1'b1, expected_fp32, expected_mx,
                        '0, '0, '0, '0, 1'b0);

        scenario_id = 8'd18;
        control_i.mx_format = MXFP8_E4M3;
        expected_mx_scale = 8'd119;
        expected_mx = {16{8'h78}};
        start_request(VECTOR_ENGINE_OP_EPILOGUE, 16'hffff, 8'h23, 1'b0);
        start_request(VECTOR_ENGINE_OP_EPILOGUE, 16'hffff, 8'h24, 1'b1);
        expect_response(VECTOR_ENGINE_OP_EPILOGUE,
                        VECTOR_ENGINE_RESULT_MX_VECTOR,
                        16'hffff, 8'h23, 1'b0, expected_fp32, expected_mx,
                        '0, '0, '0, '0, 1'b0);
        expect_response(VECTOR_ENGINE_OP_EPILOGUE,
                        VECTOR_ENGINE_RESULT_MX_VECTOR,
                        16'hffff, 8'h24, 1'b1, expected_fp32, expected_mx,
                        '0, '0, '0, '0, 1'b0);

        scenario_id = 8'd19;
        control_i.mx_format = MXFP4_E2M1;
        expected_mx_scale = 8'd125;
        expected_mx = {64'd0, {16{4'h6}}};
        start_request(VECTOR_ENGINE_OP_EPILOGUE, 16'hffff, 8'h25, 1'b0);
        start_request(VECTOR_ENGINE_OP_EPILOGUE, 16'hffff, 8'h26, 1'b1);
        expect_response(VECTOR_ENGINE_OP_EPILOGUE,
                        VECTOR_ENGINE_RESULT_MX_VECTOR,
                        16'hffff, 8'h25, 1'b0, expected_fp32, expected_mx,
                        '0, '0, '0, '0, 1'b0);
        expect_response(VECTOR_ENGINE_OP_EPILOGUE,
                        VECTOR_ENGINE_RESULT_MX_VECTOR,
                        16'hffff, 8'h26, 1'b1, expected_fp32, expected_mx,
                        '0, '0, '0, '0, 1'b0);
        control_i.output_format = EPILOGUE_OUT_FP32;

        scenario_id = 8'd7;
        set_uniform_inputs(1, 0, 0);
        start_request(VECTOR_ENGINE_OP_REDUCE_SUM, 16'hffff, 8'h30, 1'b0);
        expect_response(VECTOR_ENGINE_OP_REDUCE_SUM,
                        VECTOR_ENGINE_RESULT_FP32_SCALAR,
                        16'hffff, 8'h30, 1'b0, '0, '0,
                        small_integer_to_fp32(16), '0, '0, '0, 1'b0);

        scenario_id = 8'd8;
        for (integer lane = 0; lane < VECTOR_LANES; lane++) begin
            data_a_i[lane*32 +: 32] = small_integer_to_fp32(lane);
        end
        start_request(VECTOR_ENGINE_OP_REDUCE_MAX, 16'hffff, 8'h31, 1'b1);
        expect_response(VECTOR_ENGINE_OP_REDUCE_MAX,
                        VECTOR_ENGINE_RESULT_FP32_SCALAR,
                        16'hffff, 8'h31, 1'b1, '0, '0,
                        small_integer_to_fp32(15), '0, '0, '0, 1'b0);

        scenario_id = 8'd9;
        set_uniform_inputs(0, 1, 0);
        expected_fp32 = '0;
        for (integer lane = 0; lane < VECTOR_LANES; lane++) begin
            expected_fp32[lane*32 +: 32] = 32'h3d800000;
        end
        start_request(VECTOR_ENGINE_OP_SOFTMAX, 16'hffff, 8'h40, 1'b0);
        expect_response(VECTOR_ENGINE_OP_SOFTMAX,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h40, 1'b0, expected_fp32, '0, '0,
                        '0, '0, '0, 1'b0);

        scenario_id = 8'd10;
        set_uniform_inputs(0, 1, 0);
        scalar_i = small_integer_to_fp32(1);
        control_i.affine_enable = 1'b0;
        control_i.beta_enable = 1'b0;
        start_request(VECTOR_ENGINE_OP_LAYERNORM, 16'hffff, 8'h50, 1'b0);
        expect_response(VECTOR_ENGINE_OP_LAYERNORM,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h50, 1'b0, '0, '0, '0,
                        '0, '0, '0, 1'b0);
        start_request(VECTOR_ENGINE_OP_RMSNORM, 16'hffff, 8'h51, 1'b0);
        expect_response(VECTOR_ENGINE_OP_RMSNORM,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h51, 1'b0, '0, '0, '0,
                        '0, '0, '0, 1'b0);

        scenario_id = 8'd11;
        set_uniform_inputs(0, 0, 0);
        start_request(VECTOR_ENGINE_OP_GELU, 16'hffff, 8'h60, 1'b0);
        expect_response(VECTOR_ENGINE_OP_GELU,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h60, 1'b0, '0, '0, '0,
                        '0, '0, '0, 1'b0);
        start_request(VECTOR_ENGINE_OP_SILU, 16'hffff, 8'h61, 1'b1);
        expect_response(VECTOR_ENGINE_OP_SILU,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h61, 1'b1, '0, '0, '0,
                        '0, '0, '0, 1'b0);

        // Accept and retire a continuous ALU burst at one request/result per
        // cycle after pipeline fill.  The checker runs concurrently so no
        // response can disappear while later requests are being issued.
        scenario_id = 8'd12;
        response_ready_i = 1'b1;
        fork
            begin : issue_continuous_burst
                for (integer burst_index = 0;
                     burst_index < 32;
                     burst_index++) begin
                    set_uniform_inputs(burst_index, 0, 0);
                    if (!request_ready_o) begin
                        $fatal(1,
                            "FAIL: vector_engine continuous issue blocked index=%0d",
                            burst_index);
                    end
                    start_request(VECTOR_ENGINE_OP_PASS, 16'hffff,
                                  8'(8'h80 + burst_index),
                                  burst_index == 31);
                end
            end
            begin : check_continuous_burst
                vector_fp32_data_t burst_expected;
                for (integer burst_index = 0;
                     burst_index < 32;
                     burst_index++) begin
                    burst_expected = '0;
                    for (integer lane = 0; lane < VECTOR_LANES; lane++) begin
                        burst_expected[lane*32 +: 32] =
                            small_integer_to_fp32(burst_index);
                    end
                    expect_response(VECTOR_ENGINE_OP_PASS,
                                    VECTOR_ENGINE_RESULT_FP32_VECTOR,
                                    16'hffff, 8'(8'h80 + burst_index),
                                    burst_index == 31, burst_expected, '0, '0,
                                    '0, '0, '0, 1'b0);
                end
            end
        join

        // Adjacent epilogue beats form MX blocks while the adapter overlaps
        // quantization/output of one pair with collection of the next pair.
        scenario_id = 8'd20;
        response_ready_i = 1'b1;
        set_uniform_inputs(1, 0, 0);
        control_i = '0;
        control_i.lane_mask = 16'hffff;
        control_i.operation = VECTOR_ENGINE_OP_EPILOGUE;
        control_i.output_format = EPILOGUE_OUT_MX;
        control_i.mx_format = MXFP8_E4M3;
        expected_mx_scale = 8'd119;
        fork
            begin : issue_continuous_mx
                for (integer mx_index = 0; mx_index < 32; mx_index++) begin
                    if (!request_ready_o) begin
                        $fatal(1,
                            "FAIL: continuous MX issue blocked index=%0d",
                            mx_index);
                    end
                    start_request(VECTOR_ENGINE_OP_EPILOGUE, 16'hffff,
                                  8'(8'hc0 + mx_index), mx_index == 31);
                end
            end
            begin : check_continuous_mx
                while (!response_valid_o) @(negedge clk_i);
                for (integer mx_index = 0; mx_index < 32; mx_index++) begin
                    if (!response_valid_o ||
                        (response_control_o.result_kind !==
                            VECTOR_ENGINE_RESULT_MX_VECTOR) ||
                        (response_control_o.tag !== 8'(8'hc0 + mx_index)) ||
                        (response_control_o.last !== (mx_index == 31)) ||
                        (mx_scale_o !== 8'd119) ||
                        (mx_vector_o !== {16{8'h78}})) begin
                        $fatal(1,
                            "FAIL: continuous MX output bubble/data index=%0d tag=%h valid=%b",
                            mx_index, response_control_o.tag,
                            response_valid_o);
                    end
                    check_count = check_count + 1;
                    @(negedge clk_i);
                end
            end
        join
        control_i.output_format = EPILOGUE_OUT_FP32;

        // Exercise every producer in a long mixed-latency stream.  Issuing is
        // never allowed to wait for an older request; responses are matched by
        // tag because fixed-latency pipelines may complete out of order.
        scenario_id = 8'd17;
        response_ready_i = 1'b1;
        stress_seen = '0;
        fork
            begin : issue_mixed_stress
                for (integer request_index = 0;
                     request_index < 112;
                     request_index++) begin
                    set_uniform_inputs(0, 0, 0);
                    scalar_i = small_integer_to_fp32(1);
                    control_i = '0;
                    control_i.lane_mask = 16'hffff;
                    control_i.tag = 8'(request_index);
                    control_i.last = request_index == 111;
                    control_i.operation = stress_operation(request_index);
                    control_i.operand_b_source = VECTOR_SRC_VECTOR;
                    control_i.output_format = EPILOGUE_OUT_FP32;
                    #1;
                    if (!request_ready_o) begin
                        $fatal(1,
                            "FAIL: mixed-latency issue blocked index=%0d op=%0d",
                            request_index, control_i.operation);
                    end
                    request_valid_i = 1'b1;
                    @(negedge clk_i);
                    request_valid_i = 1'b0;
                end
            end
            begin : check_mixed_stress
                integer response_index;
                logic [7:0] response_tag;
                logic [6:0] response_tag_index;
                response_index = 0;
                while (response_index < 112) begin
                    while (!response_valid_o) @(negedge clk_i);
                    response_tag = response_control_o.tag;
                    if (response_tag >= 112) begin
                        $fatal(1, "FAIL: mixed response tag out of range=%0d",
                               response_tag);
                    end
                    response_tag_index = response_tag[6:0];
                    if (stress_seen[response_tag_index] ||
                        (response_control_o.operation !==
                            stress_operation(int'(response_tag)))) begin
                        $fatal(1,
                            "FAIL: mixed response tag=%0d op=%0d seen=%b",
                            response_tag, response_control_o.operation,
                            stress_seen[response_tag_index]);
                    end
                    stress_seen[response_tag_index] = 1'b1;
                    response_index = response_index + 1;
                    check_count = check_count + 1;
                    @(negedge clk_i);
                end
            end
        join
        if (stress_seen !== {112{1'b1}}) begin
            $fatal(1, "FAIL: mixed-latency response loss seen=%h",
                   stress_seen);
        end

        clear_i = 1'b1;
        @(negedge clk_i);
        clear_i = 1'b0;
        repeat (2) @(negedge clk_i);

        // EPILOGUE issued one cycle before ALU returns on the same cycle.
        // Both producers must enqueue.  Clear initializes the round-robin
        // pointer at ALU, so ALU wins first and EPILOGUE remains queued.
        scenario_id = 8'd13;
        response_ready_i = 1'b0;
        set_uniform_inputs(1, 0, 0);
        control_i.bias_enable = 1'b0;
        control_i.residual_enable = 1'b0;
        control_i.output_format = EPILOGUE_OUT_FP32;
        start_request(VECTOR_ENGINE_OP_EPILOGUE, 16'hffff, 8'ha0, 1'b0);
        start_request(VECTOR_ENGINE_OP_PASS, 16'hffff, 8'ha1, 1'b1);
        repeat (20) @(negedge clk_i);
        response_ready_i = 1'b1;
        expected_fp32 = data_a_i;
        expected_mx = {16{8'h38}};
        expect_response(VECTOR_ENGINE_OP_PASS,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'ha1, 1'b1, expected_fp32, '0, '0,
                        '0, '0, '0, 1'b0);
        expect_response(VECTOR_ENGINE_OP_EPILOGUE,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'ha0, 1'b0, expected_fp32, '0, '0,
                        '0, '0, '0, 1'b0);

        scenario_id = 8'd14;
        set_uniform_inputs(1, 2, 0);
        expected_fp32 = '0;
        for (integer lane = 0; lane < VECTOR_LANES; lane++) begin
            expected_fp32[lane*32 +: 32] = small_integer_to_fp32(3);
        end
        response_ready_i = 1'b0;
        start_request(VECTOR_ENGINE_OP_ADD, 16'hffff, 8'h70, 1'b0);
        while (!response_valid_o) @(negedge clk_i);
        held_fp32 = fp32_vector_o;
        held_mx = mx_vector_o;
        held_control = response_control_o;
        repeat (5) begin
            @(negedge clk_i);
            if (!response_valid_o || (fp32_vector_o !== held_fp32) ||
                (mx_vector_o !== held_mx) ||
                (response_control_o !== held_control) || !request_ready_o) begin
                $fatal(1, "FAIL: vector_engine response backpressure hold");
            end
        end
        response_ready_i = 1'b1;
        expect_response(VECTOR_ENGINE_OP_ADD,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h70, 1'b0, expected_fp32, '0, '0,
                        '0, '0, '0, 1'b0);

        scenario_id = 8'd15;
        set_uniform_inputs(0, 0, 0);
        start_request(VECTOR_ENGINE_OP_SOFTMAX, 16'hffff, 8'h80, 1'b0);
        repeat (9) @(negedge clk_i);
        clear_i = 1'b1;
        @(negedge clk_i);
        clear_i = 1'b0;
        repeat (3) @(negedge clk_i);
        if (response_valid_o || !request_ready_o) begin
            $fatal(1, "FAIL: vector_engine clear did not flush/recover");
        end
        start_request(VECTOR_ENGINE_OP_PASS, 16'hffff, 8'h81, 1'b0);
        expect_response(VECTOR_ENGINE_OP_PASS,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'hffff, 8'h81, 1'b0, '0, '0, '0,
                        '0, '0, '0, 1'b0);

        scenario_id = 8'd16;
        start_request(VECTOR_ENGINE_OP_LAYERNORM, 16'hffff, 8'h90, 1'b0);
        repeat (11) @(negedge clk_i);
        rst_i = 1'b1;
        repeat (2) @(negedge clk_i);
        rst_i = 1'b0;
        repeat (3) @(negedge clk_i);
        if (response_valid_o || !request_ready_o) begin
            $fatal(1, "FAIL: vector_engine reset did not flush/recover");
        end
        start_request(VECTOR_ENGINE_OP_SILU, 16'h0000, 8'h91, 1'b1);
        expect_response(VECTOR_ENGINE_OP_SILU,
                        VECTOR_ENGINE_RESULT_FP32_VECTOR,
                        16'h0000, 8'h91, 1'b1, '0, '0, '0,
                        '0, '0, '0, 1'b1);

        $display("PASS: vector_engine16 full-rate issue, mixed-latency collision capture, ALU/Epilogue/Reduce/Softmax/Norm/GELU/SiLU routing, backpressure, clear/reset, and recovery checks=%0d",
                 check_count);
        $finish;
    end

    initial begin
        repeat (4000) @(posedge clk_i);
        $fatal(1, "FAIL: vector_engine16 timeout scenario=%0d", scenario_id);
    end

endmodule

`default_nettype wire
