`timescale 1ns/1ps

(* techmap_celltype = "$_SDFF_PP0_" *)
module tsmc28_sdff_pp0_map (
    input  wire D,
    input  wire C,
    input  wire R,
    output wire Q
);
    wire clear_n;
    wire _TECHMAP_REMOVEINIT_Q_;

    assign clear_n = ~R;
    assign _TECHMAP_REMOVEINIT_Q_ = 1'b1;

    DFKCNQD1BWP40P140 _TECHMAP_REPLACE_ (
        .D  (D),
        .CP (C),
        .CN (clear_n),
        .Q  (Q)
    );
endmodule

(* techmap_celltype = "$_SDFFE_PP0P_" *)
module tsmc28_sdffe_pp0p_map (
    input  wire D,
    input  wire C,
    input  wire R,
    input  wire E,
    output wire Q
);
    wire selected_d;
    wire clear_n;
    wire _TECHMAP_REMOVEINIT_Q_;

    assign selected_d = E ? D : Q;
    assign clear_n = ~R;
    assign _TECHMAP_REMOVEINIT_Q_ = 1'b1;

    DFKCNQD1BWP40P140 _TECHMAP_REPLACE_ (
        .D  (selected_d),
        .CP (C),
        .CN (clear_n),
        .Q  (Q)
    );
endmodule
