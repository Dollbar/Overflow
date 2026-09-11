module tl_credit_ledger #(parameter WIDTH=16)( // 二十逻辑槽信用账本，WIDTH至少1
input wire i_clk,i_rstn,i_commit,i_receive,i_send,i_finish,i_shared, // 本地规范化事件，线上策略由控制器负责
input wire [20*WIDTH-1:0] i_grants,i_demands, // 四类各Pool及四VC，低槽在低位
output wire o_allowed,o_taken,o_receive_error, // 整笔发送许可与接收异常
output reg [20*(WIDTH+1)-1:0] o_capacity,o_available, // 物理槽多一位容纳共享池总容量
output reg o_done,o_shared // 已完成初始化及冻结共享模式
); // 接口结束
wire w_finish=i_receive&&i_finish&&!o_done; // 完成事件从属于接收
wire [WIDTH:0] w_add0=i_receive?{1'b0,i_grants[0*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽0合法接收候选数量
wire [WIDTH:0] w_want0={1'b0,i_demands[0*WIDTH+:WIDTH]}; // 槽0整笔发送需求
wire [WIDTH:0] w_total0=o_available[0*(WIDTH+1)+:WIDTH+1]+w_add0; // 槽0余额更新只需低位和
wire [WIDTH:0] w_limit0=o_done?o_capacity[0*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽0状态决定的容量上限
wire [WIDTH+1:0] w_room0={1'b0,w_limit0}-{1'b0,o_available[0*(WIDTH+1)+:WIDTH+1]}; // 槽0提前计算剩余空间
wire w_bad0=(o_available[0*(WIDTH+1)+:WIDTH+1]>w_limit0)||({1'b0,w_add0}>w_room0); // 槽0保留异常余额守卫的回收越界判定
wire w_fit0=w_want0<=o_available[0*(WIDTH+1)+:WIDTH+1]; // 槽0只用旧信用
wire [WIDTH:0] w_cap0=o_capacity[0*(WIDTH+1)+:WIDTH+1]+w_add0; // 槽0初始化候选容量
wire [WIDTH:0] w_add1=i_receive?{1'b0,i_grants[1*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽1合法接收候选数量
wire [WIDTH:0] w_want1={1'b0,i_demands[1*WIDTH+:WIDTH]}; // 槽1整笔发送需求
wire [WIDTH:0] w_total1=o_available[1*(WIDTH+1)+:WIDTH+1]+w_add1; // 槽1余额更新只需低位和
wire [WIDTH:0] w_limit1=o_done?o_capacity[1*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽1状态决定的容量上限
wire [WIDTH+1:0] w_room1={1'b0,w_limit1}-{1'b0,o_available[1*(WIDTH+1)+:WIDTH+1]}; // 槽1提前计算剩余空间
wire w_bad1=(o_available[1*(WIDTH+1)+:WIDTH+1]>w_limit1)||({1'b0,w_add1}>w_room1); // 槽1保留异常余额守卫的回收越界判定
wire w_fit1=w_want1<=o_available[1*(WIDTH+1)+:WIDTH+1]; // 槽1只用旧信用
wire [WIDTH:0] w_cap1=o_capacity[1*(WIDTH+1)+:WIDTH+1]+w_add1; // 槽1初始化候选容量
wire [WIDTH:0] w_add2=i_receive?{1'b0,i_grants[2*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽2合法接收候选数量
wire [WIDTH:0] w_want2={1'b0,i_demands[2*WIDTH+:WIDTH]}; // 槽2整笔发送需求
wire [WIDTH:0] w_total2=o_available[2*(WIDTH+1)+:WIDTH+1]+w_add2; // 槽2余额更新只需低位和
wire [WIDTH:0] w_limit2=o_done?o_capacity[2*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽2状态决定的容量上限
wire [WIDTH+1:0] w_room2={1'b0,w_limit2}-{1'b0,o_available[2*(WIDTH+1)+:WIDTH+1]}; // 槽2提前计算剩余空间
wire w_bad2=(o_available[2*(WIDTH+1)+:WIDTH+1]>w_limit2)||({1'b0,w_add2}>w_room2); // 槽2保留异常余额守卫的回收越界判定
wire w_fit2=w_want2<=o_available[2*(WIDTH+1)+:WIDTH+1]; // 槽2只用旧信用
wire [WIDTH:0] w_cap2=o_capacity[2*(WIDTH+1)+:WIDTH+1]+w_add2; // 槽2初始化候选容量
wire [WIDTH:0] w_add3=i_receive?{1'b0,i_grants[3*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽3合法接收候选数量
wire [WIDTH:0] w_want3={1'b0,i_demands[3*WIDTH+:WIDTH]}; // 槽3整笔发送需求
wire [WIDTH:0] w_total3=o_available[3*(WIDTH+1)+:WIDTH+1]+w_add3; // 槽3余额更新只需低位和
wire [WIDTH:0] w_limit3=o_done?o_capacity[3*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽3状态决定的容量上限
wire [WIDTH+1:0] w_room3={1'b0,w_limit3}-{1'b0,o_available[3*(WIDTH+1)+:WIDTH+1]}; // 槽3提前计算剩余空间
wire w_bad3=(o_available[3*(WIDTH+1)+:WIDTH+1]>w_limit3)||({1'b0,w_add3}>w_room3); // 槽3保留异常余额守卫的回收越界判定
wire w_fit3=w_want3<=o_available[3*(WIDTH+1)+:WIDTH+1]; // 槽3只用旧信用
wire [WIDTH:0] w_cap3=o_capacity[3*(WIDTH+1)+:WIDTH+1]+w_add3; // 槽3初始化候选容量
wire [WIDTH:0] w_add4=i_receive?{1'b0,i_grants[4*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽4合法接收候选数量
wire [WIDTH:0] w_want4={1'b0,i_demands[4*WIDTH+:WIDTH]}; // 槽4整笔发送需求
wire [WIDTH:0] w_total4=o_available[4*(WIDTH+1)+:WIDTH+1]+w_add4; // 槽4余额更新只需低位和
wire [WIDTH:0] w_limit4=o_done?o_capacity[4*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽4状态决定的容量上限
wire [WIDTH+1:0] w_room4={1'b0,w_limit4}-{1'b0,o_available[4*(WIDTH+1)+:WIDTH+1]}; // 槽4提前计算剩余空间
wire w_bad4=(o_available[4*(WIDTH+1)+:WIDTH+1]>w_limit4)||({1'b0,w_add4}>w_room4); // 槽4保留异常余额守卫的回收越界判定
wire w_fit4=w_want4<=o_available[4*(WIDTH+1)+:WIDTH+1]; // 槽4只用旧信用
wire [WIDTH:0] w_cap4=o_capacity[4*(WIDTH+1)+:WIDTH+1]+w_add4; // 槽4初始化候选容量
wire [WIDTH:0] w_add5=i_receive?{1'b0,i_grants[5*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽5合法接收候选数量
wire [WIDTH:0] w_want5={1'b0,i_demands[5*WIDTH+:WIDTH]}; // 槽5整笔发送需求
wire [WIDTH:0] w_total5=o_available[5*(WIDTH+1)+:WIDTH+1]+w_add5; // 槽5余额更新只需低位和
wire [WIDTH:0] w_limit5=o_done?o_capacity[5*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽5状态决定的容量上限
wire [WIDTH+1:0] w_room5={1'b0,w_limit5}-{1'b0,o_available[5*(WIDTH+1)+:WIDTH+1]}; // 槽5提前计算剩余空间
wire w_bad5=(o_available[5*(WIDTH+1)+:WIDTH+1]>w_limit5)||({1'b0,w_add5}>w_room5); // 槽5保留异常余额守卫的回收越界判定
wire w_fit5=w_want5<=o_available[5*(WIDTH+1)+:WIDTH+1]; // 槽5只用旧信用
wire [WIDTH:0] w_cap5=o_capacity[5*(WIDTH+1)+:WIDTH+1]+w_add5; // 槽5初始化候选容量
wire [WIDTH:0] w_add6=i_receive?{1'b0,i_grants[6*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽6合法接收候选数量
wire [WIDTH:0] w_want6={1'b0,i_demands[6*WIDTH+:WIDTH]}; // 槽6整笔发送需求
wire [WIDTH:0] w_total6=o_available[6*(WIDTH+1)+:WIDTH+1]+w_add6; // 槽6余额更新只需低位和
wire [WIDTH:0] w_limit6=o_done?o_capacity[6*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽6状态决定的容量上限
wire [WIDTH+1:0] w_room6={1'b0,w_limit6}-{1'b0,o_available[6*(WIDTH+1)+:WIDTH+1]}; // 槽6提前计算剩余空间
wire w_bad6=(o_available[6*(WIDTH+1)+:WIDTH+1]>w_limit6)||({1'b0,w_add6}>w_room6); // 槽6保留异常余额守卫的回收越界判定
wire w_fit6=w_want6<=o_available[6*(WIDTH+1)+:WIDTH+1]; // 槽6只用旧信用
wire [WIDTH:0] w_cap6=o_capacity[6*(WIDTH+1)+:WIDTH+1]+w_add6; // 槽6初始化候选容量
wire [WIDTH:0] w_add7=i_receive?{1'b0,i_grants[7*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽7合法接收候选数量
wire [WIDTH:0] w_want7={1'b0,i_demands[7*WIDTH+:WIDTH]}; // 槽7整笔发送需求
wire [WIDTH:0] w_total7=o_available[7*(WIDTH+1)+:WIDTH+1]+w_add7; // 槽7余额更新只需低位和
wire [WIDTH:0] w_limit7=o_done?o_capacity[7*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽7状态决定的容量上限
wire [WIDTH+1:0] w_room7={1'b0,w_limit7}-{1'b0,o_available[7*(WIDTH+1)+:WIDTH+1]}; // 槽7提前计算剩余空间
wire w_bad7=(o_available[7*(WIDTH+1)+:WIDTH+1]>w_limit7)||({1'b0,w_add7}>w_room7); // 槽7保留异常余额守卫的回收越界判定
wire w_fit7=w_want7<=o_available[7*(WIDTH+1)+:WIDTH+1]; // 槽7只用旧信用
wire [WIDTH:0] w_cap7=o_capacity[7*(WIDTH+1)+:WIDTH+1]+w_add7; // 槽7初始化候选容量
wire [WIDTH:0] w_add8=i_receive?{1'b0,i_grants[8*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽8合法接收候选数量
wire [WIDTH:0] w_want8={1'b0,i_demands[8*WIDTH+:WIDTH]}; // 槽8整笔发送需求
wire [WIDTH:0] w_total8=o_available[8*(WIDTH+1)+:WIDTH+1]+w_add8; // 槽8余额更新只需低位和
wire [WIDTH:0] w_limit8=o_done?o_capacity[8*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽8状态决定的容量上限
wire [WIDTH+1:0] w_room8={1'b0,w_limit8}-{1'b0,o_available[8*(WIDTH+1)+:WIDTH+1]}; // 槽8提前计算剩余空间
wire w_bad8=(o_available[8*(WIDTH+1)+:WIDTH+1]>w_limit8)||({1'b0,w_add8}>w_room8); // 槽8保留异常余额守卫的回收越界判定
wire w_fit8=w_want8<=o_available[8*(WIDTH+1)+:WIDTH+1]; // 槽8只用旧信用
wire [WIDTH:0] w_cap8=o_capacity[8*(WIDTH+1)+:WIDTH+1]+w_add8; // 槽8初始化候选容量
wire [WIDTH:0] w_add9=i_receive?{1'b0,i_grants[9*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽9合法接收候选数量
wire [WIDTH:0] w_want9={1'b0,i_demands[9*WIDTH+:WIDTH]}; // 槽9整笔发送需求
wire [WIDTH:0] w_total9=o_available[9*(WIDTH+1)+:WIDTH+1]+w_add9; // 槽9余额更新只需低位和
wire [WIDTH:0] w_limit9=o_done?o_capacity[9*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽9状态决定的容量上限
wire [WIDTH+1:0] w_room9={1'b0,w_limit9}-{1'b0,o_available[9*(WIDTH+1)+:WIDTH+1]}; // 槽9提前计算剩余空间
wire w_bad9=(o_available[9*(WIDTH+1)+:WIDTH+1]>w_limit9)||({1'b0,w_add9}>w_room9); // 槽9保留异常余额守卫的回收越界判定
wire w_fit9=w_want9<=o_available[9*(WIDTH+1)+:WIDTH+1]; // 槽9只用旧信用
wire [WIDTH:0] w_cap9=o_capacity[9*(WIDTH+1)+:WIDTH+1]+w_add9; // 槽9初始化候选容量
wire [WIDTH:0] w_add10=i_receive?(o_shared?({1'b0,i_grants[10*WIDTH+:WIDTH]}+{1'b0,i_grants[15*WIDTH+:WIDTH]}):{1'b0,i_grants[10*WIDTH+:WIDTH]}):{(WIDTH+1){1'b0}}; // 槽10合法接收候选数量
wire [WIDTH:0] w_want10=(o_shared?({1'b0,i_demands[10*WIDTH+:WIDTH]}+{1'b0,i_demands[15*WIDTH+:WIDTH]}):{1'b0,i_demands[10*WIDTH+:WIDTH]}); // 槽10整笔发送需求
wire [WIDTH:0] w_total10=o_available[10*(WIDTH+1)+:WIDTH+1]+w_add10; // 槽10余额更新只需低位和
wire [WIDTH:0] w_limit10=o_done?o_capacity[10*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽10状态决定的容量上限
wire [WIDTH+1:0] w_room10={1'b0,w_limit10}-{1'b0,o_available[10*(WIDTH+1)+:WIDTH+1]}; // 槽10提前计算剩余空间
wire w_bad10=(o_available[10*(WIDTH+1)+:WIDTH+1]>w_limit10)||({1'b0,w_add10}>w_room10); // 槽10保留异常余额守卫的回收越界判定
wire w_fit10=w_want10<=o_available[10*(WIDTH+1)+:WIDTH+1]; // 槽10只用旧信用
wire [WIDTH:0] w_cap10=o_capacity[10*(WIDTH+1)+:WIDTH+1]+w_add10; // 槽10初始化候选容量
wire [WIDTH:0] w_add11=i_receive?{1'b0,i_grants[11*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽11合法接收候选数量
wire [WIDTH:0] w_want11={1'b0,i_demands[11*WIDTH+:WIDTH]}; // 槽11整笔发送需求
wire [WIDTH:0] w_total11=o_available[11*(WIDTH+1)+:WIDTH+1]+w_add11; // 槽11余额更新只需低位和
wire [WIDTH:0] w_limit11=o_done?o_capacity[11*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽11状态决定的容量上限
wire [WIDTH+1:0] w_room11={1'b0,w_limit11}-{1'b0,o_available[11*(WIDTH+1)+:WIDTH+1]}; // 槽11提前计算剩余空间
wire w_bad11=(o_available[11*(WIDTH+1)+:WIDTH+1]>w_limit11)||({1'b0,w_add11}>w_room11); // 槽11保留异常余额守卫的回收越界判定
wire w_fit11=w_want11<=o_available[11*(WIDTH+1)+:WIDTH+1]; // 槽11只用旧信用
wire [WIDTH:0] w_cap11=o_capacity[11*(WIDTH+1)+:WIDTH+1]+w_add11; // 槽11初始化候选容量
wire [WIDTH:0] w_add12=i_receive?{1'b0,i_grants[12*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽12合法接收候选数量
wire [WIDTH:0] w_want12={1'b0,i_demands[12*WIDTH+:WIDTH]}; // 槽12整笔发送需求
wire [WIDTH:0] w_total12=o_available[12*(WIDTH+1)+:WIDTH+1]+w_add12; // 槽12余额更新只需低位和
wire [WIDTH:0] w_limit12=o_done?o_capacity[12*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽12状态决定的容量上限
wire [WIDTH+1:0] w_room12={1'b0,w_limit12}-{1'b0,o_available[12*(WIDTH+1)+:WIDTH+1]}; // 槽12提前计算剩余空间
wire w_bad12=(o_available[12*(WIDTH+1)+:WIDTH+1]>w_limit12)||({1'b0,w_add12}>w_room12); // 槽12保留异常余额守卫的回收越界判定
wire w_fit12=w_want12<=o_available[12*(WIDTH+1)+:WIDTH+1]; // 槽12只用旧信用
wire [WIDTH:0] w_cap12=o_capacity[12*(WIDTH+1)+:WIDTH+1]+w_add12; // 槽12初始化候选容量
wire [WIDTH:0] w_add13=i_receive?{1'b0,i_grants[13*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽13合法接收候选数量
wire [WIDTH:0] w_want13={1'b0,i_demands[13*WIDTH+:WIDTH]}; // 槽13整笔发送需求
wire [WIDTH:0] w_total13=o_available[13*(WIDTH+1)+:WIDTH+1]+w_add13; // 槽13余额更新只需低位和
wire [WIDTH:0] w_limit13=o_done?o_capacity[13*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽13状态决定的容量上限
wire [WIDTH+1:0] w_room13={1'b0,w_limit13}-{1'b0,o_available[13*(WIDTH+1)+:WIDTH+1]}; // 槽13提前计算剩余空间
wire w_bad13=(o_available[13*(WIDTH+1)+:WIDTH+1]>w_limit13)||({1'b0,w_add13}>w_room13); // 槽13保留异常余额守卫的回收越界判定
wire w_fit13=w_want13<=o_available[13*(WIDTH+1)+:WIDTH+1]; // 槽13只用旧信用
wire [WIDTH:0] w_cap13=o_capacity[13*(WIDTH+1)+:WIDTH+1]+w_add13; // 槽13初始化候选容量
wire [WIDTH:0] w_add14=i_receive?{1'b0,i_grants[14*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽14合法接收候选数量
wire [WIDTH:0] w_want14={1'b0,i_demands[14*WIDTH+:WIDTH]}; // 槽14整笔发送需求
wire [WIDTH:0] w_total14=o_available[14*(WIDTH+1)+:WIDTH+1]+w_add14; // 槽14余额更新只需低位和
wire [WIDTH:0] w_limit14=o_done?o_capacity[14*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽14状态决定的容量上限
wire [WIDTH+1:0] w_room14={1'b0,w_limit14}-{1'b0,o_available[14*(WIDTH+1)+:WIDTH+1]}; // 槽14提前计算剩余空间
wire w_bad14=(o_available[14*(WIDTH+1)+:WIDTH+1]>w_limit14)||({1'b0,w_add14}>w_room14); // 槽14保留异常余额守卫的回收越界判定
wire w_fit14=w_want14<=o_available[14*(WIDTH+1)+:WIDTH+1]; // 槽14只用旧信用
wire [WIDTH:0] w_cap14=o_capacity[14*(WIDTH+1)+:WIDTH+1]+w_add14; // 槽14初始化候选容量
wire [WIDTH:0] w_add15=i_receive?(o_shared?{(WIDTH+1){1'b0}}:{1'b0,i_grants[15*WIDTH+:WIDTH]}):{(WIDTH+1){1'b0}}; // 槽15合法接收候选数量
wire [WIDTH:0] w_want15=(o_shared?{(WIDTH+1){1'b0}}:{1'b0,i_demands[15*WIDTH+:WIDTH]}); // 槽15整笔发送需求
wire [WIDTH:0] w_total15=o_available[15*(WIDTH+1)+:WIDTH+1]+w_add15; // 槽15余额更新只需低位和
wire [WIDTH:0] w_limit15=o_done?o_capacity[15*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽15状态决定的容量上限
wire [WIDTH+1:0] w_room15={1'b0,w_limit15}-{1'b0,o_available[15*(WIDTH+1)+:WIDTH+1]}; // 槽15提前计算剩余空间
wire w_bad15=(o_available[15*(WIDTH+1)+:WIDTH+1]>w_limit15)||({1'b0,w_add15}>w_room15); // 槽15保留异常余额守卫的回收越界判定
wire w_fit15=w_want15<=o_available[15*(WIDTH+1)+:WIDTH+1]; // 槽15只用旧信用
wire [WIDTH:0] w_cap15=o_capacity[15*(WIDTH+1)+:WIDTH+1]+w_add15; // 槽15初始化候选容量
wire [WIDTH:0] w_add16=i_receive?{1'b0,i_grants[16*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽16合法接收候选数量
wire [WIDTH:0] w_want16={1'b0,i_demands[16*WIDTH+:WIDTH]}; // 槽16整笔发送需求
wire [WIDTH:0] w_total16=o_available[16*(WIDTH+1)+:WIDTH+1]+w_add16; // 槽16余额更新只需低位和
wire [WIDTH:0] w_limit16=o_done?o_capacity[16*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽16状态决定的容量上限
wire [WIDTH+1:0] w_room16={1'b0,w_limit16}-{1'b0,o_available[16*(WIDTH+1)+:WIDTH+1]}; // 槽16提前计算剩余空间
wire w_bad16=(o_available[16*(WIDTH+1)+:WIDTH+1]>w_limit16)||({1'b0,w_add16}>w_room16); // 槽16保留异常余额守卫的回收越界判定
wire w_fit16=w_want16<=o_available[16*(WIDTH+1)+:WIDTH+1]; // 槽16只用旧信用
wire [WIDTH:0] w_cap16=o_capacity[16*(WIDTH+1)+:WIDTH+1]+w_add16; // 槽16初始化候选容量
wire [WIDTH:0] w_add17=i_receive?{1'b0,i_grants[17*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽17合法接收候选数量
wire [WIDTH:0] w_want17={1'b0,i_demands[17*WIDTH+:WIDTH]}; // 槽17整笔发送需求
wire [WIDTH:0] w_total17=o_available[17*(WIDTH+1)+:WIDTH+1]+w_add17; // 槽17余额更新只需低位和
wire [WIDTH:0] w_limit17=o_done?o_capacity[17*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽17状态决定的容量上限
wire [WIDTH+1:0] w_room17={1'b0,w_limit17}-{1'b0,o_available[17*(WIDTH+1)+:WIDTH+1]}; // 槽17提前计算剩余空间
wire w_bad17=(o_available[17*(WIDTH+1)+:WIDTH+1]>w_limit17)||({1'b0,w_add17}>w_room17); // 槽17保留异常余额守卫的回收越界判定
wire w_fit17=w_want17<=o_available[17*(WIDTH+1)+:WIDTH+1]; // 槽17只用旧信用
wire [WIDTH:0] w_cap17=o_capacity[17*(WIDTH+1)+:WIDTH+1]+w_add17; // 槽17初始化候选容量
wire [WIDTH:0] w_add18=i_receive?{1'b0,i_grants[18*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽18合法接收候选数量
wire [WIDTH:0] w_want18={1'b0,i_demands[18*WIDTH+:WIDTH]}; // 槽18整笔发送需求
wire [WIDTH:0] w_total18=o_available[18*(WIDTH+1)+:WIDTH+1]+w_add18; // 槽18余额更新只需低位和
wire [WIDTH:0] w_limit18=o_done?o_capacity[18*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽18状态决定的容量上限
wire [WIDTH+1:0] w_room18={1'b0,w_limit18}-{1'b0,o_available[18*(WIDTH+1)+:WIDTH+1]}; // 槽18提前计算剩余空间
wire w_bad18=(o_available[18*(WIDTH+1)+:WIDTH+1]>w_limit18)||({1'b0,w_add18}>w_room18); // 槽18保留异常余额守卫的回收越界判定
wire w_fit18=w_want18<=o_available[18*(WIDTH+1)+:WIDTH+1]; // 槽18只用旧信用
wire [WIDTH:0] w_cap18=o_capacity[18*(WIDTH+1)+:WIDTH+1]+w_add18; // 槽18初始化候选容量
wire [WIDTH:0] w_add19=i_receive?{1'b0,i_grants[19*WIDTH+:WIDTH]}:{(WIDTH+1){1'b0}}; // 槽19合法接收候选数量
wire [WIDTH:0] w_want19={1'b0,i_demands[19*WIDTH+:WIDTH]}; // 槽19整笔发送需求
wire [WIDTH:0] w_total19=o_available[19*(WIDTH+1)+:WIDTH+1]+w_add19; // 槽19余额更新只需低位和
wire [WIDTH:0] w_limit19=o_done?o_capacity[19*(WIDTH+1)+:WIDTH+1]:{1'b0,{WIDTH{1'b1}}}; // 槽19状态决定的容量上限
wire [WIDTH+1:0] w_room19={1'b0,w_limit19}-{1'b0,o_available[19*(WIDTH+1)+:WIDTH+1]}; // 槽19提前计算剩余空间
wire w_bad19=(o_available[19*(WIDTH+1)+:WIDTH+1]>w_limit19)||({1'b0,w_add19}>w_room19); // 槽19保留异常余额守卫的回收越界判定
wire w_fit19=w_want19<=o_available[19*(WIDTH+1)+:WIDTH+1]; // 槽19只用旧信用
wire [WIDTH:0] w_cap19=o_capacity[19*(WIDTH+1)+:WIDTH+1]+w_add19; // 槽19初始化候选容量
wire w_req_data=(|o_available[10*(WIDTH+1)+:WIDTH+1])||(|w_add10)||(|o_available[11*(WIDTH+1)+:WIDTH+1])||(|w_add11)||(|o_available[12*(WIDTH+1)+:WIDTH+1])||(|w_add12)||(|o_available[13*(WIDTH+1)+:WIDTH+1])||(|w_add13)||(|o_available[14*(WIDTH+1)+:WIDTH+1])||(|w_add14); // 请求数据类任意非零信用
wire w_rsp_data=(|o_available[15*(WIDTH+1)+:WIDTH+1])||(|w_add15)||(|o_available[16*(WIDTH+1)+:WIDTH+1])||(|w_add16)||(|o_available[17*(WIDTH+1)+:WIDTH+1])||(|w_add17)||(|o_available[18*(WIDTH+1)+:WIDTH+1])||(|w_add18)||(|o_available[19*(WIDTH+1)+:WIDTH+1])||(|w_add19); // 响应数据类任意非零信用
wire w_init_bad=w_finish&&!i_shared&&(!w_req_data||!w_rsp_data); // 非共享模式两类均须有数据缓冲
assign o_receive_error=i_rstn&&(w_init_bad||w_bad0||w_bad1||w_bad2||w_bad3||w_bad4||w_bad5||w_bad6||w_bad7||w_bad8||w_bad9||w_bad10||w_bad11||w_bad12||w_bad13||w_bad14||w_bad15||w_bad16||w_bad17||w_bad18||w_bad19); // 任一错误拒绝整拍
assign o_allowed=i_rstn&&o_done&&!o_receive_error&&(w_fit0&&w_fit1&&w_fit2&&w_fit3&&w_fit4&&w_fit5&&w_fit6&&w_fit7&&w_fit8&&w_fit9&&w_fit10&&w_fit11&&w_fit12&&w_fit13&&w_fit14&&w_fit15&&w_fit16&&w_fit17&&w_fit18&&w_fit19); // 全部物理槽满足才允许发送
assign o_taken=i_commit&&i_send&&o_allowed; // 整笔原子消费
always @(posedge i_clk)begin // 唯一同步时钟
if(!i_rstn)begin o_capacity<={20*(WIDTH+1){1'b0}};o_available<={20*(WIDTH+1){1'b0}};o_done<=1'b0;o_shared<=1'b0;end // 复位没有信用
else if(i_commit&&!o_receive_error)begin // 回收异常时全部状态保持
o_available[0*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total0[WIDTH:0]-w_want0):w_total0[WIDTH:0]; // 槽0合法回收与原子消费
if(!o_done)o_capacity[0*(WIDTH+1)+:WIDTH+1]<=w_cap0; // 槽0初始化容量学习
o_available[1*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total1[WIDTH:0]-w_want1):w_total1[WIDTH:0]; // 槽1合法回收与原子消费
if(!o_done)o_capacity[1*(WIDTH+1)+:WIDTH+1]<=w_cap1; // 槽1初始化容量学习
o_available[2*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total2[WIDTH:0]-w_want2):w_total2[WIDTH:0]; // 槽2合法回收与原子消费
if(!o_done)o_capacity[2*(WIDTH+1)+:WIDTH+1]<=w_cap2; // 槽2初始化容量学习
o_available[3*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total3[WIDTH:0]-w_want3):w_total3[WIDTH:0]; // 槽3合法回收与原子消费
if(!o_done)o_capacity[3*(WIDTH+1)+:WIDTH+1]<=w_cap3; // 槽3初始化容量学习
o_available[4*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total4[WIDTH:0]-w_want4):w_total4[WIDTH:0]; // 槽4合法回收与原子消费
if(!o_done)o_capacity[4*(WIDTH+1)+:WIDTH+1]<=w_cap4; // 槽4初始化容量学习
o_available[5*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total5[WIDTH:0]-w_want5):w_total5[WIDTH:0]; // 槽5合法回收与原子消费
if(!o_done)o_capacity[5*(WIDTH+1)+:WIDTH+1]<=w_cap5; // 槽5初始化容量学习
o_available[6*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total6[WIDTH:0]-w_want6):w_total6[WIDTH:0]; // 槽6合法回收与原子消费
if(!o_done)o_capacity[6*(WIDTH+1)+:WIDTH+1]<=w_cap6; // 槽6初始化容量学习
o_available[7*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total7[WIDTH:0]-w_want7):w_total7[WIDTH:0]; // 槽7合法回收与原子消费
if(!o_done)o_capacity[7*(WIDTH+1)+:WIDTH+1]<=w_cap7; // 槽7初始化容量学习
o_available[8*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total8[WIDTH:0]-w_want8):w_total8[WIDTH:0]; // 槽8合法回收与原子消费
if(!o_done)o_capacity[8*(WIDTH+1)+:WIDTH+1]<=w_cap8; // 槽8初始化容量学习
o_available[9*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total9[WIDTH:0]-w_want9):w_total9[WIDTH:0]; // 槽9合法回收与原子消费
if(!o_done)o_capacity[9*(WIDTH+1)+:WIDTH+1]<=w_cap9; // 槽9初始化容量学习
o_available[10*(WIDTH+1)+:WIDTH+1]<=(w_finish&&i_shared)?(w_total10[WIDTH:0]+w_total15[WIDTH:0]):(o_taken?(w_total10[WIDTH:0]-w_want10):w_total10[WIDTH:0]); // 槽10合法回收与原子消费
if(!o_done)o_capacity[10*(WIDTH+1)+:WIDTH+1]<=(w_finish&&i_shared)?(w_cap10+w_cap15):w_cap10; // 槽10初始化容量学习
o_available[11*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total11[WIDTH:0]-w_want11):w_total11[WIDTH:0]; // 槽11合法回收与原子消费
if(!o_done)o_capacity[11*(WIDTH+1)+:WIDTH+1]<=w_cap11; // 槽11初始化容量学习
o_available[12*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total12[WIDTH:0]-w_want12):w_total12[WIDTH:0]; // 槽12合法回收与原子消费
if(!o_done)o_capacity[12*(WIDTH+1)+:WIDTH+1]<=w_cap12; // 槽12初始化容量学习
o_available[13*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total13[WIDTH:0]-w_want13):w_total13[WIDTH:0]; // 槽13合法回收与原子消费
if(!o_done)o_capacity[13*(WIDTH+1)+:WIDTH+1]<=w_cap13; // 槽13初始化容量学习
o_available[14*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total14[WIDTH:0]-w_want14):w_total14[WIDTH:0]; // 槽14合法回收与原子消费
if(!o_done)o_capacity[14*(WIDTH+1)+:WIDTH+1]<=w_cap14; // 槽14初始化容量学习
o_available[15*(WIDTH+1)+:WIDTH+1]<=(w_finish&&i_shared)?{(WIDTH+1){1'b0}}:(o_taken?(w_total15[WIDTH:0]-w_want15):w_total15[WIDTH:0]); // 槽15合法回收与原子消费
if(!o_done)o_capacity[15*(WIDTH+1)+:WIDTH+1]<=(w_finish&&i_shared)?{(WIDTH+1){1'b0}}:w_cap15; // 槽15初始化容量学习
o_available[16*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total16[WIDTH:0]-w_want16):w_total16[WIDTH:0]; // 槽16合法回收与原子消费
if(!o_done)o_capacity[16*(WIDTH+1)+:WIDTH+1]<=w_cap16; // 槽16初始化容量学习
o_available[17*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total17[WIDTH:0]-w_want17):w_total17[WIDTH:0]; // 槽17合法回收与原子消费
if(!o_done)o_capacity[17*(WIDTH+1)+:WIDTH+1]<=w_cap17; // 槽17初始化容量学习
o_available[18*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total18[WIDTH:0]-w_want18):w_total18[WIDTH:0]; // 槽18合法回收与原子消费
if(!o_done)o_capacity[18*(WIDTH+1)+:WIDTH+1]<=w_cap18; // 槽18初始化容量学习
o_available[19*(WIDTH+1)+:WIDTH+1]<=o_taken?(w_total19[WIDTH:0]-w_want19):w_total19[WIDTH:0]; // 槽19合法回收与原子消费
if(!o_done)o_capacity[19*(WIDTH+1)+:WIDTH+1]<=w_cap19; // 槽19初始化容量学习
if(w_finish)begin o_done<=1'b1;o_shared<=i_shared;end // 完成后固定模式
end // 合法更新结束
end // 时序逻辑结束
endmodule // 账本模块结束
