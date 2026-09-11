"""Run two actual prepared TL + credit + receive SRAM + DL replay endpoints.
Example: python3 verification/endpoint_link/run.py --kd28-root PATH --label smoke --inject
Outputs build/verification/endpoint_link/LABEL/{case,record,audit}.json and full logs/trace.
Next: review audit.json, then run other depth/delay/auth/shared configurations.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def fixtures(side, role, count):
    heads, data = [], []
    for index in range(count):
        vc, pool = index % 4, int(index % 5 == 0)
        if role == 0:
            word = (1 << 124) | (0x23 << 118) | (vc << 116) | (pool << 102) | ((side + 1) << 80) | (index << 16)
        else:
            word = (2 << 60) | (vc << 58) | (index << 47) | (pool << 46) | (1 << 37) | (1 << 36) | ((side + 1) << 26) | ((2 - side) << 16)
        heads.append(f'{word:064x}')
        for half in range(2):
            payload = sum(((side << 31) | (role << 30) | (index << 12) | (half << 8) | byte) << (32 * byte) for byte in range(8))
            data.append(f'{payload:064x}')
    return dict(headers=heads, data=data)


def bench(a, streams):
    declarations, assignments, reads, done = [], [], [], []
    for side in range(2):
        for role in range(2):
            suffix = f'{side}{role}'
            declarations.append(f'reg [255:0] headers{suffix}[0:{a.count-1}], data{suffix}[0:{2*a.count-1}];')
            reads.append(f'$readmemh("headers{suffix}.hex",headers{suffix});$readmemh("data{suffix}.hex",data{suffix});')
            assignments.append(f'''assign hd[{side}][{role*256}+:256]=(wh[{side}][{role}]<{a.count})?headers{suffix}[wh[{side}][{role}]]:256'd0;
assign hv[{side}][{role}]=done[{side}]&&peer_done[{side}]&&(wh[{side}][{role}]<{a.count});
assign dv[{side}][{role*2}+:2]=(wd[{side}][{role}]+1<{2*a.count})?2'd2:(wd[{side}][{role}]<{2*a.count})?2'd1:2'd0;
assign d0[{side}][{role*256}+:256]=(wd[{side}][{role}]<{2*a.count})?data{suffix}[wd[{side}][{role}]]:256'd0;
assign d1[{side}][{role*256}+:256]=(wd[{side}][{role}]+1<{2*a.count})?data{suffix}[wd[{side}][{role}]+1]:256'd0;''')
            done.extend([f'wh[{side}][{role}]=={a.count}', f'wd[{side}][{role}]=={2*a.count}'])
    done.extend(['hcount[0]==0','hcount[1]==0','dcount[0]==0','dcount[1]==0','pending[0]==0','pending[1]==0','rxcount[0]==0','rxcount[1]==0','pub[0]==0','pub[1]==0','!fv[0]','!fv[1]','available[0]==capacity[0]','available[1]==capacity[1]','unacked[0]==0','unacked[1]==0','scheduled[0]==0','scheduled[1]==0','!pv[0]','!pv[1]'])
    text = f'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0,start=0;integer cycle=0,quiet=0,e,c,j;
integer wh[0:1][0:1],wd[0:1][0:1],originals[0:1],crcs[0:1],drops[0:1],replays[0:1],stalls[0:1],retirements[0:1];
reg crc_sent[0:1],drop_sent[0:1];
{chr(10).join(declarations)}
wire [511:0] hd[0:1],d0[0:1],d1[0:1],tx[0:1],fc[0:1],read_flit[0:1];
wire [1:0] hv[0:1],captured[0:1],source_ready[0:1],dr[0:1],ht[0:1],head_error[0:1],input_error[0:1],prep_error[0:1],prep_short[0:1],shortfall[0:1],tm[0:1],fm[0:1],read_msg[0:1];
wire [3:0] dv[0:1],da[0:1],dt[0:1],hcount[0:1];wire [5:0] dcount[0:1],classes[0:1],rxcount[0:1];
wire pv[0:1],taken[0:1],allow_tx[0:1],portfatal[0:1],rxfatal[0:1],done[0:1],peer_done[0:1],peer_shared[0:1],fv[0:1],fct[0:1],ft[0:1],ptake[0:1],rtake[0:1],ret[0:1],rel[0:1],read_valid[0:1],read_ready[0:1],config_error[0:1];
wire [179:0] available[0:1],capacity[0:1],pub[0:1];wire [6:0] pending[0:1];wire [89:0] state[0:1];wire [79:0] releases[0:1];
wire reserve[0:1],dlaccept[0:1],dlvalid[0:1],dlpayload[0:1],dlreplay[0:1],dlrx[0:1],tag_error[0:1],metadata_error[0:1],issuereplay[0:1];
wire [8:0] seq[0:1],outseq[0:1];wire [23:0] dlheader[0:1];wire [519:0] dldata[0:1],rxdata[0:1];wire [7:0] unacked[0:1],scheduled[0:1];
reg [519:0] linkdata[0:1][0:{a.delay-1}];reg [23:0] linkheader[0:1][0:{a.delay-1}];reg linkvalid[0:1][0:{a.delay-1}],linkcrc[0:1][0:{a.delay-1}];
reg drop_now,crc_now;integer trace;
{chr(10).join(assignments)}
genvar side;generate for(side=0;side<2;side=side+1)begin:ends
// 每拍预约固定延迟DL输出槽；有限停止预约模拟数字下游背压。
assign reserve[side]=rstn&&(cycle%7!=side+1)&&!(cycle>=90&&cycle<110);
assign read_ready[side]=cycle>150&&(cycle%5!=side+1)&&!(cycle>=250&&cycle<275);
tl_tx_prepared #(.WIDTH(8),.HEADER_DEPTH(2),.BANK_DEPTH(3)) sender(
.i_clk(clk),.i_rstn(rstn),.i_taken(taken[side]),.i_pending(pending[side]),.i_auth(1'b{a.auth}),.i_done(peer_done[side]),.i_shared(peer_shared[side]),.i_available(available[side]),.i_capacity(capacity[side]),.i_request_budget(state[side][9:7]),.i_response_budget(state[side][6:3]),
.i_source_valid(hv[side]),.i_source_control(hd[side]),.i_source_tags_valid(2'b11),.i_source_tags(1024'd0),.o_source_captured(captured[side]),.o_source_ready(source_ready[side]),.o_prepare_error(prep_error[side]),.o_prepare_shortfall(prep_short[side]),
.i_data_valid(dv[side]),.i_data0(d0[side]),.i_data1(d1[side]),.i_fc_valid(fv[side]),.i_fc_flit(fc[side]),.i_fc_msg(fm[side]),.o_valid(pv[side]),.o_flit(tx[side]),.o_msg(tm[side]),.o_header_taken(ht[side]),.o_data_taken(dt[side]),.o_fc_taken(fct[side]),.o_header_error(head_error[side]),.o_capacity_shortfall(shortfall[side]),.o_data_accepted(da[side]),.o_data_ready(dr[side]),.o_input_error(input_error[side]),.o_header_count(hcount[side]),.o_data_count(dcount[side]));
// 只有DL正常payload接纳扣TL信用；重放不消费TL发送源。
tl_credit_admitted_port #(.WIDTH(8)) credit(
.i_clk(clk),.i_rstn(rstn),.i_receive(dlrx[side]),.i_send(dlaccept[side]),.i_auth(1'b{a.auth}),.i_rx_flit(rxdata[side][511:0]),.i_rx_msg(rxdata[side][513:512]),.i_tx_flit(tx[side]),.i_tx_msg(tm[side]),.o_rx_taken(ptake[side]),.o_tx_allowed(allow_tx[side]),.o_tx_taken(taken[side]),.o_fatal(portfatal[side]),.o_done(peer_done[side]),.o_shared(peer_shared[side]),.o_capacity(capacity[side]),.o_available(available[side]),.o_tx_pending(pending[side]),.o_tx_validation_state(state[side]));
tl_receive_credit #(.WIDTH(8),.DEPTH(40)) receive_storage(
.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_shared(1'b{a.shared}),.i_auth(1'b{a.auth}),.i_capacities({{20{{8'd1}}}}),.o_config_error(config_error[side]),.i_valid(dlrx[side]),.i_flit(rxdata[side][511:0]),.i_msg(rxdata[side][513:512]),.o_taken(rtake[side]),.o_fatal(rxfatal[side]),.i_read_ready(read_ready[side]),.o_read_valid(read_valid[side]),.o_read_flit(read_flit[side]),.o_read_msg(read_msg[side]),.o_read_classes(classes[side]),.o_read_releases(releases[side]),.o_retired(ret[side]),.i_fc_send(fct[side]),.o_fc_valid(fv[side]),.o_fc_taken(ft[side]),.o_fc_flit(fc[side]),.o_fc_msg(fm[side]),.o_done(done[side]),.o_pending(pub[side]),.o_count(rxcount[side]),.o_release_taken(rel[side]));
// 520位是不透明本地测试记录，不是标准640-byte DL线格式。
dl_replay_data_port #(.C_DEPTH({a.depth}),.C_DATA_WIDTH(520)) replay_port(
.i_clk(clk),.i_rstn(rstn),.i_link_reset(1'b0),.i_rx_event_valid(linkvalid[side][{a.delay-1}]),.i_rx_event_discard(1'b0),.i_rx_crc_ok(linkcrc[side][{a.delay-1}]),.i_rx_header(linkheader[side][{a.delay-1}]),.i_rx_replay_limit(8'd50),.i_rx_data(linkdata[side][{a.delay-1}]),
.i_flit_request(reserve[side]),.i_new_group(1'b1),.i_payload(pv[side]&&allow_tx[side]),.i_data({{6'd0,tm[side],tx[side]}}),.o_payload_accept(dlaccept[side]),.o_issue_replay(issuereplay[side]),.o_issue_sequence(seq[side]),.o_out_valid(dlvalid[side]),.o_out_payload(dlpayload[side]),.o_out_replay(dlreplay[side]),.o_out_sequence(outseq[side]),.o_out_header(dlheader[side]),.o_out_data(dldata[side]),.o_rx_payload_accept(dlrx[side]),.o_rx_data(rxdata[side]),.o_tag_error(tag_error[side]),.o_issue_metadata_error(metadata_error[side]),.o_ctl_unacked_count(unacked[side]),.o_ctl_scheduled_count(scheduled[side]));
end endgenerate
always @(posedge clk)begin
if(!rstn)begin
for(e=0;e<2;e=e+1)begin
for(c=0;c<2;c=c+1)begin wh[e][c]<=0;wd[e][c]<=0;end
originals[e]=0;crcs[e]=0;drops[e]=0;replays[e]=0;stalls[e]=0;retirements[e]=0;crc_sent[e]=0;drop_sent[e]=0;
for(j=0;j<{a.delay};j=j+1)begin linkvalid[e][j]<=0;linkheader[e][j]<=0;linkdata[e][j]<=0;linkcrc[e][j]<=1;end
end
end else begin
for(e=0;e<2;e=e+1)begin
$fdisplay(trace,"Q %h %h %h %h %h %h %h %h",cycle,e,rxcount[e],available[e],capacity[e],pub[e],unacked[e],scheduled[e]);
if(ret[e])begin $fdisplay(trace,"S %h %h %h",cycle,e,{{releases[e],classes[e],read_msg[e],read_flit[e]}});retirements[e]=retirements[e]+1;end
// 只有DL完成接纳/去重的记录进入TL；外部链路没有TL ready旁路。
if(dlrx[e])$fdisplay(trace,"D %h %h %h %h %h",cycle,e,rxdata[e],ptake[e],rtake[e]);
if(taken[e])$fdisplay(trace,"T %h %h %h %h %h %h %h %h",cycle,e,tm[e],tx[e],ht[e],dt[e],fct[e],seq[e]);
if(portfatal[e]||rxfatal[e]||head_error[e]||input_error[e]||prep_error[e]||prep_short[e]||shortfall[e]||config_error[e]||tag_error[e]||metadata_error[e])$fatal(1,"actual RTL error side=%0d",e);
if(dlaccept[e]!==taken[e]||((ht[e]||dt[e]||fct[e])&&!dlaccept[e])||(issuereplay[e]&&taken[e]))$fatal(1,"TL/DL consume atomicity");
if(dlrx[e]&&(!ptake[e]||!rtake[e]))$fatal(1,"TL rejected DL accepted payload");
if(ret[e]!==rel[e]||ft[e]!==fct[e])$fatal(1,"credit retirement atomicity");
if(pv[e]&&!taken[e])stalls[e]=stalls[e]+1;
for(c=0;c<2;c=c+1)begin
wh[e][c]<=wh[e][c]+captured[e][c];wd[e][c]<=wd[e][c]+da[e][c*2+:2];
end
for(j=1;j<{a.delay};j=j+1)begin linkvalid[e][j]<=linkvalid[e][j-1];linkheader[e][j]<=linkheader[e][j-1];linkdata[e][j]<=linkdata[e][j-1];linkcrc[e][j]<=linkcrc[e][j-1];end
linkvalid[1-e][0]<=dlvalid[e];linkheader[1-e][0]<=dlheader[e];linkdata[1-e][0]<=dldata[e];linkcrc[1-e][0]<=1;
if(dlvalid[e])begin
if(dlpayload[e]&&!dlreplay[e])originals[e]=originals[e]+1;
drop_now=0;crc_now=1;
if({int(a.inject)}&&dlpayload[e]&&!dlreplay[e]&&originals[e]==5&&!crc_sent[e])begin crc_now=0;crc_sent[e]=1;crcs[e]=crcs[e]+1;end
if({int(a.inject)}&&dlpayload[e]&&!dlreplay[e]&&originals[e]==12&&!drop_sent[e])begin drop_now=1;drop_sent[e]=1;drops[e]=drops[e]+1;end
if(dlreplay[e])replays[e]=replays[e]+1;
linkvalid[1-e][0]<=!drop_now;linkcrc[1-e][0]<=crc_now;
$fdisplay(trace,"W %h %h %h %h %h %h %h %h %h",cycle,e,dlpayload[e],dlreplay[e],outseq[e],dlheader[e],dldata[e],drop_now,crc_now);
end
end
end
end
initial begin
trace=$fopen("trace.txt","w");
{chr(10).join(reads)}
repeat(3)@(negedge clk);rstn=1;start=1;@(negedge clk);start=0;
while(cycle<20000&&quiet<({a.delay}+20))begin
@(negedge clk);cycle=cycle+1;
if({'&&'.join(done)})quiet=quiet+1;else quiet=0;
end
if(cycle>=20000)$fatal(1,"drain timeout heads=%h/%h pending=%0d/%0d dl=%0d/%0d",hcount[0],hcount[1],pending[0],pending[1],unacked[0],unacked[1]);
if(!stalls[0]||!stalls[1]||!retirements[0]||!retirements[1])$fatal(1,"backpressure/retirement coverage missing");
if({int(a.inject)}&&(!replays[0]||!replays[1]||!crcs[0]||!crcs[1]||!drops[0]||!drops[1]))$fatal(1,"fault recovery coverage missing");
$display("PASS cycles=%0d original=%0d/%0d replay=%0d/%0d stalls=%0d/%0d retired=%0d/%0d",cycle,originals[0],originals[1],replays[0],replays[1],stalls[0],stalls[1],retirements[0],retirements[1]);$finish;
end
endmodule
'''
    if a.fault == 'replay_data':
        text = text.replace('linkdata[1-e][0]<=dldata[e];', "linkdata[1-e][0]<=dldata[e] ^ ((dlreplay[e]&&dlpayload[e]&&(dldata[e][511:256]!=0)&&(dldata[e][513:512]==0))?(520'd1<<300):520'd0);")
    elif a.fault == 'tl_consume':
        text = text.replace('.i_taken(taken[side])', '.i_taken(reserve[side]&&pv[side])')
    elif a.fault == 'retire_data':
        text = text.replace('.i_flit(rxdata[side][511:0])', ".i_flit(rxdata[side][511:0]^(((rxdata[side][511:256]!=0)&&(rxdata[side][513:512]==0))?(512'd1<<300):512'd0))")
    elif a.fault == 'rx_duplicate':
        text = text.replace('.i_receive(dlrx[side])', f'.i_receive(dlrx[side]||(linkvalid[side][{a.delay-1}]&&linkheader[side][{a.delay-1}][20]))')
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kd28-root', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--depth', type=int, default=3)
    parser.add_argument('--delay', type=int, default=3)
    parser.add_argument('--count', type=int, default=24)
    parser.add_argument('--auth', type=int, choices=(0, 1), default=0)
    parser.add_argument('--shared', type=int, choices=(0, 1), default=0)
    parser.add_argument('--inject', action='store_true')
    parser.add_argument('--fault', choices=('none', 'replay_data', 'tl_consume', 'rx_duplicate', 'retire_data'), default='none')
    a = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', a.label):
        parser.error('label must be one safe directory name')
    if not 1 <= a.depth <= 255 or not 1 <= a.delay <= 32 or not 8 <= a.count <= 1024:
        parser.error('depth 1..255, delay 1..32, count 8..1024 required')
    if a.fault != 'none' and not a.inject:
        parser.error('fault challenges require --inject')
    external_root = a.kd28_root.resolve(strict=True) / 'Library/models/kd28'
    external = [external_root / 'sram/rtl' / name for name in ('kd28_sram_sp_model.v', 'kd28_sram_sdp_model.v', 'kd28_sram_tdp_model.v', 'kd28_sram_cells.v')] + [external_root / 'fifo/rtl/kd28_fifo_sdp_storage_map.v']
    for path in external:
        if not path.is_file():
            parser.error('missing explicit SRAM dependency: ' + str(path))
    directory = ROOT / 'build/verification/endpoint_link' / a.label
    directory.mkdir(parents=True, exist_ok=False)
    streams = [[fixtures(e, r, a.count) for r in range(2)] for e in range(2)]
    for e in range(2):
        for r in range(2):
            for key in ('headers', 'data'):
                (directory / f'{key}{e}{r}.hex').write_text('\n'.join(streams[e][r][key]) + '\n')
    config = {k: v for k, v in vars(a).items() if k != 'kd28_root'} | dict(fixtures=streams, capacities=[1] * 20)
    (directory / 'case.json').write_text(json.dumps(config, indent=2) + '\n')
    tb = directory / 'tb.sv'
    tb.write_text(bench(a, streams))
    sources = sorted((ROOT / 'rtl/tl').glob('*.v')) + [ROOT / 'rtl/upli' / n for n in ('upli_receive_fifo.v', 'upli_receive_storage.v')] + [ROOT / 'rtl/dl' / n for n in ('dl_replay_data_port.v', 'dl_replay_tx_storage.v', 'dl_replay_tx_control.v', 'dl_replay_event_port.v', 'dl_replay_receiver.v', 'dl_replay_header_tx.v')]
    reference_sources = [ROOT / 'model/tl' / n for n in ('credit_context.py', 'receive_context.py', 'tl_sequence.py', 'tl_tenure.py')]
    command = ['iverilog', '-g2012', '-s', 'tb', '-o', str(directory / 'sim.vvp'), str(tb)] + [str(p) for p in sources + external]
    record = dict(evidence_layer='integrated_rtl', compile_command=command, run_command=['vvp', str(directory / 'sim.vvp')], sources={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources + external + reference_sources + [tb, Path(__file__), ROOT / 'verification/endpoint_link/check.py']})
    for tool in ('iverilog', 'vvp'):
        version = subprocess.run([tool, '-V'], capture_output=True, text=True, timeout=20)
        (directory / f'{tool}_version.txt').write_text(version.stdout + version.stderr)
    try:
        with (directory / 'compile.log').open('w') as log:
            record['compile_exit'] = subprocess.run(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT, timeout=180).returncode
        if record['compile_exit'] == 0:
            with (directory / 'run.log').open('w') as log:
                record['run_exit'] = subprocess.run(record['run_command'], cwd=directory, stdout=log, stderr=subprocess.STDOUT, timeout=180).returncode
            if record['run_exit'] == 0:
                with (directory / 'audit.log').open('w') as log:
                    record['audit_exit'] = subprocess.run([sys.executable, str(ROOT / 'verification/endpoint_link/check.py'), str(directory)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=60).returncode
    except subprocess.TimeoutExpired as error:
        record['timeout'] = str(error)
    record['passed'] = all(record.get(k) == 0 for k in ('compile_exit', 'run_exit', 'audit_exit'))
    record['artifacts'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in directory.iterdir() if p.is_file()}
    (directory / 'record.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(dict(directory=str(directory), passed=record['passed'], compile_exit=record.get('compile_exit'), run_exit=record.get('run_exit'), audit_exit=record.get('audit_exit'))))
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
