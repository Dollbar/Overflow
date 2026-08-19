module tb_kdlink_v2_env_pkg;
    import kdlink_v2_env_pkg::*;
    kdlink_v2_endpoint_location_t location;
    initial begin
        if (KDLINK_V2_CARD_SLOTS != 8 || KDLINK_V2_NPUS_PER_CARD != 4 ||
            KDLINK_V2_NODES != 32 || KDLINK_V2_PLANES != 8 ||
            KDLINK_V2_SLICES_PER_PORT != 2 || KDLINK_V2_SLICES_PER_NPU != 16 ||
            KDLINK_V2_SLICES_PER_CARD != 64 || KDLINK_V2_ENDPOINT_SLICES != 512 ||
            KDLINK_V2_PCS_LANES != 10 || KDLINK_V2_PCS_BLOCK_WIDTH != 66 ||
            KDLINK_V2_PCS_GROUP_WIDTH != 660) begin
            $fatal(1, "KDLink environment package constants changed");
        end
        if (kdlink_v2_endpoint_index(7, 3, 7, 1) != 511) begin
            $fatal(1, "KDLink environment endpoint mapping changed");
        end
        location = kdlink_v2_decode_endpoint(511);
        if (location.slot_id != 7 || location.local_npu != 3 || location.node_id != 31 ||
            location.plane_id != 7 || location.slice_id != 1) begin
            $fatal(1, "KDLink environment endpoint decode changed");
        end
        $display("TB_KDLINK_V2_ENV_PKG_PASS slots=8 npus_per_card=4 nodes=32 planes=8 endpoints=512");
        $finish;
    end
endmodule
