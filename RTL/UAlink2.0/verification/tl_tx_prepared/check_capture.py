"""Run: python3 [-O] verification/tl_tx_prepared/check_capture.py --labels LABEL [LABEL ...].
Checks actual capture/source/tag/partition traces against independent Python
PreparedPartitioner models and immutable source fixtures, including advancement
on capture, FIFO stalls and same-cycle replacement. Writes capture_evidence.json
under each supplied tl_control_partition peer label. Next combine with the
existing full wire/queue/SRAM audit; this check alone is not wire correctness.
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'model/tl'))
from prepared_partition import PreparedPartitioner


def need(value,message):
    if not value:raise ValueError(message)


def check(folder):
    report=json.loads((folder/'results.json').read_text());need(report['complete'],'completed peer run')
    for name,digest in report['sources'].items():need(hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,'compiled source identity '+name)
    totals=dict(configs=0,edges=0,captures=0,tag_captures=0,groups_queued=0,partitions=0,replacements=0,missing_tag_waits=0,held_with_changed_source=0)
    for case in report['results']:
        need(case.get('integrated') and not case['prepared'] and case['passed'],'actual production wrapper mode')
        w=case['width'];auth=bool(case['auth']);b=folder/f'w{w}_a{case["auth"]}_s{case["shared"]}_l{case["delay"]}'
        sources={};tags={};models={};captured={};queued={}
        for e in (0,1):
            for c in (0,1):
                key=e,c;sources[key]=[int(x,16) for x in (b/f'sources{e}{c}.hex').read_text().splitlines()];tags[key]=[int(x,16) for x in (b/f'source_tags{e}{c}.hex').read_text().splitlines()];models[key]=PreparedPartitioner();captured[key]=queued[key]=0
        ct=(b/'capture_trace.txt').read_text().splitlines();qt=(b/'queue_trace.txt').read_text().splitlines();pt=(b/'partition_trace.txt').read_text().splitlines()
        need(len(ct)==len(qt)==len(pt)>0,'capture/queue/partition row denominator')
        for crow,qrow,prow in zip(ct,qt,pt):
            f=crow.split();need(len(f)==17,'complete capture trace schema')
            cycle,e,c,ch,wh,sv,tv,sr,sc,st,gd,pk,done,shared=map(int,f[:14]);capacity,word,tagword=[int(x,16) for x in f[14:]];key=e,c
            q=list(map(int,qrow.split()));g=prow.split();parts=list(map(int,g[:11]));pw,ptags=[int(x,16) for x in g[11:]]
            need([cycle,e,c]==q[:3]==parts[:3],'same actual clock and lane')
            need([ch,wh]==[captured[key],queued[key]] and 0<=ch-wh<=1,'one owned group and independent source/retirement counters')
            expected_word=sources[key][ch] if ch<len(sources[key]) else 0;expected_tags=tags[key][ch] if ch<len(tags[key]) else 0
            need(word==expected_word and tagword==expected_tags,'source advances only on actual capture')
            model=models[key]
            if model.owned is not None and word!=model.owned[0]:totals['held_with_changed_source']+=1
            ready_tags=not auth or bool(tv);caps=[(capacity>>(i*(w+1)))&((1<<(w+1))-1) for i in range(20)]
            out=model.step(word,tagword,caps,valid=bool(sv and ready_tags),ready=bool(q[8]),done=bool(done),response=bool(c),auth=auth,shared=bool(shared))
            need([sr,sc,st,gd,pk]==[int(out['source_ready'] and ready_tags),int(out['captured']),int(auth and out['captured']),int(out['group_done']),int(out['taken'])],'independent capture/tag/group/partition handshake')
            need([q[7],parts[5],parts[6],parts[7],pw,ptags]==[int(out['valid']),out['cursor'],out['end'],out['fields'],out['word'],out['tags']],'all prepared Control/tag bits and metadata against independent oracle')
            need(not out['error'] and not out['shortfall'],'legal fixture preparation')
            captured[key]+=sc;queued[key]+=gd
            for name,value in [('edges',1),('captures',sc),('tag_captures',st),('groups_queued',gd),('partitions',pk),('replacements',sc and gd),('missing_tag_waits',auth and sv and not tv)]:totals[name]+=int(value)
        for key in models:need(captured[key]==queued[key]==len(sources[key]) and models[key].owned is None,'all source groups captured and retired exactly once')
        totals['configs']+=1
    need(totals['replacements']>0 and totals['held_with_changed_source']>0,'actual no-shim replacement and source-change coverage')
    if any(r['auth'] for r in report['results']):need(totals['missing_tag_waits']>0,'missing source tag validity exercised')
    totals.update(complete=True,source_report_sha256=hashlib.sha256((folder/'results.json').read_bytes()).hexdigest(),scope='actual source ownership and prepared outputs; full wire audit separate',full_goal_complete=False)
    (folder/'capture_evidence.json').write_text(json.dumps(totals,indent=2)+'\n');return totals


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--labels',nargs='+',required=True);a=p.parse_args()
    for label in a.labels:
        need(label.replace('_','').replace('-','').isalnum(),'invalid label');print(label,check(ROOT/'build/verification/tl_control_partition'/label))


if __name__=='__main__':main()
