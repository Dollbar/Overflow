`timescale 1ns/1ps
module upli_receive_channel #(
    parameter integer C_NUM_PORTS=1, C_PAYLOAD_WIDTH=32, C_CREDIT_WIDTH=4,
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY=3,
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}},
    parameter integer C_RETURN_DEPTH=4, C_PENDING_WIDTH=2
) (
    input wire i_clk,i_rstn,i_credit_connected,i_beats_connected,i_receive_valid,
    input wire [1:0] i_receive_port,i_receive_vc,
    input wire i_receive_pool,
    input wire [C_PAYLOAD_WIDTH-1:0] i_receive_payload,
    input wire [1:0] i_consumer_port,
    input wire [2:0] i_consumer_account,
    input wire i_consumer_ready,
    output wire [C_PAYLOAD_WIDTH-1:0] o_head_payload,
    output wire [1:0] o_head_vc,
    output wire o_head_pool,o_head_valid,o_consume_valid,o_receive_accepted,
    output wire [2:0] o_diagnostic,
    output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_counts,
    output wire [4*C_PENDING_WIDTH-1:0] o_pending_count,
    output wire [3:0] o_credit_valid,o_credit_pool,
    output wire [7:0] o_credit_vc,o_credit_num,
    output wire [3:0] o_credit_init_done
);
    assign o_head_payload={C_PAYLOAD_WIDTH{1'b0}};
    assign o_head_vc=2'd1;
    assign o_head_pool=1'b0;
    assign o_head_valid=1'b1;
    assign o_consume_valid=1'b1;
    assign o_receive_accepted=1'b0;
    assign o_diagnostic=3'd0;
    assign o_counts={C_NUM_PORTS*5*C_CREDIT_WIDTH{1'b0}};
    assign o_pending_count={4*C_PENDING_WIDTH{1'b0}};
    assign o_credit_valid=4'd0;
    assign o_credit_pool=4'd0;
    assign o_credit_vc=8'd0;
    assign o_credit_num=8'd0;
    assign o_credit_init_done=4'd0;
endmodule

module ordered_receive_mismatch_tb;
    reg clk=1'b0,rstn=1'b0,consumer_ready=1'b0;
    wire consume_valid;
    wire order_error;
    always #5 clk=~clk;
    upli_ordered_receive_channel #(.C_NUM_PORTS(1),.C_PAYLOAD_WIDTH(32)) dut (
        .i_clk(clk),.i_rstn(rstn),.i_credit_connected(1'b1),.i_beats_connected(1'b1),
        .i_receive_valid(1'b0),.i_receive_port(2'd0),.i_receive_vc(2'd0),.i_receive_pool(1'b0),.i_receive_payload(32'd0),
        .i_consumer_port(2'd0),.i_consumer_ready(consumer_ready),.o_consume_valid(consume_valid),.o_order_error(order_error)
    );
    initial begin
        #2 rstn=1'b1;
        force dut.order_head_valid=1'b1;
        force dut.order_head_accounts=3'd0;
        consumer_ready=1'b1;
        #1;
        if(order_error!==1'b1)$fatal(1,"ORDER_MISMATCH_NOT_REPORTED");
        if(consume_valid!==1'b0)$fatal(1,"ORDER_MISMATCH_RETIRED");
        $display("ORDER_MISMATCH_CONTAINED");
        $finish;
    end
endmodule
