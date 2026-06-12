`timescale 1ns/1ps
`default_nettype none
module switch_plane_selector #(
    parameter integer C_SOURCES = 4,
    parameter integer C_PLANES = 4,
    parameter integer C_DATA_WIDTH = 256,
    parameter integer C_META_WIDTH = 128,
    parameter integer C_SOURCE_WIDTH = 2
) (
    input wire i_clk,
    input wire i_rstn,
    input wire [C_SOURCES-1:0] i_valid,
    output reg [C_SOURCES-1:0] o_ready,
    input wire [C_SOURCES*C_DATA_WIDTH-1:0] i_data,
    input wire [C_SOURCES*C_META_WIDTH-1:0] i_meta,
    input wire [C_SOURCES-1:0] i_sop,
    input wire [C_SOURCES-1:0] i_eop,
    input wire [C_SOURCES*C_PLANES-1:0] i_eligible,
    output reg [C_PLANES-1:0] o_valid,
    input wire [C_PLANES-1:0] i_ready,
    output reg [C_PLANES*C_DATA_WIDTH-1:0] o_data,
    output reg [C_PLANES*C_META_WIDTH-1:0] o_meta,
    output reg [C_PLANES-1:0] o_sop,
    output reg [C_PLANES-1:0] o_eop,
    output wire o_quiescent
);
    reg [C_PLANES-1:0] owner_valid_q;
    reg [C_SOURCE_WIDTH-1:0] owner_source_q [0:C_PLANES-1];
    reg [C_PLANES-1:0] hold_valid_q;
    assign o_quiescent=!(|owner_valid_q)&&!(|hold_valid_q);
    reg [C_SOURCE_WIDTH-1:0] hold_source_q [0:C_PLANES-1];
    reg [C_SOURCE_WIDTH-1:0] rr_q [0:C_PLANES-1];
    function integer clog2;
        input integer value;
        integer work;
        begin
            work = value - 1;
            clog2 = 0;
            while (work > 0) begin
                clog2 = clog2 + 1;
                work = work >> 1;
            end
            if (clog2 < 1) clog2 = 1;
        end
    endfunction
    localparam integer C_PLANE_INDEX_WIDTH = clog2(C_PLANES);
    localparam [C_PLANE_INDEX_WIDTH-1:0] LAST_PLANE =
        C_PLANES[C_PLANE_INDEX_WIDTH-1:0] - 1'b1;
    reg [C_PLANE_INDEX_WIDTH-1:0] plane_rr_q;
    reg [C_PLANES-1:0] selected_valid;
    reg [C_SOURCE_WIDTH-1:0] selected_source [0:C_PLANES-1];
    localparam [C_SOURCE_WIDTH-1:0] LAST_SOURCE = C_SOURCES[C_SOURCE_WIDTH-1:0] - 1'b1;
    localparam [C_SOURCE_WIDTH:0] SOURCE_COUNT = C_SOURCES[C_SOURCE_WIDTH:0];
    reg [C_SOURCES-1:0] source_claimed;
    integer plane_index;
    integer plane_scan_index;
    integer plane_value;
    integer scan_index;
    reg [C_SOURCE_WIDTH-1:0] source_index;
    reg [C_SOURCE_WIDTH:0] source_value;
    integer claim_index;
    reg plane_rr_advance;
    reg [C_PLANE_INDEX_WIDTH-1:0] plane_rr_winner;
    always @(*) begin
        o_ready = {C_SOURCES{1'b0}};
        o_valid = {C_PLANES{1'b0}};
        o_data = {(C_PLANES*C_DATA_WIDTH){1'b0}};
        o_meta = {(C_PLANES*C_META_WIDTH){1'b0}};
        o_sop = {C_PLANES{1'b0}};
        o_eop = {C_PLANES{1'b0}};
        selected_valid = {C_PLANES{1'b0}};
        source_claimed = {C_SOURCES{1'b0}};
        scan_index = 0;
        source_index = {C_SOURCE_WIDTH{1'b0}};
        source_value = {(C_SOURCE_WIDTH+1){1'b0}};
        plane_index = 0;
        plane_value = 0;
        plane_rr_advance = 1'b0;
        plane_rr_winner = {C_PLANE_INDEX_WIDTH{1'b0}};
        for (claim_index = 0; claim_index < C_PLANES; claim_index = claim_index + 1) begin
            selected_source[claim_index] = {C_SOURCE_WIDTH{1'b0}};
            if (owner_valid_q[claim_index]) source_claimed[owner_source_q[claim_index]] = 1'b1;
            if (hold_valid_q[claim_index]) source_claimed[hold_source_q[claim_index]] = 1'b1;
        end
        // 从跨Plane RR起点开始建立匹配，避免单一source长期固定在Plane0。
        // owner/hold仍以实际Plane编号索引，因此包体不会因RR推进而换路。
        for (plane_scan_index = 0; plane_scan_index < C_PLANES; plane_scan_index = plane_scan_index + 1) begin
            plane_value = {{(32-C_PLANE_INDEX_WIDTH){1'b0}},plane_rr_q};
            plane_value = plane_value + plane_scan_index;
            if (plane_value >= C_PLANES) plane_value = plane_value - C_PLANES;
            plane_index = plane_value;
            if (owner_valid_q[plane_index]) begin
                selected_valid[plane_index] = 1'b1;
                selected_source[plane_index] = owner_source_q[plane_index];
            end else if (hold_valid_q[plane_index]) begin
                selected_valid[plane_index] = 1'b1;
                selected_source[plane_index] = hold_source_q[plane_index];
            end else begin
                for (scan_index = 0; scan_index < C_SOURCES; scan_index = scan_index + 1) begin
                    source_value = {1'b0,rr_q[plane_index]}+scan_index[C_SOURCE_WIDTH:0];
                    if(source_value>=SOURCE_COUNT)source_value=source_value-SOURCE_COUNT;
                    source_index = source_value[C_SOURCE_WIDTH-1:0];
                    if (!selected_valid[plane_index] && !source_claimed[source_index] && i_valid[source_index] &&
                        i_sop[source_index] && i_eligible[source_index*C_PLANES+plane_index]) begin
                        selected_valid[plane_index] = 1'b1;
                        selected_source[plane_index] = source_index;
                        source_claimed[source_index] = 1'b1;
                    end
                end
            end
            if (selected_valid[plane_index]) begin
                o_valid[plane_index] = i_valid[selected_source[plane_index]];
                o_data[plane_index*C_DATA_WIDTH +: C_DATA_WIDTH] = i_data[selected_source[plane_index]*C_DATA_WIDTH +: C_DATA_WIDTH];
                o_meta[plane_index*C_META_WIDTH +: C_META_WIDTH] = i_meta[selected_source[plane_index]*C_META_WIDTH +: C_META_WIDTH];
                o_sop[plane_index] = i_sop[selected_source[plane_index]];
                o_eop[plane_index] = i_eop[selected_source[plane_index]];
                o_ready[selected_source[plane_index]] = i_ready[plane_index];
                if (!owner_valid_q[plane_index] && o_valid[plane_index] && i_ready[plane_index] &&
                    o_sop[plane_index]) begin
                    plane_rr_advance = 1'b1;
                    plane_rr_winner = plane_index[C_PLANE_INDEX_WIDTH-1:0];
                end
            end
        end
        if (!i_rstn) begin
            o_ready = {C_SOURCES{1'b0}};
            o_valid = {C_PLANES{1'b0}};
        end
    end
    // 跨Plane指针只在新SOP真实接纳时推进；预握手stall和包体均不改变路径偏好。
    always @(posedge i_clk) begin
        if (!i_rstn) plane_rr_q <= {C_PLANE_INDEX_WIDTH{1'b0}};
        else if (plane_rr_advance) begin
            if (plane_rr_winner == LAST_PLANE)
                plane_rr_q <= {C_PLANE_INDEX_WIDTH{1'b0}};
            else
                plane_rr_q <= plane_rr_winner + {{(C_PLANE_INDEX_WIDTH-1){1'b0}},1'b1};
        end
    end
    genvar state_index;
    generate
        for (state_index = 0; state_index < C_PLANES; state_index = state_index + 1) begin : g_plane_path
            always @(posedge i_clk) begin
                if (!i_rstn) begin
                    owner_valid_q[state_index] <= 1'b0;
                    owner_source_q[state_index] <= {C_SOURCE_WIDTH{1'b0}};
                    hold_valid_q[state_index] <= 1'b0;
                    hold_source_q[state_index] <= {C_SOURCE_WIDTH{1'b0}};
                    rr_q[state_index] <= {C_SOURCE_WIDTH{1'b0}};
                end else if (owner_valid_q[state_index]) begin
                    if (o_valid[state_index] && i_ready[state_index] && o_eop[state_index]) begin
                        owner_valid_q[state_index] <= 1'b0;
                        if (owner_source_q[state_index] == LAST_SOURCE) rr_q[state_index] <= {C_SOURCE_WIDTH{1'b0}};
                        else rr_q[state_index] <= owner_source_q[state_index] + {{(C_SOURCE_WIDTH-1){1'b0}},1'b1};
                    end
                end else if (hold_valid_q[state_index]) begin
                    if (o_valid[state_index] && i_ready[state_index]) begin
                        hold_valid_q[state_index] <= 1'b0;
                        if (o_eop[state_index]) begin
                            if (hold_source_q[state_index] == LAST_SOURCE) rr_q[state_index] <= {C_SOURCE_WIDTH{1'b0}};
                            else rr_q[state_index] <= hold_source_q[state_index] + {{(C_SOURCE_WIDTH-1){1'b0}},1'b1};
                        end else begin
                            owner_valid_q[state_index] <= 1'b1;
                            owner_source_q[state_index] <= hold_source_q[state_index];
                        end
                    end
                end else if (selected_valid[state_index] && o_valid[state_index]) begin
                    if (!i_ready[state_index]) begin
                        hold_valid_q[state_index] <= 1'b1;
                        hold_source_q[state_index] <= selected_source[state_index];
                    end else if (o_eop[state_index]) begin
                        if (selected_source[state_index] == LAST_SOURCE) rr_q[state_index] <= {C_SOURCE_WIDTH{1'b0}};
                        else rr_q[state_index] <= selected_source[state_index] + {{(C_SOURCE_WIDTH-1){1'b0}},1'b1};
                    end else begin
                        owner_valid_q[state_index] <= 1'b1;
                        owner_source_q[state_index] <= selected_source[state_index];
                    end
                end
            end
        end
    endgenerate
endmodule
`default_nettype wire
