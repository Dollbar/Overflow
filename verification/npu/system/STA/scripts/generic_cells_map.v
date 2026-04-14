(* techmap_celltype = "$_BUF_" *)
module generic_buf_map(input wire A, output wire Y);
    BUFX1 _TECHMAP_REPLACE_ (.A(A), .Y(Y));
endmodule

(* techmap_celltype = "npu_dma_hbm_control_buffer" *)
module generic_control_buffer_map(input wire data_i, output wire data_o);
    BUFX1 _TECHMAP_REPLACE_ (.A(data_i), .Y(data_o));
endmodule

(* techmap_celltype = "$_NOT_" *)
module generic_not_map(input wire A, output wire Y);
    INVX1 _TECHMAP_REPLACE_ (.A(A), .Y(Y));
endmodule

(* techmap_celltype = "$_AND_" *)
module generic_and_map(input wire A, input wire B, output wire Y);
    AND2X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

(* techmap_celltype = "$_OR_" *)
module generic_or_map(input wire A, input wire B, output wire Y);
    OR2X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

(* techmap_celltype = "$_NAND_" *)
module generic_nand_map(input wire A, input wire B, output wire Y);
    NAND2X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

(* techmap_celltype = "$_NOR_" *)
module generic_nor_map(input wire A, input wire B, output wire Y);
    NOR2X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

(* techmap_celltype = "$_XOR_" *)
module generic_xor_map(input wire A, input wire B, output wire Y);
    XOR2X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

(* techmap_celltype = "$_XNOR_" *)
module generic_xnor_map(input wire A, input wire B, output wire Y);
    XNOR2X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y));
endmodule

(* techmap_celltype = "$_MUX_" *)
module generic_mux_map(
    input wire A,
    input wire B,
    input wire S,
    output wire Y
);
    MUX2X1 _TECHMAP_REPLACE_ (.A(A), .B(B), .S(S), .Y(Y));
endmodule
