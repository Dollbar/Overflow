"""Run: python3 [-O] verification/tl_tx_prepared/check_evidence.py.
Audits final production-wrapper evidence: exact sources, independent capture and
wire reports, all unit bits/reset counterexamples, actual wiring mutations,
structural clocks/SRAM count, decoder format equivalence and artifact gate.
Writes build/verification/tl_tx_prepared/evidence.json. Next full combined-top
formal relation and actual process STA; this is not complete IP signoff.
"""
from pathlib import Path
import hashlib,json,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
from check_capture import check as check_capture,need
from run_faults import FAULTS
STAGE=ROOT/'build/verification/tl_tx_prepared'
PEERS=ROOT/'build/verification/tl_control_partition'
REFERENCE='cdc943ca8e38fb3b67e4671049afa5c36968bc40'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text())

def identities(report):
    for name,digest in report['sources'].items():need(sha(Path(name))==digest,'compiled source identity '+name)

def numbers(path):
    lines=path.read_text().splitlines();need(all(re.fullmatch('[0-9a-fA-F]+',x) and int(x,16)<1<<1064 for x in lines),'complete binary preparation output')
    return [int(x,16) for x in lines]


def main():
    captures={}
    for label in ('prepared_top_final_peers','prepared_top_final_minimum'):
        r=read(PEERS/label/'results.json');identities(r)
        need(sorted((x['width'],x['auth'],x['shared'],x['delay']) for x in r['results'])==sorted((w,a,s,d) for w in (8,16) for a in (0,1) for s in (0,1) for d in (1,3)),'complete integrated peer matrix')
        captures[label]=check_capture(PEERS/label)
        for row in r['results']:
            b=PEERS/label/f'w{row["width"]}_a{row["auth"]}_s{row["shared"]}_l{row["delay"]}'
            tb=(b/'tb.sv').read_text();need('tl_tx_prepared #' in tb and 'source_owned' not in tb and 'tl_control_partition #' not in tb,'production wrapper without retirement shim')
            need(row['compile_exit']==row['run_exit']==0 and 'PASS prepared production captures' in (b/'run.log').read_text(),'actual integrated runtime')
    wire=read(PEERS/'prepared_top_final_wire_evidence.json')
    need(wire==read(PEERS/'prepared_top_final_wire_evidence_optimized.json') and wire['actual_configs']==32 and wire['scope']=='actual_peer_traces_only','ordinary/optimized full actual-wire audit')
    unit=STAGE/'unit_final';report=read(unit/'results.json');identities(report)
    need(report['complete'] and sorted((r['width'],r['auth'],r['depth']) for r in report['results'])==[(w,a,d) for w in range(8,17) for a in (0,1) for d in (1,3)],'all 36 reset/tag/queue cases')
    coverage={}
    for row in report['results']:
        b=unit/f'w{row["width"]}_a{row["auth"]}_d{row["depth"]}'
        actual=numbers(b/'actual.hex');expected=numbers(b/'expected.hex')
        need(row['compile_exit']==row['run_exit']==0 and row['passed'] and len(actual)==len(expected)==row['vectors']==160 and actual==expected,'all actual 1064 preparation bits and vectors')
        need('PASS prepared integration' in (b/'run.log').read_text() and 'if(rstn&&hc!==' in (b/'tb.sv').read_text(),'actual bounded FIFO occupancy assertion executed')
        for name,n in row['coverage'].items():coverage[name]=coverage.get(name,0)+n
        need(all(row['coverage'][n]>0 for n in ('captured','error','shortfall','reset_owned','reset_queued','held_source_noise')),'per-case owned/queued/error/reset coverage')
        if row['auth']:need(row['coverage']['missing_tags']>0,'per-auth missing tags coverage')
    faults=read(STAGE/'faults_final/results.json');healthy=PEERS/'prepared_top_final_peers/results.json'
    source=(ROOT/'rtl/tl/tl_tx_prepared.v').read_text();need(faults['complete'] and faults['source_sha256']==sha(ROOT/'rtl/tl/tl_tx_prepared.v') and faults['healthy_sha256']==sha(healthy),'same healthy source and wire negative matrix')
    need(sorted((r['fault'],r['width']) for r in faults['results'])==sorted((f,w) for f in FAULTS for w in (8,16)),'eleven actual faults at two widths')
    for row in faults['results']:
        folder=STAGE/'faults_final'/row['fault'];old,new=FAULTS[row['fault']]
        need(source.count(old)==1 and (folder/'tl_tx_prepared.v').read_text()==source.replace(old,new) and sha(folder/'tl_tx_prepared.v')==row['candidate_sha256'],'one intended actual wrapper mutation')
        b=folder/f'w{row["width"]}';ref=PEERS/'prepared_top_final_peers'/f'w{row["width"]}_a1_s1_l3'
        for fixture in ref.glob('*.hex'):need(sha(fixture)==sha(b/fixture.name),'unchanged independent faulty-run fixture')
        need((b/'tb.sv').read_text()==(ref/'tb.sv').read_text().replace(str(ref),str(b)),'same actual negative testbench')
        need(row['compile_exit']==0 and row['detected'] and row['run_exit'] not in (0,124) and 'FATAL:' in (b/'run.log').read_text(),'real assertion failure, not compile/tool timeout')
    reset=read(STAGE/'reset_fault_unit_final/results.json');identities(reset)
    need(not reset['complete'] and sorted((r['width'],r['auth'],r['depth']) for r in reset['results'])==[(w,a,d) for w in (8,16) for a in (0,1) for d in (1,3)],'reset fault matrix')
    old='.i_rstn(i_rstn),.i_source_valid';new='.i_rstn(i_rstn||i_source_valid[lane]),.i_source_valid'
    need(source.count(old)==1 and (STAGE/'reset_fault/tl_tx_prepared.v').read_text()==source.replace(old,new),'actual preparation reset bypass')
    for row in reset['results']:
        suffix=f'w{row["width"]}_a{row["auth"]}_d{row["depth"]}';b=STAGE/'reset_fault_unit_final'/suffix;ref=unit/suffix
        for name in ('vectors.hex','expected.hex','queue_expected.hex'):need(sha(b/name)==sha(ref/name),'same independent reset stimuli/expectations')
        actual=numbers(b/'actual.hex');expected=numbers(b/'expected.hex');need([i for i,x in enumerate(actual) if x!=expected[i]]==[40] and len(actual)==41,'reset bypass fails at actual occupied reset after 40 matching vectors')
        need(row['compile_exit']==0 and row['run_exit'] not in (0,124) and not row['passed'],'actual reset failure')
    structural=read(STAGE/'structure_final/results.json');identities(structural);need(structural['complete'] and sorted(r['width'] for r in structural['results'])==[8,16],'two-width complete structural check')
    for row in structural['results']:
        width=row['width'];g=read(STAGE/f'structure_final/synth_{width}.json')['modules']['tl_tx_prepared'];clk=g['ports']['i_clk']['bits'];ffs=[c for c in g['cells'].values() if 'DFF' in c['type'] or 'LATCH' in c['type']];macs=[c for c in g['cells'].values() if c['type'].startswith('KD28_SRAM')]
        need(len(macs)==64 and sum(len(c['connections'].get('Q',[])) for c in ffs)==row['ff_bits'],'complete actual state and SRAM inventory')
        need(all(re.match(r'^\$_(?:DFF|DFFE|SDFF|SDFFE|SDFFCE)_P',c['type']) and c['connections']['C']==clk for c in ffs),'no latch, asynchronous reset or nonoriginal FF clock')
        need(all(c['connections']['RCLK']==c['connections']['WCLK']==clk for c in macs),'actual SRAM clocks')
        need(row['lint_exit']==row['synthesis_exit']==0 and row['passed'] and not re.search(r'%Warning|%Error',(STAGE/f'structure_final/lint_{width}.log').read_text()),'strict authored RTL lint')
    art=read(STAGE/'artifact_final_report.json');need(art['ok'] and art['errors']==0,'complete owned RTL hierarchy artifact gate')
    for p in (STAGE/'artifact_final').rglob('*.v'):
        original=ROOT/('rtl/upli' if p.name.startswith('upli_') else 'rtl/tl')/p.name;need(sha(p)==sha(original),'artifact source identity')
    decoder=STAGE/'decoder_format';need((decoder/'gold.v').read_bytes()==subprocess.check_output(['git','show',REFERENCE+':rtl/tl/tl_control_decode.v'],cwd=ROOT),'immutable preformat decoder')
    need(sha(decoder/'gate.v')==sha(ROOT/'rtl/tl/tl_control_decode.v') and 'SAT proof finished - no model found: SUCCESS!' in (decoder/'proof.log').read_text(),'current decoder full combinational proof')
    graph=read(decoder/'miter.json')['modules']['miter'];expected={'in_i_half':('input',256),'trigger':('output',1)}
    for side in ('gold','gate'):
        for name,bits in [('o_valid',1),('o_requests',3),('o_responses',4),('o_field_starts',8),('o_request_starts',8),('o_response_starts',8)]:expected[side+'_'+name]=('output',bits)
    need({n:(p['direction'],len(p['bits'])) for n,p in graph['ports'].items()}==expected,'all original decoder input/output bits')
    need('miter -equiv -make_outputs -flatten gold gate miter' in (decoder/'proof.ys').read_text() and 'sat -prove trigger 0 -verify' in (decoder/'proof.ys').read_text() and '-set' not in (decoder/'proof.ys').read_text(),'actual no-assumption complete decoder miter')
    for name in subprocess.check_output(['git','ls-tree','-r','--name-only',REFERENCE,'model'],cwd=ROOT,text=True).splitlines():need((ROOT/name).read_bytes()==subprocess.check_output(['git','show',REFERENCE+':'+name],cwd=ROOT),'independent reference model unchanged '+name)
    result=dict(complete=True,rtl='rtl/tl/tl_tx_prepared.v',rtl_sha256=sha(ROOT/'rtl/tl/tl_tx_prepared.v'),decoder_sha256=sha(ROOT/'rtl/tl/tl_control_decode.v'),actual_peer_configs=32,capture_reports=captures,unit_configs=36,unit_vectors=5760,unit_observed_bits=1064,unit_coverage=coverage,actual_wire_fault_detections=22,actual_occupied_reset_fault_detections=8,decoder_formal_input_bits=256,decoder_formal_output_bits=32,artifact_errors=0,artifact_advisories=art['warnings'],structure=structural['results'],new_top_full_formal_equivalence=False,new_top_process_sta=False,macro_timing_signoff=False,full_goal_complete=False)
    (STAGE/'evidence.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))


if __name__=='__main__':main()
