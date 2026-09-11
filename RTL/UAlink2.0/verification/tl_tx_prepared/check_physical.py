"""Run python3 verification/tl_tx_prepared/check_physical.py --label physical_baseline
[--output FILE]. Audit 60 actual top measurements, exact sources/libraries and
mapped macro/clock/area inventory. Output measurement evidence with open timing.
Next mapped equivalence and real timing repair; this is not macro/IP signoff.
"""
from pathlib import Path
from collections import Counter
import argparse
import hashlib
import json
import math
import re
from timing_report import measure

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'build/verification/tl_tx_prepared'
CORNERS=('tt0p9v25c','ssg0p81v125c','ssg0p81vm40c','ffg0p99v125c','ffg0p99vm40c')


def need(ok,message):
    if not ok:raise ValueError(message)


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def inventory(graph):
    top=graph['modules']['tl_tx_prepared'];clock=top['ports']['i_clk']['bits'];counts=Counter()
    macros=[];flops=[]
    for name,cell in top['cells'].items():
        kind=cell['type'];counts[kind]+=1
        need(kind in graph['modules'],'missing cell declaration')
        if kind.startswith('KD28'):
            need(kind=='KD28_SRAM_SDP_256X32','unexpected macro class')
            expected=dict(WCLK=1,RCLK=1,WCS=1,RCS=1,WA=8,RA=8,WM=4,D=32,Q=32)
            need({n:len(v) for n,v in cell['connections'].items()}==expected,'incomplete macro interface')
            need(cell['connections']['WCLK']==clock and cell['connections']['RCLK']==clock,'macro clock mismatch');macros.append(name)
        else:
            need(kind.endswith('BWP40P140') and not kind.startswith('$'),'unmapped/foreign cell')
            if kind.startswith('DF'):
                need(kind=='DFQD2BWP40P140' and cell['connections']['CP']==clock,'nonpositive/raw FF clock mismatch');flops.append(name)
            else:need(not any(n in cell['connections'] for n in ('CP','CK','G','GN')),'unexpected sequential/gated-clock primitive')
    need(len(macros)==64 and len(flops) in (6254,6574),'unexpected state/macro count')
    return dict(cells=len(top['cells']),macros=len(macros),flops=len(flops),cell_counts=dict(sorted(counts.items())),single_positive_clock=True)


def cell_areas(library):
    source=library.read_text();starts=list(re.finditer(r'\bcell\s*\(\s*([^\s)]+)\s*\)\s*\{',source));result={}
    for index,match in enumerate(starts):
        block=source[match.end():starts[index+1].start() if index+1<len(starts) else len(source)]
        found=re.findall(r'\barea\s*:\s*([0-9.eE+-]+)\s*;',block)
        need(len(found)==1,'missing/ambiguous standard-cell area');result[match[1].strip('"')]=float(found[0])
    need(result and all(math.isfinite(x) and x>0 for x in result.values()),'invalid cell area')
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--output',type=Path);a=p.parse_args()
    need(a.label.replace('_','').replace('-','').isalnum(),'invalid label');stage=BASE/a.label
    report=json.loads((stage/'results.json').read_text());need(report['complete'],'incomplete measured matrix')
    need({r['width'] for r in report['results']}=={8,16} and len(report['results'])==2,'width matrix')
    need(set(report['libraries'])==set(CORNERS) and set(report['synthetic_macros'])=={'fast','typical','slow'},'library matrix')
    for name,digest in report['sources'].items():
        source=Path(name);need(sha(source)==digest,'changed source '+name)
        if source.is_relative_to(ROOT/'rtl'):need(sha(stage/'sources'/source.name)==digest,'snapshot mismatch')
        if source.is_relative_to(ROOT/'scripts'):need(sha(stage/source.name)==digest,'script snapshot mismatch')
    for group in ('libraries','synthetic_macros'):
        for row in report[group].values():need(sha(Path(row['path']))==row['sha256'],'changed library')
    need(sha(Path(report['sta']['path']))==report['sta']['sha256'],'changed STA executable')
    for snapshot,source in (('runner.py','run_physical.py'),('timing_report.py','timing_report.py')):
        need((stage/snapshot).read_bytes()==Path(__file__).with_name(source).read_bytes(),'changed runner/parser')
    areas=cell_areas(Path(report['libraries']['ssg0p81v125c']['path']));results=[]
    ownership_manifest=json.loads((BASE/'ownership_manifest.json').read_text())
    for row in report['results']:
        width=row['width'];folder=stage/f'w{width}';need(row['mapping']['exit']==0,'mapping failure')
        need(sha(folder/'mapped.v')==row['netlist_sha256'] and sha(folder/'mapped.json')==row['graph_sha256'],'mapped artifact changed')
        graph=json.loads((folder/'mapped.json').read_text());inv=inventory(graph)
        original=BASE/'ownership_final'/f'w{width}_d2/original.json'
        need(ownership_manifest['evidence_files'][str(original.relative_to(ROOT))]==sha(original),'unbound original top graph')
        original_ports=json.loads(original.read_text())['modules']['tl_tx_prepared']['ports']
        interface=lambda ports:{n:(p['direction'],len(p['bits'])) for n,p in ports.items()}
        need(interface(graph['modules']['tl_tx_prepared']['ports'])==interface(original_ports),'mapped public interface changed')
        need((inv['cells'],inv['flops'],inv['macros'])==(row['cells'],row['ff_cells'],row['macro_cells']),'reported mapped counts differ')
        total=sum(areas[k]*n for k,n in inv['cell_counts'].items() if not k.startswith('KD28'))
        need(abs(total-row['standard_cell_area_um2'])<0.00001,'actual Liberty area differs')
        matrix={(x['corner'],x['view'],x['period']) for x in row['sta']}
        need(len(row['sta'])==30 and matrix=={(c,v,p) for c in CORNERS for v in ('fast','typical','slow') for p in ('0.640','6.400')},'missing/duplicate STA profile')
        metrics=[]
        for item in row['sta']:
            name=f'{item["corner"]}_{item["view"]}_{item["period"]}';log=folder/(name+'.log');text=log.read_text()
            need(sha(log)==item['log_sha256'],'changed STA log')
            need(re.findall(r'^\s*time\s+(\S+)\s*$',text,re.M)==['1ns'] and re.findall(r'^\s*capacitance\s+(\S+)\s*$',text,re.M)==['1pF'],'wrong STA units')
            found=measure(text,width=width,view=item['view'],period=item['period'],exit_code=item['run']['exit'])
            need(all(item.get(k)==v for k,v in found.items()),'measurement report differs from raw log')
            command=json.loads((folder/(name+'_command.json')).read_text())
            expected=dict(UALINK_LIBERTY=report['libraries'][item['corner']]['path'],UALINK_MACRO_LIBERTY=report['synthetic_macros'][item['view']]['path'],UALINK_NETLIST=str(folder/'mapped.v'),UALINK_WIDTH=str(width),UALINK_MACRO_VIEW=item['view'],UALINK_PERIOD_NS=item['period'])
            need(command==['env',*[k+'='+v for k,v in expected.items()],report['sta']['path'],'-exit',str(ROOT/'scripts/sta_tl_tx_prepared.tcl')],'STA command did not use declared artifacts')
            metrics.append(dict(corner=item['corner'],view=item['view'],period=item['period'],**found))
        for corner in CORNERS:
            for view in ('fast','typical','slow'):
                modes={x['period']:x for x in metrics if x['corner']==corner and x['view']==view}
                need(abs(modes['6.400']['setup_slack_ns']-modes['0.640']['setup_slack_ns']-5.760)<=0.000003,'clock-period experiment mismatch')
                need(abs(modes['6.400']['hold_slack_ns']-modes['0.640']['hold_slack_ns'])<=0.000003,'hold unexpectedly depends on period')
        results.append(dict(width=width,inventory=inv,standard_cell_area_um2=round(total,6),measurements=metrics))
    evidence=dict(complete=True,scope='actual standard-cell top mapping and synthetic SRAM prelayout measurements',
                  results=results,measurements=60,main_closed=sum(x['timing_closed'] for r in results for x in r['measurements'] if x['period']=='0.640'),
                  reference_closed=sum(x['timing_closed'] for r in results for x in r['measurements'] if x['period']=='6.400'),mapped_equivalence=False,macro_signoff=False,full_goal_complete=False)
    output=a.output or stage/'evidence.json';output.write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({k:v for k,v in evidence.items() if k!='results'},indent=2))


if __name__=='__main__':main()
