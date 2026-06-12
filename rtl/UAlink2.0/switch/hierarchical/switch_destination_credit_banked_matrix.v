`timescale 1ns/1ps
`default_nettype none
// 每个目的资源实例化一个独立物理 bank。入口仅扫描 requester 一次并按资源
// 地址分发，避免 resource x requester 的组合仲裁矩阵。对外 token/account 与旧
// matrix 一致；shadow 仅校验全局 owner 并导出 per-account 统计。
module switch_destination_credit_banked_matrix #(
 parameter integer C_PLANES=32,
 parameter integer C_SLICES=4,
 parameter integer C_TILES=4,
 parameter integer C_DST_LOCALS=32,
 parameter integer C_CLASSES=4,
 parameter integer C_CAPACITY=4,
 parameter integer C_PLANE_WIDTH=5,
 parameter integer C_SLICE_WIDTH=2,
 parameter integer C_TILE_WIDTH=2,
 parameter integer C_LOCAL_WIDTH=5,
 parameter integer C_CLASS_WIDTH=2,
 parameter integer C_EPOCH_WIDTH=4,
 parameter integer C_GENERATION_WIDTH=16,
 parameter integer C_SLOT_WIDTH=13,
 parameter integer C_BANK_SLOT_WIDTH=2,
 parameter integer C_ACCOUNT_WIDTH=16,
 parameter integer C_COUNT_WIDTH=3,
 parameter integer C_RESOURCES=C_SLICES*C_TILES*C_DST_LOCALS*C_CLASSES,
 parameter integer C_ACCOUNTS=C_PLANES*C_RESOURCES,
 parameter integer C_SLOTS=C_RESOURCES*C_CAPACITY,
 parameter integer C_RELEASE_PORTS=C_SLICES*C_TILES*C_DST_LOCALS,
 parameter integer C_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_EPOCH_WIDTH-1:0] i_epoch,
 input wire [C_PLANES-1:0] i_issue_valid,
 output reg [C_PLANES-1:0] o_issue_ready,
 input wire [C_PLANES*C_SLICE_WIDTH-1:0] i_issue_dst_slice,
 input wire [C_PLANES*C_TILE_WIDTH-1:0] i_issue_dst_tile,
 input wire [C_PLANES*C_LOCAL_WIDTH-1:0] i_issue_dst_local,
 input wire [C_PLANES*C_CLASS_WIDTH-1:0] i_issue_class,
 output reg [C_PLANES*C_TOKEN_WIDTH-1:0] o_issue_token,
 output reg [C_PLANES*C_ACCOUNT_WIDTH-1:0] o_issue_account,
 input wire [C_PLANES-1:0] i_arrive_valid,
 output reg [C_PLANES-1:0] o_arrive_ready,
 input wire [C_PLANES*C_TOKEN_WIDTH-1:0] i_arrive_token,
 input wire [C_RELEASE_PORTS-1:0] i_release_valid,
 output reg [C_RELEASE_PORTS-1:0] o_release_ready,
 input wire [C_RELEASE_PORTS*C_TOKEN_WIDTH-1:0] i_release_token,
 output reg [C_RESOURCES*C_COUNT_WIDTH-1:0] o_free,
 output reg [C_ACCOUNTS*C_COUNT_WIDTH-1:0] o_issued,
 output reg [C_ACCOUNTS*C_COUNT_WIDTH-1:0] o_occupied,
 output wire o_config_error,
 output reg o_issue_overflow,
 output reg o_arrival_underflow,
 output reg o_duplicate_token,
 output reg o_stale_epoch,
 output reg o_epoch_change_error,
 output reg o_generation_exhausted,
 output reg o_malformed_token,
 output wire o_quiescent,
 output reg o_conservation_error,
 output wire o_return_malformed_event_level,
 output wire o_return_duplicate_event_level,
 output wire o_return_stale_event_level,
 output wire o_return_wrong_port_event_level,
 output wire o_error
);
 function can_encode;
  input integer width;input integer count;integer value;integer index;
  begin
   value=1;
   for(index=0;index<width;index=index+1)value=value*2;
   can_encode=(width>=1)&&(width<=30)&&(count>=1)&&(value>=count);
  end
 endfunction
 localparam CONFIG_LEGAL=(C_PLANES>=1)&&(C_PLANES<=64)&&
  (C_SLICES>=1)&&(C_SLICES<=8)&&(C_TILES>=1)&&(C_TILES<=4)&&
  (C_DST_LOCALS>=1)&&(C_DST_LOCALS<=32)&&(C_CLASSES>=1)&&(C_CLASSES<=8)&&
  (C_CAPACITY>=1)&&(C_CAPACITY<=32)&&
  (C_RESOURCES==C_SLICES*C_TILES*C_DST_LOCALS*C_CLASSES)&&
  (C_ACCOUNTS==C_PLANES*C_RESOURCES)&&(C_SLOTS==C_RESOURCES*C_CAPACITY)&&
  (C_RELEASE_PORTS==C_SLICES*C_TILES*C_DST_LOCALS)&&
  (C_TOKEN_WIDTH==C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH)&&
  can_encode(C_PLANE_WIDTH,C_PLANES)&&can_encode(C_SLICE_WIDTH,C_SLICES)&&
  can_encode(C_TILE_WIDTH,C_TILES)&&can_encode(C_LOCAL_WIDTH,C_DST_LOCALS)&&
  can_encode(C_CLASS_WIDTH,C_CLASSES)&&can_encode(C_SLOT_WIDTH,C_SLOTS)&&
  can_encode(C_BANK_SLOT_WIDTH,C_CAPACITY)&&
  can_encode(C_ACCOUNT_WIDTH,C_ACCOUNTS)&&can_encode(C_COUNT_WIDTH,C_CAPACITY+1)&&
  (C_EPOCH_WIDTH>=1)&&(C_EPOCH_WIDTH<=30)&&
  (C_GENERATION_WIDTH>=1)&&(C_GENERATION_WIDTH<=30);
 localparam integer C_BANK_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_BANK_SLOT_WIDTH;
 localparam [C_PLANE_WIDTH-1:0] LAST_PLANE=C_PLANES[C_PLANE_WIDTH-1:0]-1'b1;
 localparam [1:0] SHADOW_FREE=2'b00;
 localparam [1:0] SHADOW_ISSUED=2'b01;
 localparam [1:0] SHADOW_OCCUPIED=2'b10;

 reg [C_EPOCH_WIDTH-1:0] active_epoch_q;
 reg [C_PLANE_WIDTH-1:0] issue_rr_q,arrival_rr_q;
 reg [1:0] shadow_state_q[0:C_SLOTS-1];
 reg [C_PLANE_WIDTH-1:0] shadow_owner_q[0:C_SLOTS-1];
 reg [C_GENERATION_WIDTH-1:0] shadow_generation_q[0:C_SLOTS-1];
 reg [C_EPOCH_WIDTH-1:0] shadow_epoch_q[0:C_SLOTS-1];

 reg [C_RESOURCES-1:0] bank_issue_valid,bank_arrive_valid,bank_release_valid;
 wire [C_RESOURCES-1:0] bank_issue_ready,bank_arrive_ready,bank_release_ready;
 wire [C_RESOURCES*C_BANK_TOKEN_WIDTH-1:0] bank_issue_token;
 reg [C_RESOURCES*C_BANK_TOKEN_WIDTH-1:0] bank_arrive_token,bank_release_token;
 wire [C_RESOURCES*C_COUNT_WIDTH-1:0] bank_free,bank_issued,bank_occupied;
 wire [C_RESOURCES-1:0] bank_quiescent,bank_config_error,bank_issue_overflow;
 wire [C_RESOURCES-1:0] bank_arrival_error,bank_release_error,bank_stale_epoch;
 wire [C_RESOURCES-1:0] bank_generation_exhausted,bank_conservation_error,bank_error;
 reg [C_RESOURCES-1:0] issue_claimed,arrival_claimed,release_claimed;
 reg [C_RESOURCES*C_PLANE_WIDTH-1:0] issue_plane_by_bank,arrival_plane_by_bank;
 reg [C_RESOURCES*C_SLOT_WIDTH-1:0] issue_slot_by_bank,arrival_slot_by_bank,release_slot_by_bank;
 reg issue_bad_event,arrival_bad_event,arrival_underflow_event;
 reg arrival_duplicate_event,arrival_stale_event;
 reg release_bad_event,release_malformed_event,release_duplicate_event,release_stale_event;
 reg release_wrong_port_event;
 reg any_issue_fire,any_arrival_fire,shadow_conservation_bad;

 integer iscan,isel_plane,islice,itile,ilocal,iclass,iresource;
 integer ibank,idisp_plane,ilocal_slot,iglobal_slot,iaccount;
 reg [C_BANK_TOKEN_WIDTH-1:0] ibank_token;
 reg [C_SLOT_WIDTH-1:0] iglobal_bits;
 integer ascan,aplane,abank,aslot,alocal_slot;
 reg [C_TOKEN_WIDTH-1:0] atoken;
 reg [C_SLOT_WIDTH-1:0] aglobal_bits;
 reg [C_BANK_SLOT_WIDTH-1:0] alocal_bits;
 reg [C_GENERATION_WIDTH-1:0] ageneration;
 reg [C_EPOCH_WIDTH-1:0] aepoch;
 integer adbank,adplane;
 integer rport,rbank,rslot,rlocal_slot,rdbank,rdport;
 reg [C_TOKEN_WIDTH-1:0] rtoken;
 reg [C_SLOT_WIDTH-1:0] rglobal_bits;
 reg [C_BANK_SLOT_WIDTH-1:0] rlocal_bits;
 reg [C_GENERATION_WIDTH-1:0] rgeneration;
 reg [C_EPOCH_WIDTH-1:0] repoch;
 integer cslot,cresource,caccount,ctotal,cfree,cissued,coccupied;
 integer sslot,sbank;

 assign o_config_error=!CONFIG_LEGAL||(|bank_config_error);
 assign o_quiescent=CONFIG_LEGAL&&(&bank_quiescent);
 assign o_error=o_config_error|o_issue_overflow|o_arrival_underflow|
  o_duplicate_token|o_stale_epoch|o_epoch_change_error|
  o_generation_exhausted|o_malformed_token|o_conservation_error|(|bank_error);
 assign o_return_malformed_event_level=i_rstn&&CONFIG_LEGAL&&release_malformed_event;
 assign o_return_duplicate_event_level=i_rstn&&CONFIG_LEGAL&&release_duplicate_event;
 assign o_return_stale_event_level=i_rstn&&CONFIG_LEGAL&&release_stale_event;
 assign o_return_wrong_port_event_level=i_rstn&&CONFIG_LEGAL&&release_wrong_port_event;

 // 单次轮转 requester 扫描，同时对各自目标 bank 建立至多一个请求。
 always @(*)begin
  bank_issue_valid=0;issue_claimed=0;issue_plane_by_bank=0;issue_bad_event=1'b0;
  isel_plane=0;islice=0;itile=0;ilocal=0;iclass=0;iresource=0;
  for(iscan=0;iscan<C_PLANES;iscan=iscan+1)begin
   isel_plane=0;isel_plane[C_PLANE_WIDTH-1:0]=issue_rr_q;
   isel_plane=isel_plane+iscan;
   if(isel_plane>=C_PLANES)isel_plane=isel_plane-C_PLANES;
   islice=0;itile=0;ilocal=0;iclass=0;
   islice[C_SLICE_WIDTH-1:0]=i_issue_dst_slice[isel_plane*C_SLICE_WIDTH+:C_SLICE_WIDTH];
   itile[C_TILE_WIDTH-1:0]=i_issue_dst_tile[isel_plane*C_TILE_WIDTH+:C_TILE_WIDTH];
   ilocal[C_LOCAL_WIDTH-1:0]=i_issue_dst_local[isel_plane*C_LOCAL_WIDTH+:C_LOCAL_WIDTH];
   iclass[C_CLASS_WIDTH-1:0]=i_issue_class[isel_plane*C_CLASS_WIDTH+:C_CLASS_WIDTH];
   iresource=((islice*C_TILES+itile)*C_DST_LOCALS+ilocal)*C_CLASSES+iclass;
   if(i_issue_valid[isel_plane])begin
    if((islice>=C_SLICES)||(itile>=C_TILES)||(ilocal>=C_DST_LOCALS)||(iclass>=C_CLASSES))
     issue_bad_event=1'b1;
    else if(iresource>=C_RESOURCES)issue_bad_event=1'b1;
    else if(!issue_claimed[iresource])begin
     issue_claimed[iresource]=1'b1;bank_issue_valid[iresource]=1'b1;
     issue_plane_by_bank[iresource*C_PLANE_WIDTH+:C_PLANE_WIDTH]=
      isel_plane[C_PLANE_WIDTH-1:0];
    end
   end
  end
  if(!i_rstn||!CONFIG_LEGAL)bank_issue_valid=0;
 end

 // bank-local slot 转换为 global slot，并生成旧接口兼容 account。
 always @(*)begin
  o_issue_ready=0;o_issue_token=0;o_issue_account=0;issue_slot_by_bank=0;
  any_issue_fire=1'b0;idisp_plane=0;ilocal_slot=0;iglobal_slot=0;iaccount=0;
  ibank_token=0;iglobal_bits=0;
  for(ibank=0;ibank<C_RESOURCES;ibank=ibank+1)begin
   idisp_plane=0;
   idisp_plane[C_PLANE_WIDTH-1:0]=
    issue_plane_by_bank[ibank*C_PLANE_WIDTH+:C_PLANE_WIDTH];
   if(bank_issue_valid[ibank]&&bank_issue_ready[ibank]&&(i_epoch==active_epoch_q))begin
    o_issue_ready[idisp_plane]=1'b1;any_issue_fire=1'b1;
    ibank_token=bank_issue_token[ibank*C_BANK_TOKEN_WIDTH+:C_BANK_TOKEN_WIDTH];
    ilocal_slot=0;ilocal_slot[C_BANK_SLOT_WIDTH-1:0]=ibank_token[0+:C_BANK_SLOT_WIDTH];
    iglobal_slot=ibank*C_CAPACITY+ilocal_slot;
    iglobal_bits=iglobal_slot[C_SLOT_WIDTH-1:0];
    o_issue_token[idisp_plane*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]={
     ibank_token[C_BANK_SLOT_WIDTH+C_GENERATION_WIDTH+:C_EPOCH_WIDTH],
     ibank_token[C_BANK_SLOT_WIDTH+:C_GENERATION_WIDTH],iglobal_bits};
    iaccount=idisp_plane*C_RESOURCES+ibank;
    if((iglobal_slot<C_SLOTS)&&(iaccount<C_ACCOUNTS))begin
     o_issue_account[idisp_plane*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]=
      iaccount[C_ACCOUNT_WIDTH-1:0];
     issue_slot_by_bank[ibank*C_SLOT_WIDTH+:C_SLOT_WIDTH]=iglobal_bits;
    end
   end
  end
  if(!i_rstn||!CONFIG_LEGAL)begin o_issue_ready=0;any_issue_fire=1'b0;end
 end

 // Arrival 先校验全局 owner，再译码到一个 bank；同 bank 冲突按 RR 串行。
 always @(*)begin
  bank_arrive_valid=0;bank_arrive_token=0;arrival_claimed=0;
  arrival_plane_by_bank=0;arrival_slot_by_bank=0;
  arrival_bad_event=1'b0;arrival_underflow_event=1'b0;
  arrival_duplicate_event=1'b0;arrival_stale_event=1'b0;
  aplane=0;abank=0;aslot=0;alocal_slot=0;atoken=0;
  aglobal_bits=0;alocal_bits=0;ageneration=0;aepoch=0;
  for(ascan=0;ascan<C_PLANES;ascan=ascan+1)begin
   aplane=0;aplane[C_PLANE_WIDTH-1:0]=arrival_rr_q;aplane=aplane+ascan;
   if(aplane>=C_PLANES)aplane=aplane-C_PLANES;
   atoken=i_arrive_token[aplane*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];
   aglobal_bits=atoken[0+:C_SLOT_WIDTH];
   ageneration=atoken[C_SLOT_WIDTH+:C_GENERATION_WIDTH];
   aepoch=atoken[C_SLOT_WIDTH+C_GENERATION_WIDTH+:C_EPOCH_WIDTH];
   aslot=0;aslot[C_SLOT_WIDTH-1:0]=aglobal_bits;
   if(i_arrive_valid[aplane])begin
    if(aepoch!=active_epoch_q)arrival_stale_event=1'b1;
    else if(aslot>=C_SLOTS)arrival_bad_event=1'b1;
    else begin
     abank=aslot/C_CAPACITY;alocal_slot=aslot%C_CAPACITY;
     if(shadow_state_q[aslot]!=SHADOW_ISSUED)arrival_underflow_event=1'b1;
     else if((shadow_owner_q[aslot]!=aplane[C_PLANE_WIDTH-1:0])||
      (shadow_generation_q[aslot]!=ageneration)||(shadow_epoch_q[aslot]!=aepoch))
      arrival_duplicate_event=1'b1;
     else if((alocal_slot<C_CAPACITY)&&!arrival_claimed[abank])begin
      arrival_claimed[abank]=1'b1;bank_arrive_valid[abank]=1'b1;
      arrival_plane_by_bank[abank*C_PLANE_WIDTH+:C_PLANE_WIDTH]=aplane[C_PLANE_WIDTH-1:0];
      arrival_slot_by_bank[abank*C_SLOT_WIDTH+:C_SLOT_WIDTH]=aglobal_bits;
      alocal_bits=alocal_slot[C_BANK_SLOT_WIDTH-1:0];
      bank_arrive_token[abank*C_BANK_TOKEN_WIDTH+:C_BANK_TOKEN_WIDTH]=
       {aepoch,ageneration,alocal_bits};
     end
    end
   end
  end
  if(!i_rstn||!CONFIG_LEGAL)bank_arrive_valid=0;
 end

 always @(*)begin
  o_arrive_ready=0;any_arrival_fire=1'b0;adplane=0;
  for(adbank=0;adbank<C_RESOURCES;adbank=adbank+1)begin
   adplane=0;adplane[C_PLANE_WIDTH-1:0]=arrival_plane_by_bank[adbank*C_PLANE_WIDTH+:C_PLANE_WIDTH];
   if(bank_arrive_valid[adbank]&&bank_arrive_ready[adbank]&&
      (adplane<C_PLANES))begin
    o_arrive_ready[adplane]=1'b1;any_arrival_fire=1'b1;
   end
  end
  if(!i_rstn||!CONFIG_LEGAL)begin o_arrive_ready=0;any_arrival_fire=1'b0;end
 end

 // release lane 固定 slice/tile/local；token 的 global slot 再选 class bank。
 always @(*)begin
  bank_release_valid=0;bank_release_token=0;release_claimed=0;release_slot_by_bank=0;
  release_bad_event=1'b0;release_malformed_event=1'b0;release_duplicate_event=1'b0;
  release_stale_event=1'b0;release_wrong_port_event=1'b0;
  rbank=0;rslot=0;rlocal_slot=0;rtoken=0;rglobal_bits=0;rlocal_bits=0;
  rgeneration=0;repoch=0;
  for(rport=0;rport<C_RELEASE_PORTS;rport=rport+1)begin
   rtoken=i_release_token[rport*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];
   rglobal_bits=rtoken[0+:C_SLOT_WIDTH];
   rgeneration=rtoken[C_SLOT_WIDTH+:C_GENERATION_WIDTH];
   repoch=rtoken[C_SLOT_WIDTH+C_GENERATION_WIDTH+:C_EPOCH_WIDTH];
   rslot=0;rslot[C_SLOT_WIDTH-1:0]=rglobal_bits;
   if(i_release_valid[rport])begin
    if(repoch!=active_epoch_q)release_stale_event=1'b1;
    else if(rslot>=C_SLOTS)begin release_bad_event=1'b1;release_malformed_event=1'b1;end
    else begin
     rbank=rslot/C_CAPACITY;rlocal_slot=rslot%C_CAPACITY;
     if((rbank/C_CLASSES)!=rport)begin release_bad_event=1'b1;release_wrong_port_event=1'b1;end
     else if((shadow_state_q[rslot]!=SHADOW_OCCUPIED)||
      (shadow_generation_q[rslot]!=rgeneration)||(shadow_epoch_q[rslot]!=repoch))
      release_duplicate_event=1'b1;
     else if((rlocal_slot<C_CAPACITY)&&!release_claimed[rbank])begin
      release_claimed[rbank]=1'b1;bank_release_valid[rbank]=1'b1;
      release_slot_by_bank[rbank*C_SLOT_WIDTH+:C_SLOT_WIDTH]=rglobal_bits;
      rlocal_bits=rlocal_slot[C_BANK_SLOT_WIDTH-1:0];
      bank_release_token[rbank*C_BANK_TOKEN_WIDTH+:C_BANK_TOKEN_WIDTH]=
       {repoch,rgeneration,rlocal_bits};
     end
    end
   end
  end
  if(!i_rstn||!CONFIG_LEGAL)bank_release_valid=0;
 end

 always @(*)begin
  o_release_ready=0;rdport=0;
  for(rdbank=0;rdbank<C_RESOURCES;rdbank=rdbank+1)begin
   rdport=rdbank/C_CLASSES;
   if(bank_release_valid[rdbank]&&bank_release_ready[rdbank]&&
      (rdport<C_RELEASE_PORTS))
    o_release_ready[rdport]=1'b1;
  end
  if(!i_rstn||!CONFIG_LEGAL)o_release_ready=0;
 end

 // 每物理 slot 扫描一次，统计投影到 requester/resource account。
 always @(*)begin
  o_free=bank_free;o_issued=0;o_occupied=0;shadow_conservation_bad=1'b0;
  ctotal=0;cresource=0;caccount=0;cfree=0;cissued=0;coccupied=0;
  for(cslot=0;cslot<C_SLOTS;cslot=cslot+1)begin
   cresource=cslot/C_CAPACITY;
   if(shadow_state_q[cslot]==SHADOW_FREE)ctotal=ctotal+1;
   else if(shadow_state_q[cslot]==SHADOW_ISSUED)begin
    ctotal=ctotal+1;caccount=shadow_owner_q[cslot]*C_RESOURCES+cresource;
    o_issued[caccount*C_COUNT_WIDTH+:C_COUNT_WIDTH]=
     o_issued[caccount*C_COUNT_WIDTH+:C_COUNT_WIDTH]+1'b1;
   end else if(shadow_state_q[cslot]==SHADOW_OCCUPIED)begin
    ctotal=ctotal+1;caccount=shadow_owner_q[cslot]*C_RESOURCES+cresource;
    o_occupied[caccount*C_COUNT_WIDTH+:C_COUNT_WIDTH]=
     o_occupied[caccount*C_COUNT_WIDTH+:C_COUNT_WIDTH]+1'b1;
   end
  end
  if(ctotal!=C_SLOTS)shadow_conservation_bad=1'b1;
  for(cresource=0;cresource<C_RESOURCES;cresource=cresource+1)begin
   cfree=0;cissued=0;coccupied=0;
   cfree[C_COUNT_WIDTH-1:0]=bank_free[cresource*C_COUNT_WIDTH+:C_COUNT_WIDTH];
   cissued[C_COUNT_WIDTH-1:0]=bank_issued[cresource*C_COUNT_WIDTH+:C_COUNT_WIDTH];
   coccupied[C_COUNT_WIDTH-1:0]=bank_occupied[cresource*C_COUNT_WIDTH+:C_COUNT_WIDTH];
   if((cfree+cissued+coccupied)!=C_CAPACITY)shadow_conservation_bad=1'b1;
  end
 end

 always @(posedge i_clk)begin
  if(!i_rstn)begin
   active_epoch_q<=i_epoch;issue_rr_q<=0;arrival_rr_q<=0;
   o_issue_overflow<=1'b0;o_arrival_underflow<=1'b0;o_duplicate_token<=1'b0;
   o_stale_epoch<=1'b0;o_epoch_change_error<=1'b0;o_generation_exhausted<=1'b0;
   o_malformed_token<=1'b0;o_conservation_error<=1'b0;
   for(sslot=0;sslot<C_SLOTS;sslot=sslot+1)begin
    shadow_state_q[sslot]<=SHADOW_FREE;shadow_owner_q[sslot]<=0;
    shadow_generation_q[sslot]<=0;shadow_epoch_q[sslot]<=0;
   end
  end else begin
   if(!CONFIG_LEGAL||issue_bad_event||arrival_bad_event||release_bad_event)
    o_malformed_token<=1'b1;
   if(arrival_underflow_event)o_arrival_underflow<=1'b1;
   if(arrival_duplicate_event||release_duplicate_event)o_duplicate_token<=1'b1;
   if(arrival_stale_event||release_stale_event||(|bank_stale_epoch))o_stale_epoch<=1'b1;
   if((i_epoch!=active_epoch_q)&&!o_quiescent)o_epoch_change_error<=1'b1;
   if(|bank_issue_overflow)o_issue_overflow<=1'b1;
   if(|bank_generation_exhausted)o_generation_exhausted<=1'b1;
   if(shadow_conservation_bad||(|bank_conservation_error))o_conservation_error<=1'b1;
   if(any_issue_fire)begin
    if(issue_rr_q==LAST_PLANE)issue_rr_q<=0;else issue_rr_q<=issue_rr_q+1'b1;
   end
   if(any_arrival_fire)begin
    if(arrival_rr_q==LAST_PLANE)arrival_rr_q<=0;else arrival_rr_q<=arrival_rr_q+1'b1;
   end
   for(sbank=0;sbank<C_RESOURCES;sbank=sbank+1)begin
    if(bank_issue_valid[sbank]&&bank_issue_ready[sbank]&&(i_epoch==active_epoch_q))begin
     shadow_state_q[issue_slot_by_bank[sbank*C_SLOT_WIDTH+:C_SLOT_WIDTH]]<=SHADOW_ISSUED;
     shadow_owner_q[issue_slot_by_bank[sbank*C_SLOT_WIDTH+:C_SLOT_WIDTH]]<=
      issue_plane_by_bank[sbank*C_PLANE_WIDTH+:C_PLANE_WIDTH];
     shadow_generation_q[issue_slot_by_bank[sbank*C_SLOT_WIDTH+:C_SLOT_WIDTH]]<=
      bank_issue_token[sbank*C_BANK_TOKEN_WIDTH+C_BANK_SLOT_WIDTH+:C_GENERATION_WIDTH];
     shadow_epoch_q[issue_slot_by_bank[sbank*C_SLOT_WIDTH+:C_SLOT_WIDTH]]<=active_epoch_q;
    end
    if(bank_arrive_valid[sbank]&&bank_arrive_ready[sbank])
     shadow_state_q[arrival_slot_by_bank[sbank*C_SLOT_WIDTH+:C_SLOT_WIDTH]]<=SHADOW_OCCUPIED;
    if(bank_release_valid[sbank]&&bank_release_ready[sbank])
     shadow_state_q[release_slot_by_bank[sbank*C_SLOT_WIDTH+:C_SLOT_WIDTH]]<=SHADOW_FREE;
   end
   if(o_quiescent&&(i_epoch!=active_epoch_q))begin
    active_epoch_q<=i_epoch;o_generation_exhausted<=1'b0;
    for(sslot=0;sslot<C_SLOTS;sslot=sslot+1)shadow_generation_q[sslot]<=0;
   end
  end
 end

 genvar resource_gen;
 generate for(resource_gen=0;resource_gen<C_RESOURCES;resource_gen=resource_gen+1)begin:g_bank
  switch_destination_credit_resource_bank #(
   .C_REQUESTERS(1),.C_CAPACITY(C_CAPACITY),.C_REQUESTER_WIDTH(1),
   .C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_GENERATION_WIDTH(C_GENERATION_WIDTH),
   .C_SLOT_WIDTH(C_BANK_SLOT_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),
   .C_TOKEN_WIDTH(C_BANK_TOKEN_WIDTH)) u_bank(
   .i_clk(i_clk),.i_rstn(i_rstn),.i_epoch(active_epoch_q),
   .i_issue_valid(bank_issue_valid[resource_gen]),
   .o_issue_ready(bank_issue_ready[resource_gen]),
   .o_issue_token(bank_issue_token[resource_gen*C_BANK_TOKEN_WIDTH+:C_BANK_TOKEN_WIDTH]),
   .i_arrive_valid(bank_arrive_valid[resource_gen]),
   .o_arrive_ready(bank_arrive_ready[resource_gen]),
   .i_arrive_token(bank_arrive_token[resource_gen*C_BANK_TOKEN_WIDTH+:C_BANK_TOKEN_WIDTH]),
   .i_release_valid(bank_release_valid[resource_gen]),
   .o_release_ready(bank_release_ready[resource_gen]),
   .i_release_token(bank_release_token[resource_gen*C_BANK_TOKEN_WIDTH+:C_BANK_TOKEN_WIDTH]),
   .o_free(bank_free[resource_gen*C_COUNT_WIDTH+:C_COUNT_WIDTH]),
   .o_issued(bank_issued[resource_gen*C_COUNT_WIDTH+:C_COUNT_WIDTH]),
   .o_occupied(bank_occupied[resource_gen*C_COUNT_WIDTH+:C_COUNT_WIDTH]),
   .o_quiescent(bank_quiescent[resource_gen]),
   .o_config_error(bank_config_error[resource_gen]),
   .o_issue_overflow(bank_issue_overflow[resource_gen]),
   .o_arrival_error(bank_arrival_error[resource_gen]),
   .o_release_error(bank_release_error[resource_gen]),
   .o_stale_epoch(bank_stale_epoch[resource_gen]),
   .o_generation_exhausted(bank_generation_exhausted[resource_gen]),
   .o_conservation_error(bank_conservation_error[resource_gen]),
   .o_error(bank_error[resource_gen]));
 end endgenerate
 wire unused_leaf_errors=&{1'b0,bank_arrival_error,bank_release_error,1'b0};
endmodule
`default_nettype wire
