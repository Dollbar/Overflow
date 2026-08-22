`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_link_manager;
    reg clk;
    reg rst_n;
    reg enable;
    reg [7:0] epoch;
    reg rx_activity;
    reg rx_credit_valid;
    reg [2:0] rx_credit_vc;
    reg rx_init_ack;
    reg rx_keepalive_ack;
    reg rx_link_reset;
    wire event_valid;
    reg event_ready;
    wire [3:0] event_type;
    wire [2:0] event_vc;
    wire [4:0] event_destination;
    wire [15:0] event_credit_total;
    wire [7:0] event_status;
    wire link_up;
    wire reinitialize;
    wire [2:0] state;
    integer credit_events;
    integer init_events;
    integer keepalive_events;
    integer reset_events;
    integer reinitialize_events;
    integer vc_index;
    integer timeout_cycles;

    kdlink_link_manager #(
        .INITIAL_CREDITS(16'hffff), .KEEPALIVE_CYCLES(4), .TIMEOUT_CYCLES(16)
    ) dut (
        .clk_i(clk), .rst_n_i(rst_n), .enable_i(enable),
        .peer_node_i(5'd9), .link_epoch_i(epoch),
        .rx_activity_i(rx_activity), .rx_credit_valid_i(rx_credit_valid),
        .rx_credit_vc_i(rx_credit_vc), .rx_init_ack_i(rx_init_ack),
        .rx_keepalive_ack_i(rx_keepalive_ack), .rx_link_reset_i(rx_link_reset),
        .event_valid_o(event_valid), .event_ready_i(event_ready),
        .event_type_o(event_type), .event_vc_o(event_vc),
        .event_dst_node_o(event_destination),
        .event_credit_total_o(event_credit_total),
        .event_status_o(event_status), .link_up_o(link_up),
        .reinitialize_o(reinitialize), .state_o(state)
    );

    always #1 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n && event_valid && event_ready) begin
            if (event_destination != 5'd9) $fatal(1, "management destination mismatch");
            case (event_type)
                `KDL_REVERSE_TYPE_CREDIT: begin
                    if (event_credit_total != 16'hffff) $fatal(1, "initial credit total mismatch");
                    credit_events <= credit_events + 1;
                end
                `KDL_REVERSE_TYPE_INIT_ACK: init_events <= init_events + 1;
                `KDL_REVERSE_TYPE_KEEPALIVE_ACK: keepalive_events <= keepalive_events + 1;
                `KDL_REVERSE_TYPE_LINK_RESET: reset_events <= reset_events + 1;
                default: $fatal(1, "unexpected management event type %0d", event_type);
            endcase
        end
        if (rst_n && reinitialize) reinitialize_events <= reinitialize_events + 1;
    end

    task advertise_peer;
        begin
            for (vc_index = 0; vc_index < 8; vc_index = vc_index + 1) begin
                @(negedge clk);
                rx_credit_vc = vc_index[2:0];
                rx_credit_valid = 1'b1;
                rx_activity = 1'b1;
                @(negedge clk);
                rx_credit_valid = 1'b0;
                rx_activity = 1'b0;
            end
            @(negedge clk);
            rx_init_ack = 1'b1;
            rx_activity = 1'b1;
            @(negedge clk);
            rx_init_ack = 1'b0;
            rx_activity = 1'b0;
        end
    endtask

    task wait_link_up;
        begin
            timeout_cycles = 0;
            while (!link_up && timeout_cycles < 100) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            if (!link_up || state != 3'd4) $fatal(1, "link did not reach operational state");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        enable = 1'b0;
        epoch = 8'h20;
        rx_activity = 1'b0;
        rx_credit_valid = 1'b0;
        rx_credit_vc = 3'd0;
        rx_init_ack = 1'b0;
        rx_keepalive_ack = 1'b0;
        rx_link_reset = 1'b0;
        event_ready = 1'b1;
        credit_events = 0;
        init_events = 0;
        keepalive_events = 0;
        reset_events = 0;
        reinitialize_events = 0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1; enable = 1'b1;
        wait (state == 3'd3);
        advertise_peer();
        wait_link_up();
        if (credit_events != 8 || init_events != 1) $fatal(1, "initial negotiation event count mismatch");

        wait (keepalive_events == 1);
        @(negedge clk); rx_keepalive_ack = 1'b1; rx_activity = 1'b1;
        @(negedge clk); rx_keepalive_ack = 1'b0; rx_activity = 1'b0;

        @(negedge clk); enable = 1'b0;
        wait (!link_up && state == 3'd0);
        @(negedge clk); enable = 1'b1;
        wait (state == 3'd3);
        advertise_peer();
        wait_link_up();
        if (credit_events != 16 || init_events != 2)
            $fatal(1, "administrative disable recovery event count mismatch");

        @(negedge clk); epoch = 8'ha5;
        wait (!link_up && state == 3'd1);
        wait (state == 3'd3);
        advertise_peer();
        wait_link_up();
        if (credit_events != 24 || init_events != 3) $fatal(1, "epoch renegotiation event count mismatch");

        @(negedge clk); rx_link_reset = 1'b1; rx_activity = 1'b1;
        @(negedge clk); rx_link_reset = 1'b0; rx_activity = 1'b0;
        wait (!link_up && state == 3'd1);
        wait (state == 3'd3);
        advertise_peer();
        wait_link_up();
        if (credit_events != 32 || init_events != 4)
            $fatal(1, "peer reset recovery event count mismatch");

        @(negedge clk); epoch = 8'h5a;
        wait (!link_up && state == 3'd1);
        wait (state == 3'd3);
        advertise_peer();
        wait_link_up();
        if (credit_events != 40 || init_events != 5)
            $fatal(1, "second high-entropy epoch recovery event count mismatch");

        timeout_cycles = 0;
        while ((reset_events == 0) && (timeout_cycles < 100)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (reset_events != 1) $fatal(1, "peer-silence timeout did not emit LINK_RESET");
        repeat (2) @(posedge clk);
        if (reinitialize_events < 5) $fatal(1, "reinitialization pulses did not cover startup disable epoch peer reset and timeout");
        if (event_status[2:0] > 3'd5) $fatal(1, "invalid exported state status");
        $display("TB_KDLINK_LINK_MANAGER_PASS credits=40 init=5 keepalive=%0d timeout_reset=1 epoch_recovery=2 disable_recovery=1 peer_reset=1", keepalive_events);
        $finish;
    end
endmodule
