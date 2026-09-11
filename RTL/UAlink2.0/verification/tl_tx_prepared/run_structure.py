"""Run: python3 verification/tl_tx_prepared/run_structure.py --kd28-root PATH [--label structure].
Strict Verilog-2001 lint uses actual authorized SRAM models (only the existing
external DECLFILENAME waiver). Yosys structural synthesis uses their declared
blackboxes; records every actual FF and SRAM clock, rejects latches/other clocks.
Outputs logs/netlists/source identities in build/verification/tl_tx_prepared.
Next actual process mapping and top STA; blackbox structure is not macro timing.
"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[2]


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='structure');a=p.parse_args()
    if not a.label.replace('_','').replace('-','').isalnum():p.error('invalid label')
    stage=ROOT/'build/verification/tl_tx_prepared'/a.label;stage.mkdir(parents=True,exist_ok=False)
    src=sorted((ROOT/'rtl/tl').glob('*.v'))+[ROOT/'rtl/upli/upli_receive_fifo.v',ROOT/'rtl/upli/upli_receive_storage.v'];external=a.kd28_root/'Library/models/kd28';models=[external/'sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')];mapping=external/'fifo/rtl/kd28_fifo_sdp_storage_map.v';blackboxes=external/'sram/rtl/kd28_sram_blackboxes.v';vlt=ROOT/'config/kd28_verilator.vlt'
    report=dict(complete=False,sources={str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in src+models+[mapping,blackboxes,vlt]},results=[],process_sta=False)
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    for width in (8,16):
        lint=subprocess.run(['verilator','--lint-only','--language','1364-2001','-Wall','--timescale-override','1ps/1ps','--top-module','tl_tx_prepared',f'-GWIDTH={width}',str(vlt),*map(str,src+models+[mapping])],capture_output=True,text=True,timeout=180);(stage/f'lint_{width}.log').write_text(lint.stdout+lint.stderr)
        script='read_verilog '+' '.join('"'+str(x)+'"' for x in src+[blackboxes,mapping])+f'\nchparam -set WIDTH {width} tl_tx_prepared\nsynth -flatten -noabc -top tl_tx_prepared\ncheck -assert\nwrite_json {stage}/synth_{width}.json\nstat\n';(stage/f'synth_{width}.ys').write_text(script)
        syn=subprocess.run(['yosys','-Q','-T','-s',str(stage/f'synth_{width}.ys')],capture_output=True,text=True,timeout=240);(stage/f'synth_{width}.log').write_text(syn.stdout+syn.stderr)
        row=dict(width=width,lint_exit=lint.returncode,synthesis_exit=syn.returncode,passed=False)
        if syn.returncode==0:
            graph=json.loads((stage/f'synth_{width}.json').read_text())['modules']['tl_tx_prepared'];clock=graph['ports']['i_clk']['bits'];cells=graph['cells'];ff=[c for c in cells.values() if 'DFF' in c['type'] or 'LATCH' in c['type']];macros=[c for c in cells.values() if c['type'].startswith('KD28_SRAM')]
            sync=all(re.match(r'^\$_(?:DFF|DFFE|SDFF|SDFFE|SDFFCE)_P',c['type']) and c['connections'].get('C')==clock for c in ff)
            macroclock=all(c['connections']['RCLK']==clock and c['connections']['WCLK']==clock for c in macros)
            row.update(cells=len(cells),ff_bits=sum(len(c['connections'].get('Q',[])) for c in ff),ff_types=sorted({c['type'] for c in ff}),sram_cells=len(macros),single_positive_clock=bool(sync and macroclock),passed=lint.returncode==0 and len(macros)==64 and bool(ff) and bool(sync and macroclock))
        report['results'].append(row);(stage/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(row,flush=True)
    report['complete']=len(report['results'])==2 and all(r['passed'] for r in report['results']);(stage/'results.json').write_text(json.dumps(report,indent=2)+'\n');return 0 if report['complete'] else 1


if __name__=='__main__':raise SystemExit(main())
