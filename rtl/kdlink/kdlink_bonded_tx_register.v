module kdlink_bonded_tx_register ( // 定义 bonded shared arbitration 到独立 codec 的注册边界
    input wire clk_i, // 接收 bonded port 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [1:0] replay_valid_i, // 接收两个 physical slice replay 占用
    input wire [1:0] replay_select1_i, // 接收两个 physical slice replay origin 选择
    input wire [1215:0] replay_body_i, // 接收两个 origin replay body
    input wire [1:0] normal_valid_i, // 接收两个 physical slice normal 有效
    input wire [1:0] normal_select1_i, // 接收两个 physical slice normal lane 选择
    input wire [191:0] normal_header_i, // 接收两个 normal lane header
    input wire [1023:0] normal_payload_i, // 接收两个 normal lane payload
    input wire [13:0] normal_payload_bytes_i, // 接收两个 normal lane 字节数
    output reg [1:0] codec_valid_o, // 输出注册后的两个 codec valid
    output reg [191:0] codec_header_o, // 输出注册后的两个 codec header
    output reg [1023:0] codec_payload_o, // 输出注册后的两个 codec payload
    output reg [13:0] codec_payload_bytes_o // 输出注册后的两个 codec 字节数
); // 结束端口声明
    wire [1:0] codec_valid_d; // 保存组合 codec valid
    wire [191:0] codec_header_d; // 保存组合 codec header
    wire [1023:0] codec_payload_d; // 保存组合 codec payload
    wire [13:0] codec_payload_bytes_d; // 保存组合 codec 字节数
    assign codec_valid_d = replay_valid_i | normal_valid_i; // replay 优先时仍保持每 physical slice 单一 valid
    assign codec_header_d[95:0] = replay_valid_i[0] ? (replay_select1_i[0] ? replay_body_i[1215:1120] : replay_body_i[607:512]) : (normal_select1_i[0] ? normal_header_i[191:96] : normal_header_i[95:0]); // 选择 physical 零 header
    assign codec_header_d[191:96] = replay_valid_i[1] ? (replay_select1_i[1] ? replay_body_i[1215:1120] : replay_body_i[607:512]) : (normal_select1_i[1] ? normal_header_i[191:96] : normal_header_i[95:0]); // 选择 physical 一 header
    assign codec_payload_d[511:0] = replay_valid_i[0] ? (replay_select1_i[0] ? replay_body_i[1119:608] : replay_body_i[511:0]) : (normal_select1_i[0] ? normal_payload_i[1023:512] : normal_payload_i[511:0]); // 选择 physical 零 payload
    assign codec_payload_d[1023:512] = replay_valid_i[1] ? (replay_select1_i[1] ? replay_body_i[1119:608] : replay_body_i[511:0]) : (normal_select1_i[1] ? normal_payload_i[1023:512] : normal_payload_i[511:0]); // 选择 physical 一 payload
    assign codec_payload_bytes_d[6:0] = replay_valid_i[0] ? codec_header_d[94:88] : (normal_select1_i[0] ? normal_payload_bytes_i[13:7] : normal_payload_bytes_i[6:0]); // 选择 physical 零字节数
    assign codec_payload_bytes_d[13:7] = replay_valid_i[1] ? codec_header_d[190:184] : (normal_select1_i[1] ? normal_payload_bytes_i[13:7] : normal_payload_bytes_i[6:0]); // 选择 physical 一字节数
    always @(posedge clk_i or negedge rst_n_i) begin // 注册 shared arbitration 输出
        if (!rst_n_i) begin // 检测复位有效
            codec_valid_o <= 2'b00; // 清除两个 codec valid
            codec_header_o <= 192'd0; // 清零两个 codec header
            codec_payload_o <= 1024'd0; // 清零两个 codec payload
            codec_payload_bytes_o <= 14'd0; // 清零两个 codec 字节数
        end else begin // 处理正常 arbitration 输出注册
            codec_valid_o <= codec_valid_d; // 注册两个 codec valid
            codec_header_o <= codec_header_d; // 注册两个 codec header
            codec_payload_o <= codec_payload_d; // 注册两个 codec payload
            codec_payload_bytes_o <= codec_payload_bytes_d; // 注册两个 codec 字节数
        end // 结束正常 arbitration 输出注册
    end // 结束 shared arbitration 注册边界
endmodule // 结束 bonded TX 注册边界
