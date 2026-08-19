module kdlink_v2_credit_bank8 #(
    parameter [15:0] INITIAL_CREDITS = 16'd1024
) (
    input wire clk_i,
    input wire rst_n_i,
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
    reg [15:0] credit_q [0:7];
    reg [15:0] return_total_q [0:7];
    wire [15:0] return_delta;
    wire return_send_same_vc;
    wire [16:0] return_credit_sum;
    integer vc_index;

    genvar packed_vc;
    generate
        for (packed_vc = 0; packed_vc < 8; packed_vc = packed_vc + 1) begin : g_credit_output
            assign admit_o[packed_vc] = credit_q[packed_vc] != 16'd0;
            assign credit_count_o[packed_vc*16 +: 16] = credit_q[packed_vc];
        end
    endgenerate
    assign return_delta = return_total_i - return_total_q[return_vc_i];
    assign return_send_same_vc = send_valid_i && (send_vc_i == return_vc_i) &&
        (credit_q[return_vc_i] != 16'd0);
    assign return_credit_sum = {1'b0, credit_q[return_vc_i]} +
        {1'b0, return_delta} - return_send_same_vc;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            underflow_o <= 1'b0;
            overflow_o <= 1'b0;
            stale_return_o <= 1'b0;
            for (vc_index = 0; vc_index < 8; vc_index = vc_index + 1) begin
                credit_q[vc_index] <= INITIAL_CREDITS;
                return_total_q[vc_index] <= 16'd0;
            end
        end else begin
            underflow_o <= send_valid_i && (credit_q[send_vc_i] == 16'd0);
            overflow_o <= 1'b0;
            stale_return_o <= 1'b0;

            if (send_valid_i && (credit_q[send_vc_i] != 16'd0)) begin
                credit_q[send_vc_i] <= credit_q[send_vc_i] - 16'd1;
            end

            if (return_valid_i) begin
                if ((return_delta != 16'd0) && !return_delta[15] &&
                    (return_delta <= INITIAL_CREDITS)) begin
                    if (return_credit_sum <= {1'b0, INITIAL_CREDITS}) begin
                        credit_q[return_vc_i] <= return_credit_sum[15:0];
                    end else begin
                        credit_q[return_vc_i] <= INITIAL_CREDITS;
                        overflow_o <= 1'b1;
                    end
                    return_total_q[return_vc_i] <= return_total_i;
                end else if (return_delta == 16'd0 || return_delta[15]) begin
                    stale_return_o <= 1'b1;
                end else begin
                    overflow_o <= 1'b1;
                end
            end
        end
    end
endmodule
