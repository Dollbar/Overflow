interface kdlink_stream_if(input logic clk_i);
    logic valid;
    logic ready;
    logic [639:0] flit;

    task automatic drive_idle;
        valid = 1'b0;
        flit = 640'd0;
    endtask

    task automatic send(input logic [639:0] value);
        @(negedge clk_i);
        valid = 1'b1;
        flit = value;
        do @(posedge clk_i); while (!ready);
        @(negedge clk_i);
        valid = 1'b0;
        flit = 640'd0;
    endtask

    modport source(output valid, output flit, input ready);
    modport sink(input valid, input flit, output ready);
    modport monitor(input valid, input ready, input flit);
endinterface
