`timescale 1ns/1ps
`include "collective_defs.vh"

module tb_kdlink_v2_reduction_dtype_ii1;
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
                    local_i <= {16{32'd1}};
                    remote_i <= {16{32'd2}};
                end
                `COLL_DTYPE_FP32: begin
                    local_i <= {16{32'h3f80_0000}};
                    remote_i <= {16{32'h4000_0000}};
                end
                `COLL_DTYPE_FP16: begin
                    local_i <= {32{16'h3c00}};
                    remote_i <= {32{16'h4000}};
                end
                default: begin
                    local_i <= {32{16'h3f80}};
                    remote_i <= {32{16'h4000}};
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
                    if (result_o != {16{32'd3}})
                        $fatal(1, "INT32 mixed-stream reduction mismatch output=%0d", output_count);
                `COLL_DTYPE_FP32:
                    if (result_o != {16{32'h4040_0000}})
                        $fatal(1, "FP32 mixed-stream reduction mismatch output=%0d", output_count);
                `COLL_DTYPE_FP16:
                    if (result_o != {32{16'h4200}})
                        $fatal(1, "FP16 mixed-stream reduction mismatch output=%0d", output_count);
                default:
                    if (result_o != {32{16'h4040}})
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
        $display("TB_KDLINK_V2_REDUCTION_DTYPE_II1_PASS flits=%0d dtypes=INT32,FP32,FP16,BF16 output_bubbles=0 initiation_interval=1 lanes32=16 lanes16=32 logical_clock_GHz=1.000",
            STREAM_FLITS);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "KDLink-v2 reduction dtype II=1 timeout");
    end
endmodule
