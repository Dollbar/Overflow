`timescale 1ns/1ps
`default_nettype none
// Tile多入口banked buffer：每个入口独立保存packet归属，每个bank每周期最多提交一个写入。
// 本叶模块拥有VOQ occupancy/reservation/tail/head和payload存储，避免多个入口复制容量账本。
module switch_tile_multi_ingress_buffer #(
    parameter integer C_INGRESS_PORTS=4,
    parameter integer C_NUM_BANKS=2,
    parameter integer C_NUM_VOQS=4,
    parameter integer C_QUEUE_DEPTH=4,
    parameter integer C_DATA_WIDTH=32,
    parameter integer C_META_WIDTH=16,
    parameter integer C_QUEUE_WIDTH=2,
    parameter integer C_ADDR_WIDTH=2,
    parameter integer C_COUNT_WIDTH=3,
    parameter integer C_INGRESS_WIDTH=2,
    parameter integer C_BANK_WIDTH=1
) (
    input wire i_clk,
    input wire i_rstn,
    input wire [C_INGRESS_PORTS-1:0] i_valid,
    output reg [C_INGRESS_PORTS-1:0] o_ready,
    input wire [C_INGRESS_PORTS*C_DATA_WIDTH-1:0] i_data,
    input wire [C_INGRESS_PORTS*C_META_WIDTH-1:0] i_meta,
    input wire [C_INGRESS_PORTS*C_QUEUE_WIDTH-1:0] i_queue,
    input wire [C_INGRESS_PORTS-1:0] i_sop,
    input wire [C_INGRESS_PORTS-1:0] i_eop,
    input wire [C_INGRESS_PORTS*C_COUNT_WIDTH-1:0] i_packet_flits,
    input wire [C_NUM_BANKS-1:0] i_dequeue_request,
    input wire [C_NUM_BANKS*C_QUEUE_WIDTH-1:0] i_dequeue_queue,
    output reg [C_NUM_BANKS-1:0] o_dequeue_valid,
    input wire [C_NUM_BANKS-1:0] i_dequeue_ready,
    output reg [C_NUM_BANKS*C_DATA_WIDTH-1:0] o_dequeue_data,
    output reg [C_NUM_BANKS*C_META_WIDTH-1:0] o_dequeue_meta,
    output reg [C_NUM_BANKS-1:0] o_dequeue_sop,
    output reg [C_NUM_BANKS-1:0] o_dequeue_eop,
    output reg [C_NUM_BANKS-1:0] o_bank_conflict,
    output reg [C_INGRESS_PORTS-1:0] o_retry,
    output reg [C_NUM_VOQS*C_COUNT_WIDTH-1:0] o_occupancy,
    output reg [C_NUM_VOQS*C_COUNT_WIDTH-1:0] o_reserved,
    output reg [15:0] o_total_occupancy,
    output reg [15:0] o_total_reserved,
    output reg o_protocol_error,
    output reg o_overflow_error,
    output reg o_underflow_error,
    output reg o_overflow_event_level,
    output reg o_underflow_event_level,
    output wire o_config_error,
    output wire o_error,
    output wire o_quiescent
);
    localparam integer C_TOTAL_SLOTS=C_NUM_VOQS*C_QUEUE_DEPTH;
    localparam integer C_QUEUES_PER_BANK=(C_NUM_VOQS+C_NUM_BANKS-1)/C_NUM_BANKS;
    localparam integer C_BANK_LOCAL_SLOTS=C_QUEUES_PER_BANK*C_QUEUE_DEPTH;
    localparam integer C_BANK_ADDRESS_WIDTH=C_QUEUE_WIDTH-C_BANK_WIDTH+C_ADDR_WIDTH;
    localparam [C_COUNT_WIDTH-1:0] C_DEPTH_COUNT=C_QUEUE_DEPTH[C_COUNT_WIDTH-1:0];
    localparam [C_ADDR_WIDTH-1:0] C_LAST_ADDRESS=C_QUEUE_DEPTH[C_ADDR_WIDTH-1:0]-1'b1;
    localparam [C_INGRESS_WIDTH-1:0] C_LAST_INGRESS=C_INGRESS_PORTS[C_INGRESS_WIDTH-1:0]-1'b1;
    localparam CONFIG_LEGAL=(C_INGRESS_PORTS>=1)&&(C_INGRESS_PORTS<=32)&&
        (C_NUM_BANKS>=1)&&(C_NUM_BANKS<=32)&&(C_NUM_VOQS>=C_NUM_BANKS)&&
        (C_QUEUE_DEPTH>=1)&&(C_DATA_WIDTH>=1)&&(C_META_WIDTH>=1)&&
        (C_INGRESS_WIDTH>=1)&&(C_INGRESS_WIDTH<=5)&&(C_BANK_WIDTH>=1)&&(C_BANK_WIDTH<=5)&&
        (C_QUEUE_WIDTH>=1)&&(C_QUEUE_WIDTH<=16)&&(C_ADDR_WIDTH>=1)&&(C_ADDR_WIDTH<=16)&&
        (C_COUNT_WIDTH>=1)&&
        (C_TOTAL_SLOTS<=65535)&&
        (C_QUEUE_WIDTH>=C_BANK_WIDTH)&&
        ((1<<C_INGRESS_WIDTH)>=C_INGRESS_PORTS)&&((1<<C_BANK_WIDTH)==C_NUM_BANKS)&&
        ((1<<C_QUEUE_WIDTH)>=C_NUM_VOQS)&&((1<<C_ADDR_WIDTH)==C_QUEUE_DEPTH)&&
        (C_COUNT_WIDTH<=16)&&((1<<C_COUNT_WIDTH)>C_QUEUE_DEPTH);

    reg [C_ADDR_WIDTH-1:0] head_q [0:C_NUM_VOQS-1];
    reg [C_ADDR_WIDTH-1:0] tail_q [0:C_NUM_VOQS-1];
    reg [C_COUNT_WIDTH-1:0] occupancy_q [0:C_NUM_VOQS-1];
    reg [C_COUNT_WIDTH-1:0] reserved_q [0:C_NUM_VOQS-1];
    reg queue_owner_valid_q [0:C_NUM_VOQS-1];
    reg [C_INGRESS_WIDTH-1:0] queue_owner_q [0:C_NUM_VOQS-1];
    reg input_owner_valid_q [0:C_INGRESS_PORTS-1];
    reg [C_QUEUE_WIDTH-1:0] input_owner_queue_q [0:C_INGRESS_PORTS-1];
    reg [C_INGRESS_WIDTH-1:0] rr_q [0:C_NUM_BANKS-1];
    reg [C_NUM_BANKS-1:0] dequeue_hold_valid_q;
    reg [C_NUM_BANKS*C_QUEUE_WIDTH-1:0] dequeue_hold_queue_q;
    reg [C_NUM_BANKS*C_DATA_WIDTH-1:0] dequeue_hold_data_q;
    reg [C_NUM_BANKS*C_META_WIDTH-1:0] dequeue_hold_meta_q;
    reg [C_NUM_BANKS-1:0] dequeue_hold_sop_q,dequeue_hold_eop_q;
    wire [C_NUM_BANKS*C_DATA_WIDTH-1:0] bank_read_data;
    wire [C_NUM_BANKS*C_META_WIDTH-1:0] bank_read_meta;
    wire [C_NUM_BANKS-1:0] bank_read_sop,bank_read_eop;
    reg selected_valid [0:C_NUM_BANKS-1];
    reg [C_INGRESS_WIDTH-1:0] selected_input [0:C_NUM_BANKS-1];
    reg [C_QUEUE_WIDTH-1:0] selected_queue [0:C_NUM_BANKS-1];
    reg [C_NUM_VOQS-1:0] enqueue_fire_queue,dequeue_fire_queue;
    reg [C_INGRESS_PORTS-1:0] enqueue_fire_input;
    reg [15:0] occupancy_sum,reserved_sum;
    integer arb_bank_index,input_index,scan_offset,scan_input,queue_value,bank_value;
    integer dequeue_bank_index,sum_queue_index,state_queue_index;
    integer conflict_count,read_queue;
    integer state_bank,state_input,write_bank;
    reg input_protocol_legal,input_capacity_legal,input_eligible;

    assign o_config_error=!CONFIG_LEGAL;
    assign o_error=o_config_error|o_protocol_error|o_overflow_error|o_underflow_error;
    assign o_quiescent=CONFIG_LEGAL&&(o_total_occupancy==0)&&(o_total_reserved==0)&&!(|dequeue_hold_valid_q);

    // 每个generate实例拥有独立物理memory和唯一时序写口；非整除VOQ数由ceil bank深度容纳。
    genvar memory_bank;
    generate
        for(memory_bank=0;memory_bank<C_NUM_BANKS;memory_bank=memory_bank+1)begin:g_bank_memory
            reg [C_DATA_WIDTH-1:0] data_memory [0:C_BANK_LOCAL_SLOTS-1];
            reg [C_META_WIDTH-1:0] meta_memory [0:C_BANK_LOCAL_SLOTS-1];
            reg sop_memory [0:C_BANK_LOCAL_SLOTS-1];
            reg eop_memory [0:C_BANK_LOCAL_SLOTS-1];
            wire write_enable;
            wire [C_BANK_ADDRESS_WIDTH-1:0] write_local_address;
            wire [31:0] read_queue_value;
            reg [C_QUEUE_WIDTH-1:0] safe_read_queue;
            wire [C_BANK_ADDRESS_WIDTH-1:0] read_local_address;
            assign write_enable=selected_valid[memory_bank]&&
                enqueue_fire_input[selected_input[memory_bank]];
            assign write_local_address[C_ADDR_WIDTH-1:0]=tail_q[selected_queue[memory_bank]];
            assign read_queue_value={{(32-C_QUEUE_WIDTH){1'b0}},
                i_dequeue_queue[memory_bank*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]};
            if(C_QUEUE_WIDTH>C_BANK_WIDTH)begin:g_bank_address_upper
                assign write_local_address[C_BANK_ADDRESS_WIDTH-1:C_ADDR_WIDTH]=
                    selected_queue[memory_bank][C_QUEUE_WIDTH-1:C_BANK_WIDTH];
                assign read_local_address[C_BANK_ADDRESS_WIDTH-1:C_ADDR_WIDTH]=
                    safe_read_queue[C_QUEUE_WIDTH-1:C_BANK_WIDTH];
            end
            assign read_local_address[C_ADDR_WIDTH-1:0]=head_q[safe_read_queue];
            always @(*)begin
                safe_read_queue={C_QUEUE_WIDTH{1'b0}};
                if(read_queue_value<C_NUM_VOQS)begin
                    if((read_queue_value%C_NUM_BANKS)==memory_bank)
                        safe_read_queue=i_dequeue_queue[memory_bank*C_QUEUE_WIDTH+:C_QUEUE_WIDTH];
                end
            end
            assign bank_read_data[memory_bank*C_DATA_WIDTH+:C_DATA_WIDTH]=data_memory[read_local_address];
            assign bank_read_meta[memory_bank*C_META_WIDTH+:C_META_WIDTH]=meta_memory[read_local_address];
            assign bank_read_sop[memory_bank]=sop_memory[read_local_address];
            assign bank_read_eop[memory_bank]=eop_memory[read_local_address];
            always @(posedge i_clk)begin
                if(i_rstn&&CONFIG_LEGAL&&write_enable)begin
                    data_memory[write_local_address]<=i_data[selected_input[memory_bank]*C_DATA_WIDTH+:C_DATA_WIDTH];
                    meta_memory[write_local_address]<=i_meta[selected_input[memory_bank]*C_META_WIDTH+:C_META_WIDTH];
                    sop_memory[write_local_address]<=i_sop[selected_input[memory_bank]];
                    eop_memory[write_local_address]<=i_eop[selected_input[memory_bank]];
                end
            end
        end
    endgenerate

    // 每个bank独立RR；同一入口最多被其目标queue所属bank观察，因此不会重复接纳。
    always @(*) begin
        o_ready={C_INGRESS_PORTS{1'b0}};
        o_retry={C_INGRESS_PORTS{1'b0}};
        o_bank_conflict={C_NUM_BANKS{1'b0}};
        enqueue_fire_input={C_INGRESS_PORTS{1'b0}};
        enqueue_fire_queue={C_NUM_VOQS{1'b0}};
        for(arb_bank_index=0;arb_bank_index<C_NUM_BANKS;arb_bank_index=arb_bank_index+1)begin
            selected_valid[arb_bank_index]=1'b0;
            selected_input[arb_bank_index]={C_INGRESS_WIDTH{1'b0}};
            selected_queue[arb_bank_index]={C_QUEUE_WIDTH{1'b0}};
            conflict_count=0;
            for(scan_offset=0;scan_offset<C_INGRESS_PORTS;scan_offset=scan_offset+1)begin
                scan_input={{(32-C_INGRESS_WIDTH){1'b0}},rr_q[arb_bank_index]}+scan_offset;
                if(scan_input>=C_INGRESS_PORTS)scan_input=scan_input-C_INGRESS_PORTS;
                queue_value=0;bank_value=0;input_protocol_legal=1'b0;
                input_capacity_legal=1'b0;input_eligible=1'b0;
                if(scan_input<C_INGRESS_PORTS)begin
                    queue_value={{(32-C_QUEUE_WIDTH){1'b0}},i_queue[scan_input*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]};
                    if(queue_value<C_NUM_VOQS)begin
                        bank_value=queue_value%C_NUM_BANKS;
                        if(input_owner_valid_q[scan_input])begin
                            input_protocol_legal=!i_sop[scan_input]&&
                                (i_queue[scan_input*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]==input_owner_queue_q[scan_input])&&
                                (i_packet_flits[scan_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]==0)&&
                                queue_owner_valid_q[queue_value]&&
                                (queue_owner_q[queue_value]==scan_input[C_INGRESS_WIDTH-1:0])&&
                                (reserved_q[queue_value]!=0)&&
                                ((reserved_q[queue_value]==1)==i_eop[scan_input]);
                            input_capacity_legal=1'b1;
                        end else begin
                            input_protocol_legal=i_sop[scan_input]&&
                                (i_packet_flits[scan_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]!=0)&&
                                (i_packet_flits[scan_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]<=C_DEPTH_COUNT)&&
                                ((i_packet_flits[scan_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]==1)==i_eop[scan_input]);
                            input_capacity_legal=({1'b0,occupancy_q[queue_value]}+
                                {1'b0,reserved_q[queue_value]}+
                                {1'b0,i_packet_flits[scan_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]})<=
                                {1'b0,C_DEPTH_COUNT};
                        end
                        input_eligible=i_valid[scan_input]&&(bank_value==arb_bank_index)&&
                            input_protocol_legal&&input_capacity_legal&&
                            (input_owner_valid_q[scan_input]||!queue_owner_valid_q[queue_value]);
                        if(input_eligible)begin
                            conflict_count=conflict_count+1;
                            if(!selected_valid[arb_bank_index])begin
                                selected_valid[arb_bank_index]=1'b1;
                                selected_input[arb_bank_index]=scan_input[C_INGRESS_WIDTH-1:0];
                                selected_queue[arb_bank_index]=queue_value[C_QUEUE_WIDTH-1:0];
                            end
                        end
                    end
                end
            end
            if(conflict_count>1)o_bank_conflict[arb_bank_index]=1'b1;
            if(selected_valid[arb_bank_index])o_ready[selected_input[arb_bank_index]]=i_rstn&&CONFIG_LEGAL;
        end
        for(input_index=0;input_index<C_INGRESS_PORTS;input_index=input_index+1)
            if(i_valid[input_index]&&!o_ready[input_index])begin
                queue_value={{(32-C_QUEUE_WIDTH){1'b0}},i_queue[input_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]};
                if(queue_value<C_NUM_VOQS)begin
                    bank_value=queue_value%C_NUM_BANKS;
                    input_eligible=1'b0;
                    if(input_owner_valid_q[input_index])
                        input_eligible=!i_sop[input_index]&&
                            (i_queue[input_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]==input_owner_queue_q[input_index])&&
                            (i_packet_flits[input_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]==0)&&
                            queue_owner_valid_q[queue_value]&&
                            (queue_owner_q[queue_value]==input_index[C_INGRESS_WIDTH-1:0])&&
                            (reserved_q[queue_value]!=0)&&((reserved_q[queue_value]==1)==i_eop[input_index]);
                    else input_eligible=i_sop[input_index]&&
                        (i_packet_flits[input_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]!=0)&&
                        (i_packet_flits[input_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]<=C_DEPTH_COUNT)&&
                        ((i_packet_flits[input_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]==1)==i_eop[input_index])&&
                        !queue_owner_valid_q[queue_value]&&
                        (({1'b0,occupancy_q[queue_value]}+{1'b0,reserved_q[queue_value]}+
                          {1'b0,i_packet_flits[input_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]})<={1'b0,C_DEPTH_COUNT});
                    if(input_eligible&&selected_valid[bank_value])o_retry[input_index]=1'b1;
                end
            end
        for(arb_bank_index=0;arb_bank_index<C_NUM_BANKS;arb_bank_index=arb_bank_index+1)
            if(selected_valid[arb_bank_index]&&o_ready[selected_input[arb_bank_index]])begin
                enqueue_fire_input[selected_input[arb_bank_index]]=i_valid[selected_input[arb_bank_index]];
                enqueue_fire_queue[selected_queue[arb_bank_index]]=i_valid[selected_input[arb_bank_index]];
            end
    end

    // 每bank一个读tenure；首次展示后即使request撤销或改queue，仍保持到真实handshake。
    always @(*) begin
        o_dequeue_valid={C_NUM_BANKS{1'b0}};o_dequeue_data={(C_NUM_BANKS*C_DATA_WIDTH){1'b0}};
        o_dequeue_meta={(C_NUM_BANKS*C_META_WIDTH){1'b0}};o_dequeue_sop={C_NUM_BANKS{1'b0}};
        o_dequeue_eop={C_NUM_BANKS{1'b0}};
        dequeue_fire_queue={C_NUM_VOQS{1'b0}};
        for(dequeue_bank_index=0;dequeue_bank_index<C_NUM_BANKS;dequeue_bank_index=dequeue_bank_index+1)begin
            read_queue={{(32-C_QUEUE_WIDTH){1'b0}},i_dequeue_queue[dequeue_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]};
            if(CONFIG_LEGAL&&i_rstn&&dequeue_hold_valid_q[dequeue_bank_index])begin
                o_dequeue_valid[dequeue_bank_index]=1'b1;
                o_dequeue_data[dequeue_bank_index*C_DATA_WIDTH+:C_DATA_WIDTH]=
                    dequeue_hold_data_q[dequeue_bank_index*C_DATA_WIDTH+:C_DATA_WIDTH];
                o_dequeue_meta[dequeue_bank_index*C_META_WIDTH+:C_META_WIDTH]=
                    dequeue_hold_meta_q[dequeue_bank_index*C_META_WIDTH+:C_META_WIDTH];
                o_dequeue_sop[dequeue_bank_index]=dequeue_hold_sop_q[dequeue_bank_index];
                o_dequeue_eop[dequeue_bank_index]=dequeue_hold_eop_q[dequeue_bank_index];
                if(i_dequeue_ready[dequeue_bank_index])begin
                    dequeue_fire_queue[dequeue_hold_queue_q[dequeue_bank_index*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]]=1'b1;
                end
            end else if(CONFIG_LEGAL&&i_rstn&&i_dequeue_request[dequeue_bank_index])begin
                if(read_queue<C_NUM_VOQS)begin
                    if((read_queue%C_NUM_BANKS)==dequeue_bank_index)begin
                        if(occupancy_q[read_queue]!=0)begin
                            o_dequeue_valid[dequeue_bank_index]=1'b1;
                            o_dequeue_data[dequeue_bank_index*C_DATA_WIDTH+:C_DATA_WIDTH]=
                                bank_read_data[dequeue_bank_index*C_DATA_WIDTH+:C_DATA_WIDTH];
                            o_dequeue_meta[dequeue_bank_index*C_META_WIDTH+:C_META_WIDTH]=
                                bank_read_meta[dequeue_bank_index*C_META_WIDTH+:C_META_WIDTH];
                            o_dequeue_sop[dequeue_bank_index]=bank_read_sop[dequeue_bank_index];
                            o_dequeue_eop[dequeue_bank_index]=bank_read_eop[dequeue_bank_index];
                            if(i_dequeue_ready[dequeue_bank_index])dequeue_fire_queue[read_queue]=1'b1;
                        end
                    end
                end
            end
        end
    end

    always @(*) begin
        o_occupancy={(C_NUM_VOQS*C_COUNT_WIDTH){1'b0}};
        o_reserved={(C_NUM_VOQS*C_COUNT_WIDTH){1'b0}};occupancy_sum=0;reserved_sum=0;
        for(sum_queue_index=0;sum_queue_index<C_NUM_VOQS;sum_queue_index=sum_queue_index+1)begin
            o_occupancy[sum_queue_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]=occupancy_q[sum_queue_index];
            o_reserved[sum_queue_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]=reserved_q[sum_queue_index];
            occupancy_sum=occupancy_sum+{{(16-C_COUNT_WIDTH){1'b0}},occupancy_q[sum_queue_index]};
            reserved_sum=reserved_sum+{{(16-C_COUNT_WIDTH){1'b0}},reserved_q[sum_queue_index]};
        end
        o_total_occupancy=occupancy_sum;o_total_reserved=reserved_sum;
    end

    always @(posedge i_clk)begin
        if(!i_rstn)begin
            o_protocol_error<=1'b0;o_overflow_error<=1'b0;o_underflow_error<=1'b0;
            o_overflow_event_level<=1'b0;o_underflow_event_level<=1'b0;
            dequeue_hold_valid_q<={C_NUM_BANKS{1'b0}};
            dequeue_hold_queue_q<={(C_NUM_BANKS*C_QUEUE_WIDTH){1'b0}};
            dequeue_hold_data_q<={(C_NUM_BANKS*C_DATA_WIDTH){1'b0}};
            dequeue_hold_meta_q<={(C_NUM_BANKS*C_META_WIDTH){1'b0}};
            dequeue_hold_sop_q<={C_NUM_BANKS{1'b0}};dequeue_hold_eop_q<={C_NUM_BANKS{1'b0}};
            for(state_input=0;state_input<C_INGRESS_PORTS;state_input=state_input+1)begin
                input_owner_valid_q[state_input]<=1'b0;input_owner_queue_q[state_input]<={C_QUEUE_WIDTH{1'b0}};
            end
            for(state_bank=0;state_bank<C_NUM_BANKS;state_bank=state_bank+1)rr_q[state_bank]<={C_INGRESS_WIDTH{1'b0}};
            for(state_queue_index=0;state_queue_index<C_NUM_VOQS;state_queue_index=state_queue_index+1)begin
                head_q[state_queue_index]<={C_ADDR_WIDTH{1'b0}};tail_q[state_queue_index]<={C_ADDR_WIDTH{1'b0}};
                occupancy_q[state_queue_index]<={C_COUNT_WIDTH{1'b0}};reserved_q[state_queue_index]<={C_COUNT_WIDTH{1'b0}};
                queue_owner_valid_q[state_queue_index]<=1'b0;queue_owner_q[state_queue_index]<={C_INGRESS_WIDTH{1'b0}};
            end
        end else begin
            o_overflow_event_level<=1'b0;o_underflow_event_level<=1'b0;
            if(!CONFIG_LEGAL)o_protocol_error<=1'b1;
            for(state_input=0;state_input<C_INGRESS_PORTS;state_input=state_input+1)begin
                if(i_valid[state_input])begin
                    if({{(32-C_QUEUE_WIDTH){1'b0}},i_queue[state_input*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]}>=C_NUM_VOQS)o_protocol_error<=1'b1;
                    else if(input_owner_valid_q[state_input])begin
                        if(i_sop[state_input]||(i_queue[state_input*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]!=input_owner_queue_q[state_input])||
                           (i_packet_flits[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]!=0)||
                           !queue_owner_valid_q[i_queue[state_input*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]]||
                           (queue_owner_q[i_queue[state_input*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]]!=state_input[C_INGRESS_WIDTH-1:0])||
                           (reserved_q[i_queue[state_input*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]]==0)||
                           ((reserved_q[i_queue[state_input*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]]==1)!=i_eop[state_input]))o_protocol_error<=1'b1;
                    end else if(!i_sop[state_input]||(i_packet_flits[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]==0)||
                            (i_packet_flits[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]>C_DEPTH_COUNT)||
                            ((i_packet_flits[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]==1)!=i_eop[state_input]))begin
                        o_protocol_error<=1'b1;
                        if(i_sop[state_input]&&
                           (i_packet_flits[state_input*C_COUNT_WIDTH+:C_COUNT_WIDTH]>C_DEPTH_COUNT))begin
                            o_overflow_error<=1'b1;o_overflow_event_level<=1'b1;
                        end
                    end
                end
                if(enqueue_fire_input[state_input])begin
                    if(!input_owner_valid_q[state_input])begin
                        input_owner_queue_q[state_input]<=i_queue[state_input*C_QUEUE_WIDTH+:C_QUEUE_WIDTH];
                        input_owner_valid_q[state_input]<=!i_eop[state_input];
                    end else if(i_eop[state_input])input_owner_valid_q[state_input]<=1'b0;
                end
            end
            for(state_bank=0;state_bank<C_NUM_BANKS;state_bank=state_bank+1)begin
                if(selected_valid[state_bank]&&enqueue_fire_input[selected_input[state_bank]])begin
                    if(selected_input[state_bank]==C_LAST_INGRESS)rr_q[state_bank]<={C_INGRESS_WIDTH{1'b0}};
                    else rr_q[state_bank]<=selected_input[state_bank]+1'b1;
                end
                if(dequeue_hold_valid_q[state_bank])begin
                    if(i_dequeue_ready[state_bank])dequeue_hold_valid_q[state_bank]<=1'b0;
                end else begin
                    if(o_dequeue_valid[state_bank]&&!i_dequeue_ready[state_bank])begin
                        dequeue_hold_valid_q[state_bank]<=1'b1;
                        dequeue_hold_queue_q[state_bank*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]
                            <=i_dequeue_queue[state_bank*C_QUEUE_WIDTH+:C_QUEUE_WIDTH];
                        dequeue_hold_data_q[state_bank*C_DATA_WIDTH+:C_DATA_WIDTH]
                            <=o_dequeue_data[state_bank*C_DATA_WIDTH+:C_DATA_WIDTH];
                        dequeue_hold_meta_q[state_bank*C_META_WIDTH+:C_META_WIDTH]
                            <=o_dequeue_meta[state_bank*C_META_WIDTH+:C_META_WIDTH];
                        dequeue_hold_sop_q[state_bank]<=o_dequeue_sop[state_bank];
                        dequeue_hold_eop_q[state_bank]<=o_dequeue_eop[state_bank];
                    end
                    if(i_dequeue_request[state_bank])begin
                        if({{(32-C_QUEUE_WIDTH){1'b0}},i_dequeue_queue[state_bank*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]}>=C_NUM_VOQS)
                            o_protocol_error<=1'b1;
                        else if(({{(32-C_QUEUE_WIDTH){1'b0}},i_dequeue_queue[state_bank*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]}%C_NUM_BANKS)!=state_bank)
                            o_protocol_error<=1'b1;
                        else if(occupancy_q[i_dequeue_queue[state_bank*C_QUEUE_WIDTH+:C_QUEUE_WIDTH]]==0)begin
                            o_underflow_error<=1'b1;o_underflow_event_level<=1'b1;
                        end
                    end
                end
            end
            for(state_queue_index=0;state_queue_index<C_NUM_VOQS;state_queue_index=state_queue_index+1)begin
                if(({1'b0,occupancy_q[state_queue_index]}+{1'b0,reserved_q[state_queue_index]})>{1'b0,C_DEPTH_COUNT})begin
                    o_overflow_error<=1'b1;o_overflow_event_level<=1'b1;
                end
                case({enqueue_fire_queue[state_queue_index],dequeue_fire_queue[state_queue_index]})
                    2'b10:occupancy_q[state_queue_index]<=occupancy_q[state_queue_index]+1'b1;
                    2'b01:occupancy_q[state_queue_index]<=occupancy_q[state_queue_index]-1'b1;
                    default:occupancy_q[state_queue_index]<=occupancy_q[state_queue_index];
                endcase
                if(enqueue_fire_queue[state_queue_index])begin
                    if(tail_q[state_queue_index]==C_LAST_ADDRESS)tail_q[state_queue_index]<={C_ADDR_WIDTH{1'b0}};
                    else tail_q[state_queue_index]<=tail_q[state_queue_index]+1'b1;
                    for(write_bank=0;write_bank<C_NUM_BANKS;write_bank=write_bank+1)
                        if(selected_valid[write_bank]&&(selected_queue[write_bank]==state_queue_index[C_QUEUE_WIDTH-1:0]))begin
                            if(i_sop[selected_input[write_bank]])begin
                                reserved_q[state_queue_index]<=i_packet_flits[selected_input[write_bank]*C_COUNT_WIDTH+:C_COUNT_WIDTH]-1'b1;
                                queue_owner_valid_q[state_queue_index]<=!i_eop[selected_input[write_bank]];
                                queue_owner_q[state_queue_index]<=selected_input[write_bank];
                            end else begin
                                reserved_q[state_queue_index]<=reserved_q[state_queue_index]-1'b1;
                                if(i_eop[selected_input[write_bank]])queue_owner_valid_q[state_queue_index]<=1'b0;
                            end
                        end
                end
                if(dequeue_fire_queue[state_queue_index])begin
                    if(head_q[state_queue_index]==C_LAST_ADDRESS)head_q[state_queue_index]<={C_ADDR_WIDTH{1'b0}};
                    else head_q[state_queue_index]<=head_q[state_queue_index]+1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
