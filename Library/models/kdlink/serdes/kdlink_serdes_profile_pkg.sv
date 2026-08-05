package kdlink_serdes_profile_pkg;
    localparam integer SERDES_MODULATION_NRZ = 1;
    localparam integer SERDES_MODULATION_PAM4 = 2;

    localparam integer SERDES_25G_NRZ_LINE_RATE_KBPS = 25_781_250;
    localparam integer SERDES_25G_NRZ_GROUP_CLOCK_HZ = 390_625_000;

    localparam integer SERDES_53G_PAM4_LINE_RATE_KBPS = 53_125_000;
    localparam integer SERDES_53G_PAM4_GROUP_CLOCK_HZ_ROUNDED = 804_924_242;

    localparam integer SERDES_106G_PAM4_LINE_RATE_KBPS = 106_250_000;
    localparam integer SERDES_106G_PAM4_BLOCK_CAPACITY_HZ_ROUNDED = 1_609_848_485;

    localparam integer KDLINK_LOGICAL_GROUP_CLOCK_HZ = 1_000_000_000;
    localparam integer KDLINK_LANES_PER_SLICE = 10;
    localparam integer KDLINK_BLOCK_BITS = 66;
    localparam integer KDLINK_DATA_BITS_PER_BLOCK = 64;
    localparam integer KDLINK_PAYLOAD_BITS_PER_FLIT = 512;
endpackage
