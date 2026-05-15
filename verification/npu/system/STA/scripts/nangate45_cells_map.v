(* techmap_celltype = "$_BUF_" *)
module nangate45_buf_map(input wire A, output wire Y);
    BUF_X8 _TECHMAP_REPLACE_ (.A(A), .Z(Y));
endmodule

(* techmap_celltype = "npu_dma_hbm_control_buffer" *)
module nangate45_control_buffer_map(input wire data_i, output wire data_o);
    BUF_X2 _TECHMAP_REPLACE_ (.A(data_i), .Z(data_o));
endmodule

(* techmap_celltype = "npu_dma_hbm_wide_control_buffer" *)
module nangate45_wide_control_buffer_map(input wire data_i, output wire data_o);
    BUF_X8 _TECHMAP_REPLACE_ (.A(data_i), .Z(data_o));
endmodule

(* techmap_celltype = "$_NOT_" *)
module nangate45_not_map(input wire A, output wire Y);
    INV_X1 _TECHMAP_REPLACE_ (.A(A), .ZN(Y));
endmodule

(* techmap_celltype = "$_AND_" *)
module nangate45_and_map(input wire A, input wire B, output wire Y);
    AND2_X1 _TECHMAP_REPLACE_ (.A1(A), .A2(B), .ZN(Y));
endmodule

(* techmap_celltype = "$_OR_" *)
module nangate45_or_map(input wire A, input wire B, output wire Y);
    OR2_X1 _TECHMAP_REPLACE_ (.A1(A), .A2(B), .ZN(Y));
endmodule

(* techmap_celltype = "$_NAND_" *)
module nangate45_nand_map(input wire A, input wire B, output wire Y);
    NAND2_X1 _TECHMAP_REPLACE_ (.A1(A), .A2(B), .ZN(Y));
endmodule

(* techmap_celltype = "$_NOR_" *)
module nangate45_nor_map(input wire A, input wire B, output wire Y);
    NOR2_X1 _TECHMAP_REPLACE_ (.A1(A), .A2(B), .ZN(Y));
endmodule

(* techmap_celltype = "$_XOR_" *)
module nangate45_xor_map(input wire A, input wire B, output wire Y);
    XOR2_X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .Z(Y));
endmodule

(* techmap_celltype = "$_XNOR_" *)
module nangate45_xnor_map(input wire A, input wire B, output wire Y);
    XNOR2_X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .ZN(Y));
endmodule

(* techmap_celltype = "$_MUX_" *)
module nangate45_mux_map(
    input wire A,
    input wire B,
    input wire S,
    output wire Y
);
    MUX2_X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .S(S), .Z(Y));
endmodule

(* techmap_celltype = "NOR4_X1" *)
module nangate45_nor4_x1_upsize_map(
    input wire A1,
    input wire A2,
    input wire A3,
    input wire A4,
    output wire ZN
);
    NOR4_X2 _TECHMAP_REPLACE_ (
        .A1(A1),
        .A2(A2),
        .A3(A3),
        .A4(A4),
        .ZN(ZN)
    );
endmodule

(* techmap_celltype = "NOR3_X1" *)
module nangate45_nor3_x1_upsize_map(
    input wire A1,
    input wire A2,
    input wire A3,
    output wire ZN
);
    NOR3_X2 _TECHMAP_REPLACE_ (
        .A1(A1),
        .A2(A2),
        .A3(A3),
        .ZN(ZN)
    );
endmodule

(* techmap_celltype = "NOR2_X1" *)
module nangate45_nor2_x1_upsize_map(
    input wire A1,
    input wire A2,
    output wire ZN
);
    NOR2_X2 _TECHMAP_REPLACE_ (
        .A1(A1),
        .A2(A2),
        .ZN(ZN)
    );
endmodule

(* techmap_celltype = "OR3_X1" *)
module nangate45_or3_x1_upsize_map(
    input wire A1,
    input wire A2,
    input wire A3,
    output wire ZN
);
    OR3_X2 _TECHMAP_REPLACE_ (
        .A1(A1),
        .A2(A2),
        .A3(A3),
        .ZN(ZN)
    );
endmodule

(* techmap_celltype = "OR4_X1" *)
module nangate45_or4_x1_upsize_map(
    input wire A1,
    input wire A2,
    input wire A3,
    input wire A4,
    output wire ZN
);
    OR4_X2 _TECHMAP_REPLACE_ (
        .A1(A1),
        .A2(A2),
        .A3(A3),
        .A4(A4),
        .ZN(ZN)
    );
endmodule

(* techmap_celltype = "AOI21_X1" *)
module nangate45_aoi21_x1_upsize_map(
    input wire A,
    input wire B1,
    input wire B2,
    output wire ZN
);
    AOI21_X2 _TECHMAP_REPLACE_ (
        .A(A),
        .B1(B1),
        .B2(B2),
        .ZN(ZN)
    );
endmodule

(* techmap_celltype = "BUF_X1" *)
module nangate45_buf_x1_upsize_map(
    input wire A,
    output wire Z
);
    BUF_X2 _TECHMAP_REPLACE_ (
        .A(A),
        .Z(Z)
    );
endmodule
