`timescale 1ns/1ps
`default_nettype none

module npu_round_robin_arbiter16 (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic [15:0] request_i,
    output logic [15:0] grant_o
);

    logic [3:0] pointer_q;
    logic [15:0] upper_mask;
    logic [15:0] upper_request;
    logic upper_found;
    logic lower_found;

    always_comb begin
        upper_mask = 16'hffff << pointer_q;
        upper_request = request_i & upper_mask;
        grant_o = '0;
        upper_found = 1'b0;
        lower_found = 1'b0;
        for (integer request = 0; request < 16; request++) begin
            if (upper_request[request] && !upper_found) begin
                grant_o[request] = 1'b1;
                upper_found = 1'b1;
            end
        end
        if (!upper_found) begin
            for (integer request = 0; request < 16; request++) begin
                if (request_i[request] && !lower_found) begin
                    grant_o[request] = 1'b1;
                    lower_found = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            pointer_q <= '0;
        end else begin
            for (integer request = 0; request < 16; request++) begin
                if (grant_o[request]) begin
                    if (request == 15) begin
                        pointer_q <= '0;
                    end else begin
                        pointer_q <= 4'(request + 1);
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
