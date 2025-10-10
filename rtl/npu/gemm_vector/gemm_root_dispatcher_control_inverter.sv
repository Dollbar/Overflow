`timescale 1ns/1ps
`default_nettype none

// 根分发器宽寄存器timing island使用的保留本地缓冲级。
(* keep_hierarchy = "yes" *)
module gemm_root_dispatcher_control_inverter (
    input  logic data_i,
    output logic data_o
);

    assign data_o = ~data_i;

endmodule

`default_nettype wire
