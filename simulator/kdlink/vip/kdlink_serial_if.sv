interface kdlink_serial_if(input logic clk_i);
    logic group_valid;
    logic [659:0] group_blocks;
    logic [9:0] lane_valid;
    logic [659:0] lane_blocks;
    logic [1:0] link_state;
    logic link_up;

    modport pcs_tx(
        input clk_i,
        output group_valid,
        output group_blocks
    );

    modport channel(
        input clk_i,
        input group_valid,
        input group_blocks,
        output lane_valid,
        output lane_blocks,
        output link_state,
        output link_up
    );

    modport pcs_rx(
        input clk_i,
        input lane_valid,
        input lane_blocks,
        input link_state,
        input link_up
    );
endinterface
