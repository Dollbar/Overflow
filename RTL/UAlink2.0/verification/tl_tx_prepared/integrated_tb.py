"""Used by tl_control_partition/run_peers.py --integrated --kd28-root PATH.
Builds a capture-driven producer around actual tl_tx_prepared, with independent
retirement and source counters and a separate ownership trace. Outputs are under
the peer run label; next run both wire/queue and capture ownership audits.
"""
import re


def replace_once(text,old,new):
    if text.count(old)!=1:raise ValueError('ambiguous testbench anchor '+old[:80])
    return text.replace(old,new)


def integrate(tb,folder,auth):
    start=tb.index(' for(lane=0;lane<2;lane=lane+1)begin:partition\n')
    end=tb.index(' assign rx[side]=',start)
    tb=tb[:start]+tb[end:]
    # Advance only the producer-indexed assignments, not the retirement scoreboard.
    lines=tb.splitlines()
    for index,line in enumerate(lines):
        if line.startswith('assign shd[') or line.startswith('assign source_auth['):
            lines[index]=line.replace('wh[','ch[')
    tb='\n'.join(lines)+'\n'
    tb=replace_once(tb,'module tb;','module tb;\ninteger ch[0:1][0:1];integer replacements=0,tag_waits=0;wire [1:0] sc[0:1],sr[0:1],sgt[0:1],stv[0:1];')
    tb=replace_once(tb,' tl_tx_buffered #',' tl_tx_prepared #')
    tb=replace_once(tb,'.i_header_valid(hv[side]),.i_headers(hd[side]),.i_tags_valid(tags_valid[side]),.i_tags(tags_in[side]),','.i_source_valid(shv[side]),.i_source_control(shd[side]),.i_source_tags_valid(stv[side]),.i_source_tags(source_auth[side]),')
    tb=replace_once(tb,'.o_header_ready(hr[side]),','.o_source_ready(sr[side]),.o_source_captured(sc[side]),.o_source_tags_taken(sgt[side]),.o_group_queued(hs[side]),.o_partition_taken(ph[side]),.o_prepare_error(partition_error[side]),.o_prepare_shortfall(partition_shortfall[side]),')
    marker=' tl_credit_admitted_port #'
    observation=''' assign stv[side]=2'b11&{2{(cycle%11!=3)&&(cycle%11!=4)}};
 assign hv[side]=scheduler.partition_valid;assign hr[side]=scheduler.partition_ready;
 assign hd[side]=scheduler.partition_control;assign tags_in[side]=scheduler.partition_tags;
 assign cursor[side]=scheduler.partition_cursor;assign partition_end[side]=scheduler.partition_end;assign partition_fields[side]=scheduler.partition_fields;
'''
    tb=replace_once(tb,marker,observation+marker)
    tb=replace_once(tb,'wh[e][c]<=0;','wh[e][c]<=0;ch[e][c]<=0;')
    tb=replace_once(tb,'if(hs[e][c])begin wh[e][c]<=wh[e][c]+1;next_h[e][c]<=cycle+(wh[e][c]%4);end','''if(hs[e][c])wh[e][c]<=wh[e][c]+1;
 if(sc[e][c])begin ch[e][c]<=ch[e][c]+1;next_h[e][c]<=cycle+(ch[e][c]%4);end
 if(sc[e][c]&&hs[e][c])replacements=replacements+1;
 if(shv[e][c]&&!stv[e][c])tag_waits=tag_waits+1;
 if(sc[e][c]!== (shv[e][c]&&sr[e][c])||sgt[e][c]!== (AUTH_TEST&&sc[e][c]))$fatal(1,"capture/tag handshake mismatch");
 if(ch[e][c]<wh[e][c]||ch[e][c]>wh[e][c]+1)$fatal(1,"prepared source ownership conservation");
 $fdisplay(ctrace,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0h %0h %0h",cycle,e,c,ch[e][c],wh[e][c],shv[e][c],stv[e][c],sr[e][c],sc[e][c],sgt[e][c],hs[e][c],ph[e][c],peer_done[e],peer_shared[e],capacity[e],shd[e][c*256+:256],source_auth[e][c*512+:512]);'''.replace('AUTH_TEST',"1'b"+str(auth)))
    tb=replace_once(tb,'integer trace,qtrace,ptrace;','integer ctrace;initial ctrace=$fopen("'+str(folder/'capture_trace.txt')+'","w");\ninteger trace,qtrace,ptrace;')
    tb=replace_once(tb,'$display("PASS Tx queues hwait=%0d dwait=%0d",hwait,dwait);$finish;', '$display("PASS Tx queues hwait=%0d dwait=%0d",hwait,dwait);if(!replacements)$fatal(1,"missing same-cycle group replacement");$display("PASS prepared production captures replacements=%0d tag_waits=%0d",replacements,tag_waits);$finish;')
    if 'source_owned' in tb or 'tl_control_partition #' in tb:raise ValueError('retirement shim remains')
    return tb
