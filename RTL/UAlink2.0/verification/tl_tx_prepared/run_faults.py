"""Run: python3 verification/tl_tx_prepared/run_faults.py [--label faults].
Requires prepared_top_peers healthy actual SRAM/credit runs. Recompiles eleven real
wrapper wiring mutations against the unchanged independent healthy fixtures at
WIDTH 8/16, Auth/shared enabled, delay three. Saves mutated RTL, full testbench,
fixtures, traces and compile/run diagnostics under tl_tx_prepared/LABEL. A tool
timeout or compile error is not a detection. Next audit exact failed assertions.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
FAULTS={
 'capture_without_tags':('.i_source_valid(i_source_valid[lane]&&tags_ready)','.i_source_valid(i_source_valid[lane])'),
 'wrong_response_class':('.i_response(RESPONSE)',".i_response(1'b0)"),
 'advance_while_queue_full':('.i_ready(partition_ready[lane])',".i_ready(1'b1)"),
 'source_ready_at_retire':('o_source_ready[lane]=capture_ready&&tags_ready','o_source_ready[lane]=o_group_queued[lane]&&tags_ready'),
 'wrong_source_lane':('i_source_control[lane*256+:256]','i_source_control[(1-lane)*256+:256]'),
 'wrong_tag_lane':('i_source_tags[lane*512+:512]','i_source_tags[(1-lane)*512+:512]'),
 'live_buffer_header':('.i_headers(partition_control)','.i_headers(i_source_control)'),
 'tags_ack_at_enqueue':('o_source_tags_taken[lane]=i_auth&&o_source_captured[lane]','o_source_tags_taken[lane]=i_auth&&o_partition_taken[lane]'),
 'live_buffer_tags':('.i_tags(partition_tags)','.i_tags(i_source_tags[511:0])'),
 'swapped_data_lanes':('.i_data0(i_data0)','.i_data0({i_data0[255:0],i_data0[511:256]})'),
 'blocked_fc':('.i_fc_valid(i_fc_valid)',".i_fc_valid(1'b0)"),
}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',default='faults');p.add_argument('--peers-label',default='prepared_top_peers');a=p.parse_args()
    if not all(n.replace('_','').replace('-','').isalnum() for n in (a.label,a.peers_label)):p.error('invalid label')
    healthy=ROOT/'build/verification/tl_control_partition'/a.peers_label;original=json.loads((healthy/'results.json').read_text())
    if not original['complete']:raise ValueError('complete healthy matrix required')
    for name,digest in original['sources'].items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest()!=digest:raise ValueError('healthy source changed')
    stage=ROOT/'build/verification/tl_tx_prepared'/a.label;stage.mkdir(parents=True,exist_ok=False);source=(ROOT/'rtl/tl/tl_tx_prepared.v').read_text();report=dict(complete=False,peers_label=a.peers_label,source_sha256=hashlib.sha256(source.encode()).hexdigest(),healthy_sha256=hashlib.sha256((healthy/'results.json').read_bytes()).hexdigest(),results=[])
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    for fault,(old,new) in FAULTS.items():
        if source.count(old)!=1:raise ValueError('ambiguous mutation '+fault)
        folder=stage/fault;folder.mkdir();candidate=folder/'tl_tx_prepared.v';candidate.write_text(source.replace(old,new))
        for width in (8,16):
            src=healthy/f'w{width}_a1_s1_l3';dest=folder/f'w{width}';dest.mkdir()
            for fixture in src.glob('*.hex'):(dest/fixture.name).write_bytes(fixture.read_bytes())
            tb=dest/'tb.sv';tb.write_text((src/'tb.sv').read_text().replace(str(src),str(dest)))
            files=[candidate if Path(n).name=='tl_tx_prepared.v' else Path(n) for n in original['sources']]
            compile_run=subprocess.run(['iverilog','-g2012','-s','tb','-o',str(dest/'sim.vvp'),*map(str,files),str(tb)],capture_output=True,text=True,timeout=90);(dest/'compile.log').write_text(compile_run.stdout+compile_run.stderr);row=dict(fault=fault,width=width,auth=1,shared=1,delay=3,compile_exit=compile_run.returncode,candidate_sha256=hashlib.sha256(candidate.read_bytes()).hexdigest(),detected=False)
            if compile_run.returncode==0:
                try:
                    run=subprocess.run(['vvp',str(dest/'sim.vvp')],capture_output=True,text=True,timeout=120);log=run.stdout+run.stderr;(dest/'run.log').write_text(log);row.update(run_exit=run.returncode,detected=run.returncode!=0 and 'FATAL:' in log)
                except subprocess.TimeoutExpired as error:
                    (dest/'run.log').write_bytes((error.stdout or b'')+(error.stderr or b''));row.update(run_exit=124)
            report['results'].append(row);(stage/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(fault,width,row['detected'],flush=True)
    report['complete']=len(report['results'])==len(FAULTS)*2 and all(r['detected'] for r in report['results']);(stage/'results.json').write_text(json.dumps(report,indent=2)+'\n');return 0 if report['complete'] else 1


if __name__=='__main__':raise SystemExit(main())
