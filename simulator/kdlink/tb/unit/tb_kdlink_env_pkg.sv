module tb_kdlink_env_pkg;
    import kdlink_env_pkg::*;
    kdlink_endpoint_location_t location;
    int unsigned endpoint_index;
    int unsigned profile_index;
    int unsigned expected_npu_count;
    int unsigned expected_node;
    int unsigned expected_slot;
    int unsigned expected_local_npu;
    int unsigned expected_plane;
    int unsigned expected_slice;
    initial begin
        if (KDLINK_MAX_CARD_SLOTS != 32 || KDLINK_DEFAULT_CARD_SLOTS != 8 ||
            KDLINK_DEFAULT_NPUS_PER_CARD != 4 || KDLINK_CARD_SLOTS != 8 || KDLINK_NPUS_PER_CARD != 4 ||
            KDLINK_NODES != 32 || KDLINK_PLANES != 8 ||
            KDLINK_SLICES_PER_PORT != 2 || KDLINK_SLICES_PER_NPU != 16 ||
            KDLINK_SLICES_PER_CARD != 64 || KDLINK_ENDPOINT_SLICES != 512 ||
            KDLINK_PCS_LANES != 10 || KDLINK_PCS_BLOCK_WIDTH != 66 ||
            KDLINK_PCS_GROUP_WIDTH != 660) begin
            $fatal(1, "KDLink environment package constants changed");
        end
        if (KDLINK_NPU_COUNT_CODE_1 != 0 || KDLINK_NPU_COUNT_CODE_2 != 1 ||
            KDLINK_NPU_COUNT_CODE_4 != 2 || KDLINK_NPU_COUNT_CODE_8 != 3 ||
            KDLINK_NPU_COUNT_CODE_16 != 4 || KDLINK_NPU_COUNT_CODE_32 != 5) begin
            $fatal(1, "KDLink card profile code mapping changed");
        end
        for (profile_index = 0; profile_index < 8; profile_index++) begin
            expected_npu_count = (profile_index < 6) ? (1 << profile_index) : 0;
            if (kdlink_npu_count_code_is_valid(profile_index[2:0]) !=
                    (profile_index < 6) ||
                kdlink_npu_count_from_code(profile_index[2:0]) != expected_npu_count ||
                kdlink_card_slices_from_code(profile_index[2:0]) !=
                    (expected_npu_count * KDLINK_SLICES_PER_NPU)) begin
                $fatal(1, "KDLink card profile helper mismatch code=%0d", profile_index);
            end
        end
        for (endpoint_index = 0; endpoint_index < KDLINK_ENDPOINT_SLICES;
             endpoint_index++) begin
            location = kdlink_decode_endpoint(endpoint_index);
            expected_node = endpoint_index / KDLINK_SLICES_PER_NPU;
            expected_slot = expected_node / KDLINK_DEFAULT_NPUS_PER_CARD;
            expected_local_npu = expected_node % KDLINK_DEFAULT_NPUS_PER_CARD;
            expected_plane = (endpoint_index % KDLINK_SLICES_PER_NPU) /
                KDLINK_SLICES_PER_PORT;
            expected_slice = endpoint_index % KDLINK_SLICES_PER_PORT;
            if (int'(location.node_id) != expected_node ||
                int'(location.slot_id) != expected_slot ||
                int'(location.local_npu) != expected_local_npu ||
                int'(location.plane_id) != expected_plane ||
                int'(location.slice_id) != expected_slice ||
                kdlink_endpoint_index(expected_slot, expected_local_npu,
                                      expected_plane, expected_slice) != endpoint_index) begin
                $fatal(1, "KDLink endpoint package round trip failed endpoint=%0d", endpoint_index);
            end
        end
        $display("TB_KDLINK_ENV_PKG_PASS max_slots=32 default_slots=8 default_npus_per_card=4 profiles=6 nodes=32 planes=8 endpoints=512");
        $finish;
    end
endmodule
