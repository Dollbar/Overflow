`timescale 1ns/1ps
`default_nettype none
// Destination-owned token ledger. Each token names one physical destination slot;
// physical free capacity is never replicated across Plane accounts.
module switch_destination_credit_ledger_matrix #(
 parameter integer C_PLANES=32, parameter integer C_SLICES=4,
 parameter integer C_TILES=4, parameter integer C_DST_LOCALS=32,
 parameter integer C_CLASSES=4, parameter integer C_CAPACITY=4,
 parameter integer C_PLANE_WIDTH=5, parameter integer C_SLICE_WIDTH=2,
 parameter integer C_TILE_WIDTH=2, parameter integer C_LOCAL_WIDTH=5,
 parameter integer C_CLASS_WIDTH=2, parameter integer C_EPOCH_WIDTH=4,
 parameter integer C_GENERATION_WIDTH=16, parameter integer C_SLOT_WIDTH=13,
 parameter integer C_ACCOUNT_WIDTH=16, parameter integer C_COUNT_WIDTH=3,
 parameter integer C_RESOURCES=C_SLICES*C_TILES*C_DST_LOCALS*C_CLASSES,
 parameter integer C_ACCOUNTS=C_PLANES*C_RESOURCES,
 parameter integer C_SLOTS=C_RESOURCES*C_CAPACITY,
 parameter integer C_RELEASE_PORTS=C_SLICES*C_TILES*C_DST_LOCALS,
 parameter integer C_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH
)(
 input wire i_clk,input wire i_rstn,input wire [C_EPOCH_WIDTH-1:0] i_epoch,
 input wire [C_PLANES-1:0] i_issue_valid,output reg [C_PLANES-1:0] o_issue_ready,
 input wire [C_PLANES*C_SLICE_WIDTH-1:0] i_issue_dst_slice,
 input wire [C_PLANES*C_TILE_WIDTH-1:0] i_issue_dst_tile,
 input wire [C_PLANES*C_LOCAL_WIDTH-1:0] i_issue_dst_local,
 input wire [C_PLANES*C_CLASS_WIDTH-1:0] i_issue_class,
 output reg [C_PLANES*C_TOKEN_WIDTH-1:0] o_issue_token,
 output reg [C_PLANES*C_ACCOUNT_WIDTH-1:0] o_issue_account,
 input wire [C_PLANES-1:0] i_arrive_valid,output reg [C_PLANES-1:0] o_arrive_ready,
 input wire [C_PLANES*C_TOKEN_WIDTH-1:0] i_arrive_token,
 input wire [C_RELEASE_PORTS-1:0] i_release_valid,output reg [C_RELEASE_PORTS-1:0] o_release_ready,
 input wire [C_RELEASE_PORTS*C_TOKEN_WIDTH-1:0] i_release_token,
 output reg [C_RESOURCES*C_COUNT_WIDTH-1:0] o_free,
 output reg [C_ACCOUNTS*C_COUNT_WIDTH-1:0] o_issued,
 output reg [C_ACCOUNTS*C_COUNT_WIDTH-1:0] o_occupied,
 output wire o_config_error,output reg o_issue_overflow,output reg o_arrival_underflow,
 output reg o_duplicate_token,output reg o_stale_epoch,output reg o_epoch_change_error,
 output reg o_generation_exhausted,
 output reg o_malformed_token,output reg o_quiescent,
 output reg o_conservation_error,output wire o_error
);
 function can_encode;input integer width;input integer count;integer capacity;integer bit_index;
  begin capacity=1;for(bit_index=0;bit_index<width;bit_index=bit_index+1)capacity=capacity*2;
   can_encode=(width>=1)&&(width<=30)&&(count>=1)&&(capacity>=count);end endfunction
 localparam CONFIG_LEGAL=(C_PLANES>=1)&&(C_PLANES<=64)&&(C_SLICES>=1)&&(C_SLICES<=8)&&
  (C_TILES>=1)&&(C_TILES<=4)&&(C_DST_LOCALS>=1)&&(C_DST_LOCALS<=32)&&
  (C_CLASSES>=1)&&(C_CLASSES<=8)&&(C_CAPACITY>=1)&&(C_CAPACITY<=32)&&
  (C_RESOURCES==C_SLICES*C_TILES*C_DST_LOCALS*C_CLASSES)&&
  (C_ACCOUNTS==C_PLANES*C_RESOURCES)&&(C_SLOTS==C_RESOURCES*C_CAPACITY)&&
  (C_RELEASE_PORTS==C_SLICES*C_TILES*C_DST_LOCALS)&&
  (C_TOKEN_WIDTH==C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH)&&
  can_encode(C_PLANE_WIDTH,C_PLANES)&&can_encode(C_SLICE_WIDTH,C_SLICES)&&
  can_encode(C_TILE_WIDTH,C_TILES)&&can_encode(C_LOCAL_WIDTH,C_DST_LOCALS)&&
  can_encode(C_CLASS_WIDTH,C_CLASSES)&&can_encode(C_SLOT_WIDTH,C_SLOTS)&&
  can_encode(C_ACCOUNT_WIDTH,C_ACCOUNTS)&&
  can_encode(C_COUNT_WIDTH,C_CAPACITY+1)&&(C_EPOCH_WIDTH>=1)&&(C_EPOCH_WIDTH<=30)&&
  (C_GENERATION_WIDTH>=1)&&(C_GENERATION_WIDTH<=30);
 localparam [1:0] SLOT_FREE=2'b00,SLOT_ISSUED=2'b01,SLOT_OCCUPIED=2'b10;
 reg [1:0] slot_state_q[0:C_SLOTS-1];
 reg [C_PLANE_WIDTH-1:0] slot_plane_q[0:C_SLOTS-1];
 reg [C_GENERATION_WIDTH-1:0] slot_generation_q[0:C_SLOTS-1];
 reg [C_EPOCH_WIDTH-1:0] slot_epoch_q[0:C_SLOTS-1];
 reg [C_EPOCH_WIDTH-1:0] active_epoch_q;
 reg [C_PLANE_WIDTH-1:0] rr_q[0:C_RESOURCES-1];
 reg [C_SLOTS-1:0] issue_slot_fire,arrival_slot_fire,release_slot_fire;
 reg [C_RESOURCES-1:0] issue_resource_fire;
 reg issue_bad,arrival_bad,release_bad,arrival_underflow_event;
 reg arrival_duplicate_event,release_duplicate_event,arrival_stale_event,release_stale_event;
 reg conservation_bad,issue_overflow_event,generation_exhausted_event;
 reg [C_PLANE_WIDTH-1:0] winner[0:C_RESOURCES-1];
 reg [C_SLOT_WIDTH-1:0] winner_slot[0:C_RESOURCES-1];
 integer ip,ir,ik,iscan,iscan_plane,isl,it,il,ic,ires;
 integer ap,aslot;
 integer rp,rslot,rresource,rlane;
 integer or_index,oa_index,os_index,ototal;
 integer sr_index,state_slot_index;
 reg ifound;
 reg [C_TOKEN_WIDTH-1:0] atoken,rtoken;
 reg [C_EPOCH_WIDTH-1:0] aepoch,repoch;
 reg [C_GENERATION_WIDTH-1:0] ageneration,rgeneration;
 reg [C_SLOT_WIDTH-1:0] atoken_slot,rtoken_slot;
 assign o_config_error=!CONFIG_LEGAL;
 assign o_error=o_config_error|o_issue_overflow|o_arrival_underflow|o_duplicate_token|
  o_stale_epoch|o_epoch_change_error|o_generation_exhausted|o_malformed_token|o_conservation_error;

 // Per-resource RR grants one request and allocates exactly one physical slot.
 always @(*)begin
  o_issue_ready={C_PLANES{1'b0}};o_issue_token={(C_PLANES*C_TOKEN_WIDTH){1'b0}};
  o_issue_account={(C_PLANES*C_ACCOUNT_WIDTH){1'b0}};
  issue_slot_fire={C_SLOTS{1'b0}};issue_resource_fire={C_RESOURCES{1'b0}};issue_bad=1'b0;generation_exhausted_event=1'b0;ik=0;
  for(ir=0;ir<C_RESOURCES;ir=ir+1)begin winner[ir]={C_PLANE_WIDTH{1'b0}};winner_slot[ir]={C_SLOT_WIDTH{1'b0}};end
  for(ir=0;ir<C_RESOURCES;ir=ir+1)begin
   ifound=1'b0;
   for(iscan=0;iscan<C_PLANES;iscan=iscan+1)begin
    iscan_plane=0;iscan_plane[C_PLANE_WIDTH-1:0]=rr_q[ir];iscan_plane=iscan_plane+iscan;if(iscan_plane>=C_PLANES)iscan_plane=iscan_plane-C_PLANES;
    isl=0;it=0;il=0;ic=0;
    isl[C_SLICE_WIDTH-1:0]=i_issue_dst_slice[iscan_plane*C_SLICE_WIDTH+:C_SLICE_WIDTH];
    it[C_TILE_WIDTH-1:0]=i_issue_dst_tile[iscan_plane*C_TILE_WIDTH+:C_TILE_WIDTH];
    il[C_LOCAL_WIDTH-1:0]=i_issue_dst_local[iscan_plane*C_LOCAL_WIDTH+:C_LOCAL_WIDTH];
    ic[C_CLASS_WIDTH-1:0]=i_issue_class[iscan_plane*C_CLASS_WIDTH+:C_CLASS_WIDTH];
    ires=((isl*C_TILES+it)*C_DST_LOCALS+il)*C_CLASSES+ic;
    if(!ifound&&i_issue_valid[iscan_plane]&&(isl<C_SLICES)&&(it<C_TILES)&&(il<C_DST_LOCALS)&&(ic<C_CLASSES)&&(ires==ir))begin
     for(ik=0;ik<C_CAPACITY;ik=ik+1)if(!ifound&&(slot_state_q[ir*C_CAPACITY+ik]==SLOT_FREE)&&!(&slot_generation_q[ir*C_CAPACITY+ik]))begin
      ifound=1'b1;winner[ir]=iscan_plane[C_PLANE_WIDTH-1:0];ires=ir*C_CAPACITY+ik;winner_slot[ir]=ires[C_SLOT_WIDTH-1:0];
     end
     else if(!ifound&&(slot_state_q[ir*C_CAPACITY+ik]==SLOT_FREE)&&(&slot_generation_q[ir*C_CAPACITY+ik]))generation_exhausted_event=1'b1;
    end
   end
   if(ifound&&CONFIG_LEGAL&&(i_epoch==active_epoch_q))begin
    o_issue_ready[winner[ir]]=1'b1;issue_resource_fire[ir]=1'b1;issue_slot_fire[winner_slot[ir]]=1'b1;
    o_issue_token[winner[ir]*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]=
     {active_epoch_q,slot_generation_q[winner_slot[ir]]+1'b1,winner_slot[ir]};
    ires=winner[ir]*C_RESOURCES+ir;o_issue_account[winner[ir]*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]=ires[C_ACCOUNT_WIDTH-1:0];
   end
  end
  for(ip=0;ip<C_PLANES;ip=ip+1)if(i_issue_valid[ip])begin
   isl=0;it=0;il=0;ic=0;
   isl[C_SLICE_WIDTH-1:0]=i_issue_dst_slice[ip*C_SLICE_WIDTH+:C_SLICE_WIDTH];
   it[C_TILE_WIDTH-1:0]=i_issue_dst_tile[ip*C_TILE_WIDTH+:C_TILE_WIDTH];
   il[C_LOCAL_WIDTH-1:0]=i_issue_dst_local[ip*C_LOCAL_WIDTH+:C_LOCAL_WIDTH];
   ic[C_CLASS_WIDTH-1:0]=i_issue_class[ip*C_CLASS_WIDTH+:C_CLASS_WIDTH];
   if((isl>=C_SLICES)||(it>=C_TILES)||(il>=C_DST_LOCALS)||(ic>=C_CLASSES))issue_bad=1'b1;
  end
 end

 always @(*)begin
  o_arrive_ready={C_PLANES{1'b0}};arrival_slot_fire={C_SLOTS{1'b0}};
  arrival_bad=1'b0;arrival_underflow_event=1'b0;arrival_duplicate_event=1'b0;arrival_stale_event=1'b0;
  atoken={C_TOKEN_WIDTH{1'b0}};atoken_slot={C_SLOT_WIDTH{1'b0}};aslot=0;
  ageneration={C_GENERATION_WIDTH{1'b0}};aepoch={C_EPOCH_WIDTH{1'b0}};
  for(ap=0;ap<C_PLANES;ap=ap+1)begin
   atoken=i_arrive_token[ap*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];
   atoken_slot=atoken[0+:C_SLOT_WIDTH];ageneration=atoken[C_SLOT_WIDTH+:C_GENERATION_WIDTH];
   aepoch=atoken[C_SLOT_WIDTH+C_GENERATION_WIDTH+:C_EPOCH_WIDTH];aslot=0;aslot[C_SLOT_WIDTH-1:0]=atoken_slot;
   if(aepoch!=active_epoch_q)begin if(i_arrive_valid[ap])arrival_stale_event=1'b1;end
   else if(aslot>=C_SLOTS)begin if(i_arrive_valid[ap])arrival_bad=1'b1;end
   else if(slot_state_q[aslot]!=SLOT_ISSUED)begin if(i_arrive_valid[ap])begin arrival_underflow_event=1'b1;arrival_duplicate_event=1'b1;end end
   else if((slot_plane_q[aslot]!=ap[C_PLANE_WIDTH-1:0])||
           (slot_generation_q[aslot]!=ageneration)||(slot_epoch_q[aslot]!=aepoch))begin if(i_arrive_valid[ap])arrival_duplicate_event=1'b1;end
   else begin o_arrive_ready[ap]=CONFIG_LEGAL;if(i_arrive_valid[ap])arrival_slot_fire[aslot]=CONFIG_LEGAL;end
  end
 end

 // One return port per slice/tile/local; classes share this registered-credit return lane.
 always @(*)begin
  o_release_ready={C_RELEASE_PORTS{1'b0}};release_slot_fire={C_SLOTS{1'b0}};
  release_bad=1'b0;release_duplicate_event=1'b0;release_stale_event=1'b0;
  rtoken={C_TOKEN_WIDTH{1'b0}};rtoken_slot={C_SLOT_WIDTH{1'b0}};rslot=0;rresource=0;rlane=0;
  rgeneration={C_GENERATION_WIDTH{1'b0}};repoch={C_EPOCH_WIDTH{1'b0}};
  for(rp=0;rp<C_RELEASE_PORTS;rp=rp+1)if(i_release_valid[rp])begin
   rtoken=i_release_token[rp*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];
   rtoken_slot=rtoken[0+:C_SLOT_WIDTH];rgeneration=rtoken[C_SLOT_WIDTH+:C_GENERATION_WIDTH];
   repoch=rtoken[C_SLOT_WIDTH+C_GENERATION_WIDTH+:C_EPOCH_WIDTH];rslot=0;rslot[C_SLOT_WIDTH-1:0]=rtoken_slot;
   if(repoch!=active_epoch_q)release_stale_event=1'b1;
   else if(rslot>=C_SLOTS)release_bad=1'b1;
   else begin rresource=rslot/C_CAPACITY;rlane=rresource/C_CLASSES;
    if(rlane!=rp)release_bad=1'b1;
    else if(release_slot_fire[rslot]||(slot_state_q[rslot]!=SLOT_OCCUPIED)||
            (slot_generation_q[rslot]!=rgeneration)||(slot_epoch_q[rslot]!=repoch))release_duplicate_event=1'b1;
    else begin o_release_ready[rp]=CONFIG_LEGAL;release_slot_fire[rslot]=CONFIG_LEGAL;end
   end
  end
 end

 // Derived counters make conservation independently checkable from slot ownership.
 always @(*)begin
  o_free=0;o_issued=0;
  o_occupied=0;conservation_bad=1'b0;issue_overflow_event=1'b0;oa_index=0;o_quiescent=1'b1;
  for(or_index=0;or_index<C_RESOURCES;or_index=or_index+1)begin
   ototal=0;
   for(os_index=0;os_index<C_CAPACITY;os_index=os_index+1)begin
    if(slot_state_q[or_index*C_CAPACITY+os_index]==SLOT_FREE)begin o_free[or_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]=o_free[or_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]+1'b1;ototal=ototal+1;end
    else if(slot_state_q[or_index*C_CAPACITY+os_index]==SLOT_ISSUED)begin o_quiescent=1'b0;oa_index=slot_plane_q[or_index*C_CAPACITY+os_index]*C_RESOURCES+or_index;o_issued[oa_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]=o_issued[oa_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]+1'b1;ototal=ototal+1;end
    else if(slot_state_q[or_index*C_CAPACITY+os_index]==SLOT_OCCUPIED)begin o_quiescent=1'b0;oa_index=slot_plane_q[or_index*C_CAPACITY+os_index]*C_RESOURCES+or_index;o_occupied[oa_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]=o_occupied[oa_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]+1'b1;ototal=ototal+1;end
   end
   if(ototal!=C_CAPACITY)conservation_bad=1'b1;
   if(issue_resource_fire[or_index]&&(o_free[or_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]==0))issue_overflow_event=1'b1;
  end
 end

 always @(posedge i_clk)begin
  if(!i_rstn)begin
   o_issue_overflow<=1'b0;o_arrival_underflow<=1'b0;o_duplicate_token<=1'b0;o_stale_epoch<=1'b0;o_epoch_change_error<=1'b0;o_generation_exhausted<=1'b0;active_epoch_q<=i_epoch;
   o_malformed_token<=1'b0;o_conservation_error<=1'b0;
   for(state_slot_index=0;state_slot_index<C_SLOTS;state_slot_index=state_slot_index+1)begin slot_state_q[state_slot_index]<=SLOT_FREE;slot_plane_q[state_slot_index]<={C_PLANE_WIDTH{1'b0}};slot_generation_q[state_slot_index]<={C_GENERATION_WIDTH{1'b0}};slot_epoch_q[state_slot_index]<={C_EPOCH_WIDTH{1'b0}};end
   for(sr_index=0;sr_index<C_RESOURCES;sr_index=sr_index+1)rr_q[sr_index]<={C_PLANE_WIDTH{1'b0}};
  end else begin
   if(!CONFIG_LEGAL||issue_bad||arrival_bad||release_bad)o_malformed_token<=1'b1;
   if(issue_overflow_event)o_issue_overflow<=1'b1;if(arrival_underflow_event)o_arrival_underflow<=1'b1;
   if(arrival_duplicate_event||release_duplicate_event)o_duplicate_token<=1'b1;
   if(arrival_stale_event||release_stale_event)o_stale_epoch<=1'b1;
   if((i_epoch!=active_epoch_q)&&!o_quiescent)o_epoch_change_error<=1'b1;
   if(generation_exhausted_event)o_generation_exhausted<=1'b1;
   if(o_quiescent&&(i_epoch!=active_epoch_q))begin
    active_epoch_q<=i_epoch;
    o_generation_exhausted<=1'b0;
    for(state_slot_index=0;state_slot_index<C_SLOTS;state_slot_index=state_slot_index+1)slot_generation_q[state_slot_index]<={C_GENERATION_WIDTH{1'b0}};
   end
   if(conservation_bad)o_conservation_error<=1'b1;
   for(sr_index=0;sr_index<C_RESOURCES;sr_index=sr_index+1)if(issue_resource_fire[sr_index])begin
    if(winner[sr_index]==C_PLANES[C_PLANE_WIDTH-1:0]-1'b1)rr_q[sr_index]<={C_PLANE_WIDTH{1'b0}};else rr_q[sr_index]<=winner[sr_index]+1'b1;
   end
   for(state_slot_index=0;state_slot_index<C_SLOTS;state_slot_index=state_slot_index+1)begin
    if(issue_slot_fire[state_slot_index])begin slot_state_q[state_slot_index]<=SLOT_ISSUED;slot_plane_q[state_slot_index]<=winner[state_slot_index/C_CAPACITY];slot_generation_q[state_slot_index]<=slot_generation_q[state_slot_index]+1'b1;slot_epoch_q[state_slot_index]<=active_epoch_q;end
    else if(arrival_slot_fire[state_slot_index])slot_state_q[state_slot_index]<=SLOT_OCCUPIED;
    else if(release_slot_fire[state_slot_index])slot_state_q[state_slot_index]<=SLOT_FREE;
   end
  end
 end
endmodule
`default_nettype wire
