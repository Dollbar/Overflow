`timescale 1ns/1ps
module tb_kdlink_serial_if;
    logic clk;
    kdlink_serial_if serial_if(clk);

    always #0.5 clk = ~clk;

    initial begin
        clk = 1'b0;
        serial_if.group_valid = 1'b1;
        serial_if.group_blocks = 660'h1234;
        serial_if.lane_valid = 10'h3ff;
        serial_if.lane_blocks = 660'h5678;
        serial_if.link_state = 2'd2;
        serial_if.link_up = 1'b1;
        #1.01;
        if (!serial_if.group_valid || serial_if.group_blocks != 660'h1234 ||
            serial_if.lane_valid != 10'h3ff || serial_if.lane_blocks != 660'h5678 ||
            serial_if.link_state != 2'd2 || !serial_if.link_up) begin
            $fatal(1, "KDLink serial interface signal contract mismatch");
        end
        $display("TB_KDLINK_SERIAL_IF_PASS lanes=10 block_width=66 group_width=660");
        $finish;
    end
endmodule
