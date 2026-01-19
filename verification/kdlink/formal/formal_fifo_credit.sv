module formal_fifo_credit;
    (* gclk *) reg clk;
    reg past_valid;
    wire rst_n;
    (* anyseq *) reg fifo_push_valid;
    (* anyseq *) reg fifo_pop_ready;
    (* anyseq *) reg [7:0] fifo_push_data;
    wire fifo_push_ready;
    wire fifo_pop_valid;
    wire [2:0] fifo_occupancy;
    wire fifo_overflow;
    wire fifo_underflow;
    reg [2:0] fifo_shadow_q;
    (* anyseq *) reg send_valid;
    (* anyseq *) reg return_valid;
    wire [7:0] credit_admit;
    wire [127:0] credit_count;
    wire credit_underflow;
    wire credit_overflow;
    wire stale_return;
    reg [2:0] credit_shadow_q;
    reg credit_return_pending_q;
    reg credit_delta_pending_q;
    reg credit_input_pending_q;
    reg [15:0] return_total_q;
    wire [15:0] next_return_total;
    wire fifo_push_fire;
    wire fifo_pop_fire;

    initial begin
        past_valid = 1'b0;
        fifo_shadow_q = 3'd0;
        credit_shadow_q = 3'd4;
        credit_return_pending_q = 1'b0;
        credit_delta_pending_q = 1'b0;
        credit_input_pending_q = 1'b0;
        return_total_q = 16'd0;
    end
    assign rst_n = past_valid;
    assign fifo_push_fire = fifo_push_valid && fifo_push_ready;
    assign fifo_pop_fire = fifo_pop_ready && fifo_pop_valid;
    assign next_return_total = return_total_q + (return_valid ? 16'd1 : 16'd0);

    coll_sync_fifo #(.WIDTH(8), .DEPTH(4), .ADDR_W(2), .COUNT_W(3)) u_fifo (
        .clk_i(clk), .rst_n_i(rst_n), .push_data_i(fifo_push_data),
        .push_valid_i(fifo_push_valid), .push_ready_o(fifo_push_ready),
        .pop_data_o(), .pop_valid_o(fifo_pop_valid),
        .pop_ready_i(fifo_pop_ready), .occupancy_o(fifo_occupancy),
        .overflow_o(fifo_overflow), .underflow_o(fifo_underflow)
    );

    kdlink_credit_bank8 #(.INITIAL_CREDITS(16'd4)) u_credit (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(1'b0),
        .send_valid_i(send_valid), .send_vc_i(3'd0),
        .return_valid_i(return_valid), .return_vc_i(3'd0),
        .return_total_i(next_return_total), .admit_o(credit_admit),
        .credit_count_o(credit_count), .underflow_o(credit_underflow),
        .overflow_o(credit_overflow), .stale_return_o(stale_return)
    );

    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            fifo_shadow_q <= 3'd0;
            credit_shadow_q <= 3'd4;
            credit_return_pending_q <= 1'b0;
            credit_delta_pending_q <= 1'b0;
            credit_input_pending_q <= 1'b0;
            return_total_q <= 16'd0;
        end else begin
            assume (!send_valid || credit_shadow_q != 3'd0);
            assume (!credit_return_pending_q || credit_shadow_q != 3'd4 || send_valid);
            case ({fifo_push_fire, fifo_pop_fire})
                2'b10: fifo_shadow_q <= fifo_shadow_q + 1'b1;
                2'b01: fifo_shadow_q <= fifo_shadow_q - 1'b1;
                default: fifo_shadow_q <= fifo_shadow_q;
            endcase
            case ({send_valid, credit_return_pending_q})
                2'b10: credit_shadow_q <= credit_shadow_q - 1'b1;
                2'b01: credit_shadow_q <= credit_shadow_q + 1'b1;
                default: credit_shadow_q <= credit_shadow_q;
            endcase
            credit_return_pending_q <= credit_delta_pending_q;
            credit_delta_pending_q <= credit_input_pending_q;
            credit_input_pending_q <= return_valid;
            if (return_valid) return_total_q <= return_total_q + 16'd1;
            if ($past(past_valid)) begin
                assert (fifo_occupancy == fifo_shadow_q);
                assert (fifo_occupancy <= 3'd4);
                assert (!fifo_overflow && !fifo_underflow);
                assert (credit_count[15:0] == {13'd0, credit_shadow_q});
                assert (credit_admit[0] == (credit_shadow_q != 3'd0));
                assert (!credit_underflow && !credit_overflow && !stale_return);
            end
        end
    end
endmodule
