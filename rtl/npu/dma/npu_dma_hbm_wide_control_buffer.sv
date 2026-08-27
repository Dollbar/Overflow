`timescale 1ns/1ps
`default_nettype none

(* keep_hierarchy = "true" *)
module npu_dma_hbm_wide_control_buffer (
    input  logic data_i,
    output logic data_o
);
    always_comb begin
        data_o = data_i;
    end
endmodule

`default_nettype wire
