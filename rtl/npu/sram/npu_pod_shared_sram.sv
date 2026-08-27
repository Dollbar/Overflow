`timescale 1ns/1ps
`default_nettype none

module npu_pod_shared_sram #(
    parameter int unsigned CLIENTS = 16,
    parameter int unsigned BANKS = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned DATA_WIDTH = DATA_BYTES * 8,
    parameter int unsigned ADDRESS_WIDTH = 24,
    parameter int unsigned BANK_INDEX_WIDTH = $clog2(BANKS),
    parameter int unsigned CLIENT_INDEX_WIDTH = $clog2(CLIENTS),
    parameter int unsigned BANK_DEPTH = 16384,
    parameter int unsigned BANK_ADDRESS_WIDTH = $clog2(BANK_DEPTH)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic [CLIENTS-1:0] read_request_valid_i,
    output logic [CLIENTS-1:0] read_request_ready_o,
    input  logic [CLIENTS*ADDRESS_WIDTH-1:0] read_request_address_i,
    output logic [CLIENTS-1:0] read_response_valid_o,
    input  logic [CLIENTS-1:0] read_response_ready_i,
    output logic [CLIENTS*DATA_WIDTH-1:0] read_response_data_o,

    input  logic [CLIENTS-1:0] write_valid_i,
    output logic [CLIENTS-1:0] write_ready_o,
    input  logic [CLIENTS*ADDRESS_WIDTH-1:0] write_address_i,
    input  logic [CLIENTS*DATA_WIDTH-1:0] write_data_i,
    input  logic [CLIENTS*DATA_BYTES-1:0] write_byte_enable_i,

    output logic busy_o,
    output logic protocol_error_o,
    output logic [63:0] accepted_reads_o,
    output logic [63:0] accepted_writes_o,
    output logic [63:0] read_conflict_cycles_o,
    output logic [63:0] write_conflict_cycles_o
);

    localparam logic [ADDRESS_WIDTH:0] CAPACITY_BYTES = 25'd16777216;
    localparam logic [ADDRESS_WIDTH:0] LAST_BEAT_ADDRESS =
        CAPACITY_BYTES - 25'd128;

    logic [BANKS*CLIENTS-1:0] bank_read_request;
    logic [BANKS*CLIENTS-1:0] bank_read_grant;
    logic [BANKS*CLIENTS-1:0] bank_write_request;
    logic [BANKS*CLIENTS-1:0] bank_write_grant;
    logic [BANKS-1:0] bank_read_enable;
    logic [BANKS*BANK_ADDRESS_WIDTH-1:0] bank_read_address;
    logic [BANKS-1:0] bank_write_enable;
    logic [BANKS*BANK_ADDRESS_WIDTH-1:0] bank_write_address;
    logic [BANKS*DATA_WIDTH-1:0] bank_write_data;
    logic [BANKS*DATA_WIDTH-1:0] bank_read_data;
    logic [BANKS-1:0] bank_read_return_valid_q;
    logic [BANKS*CLIENT_INDEX_WIDTH-1:0] bank_read_return_client_q;
    logic [CLIENTS-1:0] client_read_pending_q;
    logic [CLIENTS-1:0] response_buffer_valid_q;
    logic [CLIENTS*DATA_WIDTH-1:0] response_buffer_data_q;
    logic [CLIENTS-1:0] incoming_response_valid;
    logic [CLIENTS*DATA_WIDTH-1:0] incoming_response_data;
    logic [CLIENTS-1:0] read_response_fire;
    logic [CLIENTS-1:0] read_request_fire;
    logic [CLIENTS-1:0] write_fire;
    logic [CLIENTS-1:0] client_read_slot_available;
    logic malformed_request;

    always_comb begin
        incoming_response_valid = '0;
        for (integer client = 0; client < CLIENTS; client++) begin
            incoming_response_data[client*DATA_WIDTH +: DATA_WIDTH] = '0;
            for (integer bank = 0; bank < BANKS; bank++) begin
                if (bank_read_return_valid_q[bank] &&
                    (bank_read_return_client_q[
                        bank*CLIENT_INDEX_WIDTH +: CLIENT_INDEX_WIDTH] ==
                     CLIENT_INDEX_WIDTH'(client))) begin
                    incoming_response_valid[client] = 1'b1;
                    incoming_response_data[
                        client*DATA_WIDTH +: DATA_WIDTH] =
                        bank_read_data[bank*DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end
    end

    always_comb begin
        for (integer client = 0; client < CLIENTS; client++) begin
            read_response_valid_o[client] = response_buffer_valid_q[client] ||
                                            incoming_response_valid[client];
            read_response_data_o[client*DATA_WIDTH +: DATA_WIDTH] =
                response_buffer_valid_q[client] ?
                response_buffer_data_q[client*DATA_WIDTH +: DATA_WIDTH] :
                incoming_response_data[client*DATA_WIDTH +: DATA_WIDTH];
            read_response_fire[client] = read_response_valid_o[client] &&
                                         read_response_ready_i[client];
            client_read_slot_available[client] =
                !client_read_pending_q[client] || read_response_fire[client];
        end
    end

    always_comb begin
        read_request_ready_o = '0;
        write_ready_o = '0;
        bank_read_enable = '0;
        bank_read_address = '0;
        bank_write_enable = '0;
        bank_write_address = '0;
        bank_write_data = '0;
        bank_read_request = '0;
        bank_write_request = '0;
        malformed_request = 1'b0;

        for (integer client = 0; client < CLIENTS; client++) begin
            if (read_request_valid_i[client] &&
                ((read_request_address_i[
                    client*ADDRESS_WIDTH +: 7] != 7'd0) ||
                 ({1'b0, read_request_address_i[
                     client*ADDRESS_WIDTH +: ADDRESS_WIDTH]} >
                  LAST_BEAT_ADDRESS))) begin
                malformed_request = 1'b1;
            end
            if (write_valid_i[client] &&
                ((write_address_i[
                    client*ADDRESS_WIDTH +: 7] != 7'd0) ||
                 ({1'b0, write_address_i[
                     client*ADDRESS_WIDTH +: ADDRESS_WIDTH]} >
                  LAST_BEAT_ADDRESS) ||
                 (write_byte_enable_i[
                     client*DATA_BYTES +: DATA_BYTES] !=
                  {DATA_BYTES{1'b1}}))) begin
                malformed_request = 1'b1;
            end
            for (integer bank = 0; bank < BANKS; bank++) begin
                if (read_request_valid_i[client] &&
                    client_read_slot_available[client] &&
                    (read_request_address_i[
                        client*ADDRESS_WIDTH + 7 +:
                        BANK_INDEX_WIDTH] == BANK_INDEX_WIDTH'(bank)) &&
                    (read_request_address_i[
                        client*ADDRESS_WIDTH +: 7] == 7'd0) &&
                    ({1'b0, read_request_address_i[
                        client*ADDRESS_WIDTH +: ADDRESS_WIDTH]} <=
                     LAST_BEAT_ADDRESS)) begin
                    bank_read_request[bank*CLIENTS + client] = 1'b1;
                end
                if (write_valid_i[client] &&
                    (write_address_i[
                        client*ADDRESS_WIDTH + 7 +:
                        BANK_INDEX_WIDTH] == BANK_INDEX_WIDTH'(bank)) &&
                    (write_address_i[
                        client*ADDRESS_WIDTH +: 7] == 7'd0) &&
                    ({1'b0, write_address_i[
                        client*ADDRESS_WIDTH +: ADDRESS_WIDTH]} <=
                     LAST_BEAT_ADDRESS) &&
                    (write_byte_enable_i[
                        client*DATA_BYTES +: DATA_BYTES] ==
                     {DATA_BYTES{1'b1}})) begin
                    bank_write_request[bank*CLIENTS + client] = 1'b1;
                end
            end
        end

        for (integer bank = 0; bank < BANKS; bank++) begin
            bank_read_enable[bank] =
                |bank_read_grant[bank*CLIENTS +: CLIENTS];
            bank_write_enable[bank] =
                |bank_write_grant[bank*CLIENTS +: CLIENTS];
            for (integer client = 0; client < CLIENTS; client++) begin
                if (bank_read_grant[bank*CLIENTS + client]) begin
                    read_request_ready_o[client] = 1'b1;
                    bank_read_address[
                        bank*BANK_ADDRESS_WIDTH +: BANK_ADDRESS_WIDTH] =
                        read_request_address_i[
                            client*ADDRESS_WIDTH + 10 +:
                            BANK_ADDRESS_WIDTH];
                end
                if (bank_write_grant[bank*CLIENTS + client]) begin
                    write_ready_o[client] = 1'b1;
                    bank_write_address[
                        bank*BANK_ADDRESS_WIDTH +: BANK_ADDRESS_WIDTH] =
                        write_address_i[
                            client*ADDRESS_WIDTH + 10 +:
                            BANK_ADDRESS_WIDTH];
                    bank_write_data[bank*DATA_WIDTH +: DATA_WIDTH] =
                        write_data_i[
                            client*DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end
    end

    assign read_request_fire = read_request_valid_i & read_request_ready_o;
    assign write_fire = write_valid_i & write_ready_o;
    assign busy_o = (|client_read_pending_q) || (|response_buffer_valid_q) ||
                    (|bank_read_return_valid_q);

    generate
        for (genvar bank = 0; bank < BANKS; bank++) begin : g_bank
            npu_round_robin_arbiter16 u_read_arbiter (
                .clk_i,
                .rst_i,
                .clear_i,
                .request_i(bank_read_request[
                    bank*CLIENTS +: CLIENTS]),
                .grant_o(bank_read_grant[bank*CLIENTS +: CLIENTS])
            );
            npu_round_robin_arbiter16 u_write_arbiter (
                .clk_i,
                .rst_i,
                .clear_i,
                .request_i(bank_write_request[
                    bank*CLIENTS +: CLIENTS]),
                .grant_o(bank_write_grant[bank*CLIENTS +: CLIENTS])
            );
            kd28_fifo_sdp_storage_map #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH(BANK_DEPTH),
                .ADDR_WIDTH(BANK_ADDRESS_WIDTH)
            ) u_storage (
                .write_clk_i(clk_i),
                .write_cs_i(bank_write_enable[bank]),
                .write_addr_i(bank_write_address[
                    bank*BANK_ADDRESS_WIDTH +: BANK_ADDRESS_WIDTH]),
                .write_data_i(bank_write_data[
                    bank*DATA_WIDTH +: DATA_WIDTH]),
                .read_clk_i(clk_i),
                .read_cs_i(bank_read_enable[bank]),
                .read_addr_i(bank_read_address[
                    bank*BANK_ADDRESS_WIDTH +: BANK_ADDRESS_WIDTH]),
                .read_data_o(bank_read_data[
                    bank*DATA_WIDTH +: DATA_WIDTH])
            );
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            bank_read_return_valid_q <= '0;
            bank_read_return_client_q <= '0;
            client_read_pending_q <= '0;
            response_buffer_valid_q <= '0;
            for (integer client = 0; client < CLIENTS; client++) begin
                response_buffer_data_q[
                    client*DATA_WIDTH +: DATA_WIDTH] <= '0;
            end
            protocol_error_o <= 1'b0;
            accepted_reads_o <= '0;
            accepted_writes_o <= '0;
            read_conflict_cycles_o <= '0;
            write_conflict_cycles_o <= '0;
        end else begin
            bank_read_return_valid_q <= bank_read_enable;
            for (integer bank = 0; bank < BANKS; bank++) begin
                if (bank_read_enable[bank]) begin
                    for (integer client = 0; client < CLIENTS; client++) begin
                        if (bank_read_grant[bank*CLIENTS + client]) begin
                            bank_read_return_client_q[
                                bank*CLIENT_INDEX_WIDTH +:
                                CLIENT_INDEX_WIDTH] <=
                                CLIENT_INDEX_WIDTH'(client);
                        end
                    end
                end
            end

            for (integer client = 0; client < CLIENTS; client++) begin
                case ({read_request_fire[client], read_response_fire[client]})
                    2'b10: client_read_pending_q[client] <= 1'b1;
                    2'b01: client_read_pending_q[client] <= 1'b0;
                    default: client_read_pending_q[client] <=
                             client_read_pending_q[client];
                endcase
                if (response_buffer_valid_q[client] &&
                    read_response_ready_i[client]) begin
                    response_buffer_valid_q[client] <= 1'b0;
                end
                if (incoming_response_valid[client] &&
                    !(read_response_ready_i[client] &&
                      !response_buffer_valid_q[client])) begin
                    response_buffer_valid_q[client] <= 1'b1;
                    response_buffer_data_q[
                        client*DATA_WIDTH +: DATA_WIDTH] <=
                        incoming_response_data[
                            client*DATA_WIDTH +: DATA_WIDTH];
                end
            end

            accepted_reads_o <= accepted_reads_o + 64'($countones(
                read_request_fire));
            accepted_writes_o <= accepted_writes_o + 64'($countones(
                write_fire));
            if ($countones(read_request_valid_i) >
                $countones(read_request_fire)) begin
                read_conflict_cycles_o <= read_conflict_cycles_o + 64'd1;
            end
            if ($countones(write_valid_i) > $countones(write_fire)) begin
                write_conflict_cycles_o <= write_conflict_cycles_o + 64'd1;
            end
            if (malformed_request) begin
                protocol_error_o <= 1'b1;
            end
        end
    end

    initial begin
        if ((CLIENTS != 16) || (BANKS != 8) || (DATA_BYTES != 128) ||
            (DATA_WIDTH != 1024) || (ADDRESS_WIDTH != 24) ||
            (BANK_DEPTH != 16384)) begin
            $error("npu_pod_shared_sram violates the v0.1 geometry");
        end
    end

endmodule

`default_nettype wire
