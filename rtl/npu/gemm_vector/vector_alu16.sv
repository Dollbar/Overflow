`timescale 1ns/1ps
`default_nettype none

module vector_alu16 #(
    parameter bit FTZ = 1'b0
) (
    input  logic                         clk_i,
    input  logic                         rst_i,
    input  logic                         clear_i,
    input  logic                         valid_i,
    input  vector_pkg::vector_fp32_data_t a_i,
    input  vector_pkg::vector_fp32_data_t b_i,
    input  logic [31:0]                  scalar_b_i,
    input  vector_pkg::vector_lane_mask_t invalid_a_i,
    input  vector_pkg::vector_lane_mask_t invalid_b_i,
    input  logic                         scalar_b_invalid_i,
    input  vector_pkg::vector_control_t  control_i,
    output logic                         valid_o,
    output vector_pkg::vector_fp32_data_t result_o,
    output vector_pkg::vector_lane_mask_t invalid_o,
    output vector_pkg::vector_control_t  control_o
);

    localparam int unsigned LANES = vector_pkg::VECTOR_LANES;
    localparam int unsigned LATENCY = 13;
    localparam int unsigned ADD_DELAY = 7;
    localparam logic [31:0] FP32_ONE = 32'h3f800000;

    logic [31:0] a_lane [0:LANES-1];
    logic [31:0] b_lane [0:LANES-1];
    logic [31:0] selected_b_lane [0:LANES-1];
    logic        selected_b_invalid_lane [0:LANES-1];
    logic [31:0] arithmetic_a_lane_q [0:LANES-1];
    logic [31:0] arithmetic_b_lane_q [0:LANES-1];
    logic        arithmetic_invalid_a_lane_q [0:LANES-1];
    logic        arithmetic_invalid_b_lane_q [0:LANES-1];
    (* keep *) fp8_pkg::fp8_rounding_e arithmetic_rounding_lane_q [0:LANES-1];
    (* keep *) logic arithmetic_valid_lane_q [0:LANES-1];

    logic [31:0] add_result_lane [0:LANES-1];
    logic        add_invalid_lane [0:LANES-1];
    logic [31:0] mul_result_lane [0:LANES-1];
    logic        mul_invalid_lane [0:LANES-1];
    logic [31:0] minimum_lane [0:LANES-1];
    logic [31:0] maximum_lane [0:LANES-1];
    /* These interface outputs are intentionally unused by the fixed-latency mux. */
    /* verilator lint_off UNUSEDSIGNAL */
    logic        add_valid_unused [0:LANES-1];
    logic        mul_valid_unused [0:LANES-1];
    logic        compare_equal_unused [0:LANES-1];
    logic        compare_less_unused [0:LANES-1];
    logic        compare_less_equal_unused [0:LANES-1];
    logic        compare_greater_unused [0:LANES-1];
    logic        compare_greater_equal_unused [0:LANES-1];
    logic        compare_unordered_unused [0:LANES-1];
    /* verilator lint_on UNUSEDSIGNAL */

    logic [31:0] add_result_delay_q [0:ADD_DELAY-1][0:LANES-1];
    logic        add_invalid_delay_q [0:ADD_DELAY-1][0:LANES-1];
    logic [31:0] pass_delay_q [0:LATENCY][0:LANES-1];
    logic [31:0] minimum_delay_q [0:LATENCY][0:LANES-1];
    logic [31:0] maximum_delay_q [0:LATENCY][0:LANES-1];
    logic        invalid_a_delay_q [0:LATENCY][0:LANES-1];
    logic        selected_b_invalid_delay_q [0:LATENCY][0:LANES-1];
    vector_pkg::vector_lane_mask_t lane_mask_delay_q [0:LATENCY];
    logic [vector_pkg::VECTOR_TAG_WIDTH-1:0] tag_delay_q [0:LATENCY];
    logic last_delay_q [0:LATENCY];
    logic [3:0] operation_delay_q [0:LATENCY];
    logic [1:0] operand_b_source_delay_q [0:LATENCY];
    logic [1:0] rounding_delay_q [0:LATENCY];
    logic valid_delay_q [0:LATENCY];

    fp8_pkg::fp8_rounding_e rounding_comb;

    always_comb begin
        rounding_comb = fp8_pkg::fp8_rounding_e'(control_i.rounding);
        for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
            a_lane[lane_index] = a_i[lane_index*32 +: 32];
            b_lane[lane_index] = b_i[lane_index*32 +: 32];
            case (control_i.operand_b_source)
                vector_pkg::VECTOR_SRC_SCALAR: begin
                    selected_b_lane[lane_index] = scalar_b_i;
                    selected_b_invalid_lane[lane_index] = scalar_b_invalid_i;
                end
                vector_pkg::VECTOR_SRC_ZERO: begin
                    selected_b_lane[lane_index] = 32'd0;
                    selected_b_invalid_lane[lane_index] = 1'b0;
                end
                vector_pkg::VECTOR_SRC_ONE: begin
                    selected_b_lane[lane_index] = FP32_ONE;
                    selected_b_invalid_lane[lane_index] = 1'b0;
                end
                default: begin
                    selected_b_lane[lane_index] = b_lane[lane_index];
                    selected_b_invalid_lane[lane_index] = invalid_b_i[lane_index];
                end
            endcase
        end
    end

    // 在每个lane入口复制算术控制寄存器，隔离顶层控制端口的跨lane高扇出。
    // 数据寄存器无需复位；局部valid在clear/reset时清零，和共享valid流水共同完成flush。
    always_ff @(posedge clk_i) begin
        for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
            arithmetic_a_lane_q[lane_index] <= a_lane[lane_index];
            arithmetic_b_lane_q[lane_index] <= selected_b_lane[lane_index];
            arithmetic_invalid_a_lane_q[lane_index] <= invalid_a_i[lane_index];
            arithmetic_invalid_b_lane_q[lane_index] <=
                selected_b_invalid_lane[lane_index];
            arithmetic_rounding_lane_q[lane_index] <= rounding_comb;
            if (rst_i || clear_i) begin
                arithmetic_valid_lane_q[lane_index] <= 1'b0;
            end else begin
                arithmetic_valid_lane_q[lane_index] <= valid_i;
            end
        end
    end

    generate
        for (genvar lane = 0; lane < LANES; lane++) begin : g_lane
            /*
             * Lane arithmetic is stateless and its local valid outputs are not
             * architectural.  The shared valid pipeline performs the flush;
             * leaving lane datapath registers free-running avoids a high-fanout
             * reset/clear tree without exposing stale results.
             */
            fp32_add_pipeline #(
                .FTZ (FTZ)
            ) u_add (
                .clk_i      (clk_i),
                .rst_i      (1'b0),
                .clear_i    (1'b0),
                .valid_i    (arithmetic_valid_lane_q[lane]),
                .a_i        (arithmetic_a_lane_q[lane]),
                .b_i        (arithmetic_b_lane_q[lane]),
                .invalid_i  ({arithmetic_invalid_b_lane_q[lane],
                              arithmetic_invalid_a_lane_q[lane]}),
                .rounding_i (arithmetic_rounding_lane_q[lane]),
                .valid_o    (add_valid_unused[lane]),
                .result_o   (add_result_lane[lane]),
                .invalid_o  (add_invalid_lane[lane])
            );

            fp32_mul_pipeline #(
                .FTZ (FTZ)
            ) u_mul (
                .clk_i      (clk_i),
                .rst_i      (1'b0),
                .clear_i    (1'b0),
                .valid_i    (arithmetic_valid_lane_q[lane]),
                .a_i        (arithmetic_a_lane_q[lane]),
                .b_i        (arithmetic_b_lane_q[lane]),
                .invalid_i  ({arithmetic_invalid_b_lane_q[lane],
                              arithmetic_invalid_a_lane_q[lane]}),
                .rounding_i (arithmetic_rounding_lane_q[lane]),
                .valid_o    (mul_valid_unused[lane]),
                .result_o   (mul_result_lane[lane]),
                .invalid_o  (mul_invalid_lane[lane])
            );

            fp32_compare u_compare (
                .a_i             (a_lane[lane]),
                .b_i             (selected_b_lane[lane]),
                .equal_o         (compare_equal_unused[lane]),
                .less_o          (compare_less_unused[lane]),
                .less_equal_o    (compare_less_equal_unused[lane]),
                .greater_o       (compare_greater_unused[lane]),
                .greater_equal_o (compare_greater_equal_unused[lane]),
                .unordered_o     (compare_unordered_unused[lane]),
                .minimum_o       (minimum_lane[lane]),
                .maximum_o       (maximum_lane[lane])
            );
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            for (integer stage_index = 0; stage_index <= LATENCY; stage_index++) begin
                valid_delay_q[stage_index] <= 1'b0;
            end
        end else begin
            valid_delay_q[0] <= valid_i;
            for (integer stage_index = 1; stage_index <= LATENCY; stage_index++) begin
                valid_delay_q[stage_index] <= valid_delay_q[stage_index-1];
            end
        end

        /* Datapath state is don't-care while valid is low, so it needs no reset. */
        lane_mask_delay_q[0] <= control_i.lane_mask;
        tag_delay_q[0] <= control_i.tag;
        last_delay_q[0] <= control_i.last;
        operation_delay_q[0] <= control_i.operation;
        operand_b_source_delay_q[0] <= control_i.operand_b_source;
        rounding_delay_q[0] <= control_i.rounding;
        for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
            pass_delay_q[0][lane_index] <= a_lane[lane_index];
            minimum_delay_q[0][lane_index] <= minimum_lane[lane_index];
            maximum_delay_q[0][lane_index] <= maximum_lane[lane_index];
            invalid_a_delay_q[0][lane_index] <= invalid_a_i[lane_index];
            selected_b_invalid_delay_q[0][lane_index] <=
                selected_b_invalid_lane[lane_index];
            add_result_delay_q[0][lane_index] <= add_result_lane[lane_index];
            add_invalid_delay_q[0][lane_index] <= add_invalid_lane[lane_index];
        end
        for (integer stage_index = 1; stage_index <= LATENCY; stage_index++) begin
            lane_mask_delay_q[stage_index] <= lane_mask_delay_q[stage_index-1];
            tag_delay_q[stage_index] <= tag_delay_q[stage_index-1];
            last_delay_q[stage_index] <= last_delay_q[stage_index-1];
            operation_delay_q[stage_index] <= operation_delay_q[stage_index-1];
            operand_b_source_delay_q[stage_index] <=
                operand_b_source_delay_q[stage_index-1];
            rounding_delay_q[stage_index] <= rounding_delay_q[stage_index-1];
            for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
                pass_delay_q[stage_index][lane_index] <=
                    pass_delay_q[stage_index-1][lane_index];
                minimum_delay_q[stage_index][lane_index] <=
                    minimum_delay_q[stage_index-1][lane_index];
                maximum_delay_q[stage_index][lane_index] <=
                    maximum_delay_q[stage_index-1][lane_index];
                invalid_a_delay_q[stage_index][lane_index] <=
                    invalid_a_delay_q[stage_index-1][lane_index];
                selected_b_invalid_delay_q[stage_index][lane_index] <=
                    selected_b_invalid_delay_q[stage_index-1][lane_index];
            end
        end
        for (integer stage_index = 1; stage_index < ADD_DELAY; stage_index++) begin
            for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
                add_result_delay_q[stage_index][lane_index] <=
                    add_result_delay_q[stage_index-1][lane_index];
                add_invalid_delay_q[stage_index][lane_index] <=
                    add_invalid_delay_q[stage_index-1][lane_index];
            end
        end
    end

    always_comb begin
        valid_o = valid_delay_q[LATENCY];
        control_o.lane_mask = lane_mask_delay_q[LATENCY];
        control_o.tag = tag_delay_q[LATENCY];
        control_o.last = last_delay_q[LATENCY];
        control_o.operation = vector_pkg::vector_alu_op_e'(
            operation_delay_q[LATENCY]);
        control_o.operand_b_source = vector_pkg::vector_operand_source_e'(
            operand_b_source_delay_q[LATENCY]);
        control_o.rounding = rounding_delay_q[LATENCY];
        result_o = '0;
        invalid_o = '0;
        for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
            if (!lane_mask_delay_q[LATENCY][lane_index]) begin
                result_o[lane_index*32 +: 32] = pass_delay_q[LATENCY][lane_index];
                invalid_o[lane_index] = invalid_a_delay_q[LATENCY][lane_index];
            end else begin
                case (operation_delay_q[LATENCY])
                    vector_pkg::VECTOR_OP_ADD: begin
                        result_o[lane_index*32 +: 32] =
                            add_result_delay_q[ADD_DELAY-1][lane_index];
                        invalid_o[lane_index] =
                            add_invalid_delay_q[ADD_DELAY-1][lane_index];
                    end
                    vector_pkg::VECTOR_OP_MUL: begin
                        result_o[lane_index*32 +: 32] = mul_result_lane[lane_index];
                        invalid_o[lane_index] = mul_invalid_lane[lane_index];
                    end
                    vector_pkg::VECTOR_OP_MIN: begin
                        result_o[lane_index*32 +: 32] =
                            minimum_delay_q[LATENCY][lane_index];
                        invalid_o[lane_index] =
                            invalid_a_delay_q[LATENCY][lane_index] |
                            selected_b_invalid_delay_q[LATENCY][lane_index];
                    end
                    vector_pkg::VECTOR_OP_MAX: begin
                        result_o[lane_index*32 +: 32] =
                            maximum_delay_q[LATENCY][lane_index];
                        invalid_o[lane_index] =
                            invalid_a_delay_q[LATENCY][lane_index] |
                            selected_b_invalid_delay_q[LATENCY][lane_index];
                    end
                    default: begin
                        result_o[lane_index*32 +: 32] =
                            pass_delay_q[LATENCY][lane_index];
                        invalid_o[lane_index] =
                            invalid_a_delay_q[LATENCY][lane_index];
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
