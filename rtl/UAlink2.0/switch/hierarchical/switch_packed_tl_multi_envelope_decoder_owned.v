`timescale 1ns/1ps
`default_nettype none
// 给既有packed decoder增加native-word provenance，不复制TL字段解析。
// 精确支持：无Data多字段组，或含Data的单字段组；多字段含Data及同字跨组carry失败关闭。
module switch_packed_tl_multi_envelope_decoder_owned #(
 parameter integer C_PORTS=1,parameter integer C_COUNT_WIDTH=4,parameter integer C_OWNER_TOKEN_WIDTH=18,
 parameter integer C_MAX_GROUP_WORDS=17,parameter integer C_OWNER_WORD_COUNT_WIDTH=5,parameter integer C_OWNER_REF_WIDTH=4
)(
 input wire i_clk,input wire i_rstn,input wire[C_PORTS-1:0]i_valid,output wire[C_PORTS-1:0]o_ready,
 input wire[C_PORTS*512-1:0]i_tl_data,input wire[C_PORTS*2-1:0]i_tl_msg,input wire[C_PORTS*10-1:0]i_source_port,
 input wire[C_PORTS*C_OWNER_TOKEN_WIDTH-1:0]i_owner_token,input wire[C_PORTS*6-1:0]i_owner_classes,
 output wire[C_PORTS-1:0]o_valid,input wire[C_PORTS-1:0]i_ready,output wire[C_PORTS*512-1:0]o_data,
 output wire[C_PORTS*2-1:0]o_tl_msg,output wire[C_PORTS*10-1:0]o_dst_id,output wire[C_PORTS*2-1:0]o_class,
 output wire[C_PORTS*2-1:0]o_original_vc,output wire[C_PORTS-1:0]o_original_pool,output wire[C_PORTS*10-1:0]o_source_port,
 output wire[C_PORTS-1:0]o_sop,output wire[C_PORTS-1:0]o_eop,output wire[C_PORTS*C_COUNT_WIDTH-1:0]o_packet_flits,
 output wire[C_PORTS-1:0]o_busy,output wire[C_PORTS-1:0]o_error,output wire o_config_error,
 output wire[C_PORTS-1:0]o_owner_bind_valid,input wire[C_PORTS-1:0]i_owner_bind_ready,
 output wire[C_PORTS*C_OWNER_TOKEN_WIDTH-1:0]o_owner_bind_token,
 output wire[C_PORTS*C_OWNER_REF_WIDTH-1:0]o_owner_bind_retire_count,output wire[C_PORTS-1:0]o_owner_bind_drop_safe,
 output wire[C_PORTS*C_MAX_GROUP_WORDS-1:0]o_owner_valid,
 output wire[C_PORTS*C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH-1:0]o_owner_tokens,
 output wire[C_PORTS*C_OWNER_WORD_COUNT_WIDTH-1:0]o_owner_count,
 input wire[C_PORTS-1:0]i_owner_retire_envelope_valid,output wire[C_PORTS-1:0]o_owner_retire_envelope_ready,input wire[C_PORTS-1:0]i_owner_retire_envelope_eop,
 input wire[C_PORTS*C_MAX_GROUP_WORDS-1:0]i_owner_retire_valid,input wire[C_PORTS*C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH-1:0]i_owner_retire_tokens,
 output wire[C_PORTS-1:0]o_owner_retire_valid,input wire[C_PORTS-1:0]i_owner_retire_ready,output wire[C_PORTS*C_OWNER_TOKEN_WIDTH-1:0]o_owner_retire_token
);
 localparam CONFIG_LEGAL=(C_PORTS>=1)&&(C_PORTS<=1024)&&(C_OWNER_TOKEN_WIDTH>=1)&&(C_OWNER_REF_WIDTH>=4)&&
  (C_OWNER_WORD_COUNT_WIDTH>=1)&&(C_OWNER_WORD_COUNT_WIDTH<=6)&&(C_MAX_GROUP_WORDS>=1)&&(C_MAX_GROUP_WORDS<32)&&((1<<C_OWNER_WORD_COUNT_WIDTH)>C_MAX_GROUP_WORDS);
 wire[C_PORTS-1:0]base_in_valid,base_ready,base_valid,base_out_ready,base_busy,base_error;wire base_config_error;
 assign o_config_error=!CONFIG_LEGAL||base_config_error;
 switch_packed_tl_multi_envelope_decoder #(.C_PORTS(C_PORTS),.C_COUNT_WIDTH(C_COUNT_WIDTH))u_decoder(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_valid(base_in_valid),.o_ready(base_ready),.i_tl_data(i_tl_data),.i_tl_msg(i_tl_msg),.i_source_port(i_source_port),
  .o_valid(base_valid),.i_ready(base_out_ready),.o_data(o_data),.o_tl_msg(o_tl_msg),.o_dst_id(o_dst_id),.o_class(o_class),.o_original_vc(o_original_vc),
  .o_original_pool(o_original_pool),.o_source_port(o_source_port),.o_sop(o_sop),.o_eop(o_eop),.o_packet_flits(o_packet_flits),.o_busy(base_busy),.o_error(base_error),.o_config_error(base_config_error));
 genvar p;generate for(p=0;p<C_PORTS;p=p+1)begin:g_owner
  reg group_q,binding_q,emitting_q,drop_q,error_q,retire_busy_q,envelope_outstanding_q;reg[C_OWNER_WORD_COUNT_WIDTH-1:0]words_q,bind_index_q;
  reg[C_OWNER_REF_WIDTH-1:0]fields_q,eops_q;reg[C_MAX_GROUP_WORDS-1:0]mask_q;reg[C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH-1:0]tokens_q;
  reg[C_MAX_GROUP_WORDS-1:0]retire_mask_q,expected_retire_mask_q;reg[C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH-1:0]retire_tokens_q,expected_retire_tokens_q;reg retire_found;reg[C_OWNER_TOKEN_WIDTH-1:0]retire_selected;integer retire_scan,retire_clear;
  wire[1:0]tenure_status;wire[3:0]tenure_fields;wire[31:0]data_counts;wire[7:0]byte_enable;
  tl_control_tenure u_tenure(i_tl_data[p*512+:256],tenure_status,tenure_fields,data_counts,byte_enable);
  wire input_control=(tenure_status==2'd0)&&(tenure_fields!=0);wire input_has_data=(|data_counts)||(|byte_enable);
  wire[2:0]lower_class=i_owner_classes[p*6+:3],upper_class=i_owner_classes[p*6+3+:3];
  wire lower_data=(lower_class==3'd1)||(lower_class==3'd2)||(lower_class==3'd5);wire upper_data=(upper_class==3'd1)||(upper_class==3'd2)||(upper_class==3'd5);
  wire profile_legal=!group_q?(input_control&&!((tenure_fields>1)&&input_has_data)):((lower_data||upper_data)&&!input_control);
  wire space=!(&mask_q);wire idle_for_input=!binding_q&&!emitting_q&&!base_valid[p];
  wire input_gate=CONFIG_LEGAL&&!error_q&&idle_for_input&&space&&profile_legal;
  wire input_fire=i_valid[p]&&o_ready[p];wire output_fire=o_valid[p]&&i_ready[p];
  assign base_in_valid[p]=i_valid[p]&&input_gate;assign o_ready[p]=base_ready[p]&&input_gate;
  assign o_valid[p]=base_valid[p]&&emitting_q&&!envelope_outstanding_q;assign base_out_ready[p]=i_ready[p]&&emitting_q&&!envelope_outstanding_q;
  always @*begin retire_found=1'b0;retire_selected={C_OWNER_TOKEN_WIDTH{1'b0}};for(retire_scan=0;retire_scan<C_MAX_GROUP_WORDS;retire_scan=retire_scan+1)if(!retire_found&&retire_mask_q[retire_scan])begin retire_found=1'b1;retire_selected=retire_tokens_q[retire_scan*C_OWNER_TOKEN_WIDTH+:C_OWNER_TOKEN_WIDTH];end end
  assign o_owner_retire_envelope_ready[p]=CONFIG_LEGAL&&!error_q&&!retire_busy_q&&envelope_outstanding_q;
  assign o_owner_retire_valid[p]=CONFIG_LEGAL&&!error_q&&retire_busy_q&&retire_found;
  assign o_owner_retire_token[p*C_OWNER_TOKEN_WIDTH+:C_OWNER_TOKEN_WIDTH]=o_owner_retire_valid[p]?retire_selected:{C_OWNER_TOKEN_WIDTH{1'b0}};
  assign o_busy[p]=base_busy[p]||group_q||binding_q||emitting_q||retire_busy_q||envelope_outstanding_q;assign o_error[p]=!CONFIG_LEGAL||base_error[p]||error_q;
  assign o_owner_bind_valid[p]=binding_q;assign o_owner_bind_token[p*C_OWNER_TOKEN_WIDTH+:C_OWNER_TOKEN_WIDTH]=binding_q?tokens_q[bind_index_q*C_OWNER_TOKEN_WIDTH+:C_OWNER_TOKEN_WIDTH]:{C_OWNER_TOKEN_WIDTH{1'b0}};
  assign o_owner_bind_retire_count[p*C_OWNER_REF_WIDTH+:C_OWNER_REF_WIDTH]=binding_q&&!drop_q?fields_q:{C_OWNER_REF_WIDTH{1'b0}};
  assign o_owner_bind_drop_safe[p]=binding_q&&drop_q;
  assign o_owner_valid[p*C_MAX_GROUP_WORDS+:C_MAX_GROUP_WORDS]=emitting_q?mask_q:{C_MAX_GROUP_WORDS{1'b0}};
  assign o_owner_tokens[p*C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH+:C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH]=emitting_q?tokens_q:{(C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH){1'b0}};
  assign o_owner_count[p*C_OWNER_WORD_COUNT_WIDTH+:C_OWNER_WORD_COUNT_WIDTH]=emitting_q?words_q:{C_OWNER_WORD_COUNT_WIDTH{1'b0}};
  always @(posedge i_clk)begin
   if(!i_rstn)begin group_q<=0;binding_q<=0;emitting_q<=0;drop_q<=0;error_q<=0;retire_busy_q<=0;envelope_outstanding_q<=0;words_q<=0;bind_index_q<=0;fields_q<=0;eops_q<=0;mask_q<=0;tokens_q<=0;retire_mask_q<=0;retire_tokens_q<=0;expected_retire_mask_q<=0;expected_retire_tokens_q<=0;end
   else if(CONFIG_LEGAL)begin
    // A legal following Control may remain asserted while the base decoder is
    // still consuming the previous word.  Diagnose its phase only when that
    // decoder is actually able to sample a word; otherwise group_q would
    // misclassify held Control as packet Data during the internal pipeline gap.
    if(i_valid[p]&&base_ready[p]&&idle_for_input&&(!space||!profile_legal))error_q<=1'b1;
    if(i_owner_retire_envelope_valid[p]&&o_owner_retire_envelope_ready[p])begin
     if(!i_owner_retire_envelope_eop[p]||
      (i_owner_retire_valid[p*C_MAX_GROUP_WORDS+:C_MAX_GROUP_WORDS]!=expected_retire_mask_q)||
      (i_owner_retire_tokens[p*C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH+:C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH]!=expected_retire_tokens_q))error_q<=1'b1;
     else begin retire_busy_q<=1'b1;retire_mask_q<=i_owner_retire_valid[p*C_MAX_GROUP_WORDS+:C_MAX_GROUP_WORDS];retire_tokens_q<=i_owner_retire_tokens[p*C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH+:C_MAX_GROUP_WORDS*C_OWNER_TOKEN_WIDTH];end
    end
    if(o_owner_retire_valid[p]&&i_owner_retire_ready[p])begin
     for(retire_clear=0;retire_clear<C_MAX_GROUP_WORDS;retire_clear=retire_clear+1)if(retire_mask_q[retire_clear]&&(retire_tokens_q[retire_clear*C_OWNER_TOKEN_WIDTH+:C_OWNER_TOKEN_WIDTH]==retire_selected))retire_mask_q[retire_clear]<=1'b0;
     if((retire_mask_q&(retire_mask_q-1'b1))==0)begin retire_busy_q<=1'b0;envelope_outstanding_q<=1'b0;end
    end
    if(input_fire)begin tokens_q[words_q*C_OWNER_TOKEN_WIDTH+:C_OWNER_TOKEN_WIDTH]<=i_owner_token[p*C_OWNER_TOKEN_WIDTH+:C_OWNER_TOKEN_WIDTH];mask_q[words_q]<=1'b1;words_q<=words_q+1'b1;
     if(!group_q)begin group_q<=1'b1;fields_q<={{(C_OWNER_REF_WIDTH-4){1'b0}},tenure_fields};eops_q<=0;end
    end
    if(group_q&&!binding_q&&!emitting_q&&base_valid[p])begin binding_q<=1'b1;bind_index_q<=0;drop_q<=1'b0;end
    if(group_q&&!binding_q&&!emitting_q&&base_error[p])begin binding_q<=1'b1;bind_index_q<=0;drop_q<=1'b1;end
    if(binding_q&&i_owner_bind_ready[p])begin
     if(bind_index_q+1'b1==words_q)begin binding_q<=0;bind_index_q<=0;if(drop_q)begin group_q<=0;words_q<=0;mask_q<=0;tokens_q<=0;end else emitting_q<=1'b1;end
     else bind_index_q<=bind_index_q+1'b1;
    end
    if(output_fire&&o_eop[p])begin envelope_outstanding_q<=1'b1;expected_retire_mask_q<=mask_q;expected_retire_tokens_q<=tokens_q;
     if(eops_q+1'b1==fields_q)begin group_q<=0;emitting_q<=0;words_q<=0;eops_q<=0;mask_q<=0;tokens_q<=0;end else eops_q<=eops_q+1'b1;
    end
   end
  end
 end endgenerate
endmodule
`default_nettype wire
