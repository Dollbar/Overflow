`timescale 1ns/1ps
module tb_kdlink_reduction_random;
    localparam integer STREAM_FLITS = 8192;
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
    logic [63:0] lfsr_a;
    logic [63:0] lfsr_b;
    logic [63:0] expected_mask [0:STREAM_FLITS-1];
    logic [63:0] result_checksum;
    integer drive_count;
    integer output_count;
    integer cycle_count;
    integer last_output_cycle;

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
            dtype_i <= 2'd0;
            byte_valid_i <= 64'd0;
            local_i <= 512'd0;
            remote_i <= 512'd0;
            lfsr_a <= 64'hd6e8_feb8_6659_fd93;
            lfsr_b <= 64'ha5a3_56e1_7c92_4f0d;
        end else if (drive_count < STREAM_FLITS) begin
            valid_i <= 1'b1;
            dtype_i <= drive_count[1:0];
            byte_valid_i <= lfsr_a ^ {lfsr_b[31:0], lfsr_b[63:32]};
            local_i <= {lfsr_a, lfsr_b, lfsr_a ^ lfsr_b, ~lfsr_a,
                {lfsr_a[30:0], lfsr_a[63:31]}, {lfsr_b[46:0], lfsr_b[63:47]},
                lfsr_a + lfsr_b, lfsr_a - lfsr_b};
            remote_i <= {~lfsr_b, lfsr_a ^ 64'hffff_0000_aaaa_5555,
                lfsr_b + 64'h9e37_79b9_7f4a_7c15, lfsr_a - lfsr_b,
                {lfsr_b[6:0], lfsr_b[63:7]}, {lfsr_a[52:0], lfsr_a[63:53]},
                lfsr_a + 64'hc2b2_ae3d_27d4_eb4f, lfsr_a ^ lfsr_b};
            expected_mask[drive_count] <= lfsr_a ^ {lfsr_b[31:0], lfsr_b[63:32]};
            lfsr_a <= {lfsr_a[62:0], lfsr_a[63] ^ lfsr_a[62] ^ lfsr_a[60] ^ lfsr_a[59]};
            lfsr_b <= {lfsr_b[62:0], lfsr_b[63] ^ lfsr_b[61] ^ lfsr_b[60] ^ lfsr_b[58]};
            drive_count <= drive_count + 1;
        end else begin
            valid_i <= 1'b0;
        end
    end

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_count <= 0;
            last_output_cycle <= -1;
            result_checksum <= 64'd0;
        end else if (valid_o) begin
            if (last_output_cycle >= 0 && cycle_count != last_output_cycle + 1)
                $fatal(1, "random reduction stream contains a bubble");
            if (byte_valid_o != expected_mask[output_count])
                $fatal(1, "random reduction byte mask mismatch output=%0d", output_count);
            result_checksum <= result_checksum ^ result_o[63:0] ^ result_o[255:192] ^ result_o[511:448];
            output_count <= output_count + 1;
            last_output_cycle <= cycle_count;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        valid_i = 1'b0;
        dtype_i = 2'd0;
        byte_valid_i = 64'd0;
        local_i = 512'd0;
        remote_i = 512'd0;
        lfsr_a = 64'hd6e8_feb8_6659_fd93;
        lfsr_b = 64'ha5a3_56e1_7c92_4f0d;
        drive_count = 0;
        output_count = 0;
        cycle_count = 0;
        last_output_cycle = -1;
        result_checksum = 64'd0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        wait (output_count == STREAM_FLITS);
        @(negedge clk);
        if (valid_o || result_checksum == 64'd0)
            $fatal(1, "random reduction completion or activity mismatch");
        $display("TB_KDLINK_REDUCTION_RANDOM_PASS flits=%0d dtypes=4 masks=random data=random output_bubbles=0 checksum=%h",
            STREAM_FLITS, result_checksum);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "KDLink random reduction timeout");
    end
endmodule
