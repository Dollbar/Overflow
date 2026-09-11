`timescale 1ps/1ps // 单资源出口完整包预约、保存及真实退休控制。
module switch_egress_packet_queue #( // switch_egress_packet_queue模块：完整包保存与一次真实退休释放。
 parameter integer PORTS=4, // 单资源出口完整包预约、保存及真实退休控制。
 parameter integer DATA_WIDTH=544, // 单资源出口完整包预约、保存及真实退休控制。
 parameter integer TOKEN_WIDTH=8, // 单资源出口完整包预约、保存及真实退休控制。
 parameter integer UNIT_WIDTH=4, // 单资源出口完整包预约、保存及真实退休控制。
 parameter [UNIT_WIDTH-1:0] DEFAULT_CAPACITY=4, // 单资源出口完整包预约、保存及真实退休控制。
 parameter [PORTS*UNIT_WIDTH-1:0] CAPACITIES={PORTS{DEFAULT_CAPACITY}} // 单资源出口完整包预约、保存及真实退休控制。
)( // 单资源出口完整包预约、保存及真实退休控制。
 input wire i_clk,i_rstn, // 单资源出口完整包预约、保存及真实退休控制。
 input wire [PORTS-1:0] i_reserve_valid, // 单资源出口完整包预约、保存及真实退休控制。
 input wire [PORTS*UNIT_WIDTH-1:0] i_reserve_units, // 单资源出口完整包预约、保存及真实退休控制。
 input wire [PORTS*TOKEN_WIDTH-1:0] i_reserve_token, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS-1:0] o_reserve_ready, // 单资源出口完整包预约、保存及真实退休控制。
 input wire [PORTS-1:0] i_write_valid, // 单资源出口完整包预约、保存及真实退休控制。
 input wire [PORTS*DATA_WIDTH-1:0] i_write_data, // 单资源出口完整包预约、保存及真实退休控制。
 input wire [PORTS-1:0] i_write_last, // 单资源出口完整包预约、保存及真实退休控制。
 input wire [PORTS*TOKEN_WIDTH-1:0] i_write_token, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS-1:0] o_write_ready, // 单资源出口完整包预约、保存及真实退休控制。
 input wire [PORTS-1:0] i_ready, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS-1:0] o_valid, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS*DATA_WIDTH-1:0] o_data, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS-1:0] o_last, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS*TOKEN_WIDTH-1:0] o_token, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS-1:0] o_release_valid, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS*UNIT_WIDTH-1:0] o_release_units, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS*UNIT_WIDTH-1:0] o_reserved,o_stored,o_completed, // 单资源出口完整包预约、保存及真实退休控制。
 output wire [PORTS-1:0] o_busy,o_error_now,o_error_sticky, // 单资源出口完整包预约、保存及真实退休控制。
 output wire o_error // 单资源出口完整包预约、保存及真实退休控制。
); // 单资源出口完整包预约、保存及真实退休控制。
 localparam [31:0] C_PORTS=PORTS; // 单资源出口完整包预约、保存及真实退休控制。
 localparam [UNIT_WIDTH-1:0] C_ONE={{(UNIT_WIDTH-1){1'b0}},1'b1}; // 单资源出口完整包预约、保存及真实退休控制。
 localparam integer RAW_WIDTH=DATA_WIDTH+TOKEN_WIDTH+UNIT_WIDTH+1; // 单资源出口完整包预约、保存及真实退休控制。
 localparam integer STORE_WIDTH=((RAW_WIDTH+7)/8)*8; // 单资源出口完整包预约、保存及真实退休控制。
 assign o_error=|o_error_now || |o_error_sticky; // 单资源出口完整包预约、保存及真实退休控制。
 genvar e; // 单资源出口完整包预约、保存及真实退休控制。
 generate // 单资源出口完整包预约、保存及真实退休控制。
 if(((PORTS!=1)&&(PORTS!=2)&&(PORTS!=4))||(UNIT_WIDTH<3)||(UNIT_WIDTH>16)||(DATA_WIDTH<1)||(TOKEN_WIDTH<1))begin:gen_invalid // 单资源出口完整包预约、保存及真实退休控制。
  switch_packet_queue_parameters_invalid Invalid_Inst(); // 单资源出口完整包预约、保存及真实退休控制。
 end // 单资源出口完整包预约、保存及真实退休控制。
 for(e=0;e<C_PORTS;e=e+1)begin:gen_port // 单资源出口完整包预约、保存及真实退休控制。
  localparam [UNIT_WIDTH-1:0] CAPACITY=CAPACITIES[e*UNIT_WIDTH+:UNIT_WIDTH]; // 单资源出口完整包预约、保存及真实退休控制。
  if(CAPACITY==0)begin:gen_disabled // 单资源出口完整包预约、保存及真实退休控制。
   assign o_reserve_ready[e]=1'b0; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_write_ready[e]=1'b0; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_valid[e]=1'b0; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_data[e*DATA_WIDTH+:DATA_WIDTH]={DATA_WIDTH{1'b0}}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_last[e]=1'b0; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_token[e*TOKEN_WIDTH+:TOKEN_WIDTH]={TOKEN_WIDTH{1'b0}}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_release_valid[e]=1'b0; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_release_units[e*UNIT_WIDTH+:UNIT_WIDTH]={UNIT_WIDTH{1'b0}}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_reserved[e*UNIT_WIDTH+:UNIT_WIDTH]={UNIT_WIDTH{1'b0}}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_stored[e*UNIT_WIDTH+:UNIT_WIDTH]={UNIT_WIDTH{1'b0}}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_completed[e*UNIT_WIDTH+:UNIT_WIDTH]={UNIT_WIDTH{1'b0}}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_busy[e]=1'b0; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_error_now[e]=i_rstn&&(i_reserve_valid[e]||i_write_valid[e]); // 单资源出口完整包预约、保存及真实退休控制。
   reg reg_error; // 单资源出口完整包预约、保存及真实退休控制。
   always @(posedge i_clk)begin // 单资源出口完整包预约、保存及真实退休控制。
    if(!i_rstn)reg_error<=1'b0; // 错误从下一沿阻断，诊断当拍旧队首仍可真实退休。
    else if(o_error_now[e])reg_error<=1'b1; // 错误从下一沿阻断，诊断当拍旧队首仍可真实退休。
   end // 单资源出口完整包预约、保存及真实退休控制。
   assign o_error_sticky[e]=i_rstn&&reg_error; // 单资源出口完整包预约、保存及真实退休控制。
  end else begin:gen_enabled // 单资源出口完整包预约、保存及真实退休控制。
   localparam integer DEPTH={{(32-UNIT_WIDTH){1'b0}},CAPACITY}; // 单资源出口完整包预约、保存及真实退休控制。
   localparam integer COUNT_WIDTH=(DEPTH<2)?1:(DEPTH<4)?2:(DEPTH<8)?3:(DEPTH<16)?4:(DEPTH<32)?5:(DEPTH<64)?6:(DEPTH<128)?7:(DEPTH<256)?8:(DEPTH<512)?9:(DEPTH<1024)?10:(DEPTH<2048)?11:(DEPTH<4096)?12:(DEPTH<8192)?13:(DEPTH<16384)?14:(DEPTH<32768)?15:16; // 单资源出口完整包预约、保存及真实退休控制。
   reg [UNIT_WIDTH-1:0] reg_reserved,reg_remaining,reg_units,reg_complete; // 单资源出口完整包预约、保存及真实退休控制。
   reg [TOKEN_WIDTH-1:0] reg_token; // 单资源出口完整包预约、保存及真实退休控制。
   reg reg_error; // 单资源出口完整包预约、保存及真实退休控制。
   wire [UNIT_WIDTH-1:0] offered; // 声明本出口资格或保存字字段。
   assign offered=i_reserve_units[e*UNIT_WIDTH+:UNIT_WIDTH]; // 明确组合资格，不引入额外状态。
   wire active; // 声明本出口资格或保存字字段。
   assign active=(reg_remaining!={UNIT_WIDTH{1'b0}}); // 明确组合资格，不引入额外状态。
   wire fifo_ready,fifo_valid; // 单资源出口完整包预约、保存及真实退休控制。
   wire [STORE_WIDTH-1:0] head; // 单资源出口完整包预约、保存及真实退休控制。
   wire [COUNT_WIDTH-1:0] fifo_count; // 单资源出口完整包预约、保存及真实退休控制。
   wire reserve_bad; // 声明本出口资格或保存字字段。
   assign reserve_bad=i_reserve_valid[e]&&o_reserve_ready[e]&&((offered==0)||(offered>(CAPACITY-reg_reserved))); // 明确组合资格，不引入额外状态。
   wire write_bad; // 声明本出口资格或保存字字段。
   assign write_bad=i_write_valid[e]&&(!active||(i_write_token[e*TOKEN_WIDTH+:TOKEN_WIDTH]!=reg_token)||(i_write_last[e]!=(reg_remaining==C_ONE))||!fifo_ready); // 明确组合资格，不引入额外状态。
   wire local_bad; // 声明本出口资格或保存字字段。
   assign local_bad=reserve_bad||write_bad; // 明确组合资格，不引入额外状态。
   wire reserve_fire; // 声明本出口资格或保存字字段。
   assign reserve_fire=i_reserve_valid[e]&&o_reserve_ready[e]&&!local_bad; // 明确组合资格，不引入额外状态。
   wire write_fire; // 声明本出口资格或保存字字段。
   assign write_fire=i_write_valid[e]&&o_write_ready[e]; // 明确组合资格，不引入额外状态。
   wire finish; // 声明本出口资格或保存字字段。
   assign finish=write_fire&&(reg_remaining==C_ONE); // 明确组合资格，不引入额外状态。
   wire pop; // 声明本出口资格或保存字字段。
   assign pop=o_valid[e]&&i_ready[e]; // 明确组合资格，不引入额外状态。
   wire retire; // 声明本出口资格或保存字字段。
   assign retire=pop&&o_last[e]; // 明确组合资格，不引入额外状态。
   wire [UNIT_WIDTH-1:0] retired_units; // 声明本出口资格或保存字字段。
   assign retired_units=head[DATA_WIDTH+TOKEN_WIDTH+:UNIT_WIDTH]; // 明确组合资格，不引入额外状态。
   wire [RAW_WIDTH-1:0] raw_write; // 声明本出口资格或保存字字段。
   assign raw_write={i_write_last[e],reg_units,reg_token,i_write_data[e*DATA_WIDTH+:DATA_WIDTH]}; // 明确组合资格，不引入额外状态。
   wire [STORE_WIDTH-1:0] write_word; // 声明本出口资格或保存字字段。
   assign write_word={{(STORE_WIDTH-RAW_WIDTH){1'b0}},raw_write}; // 明确组合资格，不引入额外状态。
   wire unused_padding; // 声明本出口资格或保存字字段。
   assign unused_padding=^(head >> RAW_WIDTH); // 明确组合资格，不引入额外状态。
   assign o_reserve_ready[e]=i_rstn&&!reg_error&&!active&&(reg_reserved<CAPACITY); // 单资源出口完整包预约、保存及真实退休控制。
   assign o_write_ready[e]=i_rstn&&!reg_error&&!local_bad&&active&&fifo_ready; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_valid[e]=i_rstn&&!reg_error&&(reg_complete!=0)&&fifo_valid; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_data[e*DATA_WIDTH+:DATA_WIDTH]=o_valid[e]?head[DATA_WIDTH-1:0]:{DATA_WIDTH{1'b0}}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_token[e*TOKEN_WIDTH+:TOKEN_WIDTH]=o_valid[e]?head[DATA_WIDTH+:TOKEN_WIDTH]:{TOKEN_WIDTH{1'b0}}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_last[e]=o_valid[e]&&head[RAW_WIDTH-1]; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_release_valid[e]=retire; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_release_units[e*UNIT_WIDTH+:UNIT_WIDTH]=retire?retired_units:{UNIT_WIDTH{1'b0}}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_reserved[e*UNIT_WIDTH+:UNIT_WIDTH]=reg_reserved; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_stored[e*UNIT_WIDTH+:UNIT_WIDTH]={{(UNIT_WIDTH-COUNT_WIDTH){1'b0}},fifo_count}; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_completed[e*UNIT_WIDTH+:UNIT_WIDTH]=reg_complete; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_busy[e]=i_rstn&&active; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_error_now[e]=i_rstn&&!reg_error&&local_bad; // 单资源出口完整包预约、保存及真实退休控制。
   assign o_error_sticky[e]=i_rstn&&reg_error; // 单资源出口完整包预约、保存及真实退休控制。
   always @(posedge i_clk)begin // 单资源出口完整包预约、保存及真实退休控制。
    if(!i_rstn)begin // 单资源出口完整包预约、保存及真实退休控制。
     reg_reserved<={UNIT_WIDTH{1'b0}};reg_remaining<={UNIT_WIDTH{1'b0}};reg_units<={UNIT_WIDTH{1'b0}};reg_complete<={UNIT_WIDTH{1'b0}};reg_token<={TOKEN_WIDTH{1'b0}};reg_error<=1'b0; // 错误从下一沿阻断，诊断当拍旧队首仍可真实退休。
    end else if(!reg_error)begin // 单资源出口完整包预约、保存及真实退休控制。
     if(local_bad)reg_error<=1'b1; // 错误从下一沿阻断，诊断当拍旧队首仍可真实退休。
     reg_reserved<=reg_reserved+(reserve_fire?offered:{UNIT_WIDTH{1'b0}})-(retire?retired_units:{UNIT_WIDTH{1'b0}}); // 单资源出口完整包预约、保存及真实退休控制。
     reg_complete<=reg_complete+(finish?C_ONE:{UNIT_WIDTH{1'b0}})-(retire?C_ONE:{UNIT_WIDTH{1'b0}}); // 单资源出口完整包预约、保存及真实退休控制。
     if(reserve_fire)begin reg_remaining<=offered;reg_units<=offered;reg_token<=i_reserve_token[e*TOKEN_WIDTH+:TOKEN_WIDTH];end // 单资源出口完整包预约、保存及真实退休控制。
     else if(write_fire)reg_remaining<=reg_remaining-C_ONE; // 单资源出口完整包预约、保存及真实退休控制。
    end // 单资源出口完整包预约、保存及真实退休控制。
   end // 单资源出口完整包预约、保存及真实退休控制。
   wire write_cs,read_cs; // 单资源出口完整包预约、保存及真实退休控制。
   localparam integer ADDR_WIDTH=(DEPTH<2)?1:((DEPTH&(DEPTH-1))==0)?COUNT_WIDTH-1:COUNT_WIDTH; // 单资源出口完整包预约、保存及真实退休控制。
   wire [COUNT_WIDTH-1:0] write_address,read_address; // 单资源出口完整包预约、保存及真实退休控制。
   wire unused_address; // 声明本出口资格或保存字字段。
   assign unused_address=^(write_address >> ADDR_WIDTH)^ (^(read_address >> ADDR_WIDTH)); // 明确组合资格，不引入额外状态。
   wire [STORE_WIDTH-1:0] memory_write_data; // 单资源出口完整包预约、保存及真实退休控制。
   reg [STORE_WIDTH-1:0] memory_read_data; // 单资源出口完整包预约、保存及真实退休控制。
   reg [STORE_WIDTH-1:0] memory[0:DEPTH-1]; // 单资源出口完整包预约、保存及真实退休控制。
   localparam [31:0] C_DEPTH=DEPTH; // 单资源出口完整包预约、保存及真实退休控制。
   reg [STORE_WIDTH-1:0] selected_read; // 单资源出口完整包预约、保存及真实退休控制。
   integer memory_index; // 单资源出口完整包预约、保存及真实退休控制。
   always @* begin // 单资源出口完整包预约、保存及真实退休控制。
    selected_read={STORE_WIDTH{1'b0}}; // 只选择真实合法存储地址，未匹配分支确定为零。
    for(memory_index=0;memory_index<C_DEPTH;memory_index=memory_index+1)begin // 单资源出口完整包预约、保存及真实退休控制。
     if(read_address==memory_index[COUNT_WIDTH-1:0])selected_read=memory[memory_index]; // 只选择真实合法存储地址，未匹配分支确定为零。
    end // 单资源出口完整包预约、保存及真实退休控制。
   end // 单资源出口完整包预约、保存及真实退休控制。
   always @(posedge i_clk)begin // 单资源出口完整包预约、保存及真实退休控制。
    if(write_cs)memory[write_address[ADDR_WIDTH-1:0]]<=memory_write_data; // 单资源出口完整包预约、保存及真实退休控制。
    if(read_cs)memory_read_data<=selected_read; // 单资源出口完整包预约、保存及真实退休控制。
   end // 单资源出口完整包预约、保存及真实退休控制。
   upli_receive_fifo #(.C_DEPTH(DEPTH),.C_DATA_WIDTH(STORE_WIDTH),.C_COUNT_WIDTH(COUNT_WIDTH)) Fifo_Inst( // 单资源出口完整包预约、保存及真实退休控制。
    .i_clk(i_clk),.i_rstn(i_rstn),.i_write_valid(write_fire),.i_write_data(write_word),.o_write_ready(fifo_ready), // 单资源出口完整包预约、保存及真实退休控制。
    .i_read_ready(pop),.o_read_valid(fifo_valid),.o_read_data(head),.o_count(fifo_count), // 单资源出口完整包预约、保存及真实退休控制。
    .o_sram_write_cs(write_cs),.o_sram_write_addr(write_address),.o_sram_write_data(memory_write_data), // 单资源出口完整包预约、保存及真实退休控制。
    .o_sram_read_cs(read_cs),.o_sram_read_addr(read_address),.i_sram_read_data(memory_read_data) // 单资源出口完整包预约、保存及真实退休控制。
   ); // 单资源出口完整包预约、保存及真实退休控制。
  end // 单资源出口完整包预约、保存及真实退休控制。
 end // 单资源出口完整包预约、保存及真实退休控制。
 endgenerate // 结束逐出口容量结构生成。
endmodule // 结束完整包缓存模块。
