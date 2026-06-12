`timescale 1ns/1ps
`default_nettype none
// Native TL接收字的信用所有权边界。精确需求/释放向量只由tl_receive_context产生。
// decoder必须保存o_decode_token，并在确认该字派生的全部内部退休责任后bind；路由拒绝只有安全丢弃后才可drop_safe。
module switch_rx_tl_credit_ownership_adapter #(
 parameter integer C_DEPTH=4,parameter integer C_SLOT_WIDTH=2,parameter integer C_GENERATION_WIDTH=8,
 parameter integer C_EPOCH_WIDTH=8,parameter integer C_REF_WIDTH=3
)(
 input wire i_clk,input wire i_rstn,input wire [C_EPOCH_WIDTH-1:0] i_epoch,input wire i_auth,
 input wire i_rx_valid,output wire o_rx_ready,input wire [511:0] i_rx_data,input wire [1:0] i_rx_msg,
 output wire o_decode_valid,input wire i_decode_ready,output wire [511:0] o_decode_data,output wire [1:0] o_decode_msg,
 output wire [C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH-1:0] o_decode_token,
 output wire [5:0] o_decode_classes,output wire [79:0] o_decode_demands,output wire [79:0] o_decode_release_obligation,
 input wire i_bind_valid,input wire [C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH-1:0] i_bind_token,
 input wire [C_REF_WIDTH-1:0] i_bind_retire_count,input wire i_bind_drop_safe,
 input wire i_retire_valid,input wire [C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH-1:0] i_retire_token,
 output wire o_release_valid,input wire i_release_ready,
 output wire [C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH-1:0] o_release_token,output wire [79:0] o_release_vector,
 output wire o_quiescent,output wire o_error,output wire o_config_error
);
 localparam integer C_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH;
 localparam [1:0] S_FREE=2'd0,S_HELD=2'd1,S_INFLIGHT=2'd2,S_PENDING=2'd3;
 localparam CONFIG_LEGAL=(C_DEPTH>=2)&&(C_DEPTH<=1024)&&(C_SLOT_WIDTH>=1)&&(C_SLOT_WIDTH<=10)&&((1<<C_SLOT_WIDTH)==C_DEPTH)&&
  (C_GENERATION_WIDTH>=1)&&(C_GENERATION_WIDTH<=30)&&(C_EPOCH_WIDTH>=1)&&(C_EPOCH_WIDTH<=30)&&(C_REF_WIDTH>=1)&&(C_REF_WIDTH<=16);
 localparam [C_SLOT_WIDTH:0] C_DEPTH_VALUE={1'b1,{C_SLOT_WIDTH{1'b0}}};
 localparam [C_SLOT_WIDTH-1:0] C_LAST_SLOT={C_SLOT_WIDTH{1'b1}};
 reg [1:0] state_q[0:C_DEPTH-1];reg bound_q[0:C_DEPTH-1];reg [C_REF_WIDTH-1:0] refs_q[0:C_DEPTH-1];
 reg [C_GENERATION_WIDTH-1:0] generation_q[0:C_DEPTH-1];reg [511:0] data_q[0:C_DEPTH-1];reg [1:0] msg_q[0:C_DEPTH-1];reg[5:0]classes_q[0:C_DEPTH-1];
 reg [79:0] demands_q[0:C_DEPTH-1],releases_q[0:C_DEPTH-1];reg [C_SLOT_WIDTH-1:0] alloc_q,dispatch_q,release_slot_q;
 reg [C_EPOCH_WIDTH-1:0] active_epoch_q;reg error_q,release_owner_q;integer scan_index,reset_index;
 wire ctx_allowed,ctx_taken,ctx_rejected,ctx_store;wire[2:0]ctx_lower,ctx_upper;wire[6:0]ctx_pending;wire[72:0]ctx_be;wire[583:0]ctx_meta;wire[79:0]ctx_demands,ctx_releases;
 tl_receive_context u_context(.i_clk(i_clk),.i_rstn(i_rstn),.i_commit(i_rx_valid&&o_rx_ready),.i_auth(i_auth),
  .i_lower(i_rx_data[255:0]),.i_msg(i_rx_msg),.i_type0(i_rx_data[7:0]),.i_type1(i_rx_data[263:256]),
  .o_allowed(ctx_allowed),.o_taken(ctx_taken),.o_rejected(ctx_rejected),.o_lower(ctx_lower),.o_upper(ctx_upper),
  .o_demands(ctx_demands),.o_releases(ctx_releases),.o_store(ctx_store),.o_pending(ctx_pending),.o_be(ctx_be),.o_metadata(ctx_meta));
 wire alloc_safe=CONFIG_LEGAL&&({1'b0,alloc_q}<C_DEPTH_VALUE);wire dispatch_safe=CONFIG_LEGAL&&({1'b0,dispatch_q}<C_DEPTH_VALUE);
 wire capture=i_rx_valid&&o_rx_ready;wire decode_fire=o_decode_valid&&i_decode_ready;
 wire generation_available=alloc_safe&&(generation_q[alloc_q]!={C_GENERATION_WIDTH{1'b1}});
 assign o_rx_ready=i_rstn&&CONFIG_LEGAL&&!error_q&&(i_epoch==active_epoch_q)&&alloc_safe&&generation_available&&(state_q[alloc_q]==S_FREE)&&(!i_rx_valid||ctx_allowed);
 assign o_decode_valid=i_rstn&&CONFIG_LEGAL&&!error_q&&dispatch_safe&&(state_q[dispatch_q]==S_HELD);
 assign o_decode_data=o_decode_valid?data_q[dispatch_q]:512'd0;assign o_decode_msg=o_decode_valid?msg_q[dispatch_q]:2'd0;
 assign o_decode_classes=o_decode_valid?classes_q[dispatch_q]:6'd0;
 assign o_decode_demands=o_decode_valid?demands_q[dispatch_q]:80'd0;assign o_decode_release_obligation=o_decode_valid?releases_q[dispatch_q]:80'd0;
 assign o_decode_token=o_decode_valid?{active_epoch_q,generation_q[dispatch_q],dispatch_q}:{C_TOKEN_WIDTH{1'b0}};
 assign o_release_valid=i_rstn&&CONFIG_LEGAL&&release_owner_q&&!error_q;
 assign o_release_token=o_release_valid?{active_epoch_q,generation_q[release_slot_q],release_slot_q}:{C_TOKEN_WIDTH{1'b0}};
 assign o_release_vector=o_release_valid?releases_q[release_slot_q]:80'd0;
 reg any_owned;reg pending_found;reg[C_SLOT_WIDTH-1:0]pending_slot,scan_slot;always @*begin
  any_owned=release_owner_q;pending_found=1'b0;pending_slot={C_SLOT_WIDTH{1'b0}};scan_slot={C_SLOT_WIDTH{1'b0}};
  for(scan_index=0;scan_index<C_DEPTH;scan_index=scan_index+1)begin
   if(state_q[scan_index]!=S_FREE)any_owned=1'b1;
   if(!pending_found&&state_q[scan_index]==S_PENDING)begin pending_found=1'b1;pending_slot=scan_slot;end
   scan_slot=scan_slot+1'b1;
  end
 end
 assign o_quiescent=i_rstn&&CONFIG_LEGAL&&!error_q&&!any_owned;assign o_error=i_rstn&&(!CONFIG_LEGAL||error_q);assign o_config_error=!CONFIG_LEGAL;
 wire [C_SLOT_WIDTH-1:0] bind_slot=i_bind_token[C_SLOT_WIDTH-1:0];wire [C_GENERATION_WIDTH-1:0] bind_gen=i_bind_token[C_SLOT_WIDTH+C_GENERATION_WIDTH-1:C_SLOT_WIDTH];
 wire [C_EPOCH_WIDTH-1:0] bind_epoch=i_bind_token[C_TOKEN_WIDTH-1:C_SLOT_WIDTH+C_GENERATION_WIDTH];
 wire bind_safe=CONFIG_LEGAL&&({1'b0,bind_slot}<C_DEPTH_VALUE);wire bind_match=bind_safe&&(bind_epoch==active_epoch_q)&&(generation_q[bind_slot]==bind_gen)&&(state_q[bind_slot]==S_INFLIGHT)&&!bound_q[bind_slot];
 wire [C_SLOT_WIDTH-1:0] retire_slot=i_retire_token[C_SLOT_WIDTH-1:0];wire [C_GENERATION_WIDTH-1:0] retire_gen=i_retire_token[C_SLOT_WIDTH+C_GENERATION_WIDTH-1:C_SLOT_WIDTH];
 wire [C_EPOCH_WIDTH-1:0] retire_epoch=i_retire_token[C_TOKEN_WIDTH-1:C_SLOT_WIDTH+C_GENERATION_WIDTH];
 wire retire_safe=CONFIG_LEGAL&&({1'b0,retire_slot}<C_DEPTH_VALUE);wire retire_match=retire_safe&&(retire_epoch==active_epoch_q)&&(generation_q[retire_slot]==retire_gen)&&(state_q[retire_slot]==S_INFLIGHT)&&bound_q[retire_slot]&&(refs_q[retire_slot]!=0);
 wire protocol_error=(i_rx_valid&&!o_rx_ready&&(!ctx_allowed||(i_epoch!=active_epoch_q)||!generation_available))||
  (i_bind_valid&&(!bind_match||(i_bind_drop_safe==(i_bind_retire_count!=0))))||(i_retire_valid&&!retire_match);
 wire unused=^{ctx_taken,ctx_rejected,ctx_store,ctx_lower,ctx_upper,ctx_pending,ctx_be,ctx_meta};
 always @(posedge i_clk)begin
  if(!i_rstn)begin
   alloc_q<=0;dispatch_q<=0;release_slot_q<=0;release_owner_q<=0;active_epoch_q<=i_epoch;error_q<=0;
   for(reset_index=0;reset_index<C_DEPTH;reset_index=reset_index+1)begin state_q[reset_index]<=S_FREE;bound_q[reset_index]<=0;refs_q[reset_index]<=0;generation_q[reset_index]<=0;data_q[reset_index]<=0;msg_q[reset_index]<=0;classes_q[reset_index]<=0;demands_q[reset_index]<=0;releases_q[reset_index]<=0;end
  end else if(CONFIG_LEGAL)begin
   if(!any_owned&&(i_epoch!=active_epoch_q))begin active_epoch_q<=i_epoch;for(reset_index=0;reset_index<C_DEPTH;reset_index=reset_index+1)generation_q[reset_index]<=0;end
   if(protocol_error)error_q<=1'b1;
   if(capture)begin state_q[alloc_q]<=S_HELD;bound_q[alloc_q]<=0;refs_q[alloc_q]<=0;generation_q[alloc_q]<=generation_q[alloc_q]+1'b1;data_q[alloc_q]<=i_rx_data;msg_q[alloc_q]<=i_rx_msg;classes_q[alloc_q]<={ctx_upper,ctx_lower};demands_q[alloc_q]<=ctx_demands;releases_q[alloc_q]<=ctx_releases;alloc_q<=(alloc_q==C_LAST_SLOT)?0:alloc_q+1'b1;end
   if(decode_fire)begin state_q[dispatch_q]<=S_INFLIGHT;dispatch_q<=(dispatch_q==C_LAST_SLOT)?0:dispatch_q+1'b1;end
   if(i_bind_valid&&bind_match)begin
    if(i_bind_drop_safe)state_q[bind_slot]<=S_PENDING;else begin bound_q[bind_slot]<=1'b1;refs_q[bind_slot]<=i_bind_retire_count;end
   end
   if(i_retire_valid&&retire_match)begin if(refs_q[retire_slot]==1)begin refs_q[retire_slot]<=0;state_q[retire_slot]<=S_PENDING;end else refs_q[retire_slot]<=refs_q[retire_slot]-1'b1;end
   if(release_owner_q&&i_release_ready)begin state_q[release_slot_q]<=S_FREE;bound_q[release_slot_q]<=0;release_owner_q<=0;end
   else if(!release_owner_q&&pending_found)begin release_owner_q<=1'b1;release_slot_q<=pending_slot;end
  end
 end
endmodule
`default_nettype wire
