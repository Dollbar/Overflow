module formal_vc_service;
    (* gclk *) reg clk;
    reg past_valid;
    wire rst_n;
    (* anyseq *) reg core_valid;
    (* anyseq *) reg [2:0] core_vc;
    (* anyseq *) reg [607:0] core_body;
    (* anyseq *) reg [7:0] admit;
    wire core_ready;
    wire phy_valid;
    wire [2:0] phy_vc;
    wire [607:0] phy_body;
    wire packet_error;
    wire cdc_error;
    wire [7:0] pending_vc;
    wire packet_locked;
    wire [2:0] packet_vc;
    wire [3:0] packet_flit_count;
    reg [4:0] management_wait_q;
    reg [4:0] replay_wait_q;

    initial begin
        past_valid = 1'b0;
        management_wait_q = 5'd0;
        replay_wait_q = 5'd0;
    end

    assign rst_n = past_valid;

    kdlink_vc_ingress8 #(.FIFO_ADDR_BITS(2)) u_dut (
        .core_clk_i(clk), .core_rst_n_i(rst_n),
        .core_valid_i(core_valid), .core_ready_o(core_ready),
        .core_vc_i(core_vc), .core_body_i(core_body),
        .phy_clk_i(clk), .phy_rst_n_i(rst_n), .admit_i(admit),
        .service_enable_i(1'b1), .phy_valid_o(phy_valid),
        .phy_ready_i(1'b1), .phy_vc_o(phy_vc), .phy_body_o(phy_body),
        .packet_error_o(packet_error), .cdc_error_o(cdc_error),
        .audit_pending_vc_o(pending_vc), .audit_packet_locked_o(packet_locked),
        .audit_packet_vc_o(packet_vc), .audit_packet_flit_count_o(packet_flit_count)
    );

    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            management_wait_q <= 5'd0;
            replay_wait_q <= 5'd0;
        end else begin
            if (core_valid)
                assume (core_body[527:525] == core_vc);
            if (packet_locked) begin
                assume (pending_vc[packet_vc]);
                assume (admit[packet_vc]);
                assert (packet_flit_count >= 4'd1);
                assert (packet_flit_count <= 4'd15);
                if (phy_valid)
                    assert (phy_vc == packet_vc);
            end
            if (!packet_locked && pending_vc[7] && admit[7])
                assert (phy_valid && phy_vc == 3'd7);
            if (!packet_locked && !pending_vc[7] && pending_vc[6] && admit[6])
                assert (phy_valid && phy_vc == 3'd6);
            if (pending_vc[7] && admit[7] &&
                !(phy_valid && phy_vc == 3'd7))
                management_wait_q <= management_wait_q + 1'b1;
            else
                management_wait_q <= 5'd0;
            if (!pending_vc[7] && pending_vc[6] && admit[6] &&
                !(phy_valid && phy_vc == 3'd6))
                replay_wait_q <= replay_wait_q + 1'b1;
            else
                replay_wait_q <= 5'd0;
            assert (management_wait_q <= 5'd16);
            assert (replay_wait_q <= 5'd16);
            assert (!cdc_error);
        end
    end
endmodule
