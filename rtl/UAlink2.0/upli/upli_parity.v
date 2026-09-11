`timescale 1ns/1ps // 公共生成器与typed接口在同一编译单元使用一致时间单位。
`default_nettype none
// Common 2.0 Tables 2-2/2-15/2-18/2-21 and section 3.1.1 parity groups.
// Packed control fields are a local wiring contract, not a serialized UPLI format.
module upli_parity #(
    parameter integer CHANNEL_KIND = 0 // 0=Request, 1=Read Response, 2=Write Response, 3=OrigData.
)(
    input wire i_check_enable, // Enables diagnostics; generation remains active every cycle.
    input wire i_valid,
    input wire [67:0] i_control, // Low 68/48/42/9 bits respectively contain the complete control group.
    input wire [56:0] i_address, // Request address has its own parity bit.
    input wire [63:0] i_auth, // Authorization tag protection is separate from control diagnosis.
    input wire [511:0] i_data, // All lanes participate, including masked or poisoned data.
    input wire [63:0] i_byte_enable,
    input wire [3:0] i_credit_valid, i_credit_pool,
    input wire [7:0] i_credit_vc, i_credit_num,
    input wire [14:0] i_received_parity,
    output reg [14:0] o_parity, // {creditFields,creditValid,BE,data[7:0],auth,address,control,valid}.
    output wire [14:0] o_errors, // Same group positions, gated by the specified valid qualifiers.
    output wire o_control_error,
    output wire o_data_error, // Includes ByteEn errors; poison policy is handled by the channel/RAS layer.
    output wire o_auth_error // Authentication parity mismatch, not an authentication verification result.
);
    localparam integer CONTROL_WIDTH = (CHANNEL_KIND==0)?68:(CHANNEL_KIND==1)?48:(CHANNEL_KIND==2)?42:9;
    localparam HAS_DATA = (CHANNEL_KIND==1)||(CHANNEL_KIND==3);
    localparam KIND_LEGAL = (CHANNEL_KIND>=0)&&(CHANNEL_KIND<=3);
    reg [14:0] checked;
    integer lane;
    // Unused fields in a selected channel have no protection group and no effect on parity.
    wire unused_channel_fields = ^{i_control,i_address,i_auth,i_data,i_byte_enable};
    always @(*) begin
        o_parity = 15'd0;
        checked = 15'd0;
        o_parity[0] = i_valid;
        o_parity[1] = ^i_control[CONTROL_WIDTH-1:0];
        if (CHANNEL_KIND==0) o_parity[2] = ^i_address;
        if (CHANNEL_KIND!=3) o_parity[3] = ^i_auth;
        for (lane=0;lane<8;lane=lane+1) begin
            if (HAS_DATA) o_parity[4+lane] = ^i_data[lane*64 +: 64];
        end
        if (CHANNEL_KIND==3) o_parity[12] = ^i_byte_enable;
        o_parity[13] = ^i_credit_valid;
        o_parity[14] = ^{i_credit_pool,i_credit_vc,i_credit_num};
        checked[0] = 1'b1;
        checked[13] = 1'b1;
        checked[14] = |i_credit_valid; // Every port's fields participate whenever any port is valid.
        if (i_valid) begin
            checked[1] = 1'b1;
            checked[2] = (CHANNEL_KIND==0);
            checked[3] = (CHANNEL_KIND!=3);
            checked[11:4] = {8{HAS_DATA}};
            checked[12] = (CHANNEL_KIND==3);
        end
    end
    assign o_errors = (o_parity ^ i_received_parity) & checked & {15{i_check_enable}};
    assign o_control_error = (|{o_errors[14:13],o_errors[2:0]}) || (i_check_enable && !KIND_LEGAL);
    assign o_data_error = |o_errors[12:4];
    assign o_auth_error = o_errors[3];
endmodule
`default_nettype wire
