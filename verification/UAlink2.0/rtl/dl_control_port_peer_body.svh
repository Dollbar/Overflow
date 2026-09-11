// 双实际RTL端的独立行为记分板；所有接收字均由对端真实发送入队。
integer cycle, seed, ignored;
integer reset_starts[2], reset_dones[2], reset_requests[2], reset_replies[2], noops[2], retry_count[2];
integer pending_sent[2], pending_received[2], auto_count[2], restart_count[2];
integer pending_width_sent[2], pending_channel_sent[2];
integer response_losses, payload_limit;
logic drop_armed, protect_channel, protect_width, reject_other_channel;
time request_time[2];
logic request_waiting[2];
integer expect_requests0, expect_retries0;

integer sent[2], received[2], local_done[2], basic_done[2], width_events[2];
integer head[2], tail[2], due[2][8192];
logic [31:0] words[2][8192], rng;
logic [11:0] advertised[2], credit_snapshot[2];
logic credit_active[2];
logic trace_checksum;
integer blocked_tx[2], blocked_rx[2], blocked_fw[2];

function automatic logic [31:0] payload(input integer endpoint, index);
    case(index % 8)
        0: payload = 32'h004c0120; // Channel在线请求位型必须保持为payload。
        1: payload = 32'h0c6c0120;
        2: payload = 32'h00410020; // Width请求位型必须保持为payload。
        3: payload = 32'h01610020;
        4: payload = 32'hf8000004; // UART头位型不能嵌套解帧。
        5: payload = 32'h08000044; // Credit位型不能修改接收计数。
        default: payload = 32'ha5000000 ^ (32'(endpoint) << 20) ^ 32'(index);
    endcase
endfunction

task automatic step(input bit active);
    // 有界独立背压；队列的发送时刻与最早交付时刻均被记录。
    for(integer e=0;e<2;e=e+1) begin
        rng = (rng >> 1) ^ (32'hd0000001 & (32'b0 - {31'b0,rng[0]}));
        i_segment_available[e] = active && rng[0 +: 3] != 0;
        i_fw_rx_ready[e] = active && rng[3 +: 2] != 0;
        i_rx_word_valid[e] = active && head[e]<tail[e] && due[e][head[e]%8192]<=cycle && rng[5 +: 2]!=0;
        i_rx_word[e] = i_rx_word_valid[e] ? words[e][head[e]%8192] : 32'b0;
        if(!credit_active[e] && o_msg_uart_rx_initialized[e] && o_msg_uart_rx_counter[e]!=advertised[e]) begin
            credit_active[e]=1;
            credit_snapshot[e]=o_msg_uart_rx_counter[e];
        end
        i_credit_pending[e]=credit_active[e];
        i_credit_word[e]={credit_snapshot[e],20'h00044};
        i_fw_tx_valid[e]=active && sent[e]<payload_limit;
        i_fw_tx_word[e]=payload(e,sent[e]);
    end
    #(C_HALF_PERIOD_PS);
    for(integer e=0;e<2;e=e+1) begin
        if(i_rstn[e]) begin
            if(o_error[e] || o_unhandled_valid[e])
                $fatal(1,"FAIL peer protocol cycle=%0d endpoint=%0d ctl=%b basic=%b uart=%b",cycle,e,o_ctl_protocol_error[e],o_msg_basic_error[e],o_msg_uart_error[e]);
            if(protect_channel && e==1 && (o_ctl_owed_restart[e]!=2 || o_ctl_owed_requests[e][63:32]!=32'h004c0120))
                $fatal(1,"FAIL pending channel ownership lost during UART reset cycle=%0d owed=%b word=%h",cycle,o_ctl_owed_restart[e],o_ctl_owed_requests[e][63:32]);
            if(protect_width && e==1 && (o_ctl_owed_restart[e]!=1 || o_ctl_owed_requests[e][31:0]!=32'h00400020))
                $fatal(1,"FAIL pending width ownership lost during UART reset");
            if(reject_other_channel && e==1 && o_ctl_local_accept[e]) $fatal(1,"FAIL wrong pending target accepted");
            if(o_ctl_pending_sent[e]) begin
                pending_sent[e]=pending_sent[e]+1;
                if(o_ctl_tx_word[e][8]) pending_channel_sent[e]=pending_channel_sent[e]+1;
                else pending_width_sent[e]=pending_width_sent[e]+1;
            end
            if(o_ctl_pending_received[e]) pending_received[e]=pending_received[e]+1;
            if(o_ctl_auto_restart[e]!=0) auto_count[e]=auto_count[e]+1;
            if(o_ctl_restart_commit[e]!=0) begin
                restart_count[e]=restart_count[e]+1;
                if(o_ctl_tx_word[e]!==((o_ctl_restart_commit[e]==2) ? 32'h004c0120 : 32'h00400020)) $fatal(1,"FAIL original pending target changed");
            end
            if(o_msg_uart_local_start[e]) reset_starts[e]=reset_starts[e]+1;
            if(o_msg_uart_local_done[e]) begin reset_dones[e]=reset_dones[e]+1; request_waiting[e]=0; end
            if(o_msg_uart_retry[e]) begin
                if(!request_waiting[e] || $time-request_time[e]<64'd10000000000 || $time-request_time[e]>=64'd10000000000+2*C_HALF_PERIOD_PS)
                    $fatal(1,"FAIL UART retry physical time endpoint=%0d elapsed=%0t",e,$time-request_time[e]);
                retry_count[e]=retry_count[e]+1; request_waiting[e]=0;
            end
            if(o_msg_uart_tx_valid[e] && o_msg_uart_tx_source[e]==0) noops[e]=noops[e]+1;
            if(o_msg_uart_tx_valid[e] && o_msg_uart_tx_source[e]==9) begin
                if(noops[e]!=40 || o_msg_uart_tx_word[e] !== (e==0 ? 32'h00000184 : 32'h00001184))
                    $fatal(1,"FAIL UART reset request/noop count endpoint=%0d noops=%0d word=%h",e,noops[e],o_msg_uart_tx_word[e]);
                noops[e]=0; reset_requests[e]=reset_requests[e]+1; request_time[e]=$time; request_waiting[e]=1;
            end
            if(o_msg_uart_tx_valid[e] && o_msg_uart_tx_source[e]==10) begin
                if(o_msg_uart_tx_word[e] !== (e==0 ? 32'h000011c4 : 32'h000001c4)) $fatal(1,"FAIL UART response scope");
                reset_replies[e]=reset_replies[e]+1;
            end
            if(o_msg_uart_fw_tx_accepted[e]) sent[e]=sent[e]+1;
            if(o_msg_uart_fw_rx_valid[e] && i_fw_rx_ready[e]) begin
                if(received[e]>=payload_limit || o_msg_uart_fw_rx_word[e]!==payload(1-e,received[e]))
                    $fatal(1,"FAIL peer payload cycle=%0d endpoint=%0d index=%0d got=%h expected=%h",cycle,e,received[e],o_msg_uart_fw_rx_word[e],payload(1-e,received[e]));
                received[e]=received[e]+1;
            end
            if(i_rx_word_valid[e]) head[e]=head[e]+1;
            if(o_msg_uart_tx_valid[e]) begin
                if(!i_segment_available[e]) $fatal(1,"FAIL send without opportunity");
                if(tail[1-e]-head[1-e]>=8192) $fatal(1,"FAIL link queue overflow");
                if(drop_armed && e==1 && o_msg_uart_tx_source[e]==10) begin
                    drop_armed=0; response_losses=response_losses+1;
                end else begin
                words[1-e][tail[1-e]%8192]=o_msg_uart_tx_word[e];
                due[1-e][tail[1-e]%8192]=cycle+3;
                tail[1-e]=tail[1-e]+1;
                end
            end
            if(o_msg_uart_stream_reset[e] || o_msg_uart_credit_cancel[e]) begin
                advertised[e]=0; credit_active[e]=0;
            end else if(o_msg_uart_credit_take[e]) begin
                advertised[e]=credit_snapshot[e]; credit_active[e]=0;
            end
            if(o_ctl_local_done[e]) local_done[e]=local_done[e]+1;
            if(o_msg_basic_local_done[e]) basic_done[e]=basic_done[e]+1;
            if(o_ctl_width_event_valid[e]) width_events[e]=width_events[e]+1;
            if(!i_segment_available[e]) blocked_tx[e]=blocked_tx[e]+1;
            if(!i_fw_rx_ready[e]) blocked_fw[e]=blocked_fw[e]+1;
            if(head[e]<tail[e] && !i_rx_word_valid[e]) blocked_rx[e]=blocked_rx[e]+1;
        end
        trace_checksum = trace_checksum ^ observation[e];
    end
    clk=1;
    #(C_HALF_PERIOD_PS);
    clk=0; cycle=cycle+1;
endtask

initial begin
    response_losses=0; payload_limit=64; drop_armed=0; protect_channel=0; protect_width=0; reject_other_channel=0;
    expect_requests0=2+C_DROP_RESPONSE; expect_retries0=C_DROP_RESPONSE;
    cycle=0; seed=17; ignored=$value$plusargs("SEED=%d",seed); rng=32'(seed)|1; trace_checksum=0;
    for(integer e=0;e<2;e=e+1) begin
        reset_starts[e]=0; reset_dones[e]=0; reset_requests[e]=0; reset_replies[e]=0; noops[e]=0; retry_count[e]=0;
        pending_sent[e]=0; pending_received[e]=0; auto_count[e]=0; restart_count[e]=0;
        pending_width_sent[e]=0; pending_channel_sent[e]=0; request_time[e]=0; request_waiting[e]=0;
        sent[e]=0; received[e]=0; local_done[e]=0; basic_done[e]=0; width_events[e]=0;
        head[e]=0; tail[e]=0; advertised[e]=0; credit_snapshot[e]=0; credit_active[e]=0;
        blocked_tx[e]=0; blocked_rx[e]=0; blocked_fw[e]=0;
        // INPUT_DEFAULTS
        i_ctl_channel_ready[e]=3; i_ctl_width_ready[e]=1;
        i_basic_port_valid[e]=1; i_basic_port[e]=12'(e+9);
    end
    repeat(3) step(0);
    for(integer e=0;e<2;e=e+1) i_rstn[e]=1;
    repeat(3) step(0);
    for(integer e=0;e<2;e=e+1) begin
        i_ctl_request_valid[e]=1; i_ctl_request_channel[e]=1; i_ctl_request_target[e]=12;
        i_basic_local_valid[e]=1; i_basic_local_kind[e]=6;
    end
    step(1);
    for(integer e=0;e<2;e=e+1) begin i_ctl_request_valid[e]=0; i_basic_local_valid[e]=0; end
    repeat(2000) step(1);
    for(integer e=0;e<2;e=e+1) begin
        if(sent[e]!=64 || received[e]!=64 || local_done[e]!=1 || basic_done[e]!=1 || o_ctl_channel_online[e]!=2)
            $fatal(1,"FAIL peer convergence endpoint=%0d sent=%0d received=%0d ctl_done=%0d basic_done=%0d online=%0d",e,sent[e],received[e],local_done[e],basic_done[e],o_ctl_channel_online[e]);
    end
    // Channel0随后在线；使用一端发起，两端必须收敛。
    i_ctl_request_valid[0]=1; i_ctl_request_target[0]=8; step(1); i_ctl_request_valid[0]=0;
    repeat(100) step(1);
    for(integer e=0;e<2;e=e+1) if(o_ctl_channel_online[e]!=3) $fatal(1,"FAIL Channel0 peer online");
    // 实际Width请求、回复与确认经同一有序队列传输。
    i_ctl_request_valid[0]=1; i_ctl_request_channel[0]=0; i_ctl_request_target[0]=1; step(1); i_ctl_request_valid[0]=0;
    repeat(100) step(1);
    for(integer e=0;e<2;e=e+1)
        if(o_ctl_negotiated_width[e]!=1 || width_events[e]!=1) $fatal(1,"FAIL peer width ACK pair endpoint=%0d width=%0d events=%0d",e,o_ctl_negotiated_width[e],width_events[e]);
    // 已排空UART后关闭、重新打开Channel4；Channel0必须保留。
    i_ctl_request_channel[0]=1; i_ctl_request_target[0]=4; i_ctl_request_valid[0]=1; step(1); i_ctl_request_valid[0]=0;
    repeat(100) step(1);
    for(integer e=0;e<2;e=e+1) if(o_ctl_channel_online[e]!=1) $fatal(1,"FAIL peer Channel4 close");
    i_ctl_request_target[0]=12; i_ctl_request_valid[0]=1; step(1); i_ctl_request_valid[0]=0;
    repeat(100) step(1);
    for(integer e=0;e<2;e=e+1) begin
        if(o_ctl_channel_online[e]!=3 || o_ctl_local_busy[e] || o_ctl_remote_busy[e] || head[e]!=tail[e]) $fatal(1,"FAIL final peer obligations");
        if(blocked_tx[e]==0 || blocked_rx[e]==0 || blocked_fw[e]==0) $fatal(1,"FAIL missing peer backpressure coverage");
    end
    // Channel4离线后，远端未ready必须回复Pending并保留原始目标。
    i_ctl_request_target[0]=4; i_ctl_request_valid[0]=1; step(1); i_ctl_request_valid[0]=0;
    repeat(100) step(1);
    i_ctl_channel_ready[1]=1; i_ctl_request_target[0]=12; i_ctl_request_valid[0]=1; step(1); i_ctl_request_valid[0]=0;
    repeat(80) step(1);
    if(o_ctl_owed_restart[1]!=2 || o_ctl_waiting_peer[0]!=2 || pending_channel_sent[1]!=1) $fatal(1,"FAIL channel Pending not established");
    protect_channel=1;
    reject_other_channel=1; i_ctl_request_valid[1]=1; i_ctl_request_channel[1]=1; i_ctl_request_target[1]=0;
    step(1); i_ctl_request_valid[1]=0; reject_other_channel=0;
    // 双端同时UART流复位；Basic仍可建立独立请求。
    for(integer e=0;e<2;e=e+1) begin i_local_request[e]=1; i_local_all[e]=(e==1); i_basic_local_valid[e]=1; end
    step(1);
    for(integer e=0;e<2;e=e+1) begin i_local_request[e]=0; i_basic_local_valid[e]=0; end
    repeat(180) step(1);
    for(integer e=0;e<2;e=e+1) begin
        if(reset_dones[e]!=1 || reset_requests[e]!=1 || reset_replies[e]!=1 || basic_done[e]!=2 || o_msg_uart_stream_reset[e]) $fatal(1,"FAIL simultaneous reset/basic completion");
    end
    protect_channel=0; i_ctl_channel_ready[1]=3; repeat(100) step(1);
    if(o_ctl_channel_online[0]!=3 || o_ctl_channel_online[1]!=3 || o_ctl_owed_restart[1]!=0 || o_ctl_waiting_peer[0]!=0 || restart_count[1]!=1) $fatal(1,"FAIL channel pending restart convergence");
    // 双Accelerator配置才允许以未ready的Accelerator响应全宽请求为Pending。
    if(C_PEER_SWITCH==0) begin
        i_ctl_width_ready[1]=0; i_ctl_request_channel[0]=0; i_ctl_request_target[0]=0; i_ctl_request_valid[0]=1;
        step(1); i_ctl_request_valid[0]=0; repeat(80) step(1);
        if(o_ctl_owed_restart[1]!=1 || o_ctl_waiting_peer[0]!=1 || pending_width_sent[1]!=1) $fatal(1,"FAIL width Pending not established");
        protect_width=1;
        // 在完整10ms重试实验前先完成Width义务，避免故意拖过Control的10ms预算。
        i_local_request[1]=1; step(1); i_local_request[1]=0; repeat(180) step(1);
        if(reset_dones[1]!=2) $fatal(1,"FAIL width pending UART reset preservation");
        protect_width=0; i_ctl_width_ready[1]=1; repeat(100) step(1);
        if(o_ctl_negotiated_width[0]!=0 || o_ctl_negotiated_width[1]!=0 || o_ctl_owed_restart[1]!=0 || o_ctl_waiting_peer[0]!=0 || restart_count[1]!=2) $fatal(1,"FAIL width pending restart convergence");
    end
    // 丢失一次真正的SUCCESS响应，实际时间10ms后必须完整重试。
    drop_armed=(C_DROP_RESPONSE!=0); i_local_request[0]=1; step(1); i_local_request[0]=0;
    if(C_DROP_RESPONSE!=0) begin
        repeat(32'(64'd10000000000/(2*C_HALF_PERIOD_PS)+600)) step(1);
    end else begin repeat(180) step(1); end
    if(reset_dones[0]!=2 || reset_requests[0]!=expect_requests0 || retry_count[0]!=expect_retries0 || response_losses!=C_DROP_RESPONSE || noops[0]!=0)
        $fatal(1,"FAIL response-loss recovery done=%0d requests=%0d retries=%0d drops=%0d",reset_dones[0],reset_requests[0],retry_count[0],response_losses);
    // 流复位后再发送新批次，只有新信用和实际固件字能使记分板完成。
    payload_limit=128; repeat(2000) step(1);
    for(integer e=0;e<2;e=e+1) begin
        if(received[e]!=128 || sent[e]!=128 || o_msg_uart_stream_reset[e] || o_ctl_local_busy[e] || o_ctl_remote_busy[e] || head[e]!=tail[e]) $fatal(1,"FAIL post-reset payload/obligation convergence endpoint=%0d received=%0d",e,received[e]);
    end
    $display("LIFECYCLE pending=%0d restarts=%0d reset_done0=%0d reset_done1=%0d requests0=%0d requests1=%0d retries=%0d drops=%0d",pending_sent[1],restart_count[1],reset_dones[0],reset_dones[1],reset_requests[0],reset_requests[1],retry_count[0],response_losses);
    $display("PASS dl_control_port_peer cycles=%0d received0=%0d received1=%0d width0=%0d width1=%0d checksum=%b ignored=%0d",cycle,received[0],received[1],width_events[0],width_events[1],trace_checksum,ignored);
    $finish;
end
