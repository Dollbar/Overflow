/* Apache-2.0 scalar front-end shells matching the abstract Liberty cells. */
(* blackbox *)
module OVERFLOW_HBM_PORT_ABSTRACT (
    input  wire CLK,
    input  wire REQ_VALID,
    input  wire REQ_WRITE,
    input  wire REQ_DATA,
    output wire REQ_READY,
    output wire RSP_VALID,
    output wire RSP_ERROR,
    output wire RSP_DATA
);
endmodule

(* blackbox *)
module OVERFLOW_SERDES_SLICE_ABSTRACT (
    input  wire CLK,
    input  wire TX_VALID,
    input  wire TX_BLOCK,
    output wire RX_VALID,
    output wire RX_BLOCK,
    output wire LINK_UP
);
endmodule
