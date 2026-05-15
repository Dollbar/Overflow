`timescale 1ns/1ps
`default_nettype none

(* keep_hierarchy = "yes" *)
module npu_dma_priority_encoder256 (
    input  logic [255:0] bits_i,
    output logic valid_o,
    output logic [7:0] index_o
);

    logic [255:0] valid_l0;
    logic [2047:0] index_l0;
    logic [127:0] valid_l1;
    logic [1023:0] index_l1;
    logic [63:0] valid_l2;
    logic [511:0] index_l2;
    logic [31:0] valid_l3;
    logic [255:0] index_l3;
    logic [15:0] valid_l4;
    logic [127:0] index_l4;
    logic [7:0] valid_l5;
    logic [63:0] index_l5;
    logic [3:0] valid_l6;
    logic [31:0] index_l6;
    logic [1:0] valid_l7;
    logic [15:0] index_l7;
    logic valid_raw;
    logic [7:0] index_raw;

    generate
        for (genvar item = 0; item < 256; item++) begin : g_l0
            assign valid_l0[item] = bits_i[item];
            assign index_l0[item*8 +: 8] = 8'(item);
        end
        for (genvar item = 0; item < 128; item++) begin : g_l1
            assign valid_l1[item] = valid_l0[item*2] | valid_l0[item*2+1];
            assign index_l1[item*8 +: 8] = valid_l0[item*2] ?
                index_l0[(item*2)*8 +: 8] : index_l0[(item*2+1)*8 +: 8];
        end
        for (genvar item = 0; item < 64; item++) begin : g_l2
            assign valid_l2[item] = valid_l1[item*2] | valid_l1[item*2+1];
            assign index_l2[item*8 +: 8] = valid_l1[item*2] ?
                index_l1[(item*2)*8 +: 8] : index_l1[(item*2+1)*8 +: 8];
        end
        for (genvar item = 0; item < 32; item++) begin : g_l3
            assign valid_l3[item] = valid_l2[item*2] | valid_l2[item*2+1];
            assign index_l3[item*8 +: 8] = valid_l2[item*2] ?
                index_l2[(item*2)*8 +: 8] : index_l2[(item*2+1)*8 +: 8];
        end
        for (genvar item = 0; item < 16; item++) begin : g_l4
            assign valid_l4[item] = valid_l3[item*2] | valid_l3[item*2+1];
            assign index_l4[item*8 +: 8] = valid_l3[item*2] ?
                index_l3[(item*2)*8 +: 8] : index_l3[(item*2+1)*8 +: 8];
        end
        for (genvar item = 0; item < 8; item++) begin : g_l5
            assign valid_l5[item] = valid_l4[item*2] | valid_l4[item*2+1];
            assign index_l5[item*8 +: 8] = valid_l4[item*2] ?
                index_l4[(item*2)*8 +: 8] : index_l4[(item*2+1)*8 +: 8];
        end
        for (genvar item = 0; item < 4; item++) begin : g_l6
            assign valid_l6[item] = valid_l5[item*2] | valid_l5[item*2+1];
            assign index_l6[item*8 +: 8] = valid_l5[item*2] ?
                index_l5[(item*2)*8 +: 8] : index_l5[(item*2+1)*8 +: 8];
        end
        for (genvar item = 0; item < 2; item++) begin : g_l7
            assign valid_l7[item] = valid_l6[item*2] | valid_l6[item*2+1];
            assign index_l7[item*8 +: 8] = valid_l6[item*2] ?
                index_l6[(item*2)*8 +: 8] : index_l6[(item*2+1)*8 +: 8];
        end
    endgenerate

    assign valid_raw = valid_l7[0] | valid_l7[1];
    assign index_raw = valid_l7[0] ? index_l7[0 +: 8] : index_l7[8 +: 8];

    npu_dma_hbm_control_buffer u_valid_buffer (
        .data_i(valid_raw),
        .data_o(valid_o)
    );
    generate
        for (genvar bit_index = 0; bit_index < 8; bit_index++) begin : g_output
            npu_dma_hbm_control_buffer u_index_buffer (
                .data_i(index_raw[bit_index]),
                .data_o(index_o[bit_index])
            );
        end
    endgenerate

endmodule

`default_nettype wire
