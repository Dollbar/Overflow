`timescale 1ns/1ps
`default_nettype none

// Post-DMA descriptor storage. A descriptor becomes schedulable only after an
// explicit submit, so partially written entries can never reach the scheduler.
module npu_descriptor_buffer #(
    parameter int unsigned ENTRY_COUNT = 16,
    parameter int unsigned INDEX_WIDTH =
        (ENTRY_COUNT <= 1) ? 1 : $clog2(ENTRY_COUNT)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic write_valid_i,
    output logic write_ready_o,
    input  logic [INDEX_WIDTH-1:0] write_index_i,
    input  logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0]
                 write_descriptor_i,

    input  logic submit_valid_i,
    output logic submit_ready_o,
    input  logic [INDEX_WIDTH-1:0] submit_index_i,

    output logic task_valid_o,
    input  logic task_ready_i,
    output logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_o,
    output logic protocol_error_o
);

    logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0]
        descriptor_mem [0:ENTRY_COUNT-1];
    logic [ENTRY_COUNT-1:0] descriptor_written_q;
    logic task_valid_q;
    logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_q;
    logic write_fire;
    logic submit_fire;

    assign write_ready_o = !rst_i && !clear_i;
    assign submit_ready_o = !rst_i && !clear_i &&
                            (!task_valid_q || task_ready_i);
    assign write_fire = write_valid_i && write_ready_o;
    assign submit_fire = submit_valid_i && submit_ready_o;
    assign task_valid_o = task_valid_q;
    assign task_o = task_q;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            descriptor_written_q <= '0;
            task_valid_q <= 1'b0;
            task_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            if (task_valid_q && task_ready_i) begin
                task_valid_q <= 1'b0;
            end
            if (write_fire) begin
                descriptor_mem[write_index_i] <= write_descriptor_i;
                descriptor_written_q[write_index_i] <= 1'b1;
            end
            if (submit_fire) begin
                if (descriptor_written_q[submit_index_i]) begin
                    task_q <= descriptor_mem[submit_index_i];
                    task_valid_q <= 1'b1;
                    descriptor_written_q[submit_index_i] <= 1'b0;
                end else begin
                    protocol_error_o <= 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
