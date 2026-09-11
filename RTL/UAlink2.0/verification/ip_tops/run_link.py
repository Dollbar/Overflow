"""Run actual Endpoint -> Switch -> Endpoint development IP tops.
Run: python3 verification/ip_tops/run_link.py --kd28-root PATH --label NEW [--inject]
Outputs snapshots, logs and the independent TL/replay/SRAM audit under
build/verification/ip_tops/NEW. Next run other switch sizes and review explicit
local-routing/CRC-status boundaries in docs/ip_top_bringup.md.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('endpoint_link_fixture',ROOT/'verification/endpoint_link/run.py')
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)


def bench(a,streams):
    text=fixture.bench(a,streams)
    inventory=json.loads((ROOT/'config/ip_module_inventory.json').read_text())
    masks={role:sum(1<<m['feature_slots'][role] for m in inventory['modules'] if m['status']=='planned' and role in m['roles']) for role in ('endpoint','switch')}
    extras=f'''
wire [127:0] pending_features[0:1],switch_pending_features;
wire [543:0] ep_data[0:1];wire ep_valid[0:1],ep_ready[0:1],ep_rx_ready[0:1],ep_error[0:1];
wire ep_payload[0:1],ep_replay[0:1];wire [8:0] ep_seq[0:1];
wire [{a.ports-1}:0] sw_valid,sw_ready,sw_out_valid,sw_out_ready,sw_last,sw_error;
wire [{a.ports*545-1}:0] sw_data,sw_out_data;wire [{a.ports*10-1}:0] sw_dst,route_ids;
wire drop_link[0:1],bad_crc[0:1];
ualink_switch_top #(.PORTS({a.ports}),.DATA_WIDTH(545)) fabric(
.clk(clk),.rstn(rstn),.i_route_ids(route_ids),.i_port_enable({a.ports}'d{(1<<a.ports)-1}),
.i_valid(sw_valid),.o_ready(sw_ready),.i_data(sw_data),.i_dst(sw_dst),.i_last({a.ports}'d{(1<<a.ports)-1}),
.o_valid(sw_out_valid),.i_ready(sw_out_ready),.o_data(sw_out_data),.o_last(sw_last),.o_route_error(sw_error),.o_pending_features(switch_pending_features));
genvar port;generate for(port=0;port<{a.ports};port=port+1)begin:route
 assign route_ids[port*10+:10]=port+1;
 if(port<2)begin:active
  assign sw_dst[port*10+:10]=2-port;
  assign drop_link[port]={int(a.inject)}&&ep_payload[port]&&!ep_replay[port]&&(originals[port]==11)&&!drop_sent[port];
  assign bad_crc[port]={int(a.inject)}&&ep_payload[port]&&!ep_replay[port]&&(originals[port]==4)&&!crc_sent[port];
  assign sw_valid[port]=ep_valid[port]&&!drop_link[port];
  assign sw_data[port*545+:545]={{!bad_crc[port],ep_data[port]}};
  assign ep_ready[port]=drop_link[port]||sw_ready[port];
  assign sw_out_ready[port]=rstn&&(cycle%7!=port+1)&&!(cycle>=90&&cycle<110);
 end else begin:unused_port
  assign sw_valid[port]=1'b0;assign sw_data[port*545+:545]=545'd0;
  assign sw_dst[port*10+:10]=10'd0;assign sw_out_ready[port]=1'b1;
 end
end endgenerate
always @(posedge clk)if(rstn)begin
 if(|sw_error)$fatal(1,"switch route rejected an active endpoint");
 if(switch_pending_features!==128'h{masks['switch']:032x})$fatal(1,"switch shell capability mismatch");
end
'''
    text=text.replace('genvar side;generate',extras+'\ngenvar side;generate',1)
    begin=text.index('tl_tx_prepared #(');end=text.index('end endgenerate',begin)
    inst=f'''
ualink_endpoint_top #(.WIDTH(8),.HEADER_DEPTH(2),.BANK_DEPTH(3),.RX_DEPTH(40),.DL_DEPTH({a.depth})) dut(
.i_clk(clk),.i_rstn(rstn),.i_link_reset(1'b0),.i_start(start),.i_auth(1'b{a.auth}),.i_shared(1'b{a.shared}),.i_capacities({{20{{8'd1}}}}),
.i_source_valid(hv[side]),.i_source_control(hd[side]),.i_source_tags_valid(2'b11),.i_source_tags(1024'd0),
.i_data_valid(dv[side]),.i_data0(d0[side]),.i_data1(d1[side]),.o_source_captured(captured[side]),.o_source_ready(source_ready[side]),.o_data_accepted(da[side]),.o_data_ready(dr[side]),
.i_read_ready(read_ready[side]),.o_read_valid(read_valid[side]),.o_read_flit(read_flit[side]),.o_read_msg(read_msg[side]),.o_read_classes(classes[side]),.o_read_releases(releases[side]),
.o_link_valid(ep_valid[side]),.o_link_data(ep_data[side]),.o_link_payload(ep_payload[side]),.o_link_replay(ep_replay[side]),.o_link_sequence(ep_seq[side]),.i_link_ready(ep_ready[side]),
.i_link_valid(linkvalid[side][{a.delay-1}]),.i_link_data({{linkheader[side][{a.delay-1}],linkdata[side][{a.delay-1}]}}),.i_link_crc_ok(linkcrc[side][{a.delay-1}]),.o_link_ready(ep_rx_ready[side]),.i_rx_replay_limit(8'd50),
.o_config_error(config_error[side]),.o_done(done[side]),.o_peer_done(peer_done[side]),.o_peer_shared(peer_shared[side]),.o_error(ep_error[side]),
.o_capacity(capacity[side]),.o_available(available[side]),.o_pending(pub[side]),.o_tx_pending(pending[side]),.o_tx_validation_state(state[side]),
.o_header_count(hcount[side]),.o_data_count(dcount[side]),.o_rx_count(rxcount[side]),.o_unacked_count(unacked[side]),.o_scheduled_count(scheduled[side]),.o_pending_features(pending_features[side]));
// Verification observations bind to actual child ports, never replace production signals.
assign pv[side]=dut.u_tx.o_valid;assign tx[side]=dut.u_tx.o_flit;assign tm[side]=dut.u_tx.o_msg;
assign taken[side]=dut.u_credit.o_tx_taken;assign ht[side]=dut.u_tx.o_header_taken;assign dt[side]=dut.u_tx.o_data_taken;assign fct[side]=dut.u_tx.o_fc_taken;
assign head_error[side]=dut.u_tx.o_header_error;assign input_error[side]=dut.u_tx.o_input_error;
assign prep_error[side]=dut.u_tx.o_prepare_error;assign prep_short[side]=dut.u_tx.o_prepare_shortfall;assign shortfall[side]=dut.u_tx.o_capacity_shortfall;
assign portfatal[side]=dut.u_credit.o_fatal;assign rxfatal[side]=dut.u_receive.o_fatal;
assign ptake[side]=dut.u_credit.o_rx_taken;assign rtake[side]=dut.u_receive.o_taken;
assign fv[side]=dut.u_receive.o_fc_valid;assign ft[side]=dut.u_receive.o_fc_taken;assign ret[side]=dut.u_receive.o_retired;assign rel[side]=dut.u_receive.o_release_taken;
assign dlaccept[side]=dut.u_dl.o_payload_accept;assign issuereplay[side]=dut.u_dl.o_issue_replay;assign seq[side]=dut.u_dl.o_issue_sequence;
assign dlrx[side]=dut.u_dl.o_rx_payload_accept;assign rxdata[side]=dut.u_dl.o_rx_data;
assign tag_error[side]=dut.u_dl.o_tag_error;assign metadata_error[side]=dut.u_dl.o_issue_metadata_error;
assign dlvalid[side]=ep_valid[side]&&ep_ready[side];assign dlheader[side]=ep_data[side][543:520];assign dldata[side]=ep_data[side][519:0];
assign dlpayload[side]=ep_payload[side];assign dlreplay[side]=ep_replay[side];assign outseq[side]=ep_seq[side];
always @(posedge clk)if(rstn)begin
 if(pending_features[side]!==128'h{masks['endpoint']:032x})$fatal(1,"endpoint shell capability mismatch");
 if(ep_error[side])$fatal(1,"endpoint top error side=%0d",side);
 if(linkvalid[side][{a.delay-1}]&&!ep_rx_ready[side])$fatal(1,"registered delivery lost RX acceptance");
end
'''
    text=text[:begin]+inst+text[end:]
    old='linkvalid[1-e][0]<=dlvalid[e];linkheader[1-e][0]<=dlheader[e];linkdata[1-e][0]<=dldata[e];linkcrc[1-e][0]<=1;'
    new='linkvalid[e][0]<=sw_out_valid[e]&&sw_out_ready[e];linkheader[e][0]<=sw_out_data[e*545+520+:24];linkdata[e][0]<=sw_out_data[e*545+:520];linkcrc[e][0]<=sw_out_data[e*545+544];'
    if text.count(old)!=1:raise ValueError('fixture link boundary changed')
    text=text.replace(old,new)
    text=text.replace('linkvalid[1-e][0]<=!drop_now;linkcrc[1-e][0]<=crc_now;','')
    # Actual external fault changes the link word presented to the Switch.
    if a.top_fault=='link_data':
        text=text.replace('!bad_crc[port],ep_data[port]',"!bad_crc[port],(ep_data[port]^((ep_payload[port]&&ep_data[port][513:512]==0&&ep_data[port][511:256]!=0)?(544'd1<<300):544'd0))")
    return text


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',required=True)
    p.add_argument('--ports',type=int,choices=(2,3,4),default=2);p.add_argument('--depth',type=int,default=3)
    p.add_argument('--delay',type=int,default=3);p.add_argument('--count',type=int,default=24)
    p.add_argument('--auth',type=int,choices=(0,1),default=0);p.add_argument('--shared',type=int,choices=(0,1),default=0)
    p.add_argument('--inject',action='store_true');p.add_argument('--top-fault',choices=('none','link_data'),default='none')
    a=p.parse_args();a.fault='none'
    if not re.fullmatch('[A-Za-z0-9_-]+',a.label) or not 1<=a.depth<=255 or not 1<=a.delay<=32 or not 8<=a.count<=1024:p.error('invalid label/depth/delay/count')
    stage=ROOT/'build/verification/ip_tops'/a.label;stage.mkdir(parents=True,exist_ok=False)
    streams=[[fixture.fixtures(e,r,a.count) for r in range(2)] for e in range(2)]
    for e in range(2):
        for r in range(2):
            for key in ('headers','data'):(stage/f'{key}{e}{r}.hex').write_text('\n'.join(streams[e][r][key])+'\n')
    config={k:v for k,v in vars(a).items() if k!='kd28_root'}|dict(fixtures=streams,capacities=[1]*20)
    (stage/'case.json').write_text(json.dumps(config,indent=2)+'\n');(stage/'tb.sv').write_text(bench(a,streams))
    external=a.kd28_root.resolve()/'Library/models/kd28'
    deps=[external/'sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[external/'fifo/rtl/kd28_fifo_sdp_storage_map.v']
    rtl=sorted((ROOT/'rtl').rglob('*.v'))
    command=['iverilog','-g2012','-s','tb','-o',str(stage/'sim.vvp'),str(stage/'tb.sv'),*map(str,rtl+deps)]
    record=dict(passed=False,compile_command=command,scope='development IP tops with explicit local route and CRC-status adapter; no standard per-hop protocol termination')
    sources=rtl+deps+[ROOT/'config/ip_module_inventory.json',Path(__file__),ROOT/'verification/endpoint_link/run.py',ROOT/'verification/endpoint_link/check.py']+list((ROOT/'model/tl').glob('*.py'))
    record['sources']={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources if f.exists()}
    steps=[('compile',command,180),('run',['vvp',str(stage/'sim.vvp')],180),('audit',[sys.executable,str(ROOT/'verification/endpoint_link/check.py'),str(stage)],60)]
    for name,cmd,timeout in steps:
        with (stage/f'{name}.log').open('w') as log:
            try:record[name+'_exit']=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=timeout).returncode
            except subprocess.TimeoutExpired:record[name+'_exit']=124
        if record[name+'_exit']!=0:break
    record['passed']=all(record.get(name+'_exit')==0 for name,_,_ in steps)
    record['artifacts']={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.iterdir() if f.is_file()}
    (stage/'record.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({k:v for k,v in record.items() if k.endswith('exit') or k=='passed'}))
    return 0 if record['passed'] else 1


if __name__=='__main__':raise SystemExit(main())
