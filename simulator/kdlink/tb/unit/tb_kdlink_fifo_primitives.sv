`timescale 1ns/1ps
module tb_kdlink_fifo_primitives;
    reg write_clk;
    reg read_clk;
    reg async_write_rst_n;
    reg async_read_rst_n;
    reg [63:0] async_write_data;
    reg async_write_valid;
    wire async_write_ready;
    wire [63:0] async_read_data;
    wire async_read_valid;
    reg async_read_ready;
    wire async_overflow;
    wire async_underflow;
    reg sync_rst_n;
    reg [63:0] sync_push_data;
    reg sync_push_valid;
    wire sync_push_ready;
    wire [63:0] sync_pop_data;
    wire sync_pop_valid;
    reg sync_pop_ready;
    wire [3:0] sync_occupancy;
    wire sync_overflow;
    wire sync_underflow;
    integer async_write_index;
    integer async_read_index;
    integer async_ready_cycle;
    integer sync_index;
    integer sync_expected;
    reg async_done;
    reg sync_done;

    function automatic [63:0] pattern(input integer value);
        reg [31:0] mixed;
        begin
            mixed = (value * 32'h9e37_79b9) ^ (value * 32'h7f4a_7c15) ^ 32'ha5c3_69f0;
            pattern = {mixed ^ 32'h5a96_c30f, mixed};
        end
    endfunction

    coll_async_fifo #(.WIDTH(64), .ADDR_W(3)) u_async_fifo (
        .write_clk_i(write_clk), .write_rst_n_i(async_write_rst_n),
        .write_data_i(async_write_data), .write_valid_i(async_write_valid),
        .write_ready_o(async_write_ready), .read_clk_i(read_clk),
        .read_rst_n_i(async_read_rst_n), .read_data_o(async_read_data),
        .read_valid_o(async_read_valid), .read_ready_i(async_read_ready),
        .overflow_o(async_overflow), .underflow_o(async_underflow)
    );

    coll_sync_fifo #(.WIDTH(64), .DEPTH(8), .ADDR_W(3), .COUNT_W(4)) u_sync_fifo (
        .clk_i(write_clk), .rst_n_i(sync_rst_n), .push_data_i(sync_push_data),
        .push_valid_i(sync_push_valid), .push_ready_o(sync_push_ready),
        .pop_data_o(sync_pop_data), .pop_valid_o(sync_pop_valid),
        .pop_ready_i(sync_pop_ready), .occupancy_o(sync_occupancy),
        .overflow_o(sync_overflow), .underflow_o(sync_underflow)
    );

    always #1.0 write_clk = ~write_clk;
    always #1.3 read_clk = ~read_clk;

    always @(posedge read_clk or negedge async_read_rst_n) begin
        if (!async_read_rst_n) begin
            async_read_index <= 0;
        end else if (async_read_valid && async_read_ready) begin
            if (async_read_data != pattern(async_read_index))
                $fatal(1, "async FIFO data mismatch index=%0d got=%h expected=%h",
                    async_read_index, async_read_data, pattern(async_read_index));
            async_read_index <= async_read_index + 1;
        end
    end

    task automatic async_push(input integer value);
        begin
            @(negedge write_clk);
            async_write_data = pattern(value);
            async_write_valid = 1'b1;
            while (!async_write_ready) @(negedge write_clk);
            @(posedge write_clk);
            @(negedge write_clk);
            async_write_valid = 1'b0;
        end
    endtask

    initial begin
        write_clk = 1'b0;
        read_clk = 1'b0;
        async_write_rst_n = 1'b0;
        async_read_rst_n = 1'b0;
        async_write_data = 64'd0;
        async_write_valid = 1'b0;
        async_read_ready = 1'b0;
        async_write_index = 0;
        async_read_index = 0;
        async_ready_cycle = 0;
        async_done = 1'b0;
        repeat (4) @(posedge write_clk);
        @(negedge write_clk); async_write_rst_n = 1'b1;
        repeat (3) @(posedge read_clk);
        @(negedge read_clk); async_read_rst_n = 1'b1;
        for (async_write_index = 0; async_write_index < 9; async_write_index = async_write_index + 1)
            async_push(async_write_index);
        repeat (2) @(posedge write_clk); #0.01;
        if (async_write_ready) $fatal(1, "async FIFO did not assert full backpressure");
        @(negedge read_clk); async_read_ready = 1'b1;
        wait (async_read_index == 9);
        fork
            begin
                for (async_write_index = 9; async_write_index < 264; async_write_index = async_write_index + 1)
                    async_push(async_write_index);
            end
            begin
                for (async_ready_cycle = 0; async_ready_cycle < 900; async_ready_cycle = async_ready_cycle + 1) begin
                    @(negedge read_clk);
                    async_read_ready = (async_ready_cycle[2:0] != 3'd2) &&
                        (async_ready_cycle[2:0] != 3'd5);
                    if (async_read_index == 264) async_ready_cycle = 900;
                end
                async_read_ready = 1'b1;
            end
        join
        wait (async_read_index == 264);
        repeat (6) @(posedge read_clk);
        if (async_overflow || async_underflow || async_read_valid)
            $fatal(1, "async FIFO final status failure overflow=%b underflow=%b valid=%b",
                async_overflow, async_underflow, async_read_valid);
        @(negedge write_clk); async_write_rst_n = 1'b0;
        @(negedge read_clk); async_read_rst_n = 1'b0;
        repeat (3) @(posedge write_clk);
        @(negedge write_clk); async_write_rst_n = 1'b1;
        @(negedge read_clk); async_read_rst_n = 1'b1;
        async_done = 1'b1;
    end

    initial begin
        sync_rst_n = 1'b0;
        sync_push_data = 64'd0;
        sync_push_valid = 1'b0;
        sync_pop_ready = 1'b0;
        sync_expected = 0;
        sync_done = 1'b0;
        repeat (5) @(posedge write_clk);
        @(negedge write_clk); sync_rst_n = 1'b1;
        for (sync_index = 0; sync_index < 8; sync_index = sync_index + 1) begin
            @(negedge write_clk);
            if (!sync_push_ready) $fatal(1, "sync FIFO filled early index=%0d", sync_index);
            sync_push_data = pattern(sync_index);
            sync_push_valid = 1'b1;
        end
        @(negedge write_clk); sync_push_valid = 1'b0; #0.01;
        if (sync_push_ready || sync_occupancy != 8)
            $fatal(1, "sync FIFO did not reach full occupancy=%0d", sync_occupancy);
        for (sync_expected = 0; sync_expected < 8; sync_expected = sync_expected + 1) begin
            @(negedge write_clk);
            if (!sync_pop_valid || sync_pop_data != pattern(sync_expected))
                $fatal(1, "sync FIFO drain mismatch index=%0d", sync_expected);
            sync_pop_ready = 1'b1;
        end
        @(negedge write_clk); sync_pop_ready = 1'b0; #0.01;
        if (sync_pop_valid || sync_occupancy != 0)
            $fatal(1, "sync FIFO did not drain occupancy=%0d", sync_occupancy);
        @(negedge write_clk);
        sync_push_data = pattern(8);
        sync_push_valid = 1'b1;
        @(negedge write_clk);
        sync_expected = 8;
        for (sync_index = 9; sync_index < 265; sync_index = sync_index + 1) begin
            if (!sync_pop_valid || sync_pop_data != pattern(sync_expected))
                $fatal(1, "sync FIFO simultaneous mismatch index=%0d", sync_expected);
            sync_push_data = pattern(sync_index);
            sync_push_valid = 1'b1;
            sync_pop_ready = 1'b1;
            sync_expected = sync_expected + 1;
            @(negedge write_clk);
        end
        sync_push_valid = 1'b0;
        if (!sync_pop_valid || sync_pop_data != pattern(sync_expected))
            $fatal(1, "sync FIFO final word mismatch index=%0d", sync_expected);
        @(negedge write_clk); sync_pop_ready = 1'b0; #0.01;
        if (sync_pop_valid || sync_occupancy != 0 || sync_overflow || sync_underflow)
            $fatal(1, "sync FIFO final status failure occupancy=%0d", sync_occupancy);
        @(negedge write_clk); sync_rst_n = 1'b0;
        repeat (2) @(posedge write_clk);
        @(negedge write_clk); sync_rst_n = 1'b1;
        sync_done = 1'b1;
    end

    initial begin
        wait (async_done && sync_done);
        $display("TB_KDLINK_FIFO_PRIMITIVES_PASS async_words=264 sync_words=265 full_empty_wrap=1 backpressure=1 exact_data=1");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "KDLink FIFO primitive test timeout async=%0d sync=%0d",
            async_read_index, sync_expected);
    end
endmodule
