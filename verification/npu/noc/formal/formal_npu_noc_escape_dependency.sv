`timescale 1ns/1ps
`default_nettype none

// Proves that every deterministic XY escape hop strictly reduces remaining
// Manhattan distance and that a vertical phase can never return horizontal.
module formal_npu_noc_escape_dependency;

    (* anyconst *) logic [2:0] source;
    (* anyconst *) logic [2:0] destination;
    logic [1:0] source_column;
    logic source_row;
    logic [1:0] destination_column;
    logic destination_row;
    logic [2:0] next_node;
    logic [2:0] current_distance;
    logic [2:0] next_distance;

    function automatic [2:0] distance(
        input logic [2:0] first,
        input logic [2:0] second
    );
        logic [2:0] horizontal;
        logic vertical;
        horizontal = (first[1:0] >= second[1:0]) ?
            3'(first[1:0] - second[1:0]) :
            3'(second[1:0] - first[1:0]);
        vertical = first[2] != second[2];
        distance = horizontal + 3'(vertical);
    endfunction

    always_comb begin
        source_column = source[1:0];
        source_row = source[2];
        destination_column = destination[1:0];
        destination_row = destination[2];
        next_node = source;
        if (destination_column > source_column) begin
            next_node[1:0] = source_column + 1'b1;
        end else if (destination_column < source_column) begin
            next_node[1:0] = source_column - 1'b1;
        end else if (destination_row != source_row) begin
            next_node[2] = destination_row;
        end
        current_distance = distance(source, destination);
        next_distance = distance(next_node, destination);
    end

    always_comb begin
        assume (source < 8 && destination < 8 && source != destination);
        assert (next_distance < current_distance);
        if (source_column == destination_column) begin
            assert (next_node[1:0] == source_column);
        end
    end

endmodule

`default_nettype wire
