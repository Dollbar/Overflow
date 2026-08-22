`timescale 1ns/1ps
module tb_kdlink_vc_ingress8;
    reg core_clk;
    reg phy_clk;
    reg core_rst_n;
    reg phy_rst_n;
    reg core_valid;
    wire core_ready;
    reg [2:0] core_vc;
    reg [607:0] core_body;
    reg [7:0] admit;
    reg service_enable;
    wire phy_valid;
    reg phy_ready;
    wire [2:0] phy_vc;
    wire [607:0] phy_body;
    wire packet_error;
    wire cdc_error;
    integer receive_count;
    integer overlength_index;
    reg [2:0] received_vc [0:31];
    reg [15:0] received_tag [0:31];

    kdlink_vc_ingress8 #(.FIFO_ADDR_BITS(3)) dut (
        .core_clk_i(core_clk), .core_rst_n_i(core_rst_n),
        .core_valid_i(core_valid), .core_ready_o(core_ready),
        .core_vc_i(core_vc), .core_body_i(core_body),
        .phy_clk_i(phy_clk), .phy_rst_n_i(phy_rst_n),
        .admit_i(admit), .service_enable_i(service_enable),
        .phy_valid_o(phy_valid), .phy_ready_i(phy_ready),
        .phy_vc_o(phy_vc), .phy_body_o(phy_body),
        .packet_error_o(packet_error), .cdc_error_o(cdc_error)
    );

    always #3 core_clk = ~core_clk;
    always #2 phy_clk = ~phy_clk;

    always @(posedge phy_clk) begin
        if (phy_rst_n && phy_valid && phy_ready) begin
            received_vc[receive_count] <= phy_vc;
            received_tag[receive_count] <= phy_body[15:0];
            receive_count <= receive_count + 1;
        end
    end

    task send_flit;
        input [2:0] vc;
        input sop;
        input eop;
        input [15:0] tag;
        begin
            @(negedge core_clk);
            core_vc = vc;
            core_body = {38{tag}};
            core_body[527:525] = vc;
            core_body[529] = sop;
            core_body[530] = eop;
            core_body[606:600] = 7'd64;
            core_body[15:0] = tag;
            core_valid = 1'b1;
            while (!core_ready) @(negedge core_clk);
            @(negedge core_clk);
            core_valid = 1'b0;
            core_body = 608'd0;
        end
    endtask

    task wait_count;
        input integer target;
        integer timeout_cycles;
        begin
            timeout_cycles = 0;
            while ((receive_count < target) && (timeout_cycles < 200)) begin
                @(posedge phy_clk);
                timeout_cycles = timeout_cycles + 1;
            end
            if (receive_count != target) $fatal(1, "timeout waiting for receive count %0d got %0d", target, receive_count);
        end
    endtask

    initial begin
        core_clk = 1'b0;
        phy_clk = 1'b0;
        core_rst_n = 1'b0;
        phy_rst_n = 1'b0;
        core_valid = 1'b0;
        core_vc = 3'd0;
        core_body = 608'd0;
        admit = 8'hff;
        service_enable = 1'b1;
        phy_ready = 1'b1;
        receive_count = 0;
        repeat (5) @(posedge core_clk);
        core_rst_n = 1'b1;
        repeat (5) @(posedge phy_clk);
        phy_rst_n = 1'b1;

        admit[2] = 1'b0;
        send_flit(3'd2, 1'b1, 1'b1, 16'h0200);
        send_flit(3'd3, 1'b1, 1'b1, 16'h0300);
        wait_count(1);
        if ((received_vc[0] != 3'd3) || (received_tag[0] != 16'h0300)) $fatal(1, "blocked VC caused HOL interference");
        admit[2] = 1'b1;
        wait_count(2);
        if ((received_vc[1] != 3'd2) || (received_tag[1] != 16'h0200)) $fatal(1, "released VC did not drain");

        send_flit(3'd1, 1'b1, 1'b0, 16'h1100);
        wait_count(3);
        send_flit(3'd7, 1'b1, 1'b1, 16'h7700);
        repeat (12) @(posedge phy_clk);
        if (receive_count != 3) $fatal(1, "management traffic interleaved into a locked packet");
        send_flit(3'd1, 1'b0, 1'b1, 16'h1101);
        wait_count(5);
        if ((received_vc[3] != 3'd1) || (received_tag[3] != 16'h1101)) $fatal(1, "packet owner did not retain service through EOP");
        if ((received_vc[4] != 3'd7) || (received_tag[4] != 16'h7700)) $fatal(1, "management traffic did not resume after EOP");

        phy_ready = 1'b0;
        send_flit(3'd1, 1'b1, 1'b1, 16'h0001);
        send_flit(3'd2, 1'b1, 1'b1, 16'h0002);
        send_flit(3'd3, 1'b1, 1'b1, 16'h0003);
        send_flit(3'd4, 1'b1, 1'b1, 16'h0004);
        repeat (12) @(posedge phy_clk);
        phy_ready = 1'b1;
        wait_count(9);
        if ((received_vc[5] != 3'd2) || (received_vc[6] != 3'd3) ||
            (received_vc[7] != 3'd4) || (received_vc[8] != 3'd1))
            $fatal(1, "data VC round-robin order mismatch");
        if (packet_error) $fatal(1, "unexpected packet format error");
        if (cdc_error) $fatal(1, "unexpected CDC FIFO protocol error");
        phy_ready = 1'b0;
        send_flit(3'd5, 1'b1, 1'b1, 16'h5a5a);
        send_flit(3'd6, 1'b1, 1'b1, 16'ha6a6);
        service_enable = 1'b0;
        phy_ready = 1'b1;
        repeat (8) @(posedge phy_clk);
        if (receive_count != 9) $fatal(1, "service disable did not suppress queued traffic");
        service_enable = 1'b1;
        wait_count(11);
        if ((received_vc[9] != 3'd6) || (received_tag[9] != 16'ha6a6) ||
            (received_vc[10] != 3'd5) || (received_tag[10] != 16'h5a5a))
            $fatal(1, "replay and control VC priority mismatch");
        send_flit(3'd1, 1'b1, 1'b0, 16'h2000);
        send_flit(3'd7, 1'b1, 1'b1, 16'h7f00);
        for (overlength_index = 1; overlength_index < 16; overlength_index = overlength_index + 1)
            send_flit(3'd1, 1'b0, 1'b0, 16'h2000 + overlength_index[15:0]);
        wait_count(28);
        if (!packet_error || received_vc[27] != 3'd7 || received_tag[27] != 16'h7f00)
            $fatal(1, "packet length limit did not release management service");
        @(negedge phy_clk); admit = 8'h00;
        repeat (2) @(posedge phy_clk);
        @(negedge phy_clk); admit = 8'hff;
        repeat (2) @(posedge phy_clk);
        @(negedge core_clk); core_rst_n = 1'b0;
        @(negedge phy_clk); phy_rst_n = 1'b0;
        repeat (6) @(posedge phy_clk); #0.01;
        if (phy_valid || packet_error || cdc_error)
            $fatal(1, "VC ingress runtime reset did not restore safe state valid=%b packet=%b cdc=%b",
                phy_valid, packet_error, cdc_error);
        @(negedge core_clk); core_rst_n = 1'b1;
        repeat (4) @(posedge phy_clk);
        @(negedge phy_clk); phy_rst_n = 1'b1;
        @(negedge core_clk);
        core_vc = 3'd0;
        core_body = 608'd0;
        core_body[527:525] = 3'd1;
        core_body[529] = 1'b1;
        core_body[530] = 1'b1;
        core_body[606:600] = 7'd64;
        core_valid = 1'b1;
        while (!core_ready) @(negedge core_clk);
        @(negedge core_clk); core_valid = 1'b0;
        repeat (12) @(posedge phy_clk);
        if (!packet_error)
            $fatal(1, "VC/header identity mismatch did not raise packet error");
        $display("TB_KDLINK_VC_INGRESS8_PASS hol_isolation=1 packet_lock=1 priority=1 data_rr=1 vcs=8 cdc=1 max_packet_flits=16 admit_sweep=1 runtime_reset=1 vc_identity_error=1");
        $finish;
    end
endmodule
