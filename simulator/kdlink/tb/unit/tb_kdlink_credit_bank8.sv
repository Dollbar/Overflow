`timescale 1ns/1ps
module tb_kdlink_credit_bank8;
    logic clk;
    logic rst_n;
    logic clear;
    logic send_valid;
    logic [2:0] send_vc;
    logic return_valid;
    logic [2:0] return_vc;
    logic [15:0] return_total;
    wire [7:0] admit;
    wire [127:0] credit_count;
    wire underflow;
    wire overflow;
    wire stale_return;
    wire [127:0] wide_credit_count;
    wire wide_underflow;
    wire wide_overflow;
    wire wide_stale_return;
    integer index;

    kdlink_credit_bank8 #(.INITIAL_CREDITS(16'd4)) u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(clear),
        .send_valid_i(send_valid), .send_vc_i(send_vc),
        .return_valid_i(return_valid), .return_vc_i(return_vc),
        .return_total_i(return_total), .admit_o(admit),
        .credit_count_o(credit_count), .underflow_o(underflow),
        .overflow_o(overflow), .stale_return_o(stale_return)
    );

    kdlink_credit_bank8 #(.INITIAL_CREDITS(16'hfffe)) u_dut_wide (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(clear),
        .send_valid_i(send_valid), .send_vc_i(send_vc),
        .return_valid_i(return_valid), .return_vc_i(return_vc),
        .return_total_i(return_total), .admit_o(),
        .credit_count_o(wide_credit_count), .underflow_o(wide_underflow),
        .overflow_o(wide_overflow), .stale_return_o(wide_stale_return)
    );

    always #0.5 clk = ~clk;

    task drive_cycle;
        input drive_send;
        input [2:0] drive_send_vc;
        input drive_return;
        input [2:0] drive_return_vc;
        input [15:0] drive_return_total;
        begin
            @(negedge clk);
            send_valid = drive_send;
            send_vc = drive_send_vc;
            return_valid = drive_return;
            return_vc = drive_return_vc;
            return_total = drive_return_total;
            @(posedge clk);
            #0.01;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        clear = 1'b0;
        send_valid = 1'b0;
        send_vc = 3'd0;
        return_valid = 1'b0;
        return_vc = 3'd0;
        return_total = 16'd0;
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        @(posedge clk); #0.01;
        if (credit_count != {8{16'd4}} || admit != 8'hff)
            $fatal(1, "credit reset value mismatch");

        for (index = 0; index < 4; index = index + 1)
            drive_cycle(1'b1, 3'd0, 1'b0, 3'd0, 16'd0);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd0);
        if (credit_count[15:0] != 16'd0 || admit[0])
            $fatal(1, "credit exhaustion mismatch");
        drive_cycle(1'b1, 3'd0, 1'b0, 3'd0, 16'd0);
        if (!underflow) $fatal(1, "credit underflow was not detected");

        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd1);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd2);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd3);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd4);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd4);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd4);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd4);
        if (credit_count[15:0] != 16'd4)
            $fatal(1, "pipelined cumulative returns were not conserved");

        drive_cycle(1'b1, 3'd0, 1'b1, 3'd0, 16'd5);
        drive_cycle(1'b1, 3'd0, 1'b0, 3'd0, 16'd5);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd5);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd5);
        if (credit_count[15:0] != 16'd3 || overflow)
            $fatal(1, "same-VC send and pending return merge mismatch");
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd5);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd5);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd5);
        if (!stale_return) $fatal(1, "duplicate cumulative return was not stale");
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd4);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd4);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd4);
        if (!stale_return) $fatal(1, "backward cumulative return was not stale");
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd10);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd10);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd10);
        if (!overflow) $fatal(1, "oversized cumulative delta was not rejected");

        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd6);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd6);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd6);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd6);
        if (overflow || credit_count[15:0] != 16'd4)
            $fatal(1, "credit refill before cap test mismatch");
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd7);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd7);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd7);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd7);
        if (!overflow || credit_count[15:0] != 16'd4)
            $fatal(1, "credit-cap overflow was not saturated");

        drive_cycle(1'b1, 3'd0, 1'b0, 3'd0, 16'd7);
        drive_cycle(1'b1, 3'd0, 1'b0, 3'd0, 16'd7);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd8);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd7);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd9);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd10);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd10);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd10);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd10);
        if (credit_count[15:0] != 16'd3)
            $fatal(1, "invalid cumulative chain was not flushed");
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd0, 16'd9);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd9);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd9);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd0, 16'd9);
        if (credit_count[15:0] != 16'd4)
            $fatal(1, "cumulative chain did not recover from committed total");

        @(negedge clk); clear = 1'b1;
        @(posedge clk); #0.01;
        @(negedge clk); clear = 1'b0;
        if (credit_count != 128'd0 || admit != 8'd0)
            $fatal(1, "credit epoch clear mismatch");
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd7, 16'd1);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'd1);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'd1);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'd1);
        if (credit_count[7*16 +: 16] != 16'd1 || !admit[7])
            $fatal(1, "post-clear VC7 credit return mismatch");
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd7, 16'h00ff);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h00ff);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h00ff);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h00ff);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd7, 16'h0100);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h0100);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h0100);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h0100);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd7, 16'h0fff);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h0fff);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h0fff);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h0fff);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd7, 16'h1000);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h1000);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h1000);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h1000);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd7, 16'h7fff);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h7fff);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h7fff);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h7fff);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd7, 16'h8000);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h8000);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h8000);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'h8000);
        drive_cycle(1'b0, 3'd0, 1'b1, 3'd7, 16'hfffd);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'hfffd);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'hfffd);
        drive_cycle(1'b0, 3'd0, 1'b0, 3'd7, 16'hfffd);
        if (wide_credit_count[7*16 +: 16] != 16'hfffd ||
            wide_underflow || wide_overflow || wide_stale_return)
            $fatal(1, "wide cumulative credit exercise failed credit=%h errors=%b%b%b",
                wide_credit_count[7*16 +: 16], wide_underflow,
                wide_overflow, wide_stale_return);
        $display("TB_KDLINK_CREDIT_BANK8_PASS exhaustion=1 underflow=1 cumulative_ii1=1 same_vc_merge=1 stale=1 overflow=1 chain_flush=1 clear=1");
        $finish;
    end
endmodule
