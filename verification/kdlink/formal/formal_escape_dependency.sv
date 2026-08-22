module formal_escape_dependency;
    (* gclk *) reg clk;
    genvar source_node;
    genvar destination_node;
    generate
        for (source_node = 0; source_node < 32; source_node = source_node + 1) begin : g_source
            for (destination_node = 0; destination_node < 32;
                 destination_node = destination_node + 1) begin : g_destination
                if (source_node != destination_node) begin : g_route
                    always @(posedge clk) begin
                        assert (destination_node != source_node);
                        assert (destination_node >= 0 && destination_node < 32);
                    end
                end
            end
        end
    endgenerate
endmodule
