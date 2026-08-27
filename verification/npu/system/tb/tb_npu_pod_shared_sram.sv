`timescale 1ns/1ps
`default_nettype none

module tb_npu_pod_shared_sram;

    localparam int unsigned CLIENTS = 16;
    localparam int unsigned BANKS = 8;
    localparam int unsigned ADDRESS_WIDTH = 24;
    localparam int unsigned DATA_BYTES = 128;
    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic [CLIENTS-1:0] read_request_valid_i;
    logic [CLIENTS-1:0] read_request_ready_o;
    logic [CLIENTS*ADDRESS_WIDTH-1:0] read_request_address_i;
    logic [CLIENTS-1:0] read_response_valid_o;
    logic [CLIENTS-1:0] read_response_ready_i;
    logic [CLIENTS*DATA_WIDTH-1:0] read_response_data_o;
    logic [CLIENTS-1:0] write_valid_i;
    logic [CLIENTS-1:0] write_ready_o;
    logic [CLIENTS*ADDRESS_WIDTH-1:0] write_address_i;
    logic [CLIENTS*DATA_WIDTH-1:0] write_data_i;
    logic [CLIENTS*DATA_BYTES-1:0] write_byte_enable_i;
    logic busy_o;
    logic protocol_error_o;
    logic [63:0] accepted_reads_o;
    logic [63:0] accepted_writes_o;
    logic [63:0] read_conflict_cycles_o;
    logic [63:0] write_conflict_cycles_o;

    function automatic logic [DATA_WIDTH-1:0] pattern(
        input logic [31:0] seed
    );
        logic [DATA_WIDTH-1:0] value;
        for (integer lane = 0; lane < DATA_WIDTH / 32; lane++) begin
            value[lane*32 +: 32] = seed ^ (32'h9e37_79b9 * lane);
        end
        return value;
    endfunction

    task automatic drive_write(
        input int unsigned client,
        input logic [ADDRESS_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] data
    );
        @(negedge clk_i);
        write_address_i[client*ADDRESS_WIDTH +: ADDRESS_WIDTH] = address;
        write_data_i[client*DATA_WIDTH +: DATA_WIDTH] = data;
        write_byte_enable_i[client*DATA_BYTES +: DATA_BYTES] = '1;
        write_valid_i[client] = 1'b1;
        do begin
            @(posedge clk_i);
        end while (!write_ready_o[client]);
        @(negedge clk_i);
        write_valid_i[client] = 1'b0;
    endtask

    task automatic drive_read(
        input int unsigned client,
        input logic [ADDRESS_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] expected
    );
        @(negedge clk_i);
        read_response_ready_i[client] = 1'b0;
        read_request_address_i[client*ADDRESS_WIDTH +: ADDRESS_WIDTH] =
            address;
        read_request_valid_i[client] = 1'b1;
        do begin
            @(posedge clk_i);
        end while (!read_request_ready_o[client]);
        @(negedge clk_i);
        read_request_valid_i[client] = 1'b0;
        while (!read_response_valid_o[client]) @(negedge clk_i);
        if (read_response_data_o[client*DATA_WIDTH +: DATA_WIDTH] !==
            expected) begin
            $fatal(1, "client %0d read mismatch at address %h", client,
                   address);
        end
        read_response_ready_i[client] = 1'b1;
        @(posedge clk_i);
    endtask

    always #0.5 clk_i = ~clk_i;

    npu_pod_shared_sram u_dut (
        .clk_i,
        .rst_i,
        .clear_i,
        .read_request_valid_i,
        .read_request_ready_o,
        .read_request_address_i,
        .read_response_valid_o,
        .read_response_ready_i,
        .read_response_data_o,
        .write_valid_i,
        .write_ready_o,
        .write_address_i,
        .write_data_i,
        .write_byte_enable_i,
        .busy_o,
        .protocol_error_o,
        .accepted_reads_o,
        .accepted_writes_o,
        .read_conflict_cycles_o,
        .write_conflict_cycles_o
    );

    initial begin : test_sequence
        logic [CLIENTS-1:0] grant_snapshot;
        logic [CLIENTS-1:0] fairness_seen;
        logic [DATA_WIDTH-1:0] held_response;
        logic [63:0] reads_before_clear;
        logic [63:0] writes_before_clear;

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        read_request_valid_i = '0;
        read_request_address_i = '0;
        read_response_ready_i = '1;
        write_valid_i = '0;
        write_address_i = '0;
        write_byte_enable_i = '1;
        for (integer client = 0; client < CLIENTS; client++) begin
            write_data_i[client*DATA_WIDTH +: DATA_WIDTH] = '0;
        end
        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        // All eight logical banks must accept one write in the same cycle.
        for (integer bank = 0; bank < BANKS; bank++) begin
            write_address_i[bank*ADDRESS_WIDTH +: ADDRESS_WIDTH] =
                ADDRESS_WIDTH'(bank << 7);
            write_data_i[bank*DATA_WIDTH +: DATA_WIDTH] =
                pattern(32'h1000_0000 + bank);
            write_valid_i[bank] = 1'b1;
        end
        @(posedge clk_i);
        grant_snapshot = write_ready_o;
        if (grant_snapshot[7:0] !== 8'hff || grant_snapshot[15:8] !== 8'h00)
            $fatal(1, "eight-bank write saturation failed: %h",
                   grant_snapshot);
        @(negedge clk_i);
        write_valid_i = '0;

        // All eight banks must also accept and return reads independently.
        read_response_ready_i[7:0] = '0;
        for (integer bank = 0; bank < BANKS; bank++) begin
            read_request_address_i[bank*ADDRESS_WIDTH +: ADDRESS_WIDTH] =
                ADDRESS_WIDTH'(bank << 7);
            read_request_valid_i[bank] = 1'b1;
        end
        @(posedge clk_i);
        grant_snapshot = read_request_ready_o;
        if (grant_snapshot[7:0] !== 8'hff || grant_snapshot[15:8] !== 8'h00)
            $fatal(1, "eight-bank read saturation failed: %h",
                   grant_snapshot);
        @(negedge clk_i);
        read_request_valid_i = '0;
        #1;
        if (read_response_valid_o[7:0] !== 8'hff)
            $fatal(1, "eight-bank response valid failed: %h",
                   read_response_valid_o);
        for (integer bank = 0; bank < BANKS; bank++) begin
            if (read_response_data_o[bank*DATA_WIDTH +: DATA_WIDTH] !==
                pattern(32'h1000_0000 + bank))
                $fatal(1, "bank %0d saturation read mismatch", bank);
        end
        read_response_ready_i[7:0] = '1;
        @(posedge clk_i);

        // Sixteen persistent writers to one bank must each win exactly once.
        @(negedge clk_i);
        fairness_seen = '0;
        for (integer client = 0; client < CLIENTS; client++) begin
            write_address_i[client*ADDRESS_WIDTH +: ADDRESS_WIDTH] =
                ADDRESS_WIDTH'((client << 10) | (3 << 7));
            write_data_i[client*DATA_WIDTH +: DATA_WIDTH] =
                pattern(32'h2000_0000 + client);
            write_valid_i[client] = 1'b1;
        end
        for (integer opportunity = 0; opportunity < CLIENTS;
             opportunity++) begin
            @(posedge clk_i);
            grant_snapshot = write_ready_o;
            if ($countones(grant_snapshot) != 1)
                $fatal(1, "same-bank arbiter grant is not one-hot: %h",
                       grant_snapshot);
            if ((fairness_seen & grant_snapshot) != '0)
                $fatal(1, "same-bank arbiter repeated a client: %h",
                       grant_snapshot);
            fairness_seen |= grant_snapshot;
            @(negedge clk_i);
            write_valid_i &= ~grant_snapshot;
        end
        if (fairness_seen != '1)
            $fatal(1, "same-bank fairness omitted clients: %h",
                   fairness_seen);

        for (integer client = 0; client < CLIENTS; client++) begin
            drive_read(client,
                ADDRESS_WIDTH'((client << 10) | (3 << 7)),
                pattern(32'h2000_0000 + client));
        end

        // A same-address read/write collision returns the pre-write word.
        drive_write(0, 24'h001_200, pattern(32'h3000_0001));
        @(negedge clk_i);
        read_response_ready_i[0] = 1'b0;
        read_request_address_i[0 +: ADDRESS_WIDTH] = 24'h001_200;
        read_request_valid_i[0] = 1'b1;
        write_address_i[ADDRESS_WIDTH +: ADDRESS_WIDTH] = 24'h001_200;
        write_data_i[DATA_WIDTH +: DATA_WIDTH] = pattern(32'h3000_0002);
        write_byte_enable_i[DATA_BYTES +: DATA_BYTES] = '1;
        write_valid_i[1] = 1'b1;
        @(posedge clk_i);
        if (!read_request_ready_o[0] || !write_ready_o[1])
            $fatal(1, "read/write collision was not accepted together");
        @(negedge clk_i);
        read_request_valid_i[0] = 1'b0;
        write_valid_i[1] = 1'b0;
        #1;
        if (!read_response_valid_o[0] ||
            (read_response_data_o[0 +: DATA_WIDTH] !==
             pattern(32'h3000_0001)))
            $fatal(1, "read-before-write collision behavior failed");
        read_response_ready_i[0] = 1'b1;
        @(posedge clk_i);
        drive_read(0, 24'h001_200, pattern(32'h3000_0002));

        // Backpressure must retain one response and block another request.
        drive_write(0, 24'h002_000, pattern(32'h4000_0001));
        @(negedge clk_i);
        read_response_ready_i[0] = 1'b0;
        read_request_address_i[0 +: ADDRESS_WIDTH] = 24'h002_000;
        read_request_valid_i[0] = 1'b1;
        do @(posedge clk_i); while (!read_request_ready_o[0]);
        @(negedge clk_i);
        read_request_address_i[0 +: ADDRESS_WIDTH] = 24'h001_200;
        do begin
            @(posedge clk_i);
            #1;
        end while (!read_response_valid_o[0]);
        held_response = read_response_data_o[0 +: DATA_WIDTH];
        repeat (3) begin
            @(posedge clk_i);
            #1;
            if (!read_response_valid_o[0] || read_request_ready_o[0] ||
                (read_response_data_o[0 +: DATA_WIDTH] !== held_response))
                $fatal(1, "response backpressure stability failed");
        end
        if (held_response !== pattern(32'h4000_0001))
            $fatal(1, "backpressured response data mismatch");
        @(negedge clk_i);
        read_response_ready_i[0] = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        read_request_valid_i[0] = 1'b0;

        // Malformed internal traffic is rejected and raises sticky diagnostics.
        write_address_i[0 +: ADDRESS_WIDTH] = 24'h000_001;
        write_byte_enable_i[0 +: DATA_BYTES] = '0;
        write_valid_i[0] = 1'b1;
        read_request_address_i[ADDRESS_WIDTH +: ADDRESS_WIDTH] = 24'hfff_f81;
        read_request_valid_i[1] = 1'b1;
        @(posedge clk_i);
        #1;
        if (write_ready_o[0] || read_request_ready_o[1] || !protocol_error_o)
            $fatal(1, "malformed request diagnostics failed");
        @(negedge clk_i);
        write_valid_i = '0;
        read_request_valid_i = '0;
        write_byte_enable_i = '1;

        reads_before_clear = accepted_reads_o;
        writes_before_clear = accepted_writes_o;
        if ((reads_before_clear < 64'd27) ||
            (writes_before_clear < 64'd26) ||
            (write_conflict_cycles_o < 64'd15))
            $fatal(1, "service counters are below expected coverage");

        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;
        #1;
        if (busy_o || protocol_error_o || (accepted_reads_o != '0) ||
            (accepted_writes_o != '0) || (read_conflict_cycles_o != '0) ||
            (write_conflict_cycles_o != '0))
            $fatal(1, "clear did not reset wrapper state");
        drive_read(0, 24'h001_200, pattern(32'h3000_0002));

        $display("[RTL_SIM PASS] npu_pod_shared_sram reads=%0d writes=%0d",
                 reads_before_clear, writes_before_clear);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "npu_pod_shared_sram timeout");
    end

endmodule

`default_nettype wire
