`timescale 1ns/1ps
`include "collective_defs.vh"

module tb_kdlink_reduction_dtype_ii1;
    localparam integer STREAM_FLITS = 4096;
    logic clk;
    logic rst_n;
    logic valid_i;
    logic [1:0] dtype_i;
    logic [63:0] byte_valid_i;
    logic [511:0] local_i;
    logic [511:0] remote_i;
    wire valid_o;
    wire [511:0] result_o;
    wire [63:0] byte_valid_o;
    integer drive_count;
    integer output_count;
    integer cycle_count;
    integer last_output_cycle;
    integer expected_dtype;

    function automatic [31:0] fp32_operand_a(input [4:0] pattern);
        if (pattern[4]) fp32_operand_a = 32'h0000_0000;
        else begin
        case (pattern[3:0])
            4'd0: fp32_operand_a = 32'h3f80_0000;
            4'd1: fp32_operand_a = 32'hbf80_0000;
            4'd2: fp32_operand_a = 32'h3f80_0000;
            4'd3: fp32_operand_a = 32'h7f80_0000;
            4'd4: fp32_operand_a = 32'h7fc0_1234;
            4'd5: fp32_operand_a = 32'h8000_0000;
            4'd6: fp32_operand_a = 32'h7f7f_ffff;
            4'd7: fp32_operand_a = 32'h0080_0000;
            4'd8: fp32_operand_a = 32'h3fc0_0000;
            4'd9: fp32_operand_a = 32'h3f80_0000;
            4'd10: fp32_operand_a = 32'h0000_0001;
            4'd11: fp32_operand_a = 32'hff7f_ffff;
            4'd12: fp32_operand_a = 32'h0000_0000;
            4'd13: fp32_operand_a = 32'h3f80_0000;
            4'd14: fp32_operand_a = 32'hbf80_0000;
            default: fp32_operand_a = 32'h4050_0000;
        endcase
        end
    endfunction

    function automatic [31:0] fp32_operand_b(input [4:0] pattern);
        if (pattern[4]) fp32_operand_b = {pattern[0],
            pattern[3], pattern[2:0], pattern[3:1], ~pattern[0],
            {5{pattern[3:0]}}, pattern[2:0]};
        else begin
        case (pattern[3:0])
            4'd0: fp32_operand_b = 32'h4000_0000;
            4'd1: fp32_operand_b = 32'h4000_0000;
            4'd2: fp32_operand_b = 32'hc000_0000;
            4'd3: fp32_operand_b = 32'hff80_0000;
            4'd4: fp32_operand_b = 32'h3f80_0000;
            4'd5: fp32_operand_b = 32'h0000_0000;
            4'd6: fp32_operand_b = 32'h7f7f_ffff;
            4'd7: fp32_operand_b = 32'h8080_0000;
            4'd8: fp32_operand_b = 32'h3f00_0000;
            4'd9: fp32_operand_b = 32'h3000_0000;
            4'd10: fp32_operand_b = 32'h0000_0001;
            4'd11: fp32_operand_b = 32'hff7f_ffff;
            4'd12: fp32_operand_b = 32'hbf80_0000;
            4'd13: fp32_operand_b = 32'h7f80_0000;
            4'd14: fp32_operand_b = 32'hc000_0000;
            default: fp32_operand_b = 32'hbfa0_0000;
        endcase
        end
    endfunction

    function automatic [31:0] fp32_expected(input [4:0] pattern);
        if (pattern[4]) fp32_expected = fp32_operand_b(pattern);
        else begin
        case (pattern[3:0])
            4'd0: fp32_expected = 32'h4040_0000;
            4'd1: fp32_expected = 32'h3f80_0000;
            4'd2: fp32_expected = 32'hbf80_0000;
            4'd3: fp32_expected = 32'h7fc0_0000;
            4'd4: fp32_expected = 32'h7fc0_0000;
            4'd5: fp32_expected = 32'h0000_0000;
            4'd6: fp32_expected = 32'h7f80_0000;
            4'd7: fp32_expected = 32'h0000_0000;
            4'd8: fp32_expected = 32'h4000_0000;
            4'd9: fp32_expected = 32'h3f80_0000;
            4'd10: fp32_expected = 32'h0000_0002;
            4'd11: fp32_expected = 32'hff80_0000;
            4'd12: fp32_expected = 32'hbf80_0000;
            4'd13: fp32_expected = 32'h7f80_0000;
            4'd14: fp32_expected = 32'hc040_0000;
            default: fp32_expected = 32'h4000_0000;
        endcase
        end
    endfunction

    function automatic [15:0] fp16_operand_a(input [4:0] pattern);
        if (pattern[4]) fp16_operand_a = 16'h0000;
        else begin
        case (pattern[3:0])
            4'd0: fp16_operand_a = 16'h3c00;
            4'd1: fp16_operand_a = 16'hbc00;
            4'd2: fp16_operand_a = 16'h3c00;
            4'd3: fp16_operand_a = 16'h7c00;
            4'd4: fp16_operand_a = 16'h7e12;
            4'd5: fp16_operand_a = 16'h8000;
            4'd6: fp16_operand_a = 16'h7bff;
            4'd7: fp16_operand_a = 16'h0400;
            4'd8: fp16_operand_a = 16'h3e00;
            4'd9: fp16_operand_a = 16'h3c00;
            4'd10: fp16_operand_a = 16'h0001;
            4'd11: fp16_operand_a = 16'hfbff;
            4'd12: fp16_operand_a = 16'h0000;
            4'd13: fp16_operand_a = 16'h3c00;
            4'd14: fp16_operand_a = 16'hbc00;
            default: fp16_operand_a = 16'h4280;
        endcase
        end
    endfunction

    function automatic [15:0] fp16_operand_b(input [4:0] pattern);
        if (pattern[4]) fp16_operand_b = {pattern[0], pattern[3],
            pattern[2:0], ~pattern[0], {2{pattern[3:0]}}, pattern[1:0]};
        else begin
        case (pattern[3:0])
            4'd0: fp16_operand_b = 16'h4000;
            4'd1: fp16_operand_b = 16'h4000;
            4'd2: fp16_operand_b = 16'hc000;
            4'd3: fp16_operand_b = 16'hfc00;
            4'd4: fp16_operand_b = 16'h3c00;
            4'd5: fp16_operand_b = 16'h0000;
            4'd6: fp16_operand_b = 16'h7bff;
            4'd7: fp16_operand_b = 16'h8400;
            4'd8: fp16_operand_b = 16'h3800;
            4'd9: fp16_operand_b = 16'h1000;
            4'd10: fp16_operand_b = 16'h0001;
            4'd11: fp16_operand_b = 16'hfbff;
            4'd12: fp16_operand_b = 16'hbc00;
            4'd13: fp16_operand_b = 16'h7c00;
            4'd14: fp16_operand_b = 16'hc000;
            default: fp16_operand_b = 16'hbd00;
        endcase
        end
    endfunction

    function automatic [15:0] fp16_expected(input [4:0] pattern);
        if (pattern[4]) fp16_expected = fp16_operand_b(pattern);
        else begin
        case (pattern[3:0])
            4'd0: fp16_expected = 16'h4200;
            4'd1: fp16_expected = 16'h3c00;
            4'd2: fp16_expected = 16'hbc00;
            4'd3: fp16_expected = 16'h7e00;
            4'd4: fp16_expected = 16'h7e00;
            4'd5: fp16_expected = 16'h0000;
            4'd6: fp16_expected = 16'h7c00;
            4'd7: fp16_expected = 16'h0000;
            4'd8: fp16_expected = 16'h4000;
            4'd9: fp16_expected = 16'h3c00;
            4'd10: fp16_expected = 16'h0002;
            4'd11: fp16_expected = 16'hfc00;
            4'd12: fp16_expected = 16'hbc00;
            4'd13: fp16_expected = 16'h7c00;
            4'd14: fp16_expected = 16'hc200;
            default: fp16_expected = 16'h4000;
        endcase
        end
    endfunction

    function automatic [15:0] bf16_operand_a(input [4:0] pattern);
        reg [31:0] expanded;
        begin
            expanded = fp32_operand_a(pattern);
            bf16_operand_a = expanded[31:16];
        end
    endfunction

    function automatic [15:0] bf16_operand_b(input [4:0] pattern);
        reg [31:0] expanded;
        begin
            expanded = fp32_operand_b(pattern);
            bf16_operand_b = expanded[31:16];
        end
    endfunction

    function automatic [15:0] bf16_expected(input [4:0] pattern);
        reg [31:0] expanded;
        begin
            expanded = fp32_expected(pattern);
            bf16_expected = expanded[31:16];
        end
    endfunction

    coll_reduction_engine u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .valid_i(valid_i),
        .dtype_i(dtype_i), .byte_valid_i(byte_valid_i),
        .local_i(local_i), .remote_i(remote_i), .valid_o(valid_o),
        .result_o(result_o), .byte_valid_o(byte_valid_o)
    );

    always #0.5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_count <= 0;
        else cycle_count <= cycle_count + 1;
    end

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drive_count <= 0;
            valid_i <= 1'b0;
            dtype_i <= `COLL_DTYPE_INT32;
            byte_valid_i <= 64'hffff_ffff_ffff_ffff;
            local_i <= 512'd0;
            remote_i <= 512'd0;
        end else if (drive_count < STREAM_FLITS) begin
            valid_i <= 1'b1;
            dtype_i <= drive_count[1:0];
            case (drive_count[1:0])
                `COLL_DTYPE_INT32: begin
                    local_i <= {16{32'h1020_3040 ^ drive_count}};
                    remote_i <= {16{32'h89ab_cdef + drive_count}};
                end
                `COLL_DTYPE_FP32: begin
                    local_i <= {16{fp32_operand_a(drive_count[6:2])}};
                    remote_i <= {16{fp32_operand_b(drive_count[6:2])}};
                end
                `COLL_DTYPE_FP16: begin
                    local_i <= {32{fp16_operand_a(drive_count[6:2])}};
                    remote_i <= {32{fp16_operand_b(drive_count[6:2])}};
                end
                default: begin
                    local_i <= {32{bf16_operand_a(drive_count[6:2])}};
                    remote_i <= {32{bf16_operand_b(drive_count[6:2])}};
                end
            endcase
            drive_count <= drive_count + 1;
        end else begin
            valid_i <= 1'b0;
        end
    end

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_count <= 0;
            last_output_cycle <= -1;
            expected_dtype <= 0;
        end else if (valid_o) begin
            expected_dtype = output_count % 4;
            if (last_output_cycle >= 0 && cycle_count != last_output_cycle + 1)
                $fatal(1, "reduction dtype stream contains a bubble output=%0d cycle=%0d last=%0d",
                    output_count, cycle_count, last_output_cycle);
            case (expected_dtype)
                `COLL_DTYPE_INT32:
                    if (result_o != {16{(32'h1020_3040 ^ output_count) +
                        (32'h89ab_cdef + output_count)}})
                        $fatal(1, "INT32 mixed-stream reduction mismatch output=%0d", output_count);
                `COLL_DTYPE_FP32:
                    if (result_o != {16{fp32_expected(output_count[6:2])}})
                        $fatal(1, "FP32 mixed-stream reduction mismatch output=%0d", output_count);
                `COLL_DTYPE_FP16:
                    if (result_o != {32{fp16_expected(output_count[6:2])}})
                        $fatal(1, "FP16 mixed-stream reduction mismatch output=%0d", output_count);
                default:
                    if (result_o != {32{bf16_expected(output_count[6:2])}})
                        $fatal(1, "BF16 mixed-stream reduction mismatch output=%0d", output_count);
            endcase
            if (byte_valid_o != 64'hffff_ffff_ffff_ffff)
                $fatal(1, "reduction dtype metadata mismatch output=%0d", output_count);
            output_count <= output_count + 1;
            last_output_cycle <= cycle_count;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        valid_i = 1'b0;
        dtype_i = `COLL_DTYPE_INT32;
        byte_valid_i = 64'hffff_ffff_ffff_ffff;
        local_i = 512'd0;
        remote_i = 512'd0;
        drive_count = 0;
        output_count = 0;
        cycle_count = 0;
        last_output_cycle = -1;
        expected_dtype = 0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        wait (output_count == STREAM_FLITS);
        @(negedge clk);
        if (valid_o) $fatal(1, "reduction dtype stream emitted excess output");
        if (last_output_cycle < 0 || output_count != STREAM_FLITS)
            $fatal(1, "reduction dtype stream completion mismatch outputs=%0d", output_count);
        $display("TB_KDLINK_REDUCTION_DTYPE_II1_PASS flits=%0d dtypes=INT32,FP32,FP16,BF16 output_bubbles=0 initiation_interval=1 lanes32=16 lanes16=32 logical_clock_GHz=1.000",
            STREAM_FLITS);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "KDLink reduction dtype II=1 timeout");
    end
endmodule
