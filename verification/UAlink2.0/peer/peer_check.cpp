#include "Vdl_replay_data_port.h"
#include "verilated.h"
#include <fstream>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <cstdint>
#include <deque>
#include <map>
#include <array>
#include <memory>
#include <stdexcept>
#ifndef PAYLOAD_WIDTH
#error PAYLOAD_WIDTH required
#endif
void input_data(Vdl_replay_data_port &d,const std::string &s){
#if PAYLOAD_WIDTH <= 64
 d.i_data=std::stoull(s,nullptr,16);
#else
 for(int j=0;j<(PAYLOAD_WIDTH+31)/32;j++)d.i_data[j]=0;
 for(int j=0;j<PAYLOAD_WIDTH/8;j++)d.i_data[j/4]|=uint32_t(std::stoul(s.substr(s.size()-2-2*j,2),nullptr,16))<<((j%4)*8);
#endif
}
std::string output_data(Vdl_replay_data_port &d){std::ostringstream s;s<<std::hex<<std::setfill('0');
 for(int j=PAYLOAD_WIDTH/8-1;j>=0;j--){
#if PAYLOAD_WIDTH <= 64
  unsigned b=(uint64_t(d.o_out_data)>>(j*8))&255;
#else
  unsigned b=(d.o_out_data[j/4]>>((j%4)*8))&255;
#endif
  s<<std::setw(2)<<b;
 }return s.str();}
void input_rx_data(Vdl_replay_data_port &d,const std::string &s){
#if PAYLOAD_WIDTH <= 64
 d.i_rx_data=std::stoull(s,nullptr,16);
#else
 for(int j=0;j<(PAYLOAD_WIDTH+31)/32;j++)d.i_rx_data[j]=0;
 for(int j=0;j<PAYLOAD_WIDTH/8;j++)d.i_rx_data[j/4]|=uint32_t(std::stoul(s.substr(s.size()-2-2*j,2),nullptr,16))<<((j%4)*8);
#endif
}
std::string output_rx_data(Vdl_replay_data_port &d){std::ostringstream s;s<<std::hex<<std::setfill('0');
 for(int j=PAYLOAD_WIDTH/8-1;j>=0;j--){
#if PAYLOAD_WIDTH <= 64
  unsigned b=(uint64_t(d.o_rx_data)>>(j*8))&255;
#else
  unsigned b=(d.o_rx_data[j/4]>>((j%4)*8))&255;
#endif
  s<<std::setw(2)<<b;
 }return s.str();}

struct Frame {uint64_t due,group;uint32_t header;std::string data;bool crc,discard;};
uint64_t random_state;
uint64_t random_word(){random_state^=random_state<<13;random_state^=random_state>>7;random_state^=random_state<<17;return random_state;}
std::string payload_word(unsigned side,uint64_t token){std::ostringstream out;out<<std::hex<<std::setfill('0');
 for(int j=PAYLOAD_WIDTH/8-1;j>=0;--j){unsigned v=j<4?unsigned(token>>(j*8)):unsigned(token*73+j*29+(token>>(j%7)));v=(v^(side?0xA7:0x3D))&255;out<<std::setw(2)<<v;}return out.str();}
void pretrace(std::ostringstream &r,uint64_t tick,unsigned side,Vdl_replay_data_port &d,const std::string &data,const std::string &rxdata){
 r<<std::dec<<tick<<" "<<side<<" "<<std::hex<<((uint64_t(d.i_rstn)<<0) | (uint64_t(d.i_link_reset)<<1) | (uint64_t(d.i_rx_event_valid)<<2) | (uint64_t(d.i_rx_event_discard)<<3) | (uint64_t(d.i_rx_crc_ok)<<4) | (uint64_t(d.i_rx_header)<<5) | (uint64_t(d.i_rx_replay_limit)<<29) | (uint64_t(d.i_flit_request)<<37) | (uint64_t(d.i_new_group)<<38) | (uint64_t(d.i_payload)<<39))<<" "<<data<<" "<<rxdata;
 r<<" "<<uint64_t(d.o_issue_ready);
 r<<" "<<uint64_t(d.o_issue_accept);
 r<<" "<<uint64_t(d.o_payload_accept);
 r<<" "<<uint64_t(d.o_issue_payload);
 r<<" "<<uint64_t(d.o_issue_replay);
 r<<" "<<uint64_t(d.o_issue_first);
 r<<" "<<uint64_t(d.o_issue_sequence);
 r<<" "<<uint64_t(d.o_out_valid);
 r<<" "<<uint64_t(d.o_out_payload);
 r<<" "<<uint64_t(d.o_out_replay);
 r<<" "<<uint64_t(d.o_out_first);
 r<<" "<<uint64_t(d.o_out_sequence);
 r<<" "<<uint64_t(d.o_tag_error);
 r<<" "<<uint64_t(d.o_out_stored_sequence);
 r<<" "<<uint64_t(d.o_ack_accept);
 r<<" "<<uint64_t(d.o_ack_count);
 r<<" "<<uint64_t(d.o_request_accept);
 r<<" "<<uint64_t(d.o_command_reject);
 r<<" "<<uint64_t(d.o_resident_count);
 r<<" "<<uint64_t(d.o_ctl_last_sequence);
 r<<" "<<uint64_t(d.o_ctl_last_ack);
 r<<" "<<uint64_t(d.o_ctl_ignore_count);
 r<<" "<<uint64_t(d.o_ctl_unacked_count);
 r<<" "<<uint64_t(d.o_ctl_head_pointer);
 r<<" "<<uint64_t(d.o_ctl_write_pointer);
 r<<" "<<uint64_t(d.o_ctl_scheduled_sequence);
 r<<" "<<uint64_t(d.o_ctl_scheduled_count);
 r<<" "<<uint64_t(d.o_ctl_scheduled_pointer);
 r<<" "<<uint64_t(d.o_ctl_first_pending);
 r<<" "<<uint64_t(d.o_rx_ingress_event);
 r<<" "<<uint64_t(d.o_rx_accept);
 r<<" "<<uint64_t(d.o_rx_payload_accept);
 r<<" "<<uint64_t(d.o_rx_sequence_valid);
 r<<" "<<uint64_t(d.o_rx_sequence);
 r<<" "<<uint64_t(d.o_rx_replay_request);
 r<<" "<<uint64_t(d.o_rx_command_valid);
 r<<" "<<uint64_t(d.o_rx_command_request);
 r<<" "<<uint64_t(d.o_rx_command_target);
 r<<" "<<uint64_t(d.o_rx_crc_error);
 r<<" "<<uint64_t(d.o_rx_zero_sequence);
 r<<" "<<uint64_t(d.o_rx_zero_command);
 r<<" "<<uint64_t(d.o_rx_backpressure_drop);
 r<<" "<<uint64_t(d.o_rx_unexpected);
 r<<" "<<uint64_t(d.o_rx_ambiguous_drop);
 r<<" "<<uint64_t(d.o_rx_replay_drop);
 r<<" "<<uint64_t(d.o_rx_last_sequence);
 r<<" "<<uint64_t(d.o_rx_bad_crc_count);
 r<<" "<<uint64_t(d.o_rx_unexpected_count);
 r<<" "<<uint64_t(d.o_rx_ambiguous);
 r<<" "<<uint64_t(d.o_rx_replay);
 r<<" "<<uint64_t(d.o_issue_header);
 r<<" "<<uint64_t(d.o_issue_header_valid);
 r<<" "<<uint64_t(d.o_issue_metadata_error);
 r<<" "<<uint64_t(d.o_tx_explicit_count);
 r<<" "<<uint64_t(d.o_tx_request_count);
 r<<" "<<uint64_t(d.o_tx_request_sequence);
 r<<" "<<uint64_t(d.o_tx_group_used);
 r<<" "<<uint64_t(d.o_rx_effective_sequence);
 r<<" "<<uint64_t(d.o_out_header);
 r<<" "<<output_data(d)<<" "<<output_rx_data(d);
}
void posttrace(std::ostringstream &r,Vdl_replay_data_port &d){r<<std::hex; r<<" "<<uint64_t(d.o_ctl_last_sequence);
 r<<" "<<uint64_t(d.o_ctl_last_ack);
 r<<" "<<uint64_t(d.o_ctl_ignore_count);
 r<<" "<<uint64_t(d.o_ctl_unacked_count);
 r<<" "<<uint64_t(d.o_ctl_head_pointer);
 r<<" "<<uint64_t(d.o_ctl_write_pointer);
 r<<" "<<uint64_t(d.o_ctl_scheduled_sequence);
 r<<" "<<uint64_t(d.o_ctl_scheduled_count);
 r<<" "<<uint64_t(d.o_ctl_scheduled_pointer);
 r<<" "<<uint64_t(d.o_ctl_first_pending);
 r<<" "<<uint64_t(d.o_rx_last_sequence);
 r<<" "<<uint64_t(d.o_rx_bad_crc_count);
 r<<" "<<uint64_t(d.o_rx_unexpected_count);
 r<<" "<<uint64_t(d.o_rx_ambiguous);
 r<<" "<<uint64_t(d.o_rx_replay);
 r<<" "<<uint64_t(d.o_tx_explicit_count);
 r<<" "<<uint64_t(d.o_tx_request_count);
 r<<" "<<uint64_t(d.o_tx_request_sequence);
 r<<" "<<uint64_t(d.o_tx_group_used);
 r<<" "<<uint64_t(d.o_resident_count);
 r<<" "<<uint64_t(d.o_out_valid);
 r<<" "<<uint64_t(d.o_out_payload);
 r<<" "<<uint64_t(d.o_out_replay);
 r<<" "<<uint64_t(d.o_out_first);
 r<<" "<<uint64_t(d.o_out_sequence);
 r<<" "<<uint64_t(d.o_tag_error);
 r<<" "<<uint64_t(d.o_out_stored_sequence);
 r<<" "<<uint64_t(d.o_out_header); r<<" "<<output_data(d)<<"\n";}
int main(int argc,char **argv){try{
 Verilated::commandArgs(argc,argv);if(argc!=8)return 2;
 unsigned group_size=std::stoul(argv[1]),delay=std::stoul(argv[2]);uint64_t target=std::stoull(argv[3]);random_state=std::stoull(argv[4]);bool inject=std::stoul(argv[5]);
 if(!group_size||!delay||!target||!random_state)return 2;
 std::ofstream trace(argv[6]),wire_trace(argv[7]);if(!trace||!wire_trace)return 2;
 std::array<std::unique_ptr<Vdl_replay_data_port>,2> dut;dut[0]=std::make_unique<Vdl_replay_data_port>("endpoint_a");dut[1]=std::make_unique<Vdl_replay_data_port>("endpoint_b");
 std::deque<Frame> link[2];std::deque<std::string> expected[2];std::map<uint64_t,unsigned> requests_per_group[2];
 uint64_t accepted[2]={},delivered[2]={},slots[2]={},replays[2]={},requests[2]={},wraps[2]={},full_nops[2]={},crc_bad[2]={},lost_group[2]={},lost_request[2]={},discarded[2]={};bool crc_once[2]={},discard_once[2]={},request_once[2]={};
 const std::string zero(PAYLOAD_WIDTH/4,'0');
 for(auto &p:dut){p->i_clk=0;p->i_rstn=0;p->eval();p->i_clk=1;p->eval();p->i_clk=0;p->eval();}
 uint64_t max_ticks=target*80+delay*100+10000,quiet=0,tick;
 for(tick=0;tick<max_ticks;++tick){
  std::ostringstream row[2];bool committed[2]={},reserved[2]={};std::string txdata[2];
  for(unsigned side=0;side<2;++side){auto &d=*dut[side];d.i_clk=0;d.i_rstn=1;d.i_link_reset=0;d.i_rx_event_valid=0;d.i_rx_event_discard=0;d.i_rx_crc_ok=1;d.i_rx_header=0;d.i_rx_replay_limit=50;std::string rxdata=zero;
   if(!link[side].empty()&&link[side].front().due<=tick){Frame f=link[side].front();link[side].pop_front();d.i_rx_event_valid=1;d.i_rx_header=f.header;d.i_rx_crc_ok=f.crc;d.i_rx_event_discard=f.discard;rxdata=f.data;}
   reserved[side]=(random_word()%4)!=0;d.i_flit_request=reserved[side];d.i_new_group=reserved[side]?(slots[side]%group_size==0):1;d.i_payload=accepted[side]<target;txdata[side]=payload_word(side,accepted[side]+1);input_data(d,txdata[side]);input_rx_data(d,rxdata);d.eval();pretrace(row[side],tick,side,d,txdata[side],rxdata);
   if(d.o_issue_accept!=reserved[side]||d.o_issue_metadata_error)throw std::runtime_error("reservation or metadata error");
   if(d.o_rx_payload_accept){unsigned source=1-side;if(expected[source].empty()||output_rx_data(d)!=expected[source].front())throw std::runtime_error("application ordering/data mismatch side="+std::to_string(side)+" tick="+std::to_string(tick));expected[source].pop_front();++delivered[source];}
   committed[side]=d.o_payload_accept;
   if(committed[side]){expected[side].push_back(txdata[side]);++accepted[side];}
   if(reserved[side]){++slots[side];full_nops[side]+=d.i_payload&&!d.o_issue_payload;}
  }
  for(auto &p:dut){p->i_clk=1;p->eval();}
  for(unsigned side=0;side<2;++side){auto &d=*dut[side];posttrace(row[side],d);trace<<row[side].str();
   if(d.o_out_valid!=reserved[side]||d.o_tag_error)throw std::runtime_error("registered response/tag mismatch");
   if(committed[side]&&d.o_ctl_write_pointer==0)++wraps[side];
   if(d.o_out_valid){uint64_t g=(slots[side]-1)/group_size;uint32_t header=d.o_out_header;std::string data=output_data(d);bool is_request=((header>>21)&7)==3;
    if(is_request&&++requests_per_group[side][g]>1)throw std::runtime_error("multiple request copies in actual reserved group");requests[side]+=is_request;replays[side]+=d.o_out_replay;
    bool crc=true,discard=false,drop=false;unsigned action=0;
    if(inject&&g==10){drop=true;action=1;++lost_group[side];}
    else if(inject&&is_request&&!request_once[side]){request_once[side]=true;drop=true;action=2;++lost_request[side];}
    else if(inject&&((d.o_out_payload&&!d.o_out_replay&&accepted[side]==9&&!crc_once[side])||g==20)){crc_once[side]=true;crc=false;action=3;header^=0x100;++crc_bad[side];}
    else if(inject&&d.o_out_payload&&!d.o_out_replay&&accepted[side]>=17&&!discard_once[side]){discard_once[side]=true;discard=true;action=4;++discarded[side];}
    wire_trace<<std::dec<<tick<<" "<<side<<" "<<tick+delay<<" "<<g<<" "<<action<<" "<<crc<<" "<<discard<<" "<<std::hex<<header<<" "<<data<<"\n";
    if(!drop)link[1-side].push_back(Frame{tick+delay,g,header,data,crc,discard});
   }
  }
  bool done=true;for(unsigned side=0;side<2;++side)done=done&&accepted[side]==target&&delivered[side]==target&&expected[side].empty()&&dut[side]->o_ctl_unacked_count==0&&dut[side]->o_ctl_scheduled_count==0&&dut[side]->o_tx_request_count==0;
  quiet=done?quiet+1:0;if(quiet>delay+group_size*4+8)break;
  for(auto &p:dut){p->i_clk=0;p->eval();}
 }
 if(tick==max_ticks)throw std::runtime_error("liveness timeout accepted="+std::to_string(accepted[0])+","+std::to_string(accepted[1])+" delivered="+std::to_string(delivered[0])+","+std::to_string(delivered[1]));
 for(unsigned side=0;side<2;++side){if(accepted[side]!=target||delivered[side]!=target)throw std::runtime_error("incomplete application traffic");if(inject&&(!crc_bad[side]||!lost_group[side]||!lost_request[side]||!discarded[side]||!replays[side]))throw std::runtime_error("missing required error/replay coverage");}
 std::cout<<"{\"passed\":true,\"ticks\":"<<tick+1<<",\"clock_edges\":"<<2*(tick+2)<<",\"accepted\":["<<accepted[0]<<","<<accepted[1]<<"],\"delivered\":["<<delivered[0]<<","<<delivered[1]<<"],\"slots\":["<<slots[0]<<","<<slots[1]<<"],\"replays\":["<<replays[0]<<","<<replays[1]<<"],\"requests\":["<<requests[0]<<","<<requests[1]<<"],\"physical_wraps\":["<<wraps[0]<<","<<wraps[1]<<"],\"full_nops\":["<<full_nops[0]<<","<<full_nops[1]<<"],\"crc_bad\":["<<crc_bad[0]<<","<<crc_bad[1]<<"],\"lost_group_flits\":["<<lost_group[0]<<","<<lost_group[1]<<"],\"lost_requests\":["<<lost_request[0]<<","<<lost_request[1]<<"],\"receive_discards\":["<<discarded[0]<<","<<discarded[1]<<"]}\n";
 return 0;
 }catch(const std::exception &e){std::cerr<<"MISMATCH "<<e.what()<<"\n";return 1;}}
