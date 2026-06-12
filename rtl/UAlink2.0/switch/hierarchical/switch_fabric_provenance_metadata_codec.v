`timescale 1ns/1ps
`default_nettype none

// Fabric provenance metadata的格式边界。
// 位布局从低到高固定为user metadata、owner valid mask、opaque owner tokens；
// 高位保留区由packer清零，unpacker拒绝任何非零保留位。
module switch_fabric_provenance_metadata_codec #(
    parameter integer C_FABRIC_META_WIDTH = 512,
    parameter integer C_USER_META_WIDTH = 128,
    parameter integer C_OWNER_COUNT = 17,
    parameter integer C_OWNER_TOKEN_WIDTH = 18
) (
    input  wire i_pack_valid,
    input  wire [C_USER_META_WIDTH-1:0] i_user_meta,
    input  wire [C_OWNER_COUNT-1:0] i_owner_valid,
    input  wire [C_OWNER_COUNT*C_OWNER_TOKEN_WIDTH-1:0] i_owner_tokens,
    output wire o_pack_valid,
    output wire [C_FABRIC_META_WIDTH-1:0] o_packed_meta,

    input  wire i_unpack_valid,
    input  wire [C_FABRIC_META_WIDTH-1:0] i_packed_meta,
    output wire o_unpack_valid,
    output wire [C_USER_META_WIDTH-1:0] o_user_meta,
    output wire [C_OWNER_COUNT-1:0] o_owner_valid,
    output wire [C_OWNER_COUNT*C_OWNER_TOKEN_WIDTH-1:0] o_owner_tokens,
    output wire o_unpack_error,
    output wire o_error,
    output wire o_config_error
);
    localparam integer C_OWNER_TOKENS_WIDTH = C_OWNER_COUNT * C_OWNER_TOKEN_WIDTH;
    localparam integer C_USED_WIDTH = C_USER_META_WIDTH + C_OWNER_COUNT + C_OWNER_TOKENS_WIDTH;
    localparam C_CONFIG_LEGAL =
        (C_FABRIC_META_WIDTH >= 1) &&
        (C_FABRIC_META_WIDTH <= 4096) &&
        (C_USER_META_WIDTH >= 1) &&
        (C_USER_META_WIDTH <= 2048) &&
        (C_OWNER_COUNT >= 1) &&
        (C_OWNER_COUNT <= 256) &&
        (C_OWNER_TOKEN_WIDTH >= 1) &&
        (C_OWNER_TOKEN_WIDTH <= 256) &&
        (C_USED_WIDTH <= C_FABRIC_META_WIDTH);

    assign o_config_error = !C_CONFIG_LEGAL;

    generate
        if (C_CONFIG_LEGAL) begin : g_legal
            reg [C_FABRIC_META_WIDTH-1:0] packed_meta;
            reg reserved_nonzero;
            integer reserved_index;

            always @* begin
                packed_meta = {C_FABRIC_META_WIDTH{1'b0}};
                packed_meta[0 +: C_USER_META_WIDTH] = i_user_meta;
                packed_meta[C_USER_META_WIDTH +: C_OWNER_COUNT] = i_owner_valid;
                packed_meta[C_USER_META_WIDTH+C_OWNER_COUNT +: C_OWNER_TOKENS_WIDTH]
                    = i_owner_tokens;

                reserved_nonzero = 1'b0;
                for (reserved_index = C_USED_WIDTH;
                     reserved_index < C_FABRIC_META_WIDTH;
                     reserved_index = reserved_index + 1) begin
                    reserved_nonzero = reserved_nonzero | i_packed_meta[reserved_index];
                end
            end

            assign o_pack_valid = i_pack_valid;
            assign o_packed_meta = i_pack_valid ? packed_meta : {C_FABRIC_META_WIDTH{1'b0}};
            assign o_unpack_error = i_unpack_valid && reserved_nonzero;
            assign o_unpack_valid = i_unpack_valid && !reserved_nonzero;
            assign o_user_meta = o_unpack_valid
                ? i_packed_meta[0 +: C_USER_META_WIDTH] : {C_USER_META_WIDTH{1'b0}};
            assign o_owner_valid = o_unpack_valid
                ? i_packed_meta[C_USER_META_WIDTH +: C_OWNER_COUNT] : {C_OWNER_COUNT{1'b0}};
            assign o_owner_tokens = o_unpack_valid
                ? i_packed_meta[C_USER_META_WIDTH+C_OWNER_COUNT +: C_OWNER_TOKENS_WIDTH]
                : {C_OWNER_TOKENS_WIDTH{1'b0}};
            assign o_error = o_unpack_error;
        end else begin : g_illegal
            assign o_pack_valid = 1'b0;
            assign o_packed_meta = {C_FABRIC_META_WIDTH{1'b0}};
            assign o_unpack_valid = 1'b0;
            assign o_user_meta = {C_USER_META_WIDTH{1'b0}};
            assign o_owner_valid = {C_OWNER_COUNT{1'b0}};
            assign o_owner_tokens = {C_OWNER_TOKENS_WIDTH{1'b0}};
            assign o_unpack_error = i_unpack_valid;
            assign o_error = 1'b1;
        end
    endgenerate
endmodule

`default_nettype wire
