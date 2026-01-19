module kdlink_credit_bank8 #(
    parameter [15:0] INITIAL_CREDITS = 16'd1024,
    parameter [0:0] START_EMPTY = 1'b0
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,
    input wire send_valid_i,
    input wire [2:0] send_vc_i,
    input wire return_valid_i,
    input wire [2:0] return_vc_i,
    input wire [15:0] return_total_i,
    output wire [7:0] admit_o,
    output wire [127:0] credit_count_o,
    output reg underflow_o,
    output reg overflow_o,
    output reg stale_return_o
);
    localparam integer CREDIT_WIDTH = (INITIAL_CREDITS < 16'd1) ? 1 :
        $clog2({1'b0, INITIAL_CREDITS} + 17'd1);
    localparam [CREDIT_WIDTH-1:0] CREDIT_ZERO = {CREDIT_WIDTH{1'b0}};
    localparam [CREDIT_WIDTH-1:0] CREDIT_ONE =
        {{(CREDIT_WIDTH-1){1'b0}}, 1'b1};
    localparam [CREDIT_WIDTH-1:0] INITIAL_CREDITS_NARROW =
        INITIAL_CREDITS[CREDIT_WIDTH-1:0];
    localparam [CREDIT_WIDTH:0] INITIAL_CREDITS_EXT =
        {1'b0, INITIAL_CREDITS_NARROW};
    reg [CREDIT_WIDTH-1:0] credit_q [0:7];
    reg [15:0] return_observed_total_q [0:7];
    reg [15:0] return_committed_total_q [0:7];
    reg [7:0] return_chain_epoch_q;
    reg return_input_valid_q;
    reg [2:0] return_input_vc_q;
    reg [15:0] return_input_total_q;
    reg [15:0] return_input_base_q;
    reg return_input_epoch_q;
    reg return_delta_valid_q;
    reg [2:0] return_delta_vc_q;
    reg [15:0] return_delta_total_q;
    reg [15:0] return_delta_q;
    reg return_delta_epoch_q;
    wire [15:0] return_input_delta;
    wire [8:0] return_delta_low_sum;
    wire [7:0] return_delta_high_no_borrow_sum;
    wire [7:0] return_delta_high_with_borrow_sum;
    wire return_delta_value_accept;
    wire return_delta_epoch_match;
    wire return_delta_accept;
    wire return_delta_invalidate;
    reg return_pending_valid_q;
    reg [2:0] return_pending_vc_q;
    reg [CREDIT_WIDTH-1:0] return_pending_delta_q;
    wire [CREDIT_WIDTH:0] pending_credit_sum_by_vc [0:7];
    wire [7:0] pending_credit_overflow_by_vc;
    wire pending_credit_overflow;
    genvar packed_vc;
    generate
        for (packed_vc = 0; packed_vc < 8; packed_vc = packed_vc + 1) begin : g_credit_output
            localparam [2:0] VC_ID = packed_vc;
            assign admit_o[packed_vc] = credit_q[packed_vc] != CREDIT_ZERO;
            assign credit_count_o[packed_vc*16 +: 16] =
                {{(16-CREDIT_WIDTH){1'b0}}, credit_q[packed_vc]};
            assign pending_credit_sum_by_vc[packed_vc] =
                {1'b0, credit_q[packed_vc]} +
                {1'b0, return_pending_delta_q} -
                ((send_valid_i && (send_vc_i == VC_ID) &&
                (credit_q[packed_vc] != CREDIT_ZERO)) ?
                {{CREDIT_WIDTH{1'b0}}, 1'b1} :
                {(CREDIT_WIDTH+1){1'b0}});
            assign pending_credit_overflow_by_vc[packed_vc] =
                return_pending_valid_q &&
                (return_pending_vc_q == VC_ID) &&
                (pending_credit_sum_by_vc[packed_vc] > INITIAL_CREDITS_EXT);

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    credit_q[packed_vc] <= START_EMPTY ? CREDIT_ZERO :
                        INITIAL_CREDITS_NARROW;
                end else if (clear_i) begin
                    credit_q[packed_vc] <= CREDIT_ZERO;
                end else if (return_pending_valid_q &&
                    (return_pending_vc_q == VC_ID)) begin
                    if (pending_credit_sum_by_vc[packed_vc] <=
                        INITIAL_CREDITS_EXT) begin
                        credit_q[packed_vc] <= pending_credit_sum_by_vc[packed_vc][CREDIT_WIDTH-1:0];
                    end else begin
                        credit_q[packed_vc] <= INITIAL_CREDITS[CREDIT_WIDTH-1:0];
                    end
                end else if (send_valid_i && (send_vc_i == VC_ID) &&
                    (credit_q[packed_vc] != CREDIT_ZERO)) begin
                    credit_q[packed_vc] <= credit_q[packed_vc] - CREDIT_ONE;
                end
            end

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    return_observed_total_q[packed_vc] <= 16'd0;
                    return_committed_total_q[packed_vc] <= 16'd0;
                    return_chain_epoch_q[packed_vc] <= 1'b0;
                end else if (clear_i) begin
                    return_observed_total_q[packed_vc] <= 16'd0;
                    return_committed_total_q[packed_vc] <= 16'd0;
                    return_chain_epoch_q[packed_vc] <= 1'b0;
                end else begin
                    if (return_delta_invalidate &&
                        (return_delta_vc_q == VC_ID)) begin
                        return_observed_total_q[packed_vc] <=
                            return_committed_total_q[packed_vc];
                        return_chain_epoch_q[packed_vc] <=
                            ~return_chain_epoch_q[packed_vc];
                    end else if (return_valid_i &&
                        (return_vc_i == VC_ID)) begin
                        return_observed_total_q[packed_vc] <= return_total_i;
                    end
                    if (return_delta_accept &&
                        (return_delta_vc_q == VC_ID)) begin
                        return_committed_total_q[packed_vc] <=
                            return_delta_total_q;
                    end
                end
            end
        end
    endgenerate
    assign return_delta_value_accept =
        (return_delta_q != 16'd0) && !return_delta_q[15] &&
        (return_delta_q <= INITIAL_CREDITS);
    assign return_delta_epoch_match = return_delta_epoch_q ==
        return_chain_epoch_q[return_delta_vc_q];
    assign return_delta_accept = return_delta_valid_q &&
        return_delta_epoch_match && return_delta_value_accept;
    assign return_delta_invalidate = return_delta_valid_q &&
        return_delta_epoch_match && !return_delta_value_accept;
    assign return_delta_low_sum = {1'b0, return_input_total_q[7:0]} +
        {1'b0, ~return_input_base_q[7:0]} + 9'd1;
    assign return_delta_high_no_borrow_sum =
        return_input_total_q[15:8] + ~return_input_base_q[15:8] + 8'd1;
    assign return_delta_high_with_borrow_sum =
        return_input_total_q[15:8] + ~return_input_base_q[15:8];
    assign return_input_delta = {
        return_delta_low_sum[8] ? return_delta_high_no_borrow_sum[7:0] :
        return_delta_high_with_borrow_sum[7:0], return_delta_low_sum[7:0]};
    assign pending_credit_overflow = |pending_credit_overflow_by_vc;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            underflow_o <= 1'b0;
            overflow_o <= 1'b0;
            stale_return_o <= 1'b0;
            return_input_valid_q <= 1'b0;
            return_input_vc_q <= 3'd0;
            return_input_total_q <= 16'd0;
            return_input_base_q <= 16'd0;
            return_input_epoch_q <= 1'b0;
            return_delta_valid_q <= 1'b0;
            return_delta_vc_q <= 3'd0;
            return_delta_total_q <= 16'd0;
            return_delta_q <= 16'd0;
            return_delta_epoch_q <= 1'b0;
            return_pending_valid_q <= 1'b0;
            return_pending_vc_q <= 3'd0;
            return_pending_delta_q <= CREDIT_ZERO;
        end else if (clear_i) begin
            underflow_o <= 1'b0;
            overflow_o <= 1'b0;
            stale_return_o <= 1'b0;
            return_input_valid_q <= 1'b0;
            return_input_vc_q <= 3'd0;
            return_input_total_q <= 16'd0;
            return_input_base_q <= 16'd0;
            return_input_epoch_q <= 1'b0;
            return_delta_valid_q <= 1'b0;
            return_delta_vc_q <= 3'd0;
            return_delta_total_q <= 16'd0;
            return_delta_q <= 16'd0;
            return_delta_epoch_q <= 1'b0;
            return_pending_valid_q <= 1'b0;
            return_pending_vc_q <= 3'd0;
            return_pending_delta_q <= CREDIT_ZERO;
        end else begin
            underflow_o <= send_valid_i &&
                (credit_q[send_vc_i] == CREDIT_ZERO);
            overflow_o <= pending_credit_overflow;
            stale_return_o <= 1'b0;
            return_pending_valid_q <= 1'b0;
            return_input_valid_q <= return_valid_i;
            return_input_vc_q <= return_vc_i;
            return_input_total_q <= return_total_i;
            return_input_base_q <= return_observed_total_q[return_vc_i];
            return_input_epoch_q <= return_chain_epoch_q[return_vc_i];
            return_delta_valid_q <= return_input_valid_q;
            return_delta_vc_q <= return_input_vc_q;
            return_delta_total_q <= return_input_total_q;
            return_delta_q <= return_input_delta;
            return_delta_epoch_q <= return_input_epoch_q;

            if (return_delta_valid_q) begin
                if (return_delta_accept) begin
                    return_pending_valid_q <= 1'b1;
                    return_pending_vc_q <= return_delta_vc_q;
                    return_pending_delta_q <=
                        return_delta_q[CREDIT_WIDTH-1:0];
                end else if (!return_delta_epoch_match ||
                    return_delta_q == 16'd0 || return_delta_q[15]) begin
                    stale_return_o <= 1'b1;
                end else begin
                    overflow_o <= 1'b1;
                end
            end
        end
    end
endmodule
