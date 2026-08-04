`timescale 1ns/1ps
`default_nettype none

module tb_npu_noc_vip;

    import npu_noc_tb_pkg::*;

    localparam int unsigned PAYLOAD_BITS = CONTROL_BYTES * 8;
    localparam int unsigned KEEP_BITS = CONTROL_BYTES;
    localparam int unsigned TRAFFIC_CLASS_LSB = PAYLOAD_BITS + KEEP_BITS;
    localparam int unsigned DESTINATION_LSB = TRAFFIC_CLASS_LSB + 2;
    localparam int unsigned SOURCE_LSB = DESTINATION_LSB + 3;
    localparam int unsigned EOP_BIT = SOURCE_LSB + 3;
    localparam int unsigned SOP_BIT = EOP_BIT + 1;

    logic clk;
    logic rst;
    logic clear;
    logic submit_valid;
    logic submit_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] submit_flit;
    logic link_valid;
    logic link_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] link_flit;
    logic sink_enable;
    logic sink_stall;
    logic [63:0] submitted_flits;
    logic [63:0] transmitted_flits;
    logic [63:0] accepted_flits;
    logic [CONTROL_FLIT_WIDTH-1:0] last_sink_flit;
    logic sink_backpressure_seen;
    logic sink_protocol_error;
    logic [63:0] observed_flits;
    logic [63:0] observed_packets;
    logic sop_seen;
    logic eop_seen;
    logic [CONTROL_FLIT_WIDTH-1:0] last_monitor_flit;
    logic checker_protocol_error;
    logic framing_error;
    logic stability_error;
    logic metadata_error;
    logic length_error;
    logic checker_override;
    logic checker_valid;
    logic checker_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] checker_flit;
    logic forced_checker_valid;
    logic forced_checker_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] forced_checker_flit;

    assign checker_valid = checker_override ? forced_checker_valid : link_valid;
    assign checker_ready = checker_override ? forced_checker_ready : link_ready;
    assign checker_flit = checker_override ? forced_checker_flit : link_flit;

    npu_noc_flit_source_vip #(
        .FLIT_WIDTH(CONTROL_FLIT_WIDTH)
    ) source (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(clear),
        .submit_valid_i(submit_valid),
        .submit_ready_o(submit_ready),
        .submit_flit_i(submit_flit),
        .link_valid_o(link_valid),
        .link_ready_i(link_ready),
        .link_flit_o(link_flit),
        .submitted_flits_o(submitted_flits),
        .transmitted_flits_o(transmitted_flits)
    );

    npu_noc_flit_sink_vip #(
        .FLIT_WIDTH(CONTROL_FLIT_WIDTH)
    ) sink (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(clear),
        .enable_i(sink_enable),
        .stall_i(sink_stall),
        .link_valid_i(link_valid),
        .link_ready_o(link_ready),
        .link_flit_i(link_flit),
        .accepted_flits_o(accepted_flits),
        .last_flit_o(last_sink_flit),
        .backpressure_seen_o(sink_backpressure_seen),
        .protocol_error_o(sink_protocol_error)
    );

    npu_noc_flit_monitor_vip #(
        .FLIT_WIDTH(CONTROL_FLIT_WIDTH),
        .SOP_BIT(SOP_BIT),
        .EOP_BIT(EOP_BIT)
    ) monitor (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(clear),
        .link_valid_i(link_valid),
        .link_ready_i(link_ready),
        .link_flit_i(link_flit),
        .observed_flits_o(observed_flits),
        .observed_packets_o(observed_packets),
        .sop_seen_o(sop_seen),
        .eop_seen_o(eop_seen),
        .last_flit_o(last_monitor_flit)
    );

    npu_noc_protocol_checker_vip #(
        .FLIT_WIDTH(CONTROL_FLIT_WIDTH),
        .SOP_BIT(SOP_BIT),
        .EOP_BIT(EOP_BIT),
        .SOURCE_LSB(SOURCE_LSB),
        .DESTINATION_LSB(DESTINATION_LSB),
        .TRAFFIC_CLASS_LSB(TRAFFIC_CLASS_LSB),
        .MAX_PACKET_FLITS(4)
    ) u_checker (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(clear),
        .link_valid_i(checker_valid),
        .link_ready_i(checker_ready),
        .link_flit_i(checker_flit),
        .protocol_error_o(checker_protocol_error),
        .framing_error_o(framing_error),
        .stability_error_o(stability_error),
        .metadata_error_o(metadata_error),
        .length_error_o(length_error)
    );

    always #0.5 clk = ~clk;

    task automatic submit_one(
        input logic [CONTROL_FLIT_WIDTH-1:0] flit
    );
        @(negedge clk);
        submit_flit = flit;
        submit_valid = 1'b1;
        do @(posedge clk); while (!submit_ready);
        @(negedge clk);
        submit_valid = 1'b0;
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        clear = 1'b0;
        submit_valid = 1'b0;
        submit_flit = '0;
        sink_enable = 1'b1;
        sink_stall = 1'b0;
        checker_override = 1'b0;
        forced_checker_valid = 1'b0;
        forced_checker_ready = 1'b0;
        forced_checker_flit = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        fork
            begin
                submit_one(make_control_flit(
                    1'b1, 1'b0, 3'd1, 3'd6, 2'd2, 128'h10));
                submit_one(make_control_flit(
                    1'b0, 1'b0, 3'd1, 3'd6, 2'd2, 128'h11));
                submit_one(make_control_flit(
                    1'b0, 1'b0, 3'd1, 3'd6, 2'd2, 128'h12));
                submit_one(make_control_flit(
                    1'b0, 1'b1, 3'd1, 3'd6, 2'd2, 128'h13));
            end
            begin
                wait (link_valid);
                @(negedge clk);
                sink_stall = 1'b1;
                repeat (3) @(posedge clk);
                @(negedge clk);
                sink_stall = 1'b0;
            end
        join
        repeat (3) @(posedge clk);

        if (submitted_flits != 4 || transmitted_flits != 4 ||
            accepted_flits != 4 || observed_flits != 4 ||
            observed_packets != 1 || !sop_seen || !eop_seen ||
            !sink_backpressure_seen || sink_protocol_error ||
            checker_protocol_error || last_sink_flit !== last_monitor_flit) begin
            $fatal(1, "VIP legal-packet smoke mismatch");
        end

        @(negedge clk);
        clear = 1'b1;
        @(negedge clk);
        clear = 1'b0;
        submit_one(make_control_flit(
            1'b0, 1'b1, 3'd0, 3'd7, 2'd0, 128'hbad));
        repeat (2) @(posedge clk);
        if (!checker_protocol_error || !framing_error ||
            stability_error || metadata_error || length_error) begin
            $fatal(1, "VIP checker failed malformed-tail diagnosis");
        end

        // Isolate the passive checker and prove that a producer changing a
        // stalled flit is diagnosed independently of the well-behaved source.
        @(negedge clk);
        clear = 1'b1;
        checker_override = 1'b1;
        forced_checker_valid = 1'b1;
        forced_checker_ready = 1'b0;
        forced_checker_flit = make_control_flit(
            1'b1, 1'b1, 3'd2, 3'd5, 2'd1, 128'h1111);
        @(negedge clk);
        clear = 1'b0;
        @(negedge clk);
        forced_checker_flit = make_control_flit(
            1'b1, 1'b1, 3'd2, 3'd5, 2'd1, 128'h2222);
        repeat (2) @(posedge clk);
        if (!checker_protocol_error || !stability_error || framing_error ||
            metadata_error || length_error) begin
            $fatal(1, "VIP checker failed stall-stability diagnosis");
        end

        $display("PASS tb_npu_noc_vip legal_flits=4 malformed=1 unstable=1");
        $finish;
    end

endmodule

`default_nettype wire
