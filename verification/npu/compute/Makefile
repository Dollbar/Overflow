VERILATOR ?= verilator
YOSYS ?= yosys
OPENSTA ?= sta
PYTHON ?= python3
GTKWAVE ?= gtkwave
JOBS ?= 1

THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(THIS_DIR)/../../..)
NPU_RTL_DIR := $(REPO_ROOT)/rtl/npu
COMMON_RTL_DIR := $(NPU_RTL_DIR)/common
TENSOR_RTL_DIR := $(NPU_RTL_DIR)/tensor
VECTOR_RTL_DIR := $(NPU_RTL_DIR)/vector
SCHEDULER_RTL_DIR := $(NPU_RTL_DIR)/scheduler
SRAM_RTL_DIR := $(NPU_RTL_DIR)/sram
COMPUTE_RTL_DIR := $(NPU_RTL_DIR)/compute
RTL_SEARCH_DIRS := $(COMMON_RTL_DIR) $(TENSOR_RTL_DIR) $(VECTOR_RTL_DIR) \
	$(SCHEDULER_RTL_DIR) $(SRAM_RTL_DIR) $(COMPUTE_RTL_DIR)
PKG_DIR := $(THIS_DIR)/pkg
VIP_DIR := $(THIS_DIR)/vip
MODEL_DIR := $(THIS_DIR)/models
TB_DIR := $(THIS_DIR)/tb
BUILD_DIR := $(THIS_DIR)/build
VERILATOR_DIR := $(BUILD_DIR)/verilator
REFERENCE_DIR := $(BUILD_DIR)/reference
WAVE_DIR := $(BUILD_DIR)/waves
SYNTH_DIR := $(BUILD_DIR)/synth
REPORT_DIR := $(BUILD_DIR)/reports
STA_DIR := $(THIS_DIR)/STA

# Foundry libraries are deliberately not bound to a developer workstation or
# copied into this open-source tree. Pass the exact readable SSG Liberty view
# through LIBERTY_SSG when invoking synth/sta/test.
LIBERTY_SSG ?=
CLOCK_PERIOD_NS ?= 1.000
CLOCK_UNCERTAINTY_NS ?= 0.030
INPUT_DELAY_NS ?= 0.050
OUTPUT_DELAY_NS ?= 0.050
OUTPUT_LOAD_PF ?= 0.005
ABC_DELAY_PS ?= 450

COMMON_FLAGS := --language 1800-2017 -Wall --timing
LARGE_BUILD_FLAGS ?= --output-split 20000 --output-split-cfuncs 20000

RTL_PACKAGES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(VECTOR_RTL_DIR)/vector_pkg.sv \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_pkg.sv

SYSTEM_PACKAGES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(VECTOR_RTL_DIR)/vector_pkg.sv \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_pkg.sv

KD28_SRAM_ADAPTER := $(SRAM_RTL_DIR)/kd28_npu_sram_adapter.sv
SYSTEM_ALL_RTL := $(sort $(foreach dir,$(RTL_SEARCH_DIRS),$(wildcard $(dir)/*.sv) $(wildcard $(dir)/*.v)))
SYSTEM_RTL := $(SYSTEM_PACKAGES) \
	$(filter-out $(SYSTEM_PACKAGES) $(KD28_SRAM_ADAPTER),$(SYSTEM_ALL_RTL))
SYSTEM_LINT_TILE_STUB := $(MODEL_DIR)/TILE_FP8_16_FIFO_lint_stub.sv
SYSTEM_LINT_RTL := $(SYSTEM_PACKAGES) \
	$(filter-out $(SYSTEM_PACKAGES) $(KD28_SRAM_ADAPTER) \
		$(TENSOR_RTL_DIR)/TILE_FP8_16_FIFO.sv,$(SYSTEM_ALL_RTL)) \
	$(SYSTEM_LINT_TILE_STUB)

SCHEDULER_RTL := \
	$(RTL_PACKAGES) \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_fifo.sv \
	$(SCHEDULER_RTL_DIR)/npu_input_scheduler.sv

VECTOR_RTL := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(VECTOR_RTL_DIR)/vector_pkg.sv \
	$(COMMON_RTL_DIR)/fp32_unpack.sv \
	$(COMMON_RTL_DIR)/fp32_subnormal_normalize.sv \
	$(COMMON_RTL_DIR)/fp32_significand_add.sv \
	$(COMMON_RTL_DIR)/fp32_normalize.sv \
	$(COMMON_RTL_DIR)/fp32_round_pack.sv \
	$(COMMON_RTL_DIR)/fp32_add_pipeline.sv \
	$(COMMON_RTL_DIR)/kogge_stone_adder_48.sv \
	$(COMMON_RTL_DIR)/fp32_mul_round_prepare.sv \
	$(COMMON_RTL_DIR)/fp32_mul_round_pack.sv \
	$(COMMON_RTL_DIR)/fp32_mul_pipeline.sv \
	$(COMMON_RTL_DIR)/fp32_compare.sv \
	$(COMMON_RTL_DIR)/fp32_to_fp8.sv \
	$(COMMON_RTL_DIR)/mxfp_apply_scale_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_scale_block32.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_block32_comb.sv \
	$(COMMON_RTL_DIR)/fp32_exp_mul_u19_u4.sv \
	$(COMMON_RTL_DIR)/fp32_exp_approx.sv \
	$(COMMON_RTL_DIR)/fp32_recip_pipeline.sv \
	$(COMMON_RTL_DIR)/fp32_rsqrt_pipeline.sv \
	$(COMMON_RTL_DIR)/fp32_add_one_pipeline.sv \
	$(COMMON_RTL_DIR)/fp32_sigmoid_pipeline.sv \
	$(VECTOR_RTL_DIR)/vector_alu16.sv \
	$(VECTOR_RTL_DIR)/gemm_epilogue16.sv \
	$(VECTOR_RTL_DIR)/vector_reduce16.sv \
	$(VECTOR_RTL_DIR)/vector_softmax_max_broadcast_slice.sv \
	$(VECTOR_RTL_DIR)/vector_softmax_recip_broadcast_slice.sv \
	$(VECTOR_RTL_DIR)/vector_softmax16.sv \
	$(VECTOR_RTL_DIR)/vector_norm_broadcast_slice.sv \
	$(VECTOR_RTL_DIR)/vector_norm16.sv \
	$(VECTOR_RTL_DIR)/vector_gelu16.sv \
	$(VECTOR_RTL_DIR)/vector_silu16.sv \
	$(VECTOR_RTL_DIR)/vector_engine_result_fifo.sv \
	$(VECTOR_RTL_DIR)/vector_epilogue_mx_adapter.sv \
	$(VECTOR_RTL_DIR)/vector_engine16.sv

DESCRIPTOR_RTL := \
	$(RTL_PACKAGES) \
	$(PKG_DIR)/npu_gemm_vector_tb_pkg.sv \
	$(VIP_DIR)/npu_descriptor_source_vip.sv \
	$(VIP_DIR)/npu_post_result_sink_vip.sv \
	$(SCHEDULER_RTL_DIR)/npu_descriptor_buffer.sv

SRAM_MODEL := $(MODEL_DIR)/sram_macro_model.sv

MX_RTL := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(COMMON_RTL_DIR)/booth_radix4_u4.sv \
	$(COMMON_RTL_DIR)/mxfp_unpack.sv \
	$(COMMON_RTL_DIR)/mxfp_to_fp32.sv \
	$(COMMON_RTL_DIR)/mxfp_mul_exact.sv

MX_ACCUM_RTL := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(SRAM_MODEL) \
	$(TENSOR_RTL_DIR)/tile_flush_buffer.sv \
	$(TENSOR_RTL_DIR)/gemm_control_tree_register.sv \
	$(TENSOR_RTL_DIR)/tile_control_inverter.sv \
	$(TENSOR_RTL_DIR)/tile_k_accum_state_mem.sv \
	$(TENSOR_RTL_DIR)/tile_k_accum_result_bank.sv \
	$(COMMON_RTL_DIR)/kogge_stone_adder_48.sv \
	$(COMMON_RTL_DIR)/mxfp_block_sum_to_fp32.sv \
	$(TENSOR_RTL_DIR)/tile_fp32_k_accumulator.sv

SCHEDULER_TOP := tb_npu_input_scheduler
VECTOR_TOP := tb_vector_engine16
DESCRIPTOR_TOP := tb_descriptor_path
SRAM_TOP := tb_sram_macro_contract
MX_TOP := tb_mxfp_numeric
MX_CONVERT_TOP := tb_mxfp_block_convert
MX_QUANT_TOP := tb_mxfp_quantize_block32
MX_ACCUM_TOP := tb_mxfp_k_accumulator
MX_FEEDBACK_TOP := tb_npu_gemm_feedback_writer16
MX_OUTPUT_TOP := tb_npu_post_output_formatter16
VECTOR_COUPLER_TOP := tb_npu_gemm_vector_coupler16_peak
LOCAL_BUFFER_TOP := tb_local_mx_buffers
TILE_MX_TOP := tb_tile_mx_gemm_path
TILE_K4096_TOP := tb_tile_mx_gemm_k4096
ARRAY16_PEAK_TOP := tb_gemm_array16_peak
M1_K8192_N8192_TOP := tb_gemm_m1_k8192_n8192
BUFFER_STREAM_TOP := tb_gemm_buffer_stream_peak
HETERO_LONG_TOP := tb_npu_heterogeneous_k8192
GIB_TASK_PAIRS ?= 128
NARROW_M ?= 4
BOUNDARY_SKEW_TOP := tb_gemm_boundary_skew
PE_EXACT_TOP := tb_pe_mx_exact

SCHEDULER_BIN := $(VERILATOR_DIR)/scheduler-sim/V$(SCHEDULER_TOP)
VECTOR_BIN := $(VERILATOR_DIR)/vector-sim/V$(VECTOR_TOP)
DESCRIPTOR_BIN := $(VERILATOR_DIR)/descriptor-sim/V$(DESCRIPTOR_TOP)
SRAM_BIN := $(VERILATOR_DIR)/sram-sim/V$(SRAM_TOP)
MX_BIN := $(VERILATOR_DIR)/mx-sim/V$(MX_TOP)
MX_CONVERT_BIN := $(VERILATOR_DIR)/mx-convert-sim/V$(MX_CONVERT_TOP)
MX_QUANT_BIN := $(VERILATOR_DIR)/mx-quant-sim/V$(MX_QUANT_TOP)
MX_ACCUM_BIN := $(VERILATOR_DIR)/mx-accum-sim/V$(MX_ACCUM_TOP)
MX_FEEDBACK_BIN := $(VERILATOR_DIR)/mx-feedback-sim/V$(MX_FEEDBACK_TOP)
MX_OUTPUT_BIN := $(VERILATOR_DIR)/mx-output-sim/V$(MX_OUTPUT_TOP)
VECTOR_COUPLER_BIN := $(VERILATOR_DIR)/vector-coupler-sim/V$(VECTOR_COUPLER_TOP)
LOCAL_BUFFER_BIN := $(VERILATOR_DIR)/local-buffer-sim/V$(LOCAL_BUFFER_TOP)
TILE_MX_BIN := $(VERILATOR_DIR)/tile-mx-sim/V$(TILE_MX_TOP)
TILE_K4096_BIN := $(VERILATOR_DIR)/tile-k4096-sim/V$(TILE_K4096_TOP)
ARRAY16_PEAK_BIN := $(VERILATOR_DIR)/array16-peak-sim/V$(ARRAY16_PEAK_TOP)
ARRAY16_PEAK_LOG := $(REPORT_DIR)/sim_array16_peak.log
M1_K8192_N8192_BIN := $(VERILATOR_DIR)/m1-k8192-n8192-sim/V$(M1_K8192_N8192_TOP)
M1_K8192_N8192_LOG := $(REPORT_DIR)/sim_m1_k8192_n8192.log
M2_K8192_N8192_BIN := $(VERILATOR_DIR)/m2-k8192-n8192-sim/V$(M1_K8192_N8192_TOP)
M2_K8192_N8192_LOG := $(REPORT_DIR)/sim_m2_k8192_n8192.log
NARROW_M_BIN := $(VERILATOR_DIR)/m$(NARROW_M)-k8192-n8192-sim/V$(M1_K8192_N8192_TOP)
NARROW_M_LOG := $(REPORT_DIR)/sim_m$(NARROW_M)_k8192_n8192.log
SHAPE_SWEEP_CSV := $(REPORT_DIR)/gemm_m_k8192_n8192_sweep.csv
SHAPE_SWEEP_MD := $(REPORT_DIR)/gemm_m_k8192_n8192_sweep.md
BUFFER_STREAM_BIN := $(VERILATOR_DIR)/buffer-stream-sim/V$(BUFFER_STREAM_TOP)
BUFFER_STREAM_LONG_BIN := $(VERILATOR_DIR)/buffer-stream-long-sim/V$(BUFFER_STREAM_TOP)
HETERO_LONG_BIN := $(VERILATOR_DIR)/heterogeneous-long-sim/V$(HETERO_LONG_TOP)
HETERO_GIB_BIN := $(VERILATOR_DIR)/heterogeneous-gib-sim/V$(HETERO_LONG_TOP)
HETERO_GIB_LOG := $(REPORT_DIR)/sim_heterogeneous_gib.log
BOUNDARY_SKEW_BIN := $(VERILATOR_DIR)/boundary-skew-sim/V$(BOUNDARY_SKEW_TOP)
PE_EXACT_BIN := $(VERILATOR_DIR)/pe-exact-sim/V$(PE_EXACT_TOP)
SCHEDULER_WAVE_BIN := $(VERILATOR_DIR)/scheduler-waves/V$(SCHEDULER_TOP)
VECTOR_WAVE_BIN := $(VERILATOR_DIR)/vector-waves/V$(VECTOR_TOP)
DESCRIPTOR_WAVE_BIN := $(VERILATOR_DIR)/descriptor-waves/V$(DESCRIPTOR_TOP)
SRAM_WAVE_BIN := $(VERILATOR_DIR)/sram-waves/V$(SRAM_TOP)
MX_CONVERT_WAVE_BIN := $(VERILATOR_DIR)/mx-convert-waves/V$(MX_CONVERT_TOP)
MX_QUANT_WAVE_BIN := $(VERILATOR_DIR)/mx-quant-waves/V$(MX_QUANT_TOP)
MX_ACCUM_WAVE_BIN := $(VERILATOR_DIR)/mx-accum-waves/V$(MX_ACCUM_TOP)
MX_FEEDBACK_WAVE_BIN := $(VERILATOR_DIR)/mx-feedback-waves/V$(MX_FEEDBACK_TOP)
MX_OUTPUT_WAVE_BIN := $(VERILATOR_DIR)/mx-output-waves/V$(MX_OUTPUT_TOP)
VECTOR_COUPLER_WAVE_BIN := $(VERILATOR_DIR)/vector-coupler-waves/V$(VECTOR_COUPLER_TOP)
LOCAL_BUFFER_WAVE_BIN := $(VERILATOR_DIR)/local-buffer-waves/V$(LOCAL_BUFFER_TOP)
TILE_MX_WAVE_BIN := $(VERILATOR_DIR)/tile-mx-waves/V$(TILE_MX_TOP)
BOUNDARY_SKEW_WAVE_BIN := $(VERILATOR_DIR)/boundary-skew-waves/V$(BOUNDARY_SKEW_TOP)

SCHEDULER_SOURCES := $(SCHEDULER_RTL) $(TB_DIR)/tb_npu_input_scheduler.sv
VECTOR_SOURCES := $(VECTOR_RTL) $(TB_DIR)/tb_vector_engine16.sv
DESCRIPTOR_SOURCES := $(DESCRIPTOR_RTL) $(TB_DIR)/tb_descriptor_path.sv
SRAM_SOURCES := $(SRAM_MODEL) $(TB_DIR)/tb_sram_macro_contract.sv
MX_SOURCES := $(MX_RTL) $(TB_DIR)/tb_mxfp_numeric.sv
MX_CONVERT_SOURCES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_block_sum_to_fp32.sv \
	$(TB_DIR)/tb_mxfp_block_convert.sv
MX_ACCUM_SOURCES := $(MX_ACCUM_RTL) $(TB_DIR)/tb_mxfp_k_accumulator.sv
MX_QUANT_SOURCES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(COMMON_RTL_DIR)/fp32_to_fp8.sv \
	$(COMMON_RTL_DIR)/mxfp_apply_scale_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_scale_block32.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_block32_comb.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_block32.sv \
	$(TB_DIR)/tb_mxfp_quantize_block32.sv
MX_FEEDBACK_SOURCES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(VECTOR_RTL_DIR)/vector_pkg.sv \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_pkg.sv \
	$(SRAM_MODEL) \
	$(COMMON_RTL_DIR)/fp32_to_fp8.sv \
	$(COMMON_RTL_DIR)/mxfp_apply_scale_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_scale_block32.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_block32_comb.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_block32.sv \
	$(COMPUTE_RTL_DIR)/npu_gemm_feedback_writer16.sv \
	$(TB_DIR)/tb_npu_gemm_feedback_writer16.sv
MX_OUTPUT_SOURCES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(VECTOR_RTL_DIR)/vector_pkg.sv \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_pkg.sv \
	$(COMMON_RTL_DIR)/fp32_to_fp8.sv \
	$(COMMON_RTL_DIR)/mxfp_apply_scale_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_scale_block32.sv \
	$(COMPUTE_RTL_DIR)/npu_post_output_formatter16.sv \
	$(TB_DIR)/tb_npu_post_output_formatter16.sv
VECTOR_COUPLER_SOURCES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(VECTOR_RTL_DIR)/vector_pkg.sv \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_unpack.sv \
	$(COMMON_RTL_DIR)/mxfp_to_fp32.sv \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_fifo.sv \
	$(MODEL_DIR)/npu_vector_engine_group_peak_model.sv \
	$(COMPUTE_RTL_DIR)/npu_gemm_vector_coupler16.sv \
	$(TB_DIR)/tb_npu_gemm_vector_coupler16_peak.sv
LOCAL_BUFFER_SOURCES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(VECTOR_RTL_DIR)/vector_pkg.sv \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_pkg.sv \
	$(SRAM_MODEL) \
	$(SRAM_RTL_DIR)/npu_local_tensor_buffer.sv \
	$(SRAM_RTL_DIR)/npu_local_vector_operand_buffer.sv \
	$(TB_DIR)/tb_local_mx_buffers.sv
GEMM_RTL_SOURCES := \
	$(filter-out $(SRAM_RTL_DIR)/sram_macro_blackbox.sv,$(SYSTEM_RTL)) \
	$(SRAM_MODEL)
TILE_MX_SOURCES := $(GEMM_RTL_SOURCES) $(TB_DIR)/tb_tile_mx_gemm_path.sv
TILE_K4096_SOURCES := \
	$(GEMM_RTL_SOURCES) \
	$(TB_DIR)/tb_tile_mx_gemm_k4096.sv
ARRAY16_TILE_LIB_NAME := array16_tile_model
ARRAY16_TILE_LIB_DIR := $(VERILATOR_DIR)/array16-tile-lib
ARRAY16_TILE_LIB_WRAPPER := $(ARRAY16_TILE_LIB_DIR)/$(ARRAY16_TILE_LIB_NAME).sv
ARRAY16_TILE_LIB_ARCHIVE := $(ARRAY16_TILE_LIB_DIR)/lib$(ARRAY16_TILE_LIB_NAME).a
ARRAY16_TILE_LIB_ADAPTER := $(MODEL_DIR)/TILE_FP8_16_FIFO_array16_lib.sv
ARRAY16_TILE_LIB_CONTROL := $(MODEL_DIR)/verilator_array16_lib.vlt
ARRAY16_TILE_LIB_SOURCES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(SRAM_MODEL) \
	$(TENSOR_RTL_DIR)/TILE_FP8_16_FIFO.sv \
	$(TENSOR_RTL_DIR)/TILE_FP8_16.sv \
	$(TENSOR_RTL_DIR)/PE_FP8.sv \
	$(TENSOR_RTL_DIR)/tile_fp32_k_accumulator.sv
ARRAY16_SHELL_RTL := \
	$(filter-out $(TENSOR_RTL_DIR)/TILE_FP8_16_FIFO.sv,$(GEMM_RTL_SOURCES))
ARRAY16_PEAK_SOURCES := \
	$(ARRAY16_TILE_LIB_CONTROL) \
	$(ARRAY16_SHELL_RTL) \
	$(ARRAY16_TILE_LIB_WRAPPER) \
	$(ARRAY16_TILE_LIB_ADAPTER) \
	$(TB_DIR)/tb_gemm_array16_peak.sv
M1_K8192_N8192_SOURCES := \
	$(ARRAY16_TILE_LIB_CONTROL) \
	$(ARRAY16_SHELL_RTL) \
	$(ARRAY16_TILE_LIB_WRAPPER) \
	$(ARRAY16_TILE_LIB_ADAPTER) \
	$(TB_DIR)/tb_gemm_m1_k8192_n8192.sv
BUFFER_STREAM_SOURCES := \
	$(ARRAY16_TILE_LIB_CONTROL) \
	$(ARRAY16_SHELL_RTL) \
	$(ARRAY16_TILE_LIB_WRAPPER) \
	$(ARRAY16_TILE_LIB_ADAPTER) \
	$(TB_DIR)/tb_gemm_buffer_stream_peak.sv
HETERO_LONG_SOURCES := \
	$(filter-out $(TENSOR_RTL_DIR)/GEMM_65536.sv \
		$(VECTOR_RTL_DIR)/npu_vector_engine_group.sv,$(GEMM_RTL_SOURCES)) \
	$(MODEL_DIR)/GEMM_65536_peak_model.sv \
	$(MODEL_DIR)/npu_vector_engine_group_peak_model.sv \
	$(PKG_DIR)/npu_gemm_vector_tb_pkg.sv \
	$(TB_DIR)/tb_npu_heterogeneous_k8192.sv
BOUNDARY_SKEW_SOURCES := \
	$(TENSOR_RTL_DIR)/gemm_boundary_skew.sv \
	$(TB_DIR)/tb_gemm_boundary_skew.sv
PE_DATAPATH_RTL := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(COMMON_RTL_DIR)/booth_radix4_u4.sv \
	$(COMMON_RTL_DIR)/mxfp_unpack.sv \
	$(COMMON_RTL_DIR)/mxfp_mul_exact.sv \
	$(TENSOR_RTL_DIR)/PE_FP8.sv
PE_EXACT_SOURCES := $(PE_DATAPATH_RTL) $(TB_DIR)/tb_pe_mx_exact.sv
PE_STA_RTL := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(COMMON_RTL_DIR)/booth_radix4_u4.sv \
	$(COMMON_RTL_DIR)/mxfp_unpack.sv \
	$(COMMON_RTL_DIR)/mxfp_mul_exact.sv \
	$(TENSOR_RTL_DIR)/PE_FP8.sv
PE_STA_TOP := PE_FP8
PE_STA_NETLIST := $(SYNTH_DIR)/PE_FP8_ssg.v
PE_STA_JSON := $(SYNTH_DIR)/PE_FP8_ssg.json
PE_STA_SYNTH_LOG := $(REPORT_DIR)/synth_PE_FP8_ssg.log
PE_STA_LOG := $(REPORT_DIR)/sta_PE_FP8_ssg_1ghz.log
PE_STA_SDC := $(STA_DIR)/sdc/PE_FP8_ssg_1ghz.sdc
PE_STA_SYNTH_SCRIPT := $(STA_DIR)/scripts/synth_pe_ssg.tcl
PE_STA_SCRIPT := $(STA_DIR)/scripts/sta_pe_ssg.tcl
PE_STA_FF_TECHMAP := $(STA_DIR)/scripts/tsmc28_sync_clear_map.v
PE_STA_ABC_CONSTR := $(STA_DIR)/scripts/abc_timing.constr
OUTPUT_STA_RTL := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(VECTOR_RTL_DIR)/vector_pkg.sv \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_pkg.sv \
	$(COMMON_RTL_DIR)/fp32_to_fp8.sv \
	$(COMMON_RTL_DIR)/mxfp_apply_scale_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_quantize_lane.sv \
	$(COMMON_RTL_DIR)/mxfp_scale_block32.sv \
	$(COMPUTE_RTL_DIR)/npu_post_output_formatter16.sv
OUTPUT_STA_TOP := npu_post_output_formatter16
OUTPUT_STA_NETLIST := $(SYNTH_DIR)/npu_post_output_formatter16_ssg.v
OUTPUT_STA_JSON := $(SYNTH_DIR)/npu_post_output_formatter16_ssg.json
OUTPUT_STA_SYNTH_LOG := $(REPORT_DIR)/synth_npu_post_output_formatter16_ssg.log
OUTPUT_STA_LOG := $(REPORT_DIR)/sta_npu_post_output_formatter16_ssg_1ghz.log
OUTPUT_STA_SDC := $(STA_DIR)/sdc/npu_post_output_formatter16_ssg_1ghz.sdc
OUTPUT_STA_SYNTH_SCRIPT := $(STA_DIR)/scripts/synth_slang_ssg.tcl
.PHONY: help lint lint-system lint-scheduler lint-vector lint-descriptor lint-sram lint-mx \
	lint-mx-convert lint-mx-accum sim sim-scheduler sim-vector sim-descriptor \
	lint-mx-quant sim-sram sim-mx sim-mx-convert sim-mx-quant sim-mx-accum \
	lint-mx-feedback sim-mx-feedback lint-mx-output sim-mx-output test references \
	lint-vector-coupler sim-vector-coupler \
	lint-local-buffer sim-local-buffer lint-tile-mx sim-tile-mx \
	lint-tile-k4096 sim-tile-k4096 \
		lint-array16-peak lint-m1-k8192-n8192 lint-m2-k8192-n8192 lint-narrow-m lint-narrow-m-sweep lint-buffer-stream lint-heterogeneous-long lint-heterogeneous-gib lint-boundary-skew \
	lint-pe-exact sim-pe-exact \
	sim-array16-peak sim-m1-k8192-n8192 sim-m2-k8192-n8192 sim-narrow-m sim-narrow-m-sweep sim-buffer-stream sim-buffer-stream-long \
		sim-heterogeneous-long sim-heterogeneous-gib sim-boundary-skew sim-peak shape-sweep \
	waves waves-scheduler waves-vector waves-descriptor waves-sram \
	waves-mx-convert waves-mx-quant waves-mx-accum waves-mx-feedback waves-mx-output \
	waves-vector-coupler \
	waves-local-buffer waves-tile-mx waves-boundary-skew \
	synth synth-pe-ssg synth-output-ssg \
	sta sta-pe-ssg sta-output-ssg view-waves clean

help:
	@echo "NPU compute integration verification targets:"
	@echo "  make lint        - run zero-warning Verilator lint for all environments"
	@echo "  make lint-system - lint 2x2 system wiring with the verified Tile interface model"
	@echo "  make sim         - build and run all deterministic self-checking tests"
	@echo "  make test        - run lint, references, RTL regressions, and SSG 1 GHz STA"
	@echo "  make sim-peak    - run K=4096 real-array, K=8192, and 1 GiB no-bubble regressions"
	@echo "  make sim-m1-k8192-n8192 - run the real-array M=1, K=8192, N=8192 regression"
	@echo "  make sim-m2-k8192-n8192 - run the real-array M=2, K=8192, N=8192 regression"
	@echo "  make sim-narrow-m NARROW_M=4 - run one M<=16 production-RTL regression"
	@echo "  make sim-narrow-m-sweep - run M=2,4,8,16 production-RTL regressions"
	@echo "  make shape-sweep - summarize M=2..8192 after the narrow-M RTL sweep"
	@echo "  make sim-heterogeneous-gib - stream 1 GiB through external/feedback routes"
	@echo "  make synth       - map PE and external MX formatter to TSMC28 SSG cells"
	@echo "  make sta         - require PE and external MX formatter SSG 1 GHz closure"
	@echo "  make waves       - rerun tests and write VCD files below build/waves"
	@echo "  make view-waves WAVE=descriptor_path - open one VCD with GTKWave"
	@echo "  make references  - regenerate deterministic Python reference vectors"
	@echo "  make clean       - remove generated build output"

lint: lint-system lint-scheduler lint-vector lint-descriptor lint-sram lint-mx \
	lint-mx-convert lint-mx-quant lint-mx-accum lint-mx-feedback \
	lint-mx-output \
	lint-vector-coupler \
	lint-local-buffer lint-pe-exact \
	lint-tile-mx lint-tile-k4096 lint-array16-peak lint-m1-k8192-n8192 lint-narrow-m-sweep lint-buffer-stream \
	lint-boundary-skew lint-heterogeneous-long lint-heterogeneous-gib

lint-system:
	mkdir -p $(VERILATOR_DIR)/system-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) \
		--top-module npu_square_gemm_system -GARRAY_DIM=2 \
		--Mdir $(VERILATOR_DIR)/system-lint $(SYSTEM_LINT_RTL)

lint-local-buffer:
	mkdir -p $(VERILATOR_DIR)/local-buffer-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(LOCAL_BUFFER_TOP) \
		--Mdir $(VERILATOR_DIR)/local-buffer-lint $(LOCAL_BUFFER_SOURCES)

lint-tile-mx:
	mkdir -p $(VERILATOR_DIR)/tile-mx-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(TILE_MX_TOP) \
		--Mdir $(VERILATOR_DIR)/tile-mx-lint $(TILE_MX_SOURCES)

lint-tile-k4096:
	mkdir -p $(VERILATOR_DIR)/tile-k4096-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(TILE_K4096_TOP) \
		--Mdir $(VERILATOR_DIR)/tile-k4096-lint $(TILE_K4096_SOURCES)

$(ARRAY16_TILE_LIB_WRAPPER): $(ARRAY16_TILE_LIB_SOURCES) $(THIS_DIR)/Makefile
	mkdir -p $(ARRAY16_TILE_LIB_DIR)
	$(VERILATOR) --cc --language 1800-2017 -Wall \
		--timescale-override /1fs --top-module TILE_FP8_16_FIFO \
		--lib-create $(ARRAY16_TILE_LIB_NAME) \
		--Mdir $(ARRAY16_TILE_LIB_DIR) $(ARRAY16_TILE_LIB_SOURCES) \
		$(foreach dir,$(RTL_SEARCH_DIRS),-y $(dir)) +libext+.sv+.v

$(ARRAY16_TILE_LIB_ARCHIVE): $(ARRAY16_TILE_LIB_WRAPPER)
	$(MAKE) -C $(ARRAY16_TILE_LIB_DIR) -f VTILE_FP8_16_FIFO.mk -j $(JOBS)

lint-array16-peak: $(ARRAY16_TILE_LIB_WRAPPER)
	mkdir -p $(VERILATOR_DIR)/array16-peak-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(ARRAY16_PEAK_TOP) \
		--Mdir $(VERILATOR_DIR)/array16-peak-lint $(ARRAY16_PEAK_SOURCES)

lint-m1-k8192-n8192: $(ARRAY16_TILE_LIB_WRAPPER)
	mkdir -p $(VERILATOR_DIR)/m1-k8192-n8192-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(M1_K8192_N8192_TOP) \
		--Mdir $(VERILATOR_DIR)/m1-k8192-n8192-lint $(M1_K8192_N8192_SOURCES)

lint-m2-k8192-n8192: $(ARRAY16_TILE_LIB_WRAPPER)
	mkdir -p $(VERILATOR_DIR)/m2-k8192-n8192-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) -GM_ELEMENTS=2 \
		--top-module $(M1_K8192_N8192_TOP) \
		--Mdir $(VERILATOR_DIR)/m2-k8192-n8192-lint $(M1_K8192_N8192_SOURCES)

lint-narrow-m:
	@test $(NARROW_M) -ge 2 -a $(NARROW_M) -le 16
	mkdir -p $(VERILATOR_DIR)/m$(NARROW_M)-k8192-n8192-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) -GM_ELEMENTS=$(NARROW_M) \
		--top-module $(M1_K8192_N8192_TOP) \
		--Mdir $(VERILATOR_DIR)/m$(NARROW_M)-k8192-n8192-lint \
		$(M1_K8192_N8192_SOURCES)

lint-narrow-m-sweep: lint-m2-k8192-n8192
	@set -e; for m in 4 8 16; do \
		$(MAKE) lint-narrow-m NARROW_M=$$m JOBS=$(JOBS); \
	done

lint-buffer-stream: $(ARRAY16_TILE_LIB_WRAPPER)
	mkdir -p $(VERILATOR_DIR)/buffer-stream-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(BUFFER_STREAM_TOP) \
		--Mdir $(VERILATOR_DIR)/buffer-stream-lint $(BUFFER_STREAM_SOURCES)

lint-heterogeneous-long:
	mkdir -p $(VERILATOR_DIR)/heterogeneous-long-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(HETERO_LONG_TOP) \
		--Mdir $(VERILATOR_DIR)/heterogeneous-long-lint $(HETERO_LONG_SOURCES)

lint-heterogeneous-gib:
	mkdir -p $(VERILATOR_DIR)/heterogeneous-gib-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) -GTASK_PAIRS=$(GIB_TASK_PAIRS) \
		-GMIN_OPERAND_BYTES=1073741824 \
		--top-module $(HETERO_LONG_TOP) \
		--Mdir $(VERILATOR_DIR)/heterogeneous-gib-lint $(HETERO_LONG_SOURCES)

lint-boundary-skew:
	mkdir -p $(VERILATOR_DIR)/boundary-skew-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(BOUNDARY_SKEW_TOP) \
		--Mdir $(VERILATOR_DIR)/boundary-skew-lint $(BOUNDARY_SKEW_SOURCES)

lint-pe-exact:
	mkdir -p $(VERILATOR_DIR)/pe-exact-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(PE_EXACT_TOP) \
		--Mdir $(VERILATOR_DIR)/pe-exact-lint $(PE_EXACT_SOURCES)

lint-mx-feedback:
	mkdir -p $(VERILATOR_DIR)/mx-feedback-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(MX_FEEDBACK_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-feedback-lint $(MX_FEEDBACK_SOURCES)

lint-mx-output:
	mkdir -p $(VERILATOR_DIR)/mx-output-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(MX_OUTPUT_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-output-lint $(MX_OUTPUT_SOURCES)

lint-vector-coupler:
	mkdir -p $(VERILATOR_DIR)/vector-coupler-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(VECTOR_COUPLER_TOP) \
		--Mdir $(VERILATOR_DIR)/vector-coupler-lint $(VECTOR_COUPLER_SOURCES)

lint-mx-quant:
	mkdir -p $(VERILATOR_DIR)/mx-quant-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(MX_QUANT_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-quant-lint $(MX_QUANT_SOURCES)

lint-scheduler:
	mkdir -p $(VERILATOR_DIR)/scheduler-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(SCHEDULER_TOP) \
		--Mdir $(VERILATOR_DIR)/scheduler-lint $(SCHEDULER_SOURCES)

lint-vector:
	mkdir -p $(VERILATOR_DIR)/vector-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(VECTOR_TOP) \
		--Mdir $(VERILATOR_DIR)/vector-lint $(VECTOR_SOURCES)

lint-descriptor:
	mkdir -p $(VERILATOR_DIR)/descriptor-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(DESCRIPTOR_TOP) \
		--Mdir $(VERILATOR_DIR)/descriptor-lint $(DESCRIPTOR_SOURCES)

lint-sram:
	mkdir -p $(VERILATOR_DIR)/sram-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(SRAM_TOP) \
		--Mdir $(VERILATOR_DIR)/sram-lint $(SRAM_SOURCES)

lint-mx:
	mkdir -p $(VERILATOR_DIR)/mx-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(MX_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-lint $(MX_SOURCES)

lint-mx-convert:
	mkdir -p $(VERILATOR_DIR)/mx-convert-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(MX_CONVERT_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-convert-lint $(MX_CONVERT_SOURCES)

sim: sim-scheduler sim-vector sim-descriptor sim-sram sim-mx sim-mx-convert \
	sim-mx-quant sim-mx-accum sim-mx-feedback sim-local-buffer \
	sim-mx-output \
	sim-vector-coupler \
	sim-pe-exact sim-tile-mx sim-boundary-skew

sim-peak: sim-tile-k4096 sim-array16-peak sim-m1-k8192-n8192 sim-narrow-m-sweep sim-buffer-stream \
	sim-buffer-stream-long sim-heterogeneous-long sim-heterogeneous-gib
	$(MAKE) shape-sweep

$(SCHEDULER_BIN): $(SCHEDULER_SOURCES)
	mkdir -p $(VERILATOR_DIR)/scheduler-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(SCHEDULER_TOP) --Mdir $(VERILATOR_DIR)/scheduler-sim \
		$(SCHEDULER_SOURCES)

sim-scheduler: $(SCHEDULER_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/scheduler-sim/V$(SCHEDULER_TOP)

$(VECTOR_BIN): $(VECTOR_SOURCES)
	mkdir -p $(VERILATOR_DIR)/vector-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(VECTOR_TOP) --Mdir $(VERILATOR_DIR)/vector-sim \
		$(VECTOR_SOURCES)

sim-vector: $(VECTOR_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/vector-sim/V$(VECTOR_TOP)

$(DESCRIPTOR_BIN): $(DESCRIPTOR_SOURCES)
	mkdir -p $(VERILATOR_DIR)/descriptor-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(DESCRIPTOR_TOP) --Mdir $(VERILATOR_DIR)/descriptor-sim \
		$(DESCRIPTOR_SOURCES)

sim-descriptor: $(DESCRIPTOR_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/descriptor-sim/V$(DESCRIPTOR_TOP)

$(SRAM_BIN): $(SRAM_SOURCES)
	mkdir -p $(VERILATOR_DIR)/sram-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(SRAM_TOP) --Mdir $(VERILATOR_DIR)/sram-sim \
		$(SRAM_SOURCES)

sim-sram: $(SRAM_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/sram-sim/V$(SRAM_TOP)

$(MX_BIN): $(MX_SOURCES) $(REFERENCE_DIR)/mxfp_decode.hex
	mkdir -p $(VERILATOR_DIR)/mx-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(MX_TOP) --Mdir $(VERILATOR_DIR)/mx-sim \
		$(MX_SOURCES)

lint-mx-accum:
	@mkdir -p $(VERILATOR_DIR)/mx-accum-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(MX_ACCUM_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-accum-lint $(MX_ACCUM_SOURCES)

sim-mx: $(MX_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/mx-sim/V$(MX_TOP)

$(MX_CONVERT_BIN): $(MX_CONVERT_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-convert-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(MX_CONVERT_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-convert-sim $(MX_CONVERT_SOURCES)

sim-mx-convert: $(MX_CONVERT_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/mx-convert-sim/V$(MX_CONVERT_TOP)

$(MX_QUANT_BIN): $(MX_QUANT_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-quant-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(MX_QUANT_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-quant-sim $(MX_QUANT_SOURCES)

sim-mx-quant: $(MX_QUANT_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/mx-quant-sim/V$(MX_QUANT_TOP)

$(MX_ACCUM_BIN): $(MX_ACCUM_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-accum-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(MX_ACCUM_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-accum-sim $(MX_ACCUM_SOURCES)

sim-mx-accum: $(MX_ACCUM_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/mx-accum-sim/V$(MX_ACCUM_TOP)

$(MX_FEEDBACK_BIN): $(MX_FEEDBACK_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-feedback-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(MX_FEEDBACK_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-feedback-sim $(MX_FEEDBACK_SOURCES)

sim-mx-feedback: $(MX_FEEDBACK_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/mx-feedback-sim/V$(MX_FEEDBACK_TOP)

$(MX_OUTPUT_BIN): $(MX_OUTPUT_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-output-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(MX_OUTPUT_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-output-sim $(MX_OUTPUT_SOURCES)

sim-mx-output: $(MX_OUTPUT_BIN)
	cd $(THIS_DIR) && $(MX_OUTPUT_BIN)

$(VECTOR_COUPLER_BIN): $(VECTOR_COUPLER_SOURCES)
	mkdir -p $(VERILATOR_DIR)/vector-coupler-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(VECTOR_COUPLER_TOP) \
		--Mdir $(VERILATOR_DIR)/vector-coupler-sim $(VECTOR_COUPLER_SOURCES)

sim-vector-coupler: $(VECTOR_COUPLER_BIN)
	cd $(THIS_DIR) && $(VECTOR_COUPLER_BIN)

$(LOCAL_BUFFER_BIN): $(LOCAL_BUFFER_SOURCES)
	mkdir -p $(VERILATOR_DIR)/local-buffer-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(LOCAL_BUFFER_TOP) \
		--Mdir $(VERILATOR_DIR)/local-buffer-sim $(LOCAL_BUFFER_SOURCES)

sim-local-buffer: $(LOCAL_BUFFER_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/local-buffer-sim/V$(LOCAL_BUFFER_TOP)

$(TILE_MX_BIN): $(TILE_MX_SOURCES)
	mkdir -p $(VERILATOR_DIR)/tile-mx-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(TILE_MX_TOP) \
		--Mdir $(VERILATOR_DIR)/tile-mx-sim $(TILE_MX_SOURCES)

sim-tile-mx: $(TILE_MX_BIN)
	cd $(THIS_DIR) && $(TILE_MX_BIN)

$(TILE_K4096_BIN): $(TILE_K4096_SOURCES)
	mkdir -p $(VERILATOR_DIR)/tile-k4096-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(TILE_K4096_TOP) \
		--Mdir $(VERILATOR_DIR)/tile-k4096-sim $(TILE_K4096_SOURCES)

sim-tile-k4096: $(TILE_K4096_BIN)
	cd $(THIS_DIR) && $(TILE_K4096_BIN)

$(ARRAY16_PEAK_BIN): $(ARRAY16_PEAK_SOURCES) $(ARRAY16_TILE_LIB_ARCHIVE)
	mkdir -p $(VERILATOR_DIR)/array16-peak-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) $(LARGE_BUILD_FLAGS) -j $(JOBS) \
		-LDFLAGS $(ARRAY16_TILE_LIB_ARCHIVE) \
		--top-module $(ARRAY16_PEAK_TOP) \
		--Mdir $(VERILATOR_DIR)/array16-peak-sim $(ARRAY16_PEAK_SOURCES)

sim-array16-peak: $(ARRAY16_PEAK_BIN)
	@mkdir -p $(REPORT_DIR)
	@status=0; cd $(THIS_DIR) && $(ARRAY16_PEAK_BIN) \
		> $(ARRAY16_PEAK_LOG) 2>&1 || status=$$?; \
		cat $(ARRAY16_PEAK_LOG); exit $$status

$(M1_K8192_N8192_BIN): $(M1_K8192_N8192_SOURCES) $(ARRAY16_TILE_LIB_ARCHIVE)
	mkdir -p $(VERILATOR_DIR)/m1-k8192-n8192-sim $(REPORT_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) $(LARGE_BUILD_FLAGS) -j $(JOBS) \
		-LDFLAGS $(ARRAY16_TILE_LIB_ARCHIVE) \
		--top-module $(M1_K8192_N8192_TOP) \
		--Mdir $(VERILATOR_DIR)/m1-k8192-n8192-sim $(M1_K8192_N8192_SOURCES)

sim-m1-k8192-n8192: $(M1_K8192_N8192_BIN)
	@status=0; cd $(THIS_DIR) && $(M1_K8192_N8192_BIN) \
		> $(M1_K8192_N8192_LOG) 2>&1 || status=$$?; \
		cat $(M1_K8192_N8192_LOG); exit $$status

$(M2_K8192_N8192_BIN): $(M1_K8192_N8192_SOURCES) $(ARRAY16_TILE_LIB_ARCHIVE)
	mkdir -p $(VERILATOR_DIR)/m2-k8192-n8192-sim $(REPORT_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) $(LARGE_BUILD_FLAGS) -j $(JOBS) \
		-GM_ELEMENTS=2 -LDFLAGS $(ARRAY16_TILE_LIB_ARCHIVE) \
		--top-module $(M1_K8192_N8192_TOP) \
		--Mdir $(VERILATOR_DIR)/m2-k8192-n8192-sim $(M1_K8192_N8192_SOURCES)

sim-m2-k8192-n8192: $(M2_K8192_N8192_BIN)
	@status=0; cd $(THIS_DIR) && $(M2_K8192_N8192_BIN) \
		> $(M2_K8192_N8192_LOG) 2>&1 || status=$$?; \
		cat $(M2_K8192_N8192_LOG); exit $$status

$(NARROW_M_BIN): $(M1_K8192_N8192_SOURCES) $(ARRAY16_TILE_LIB_ARCHIVE)
	mkdir -p $(VERILATOR_DIR)/m$(NARROW_M)-k8192-n8192-sim $(REPORT_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) $(LARGE_BUILD_FLAGS) -j $(JOBS) \
		-GM_ELEMENTS=$(NARROW_M) -LDFLAGS $(ARRAY16_TILE_LIB_ARCHIVE) \
		--top-module $(M1_K8192_N8192_TOP) \
		--Mdir $(VERILATOR_DIR)/m$(NARROW_M)-k8192-n8192-sim \
		$(M1_K8192_N8192_SOURCES)

sim-narrow-m: $(NARROW_M_BIN)
	@status=0; cd $(THIS_DIR) && $(NARROW_M_BIN) \
		> $(NARROW_M_LOG) 2>&1 || status=$$?; \
		cat $(NARROW_M_LOG); exit $$status

sim-narrow-m-sweep: sim-m2-k8192-n8192
	@set -e; for m in 4 8 16; do \
		$(MAKE) sim-narrow-m NARROW_M=$$m JOBS=$(JOBS); \
	done

shape-sweep:
	mkdir -p $(REPORT_DIR)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) $(MODEL_DIR)/gemm_shape_sweep.py \
		--report-dir $(REPORT_DIR) --require-rtl-logs \
		--csv $(SHAPE_SWEEP_CSV) --markdown $(SHAPE_SWEEP_MD)

$(BUFFER_STREAM_BIN): $(BUFFER_STREAM_SOURCES) $(ARRAY16_TILE_LIB_ARCHIVE)
	mkdir -p $(VERILATOR_DIR)/buffer-stream-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) $(LARGE_BUILD_FLAGS) -j $(JOBS) \
		-LDFLAGS $(ARRAY16_TILE_LIB_ARCHIVE) \
		--top-module $(BUFFER_STREAM_TOP) \
		--Mdir $(VERILATOR_DIR)/buffer-stream-sim $(BUFFER_STREAM_SOURCES)

sim-buffer-stream: $(BUFFER_STREAM_BIN)
	cd $(THIS_DIR) && $(BUFFER_STREAM_BIN)

$(BUFFER_STREAM_LONG_BIN): $(BUFFER_STREAM_SOURCES) $(ARRAY16_TILE_LIB_ARCHIVE)
	mkdir -p $(VERILATOR_DIR)/buffer-stream-long-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) $(LARGE_BUILD_FLAGS) -j $(JOBS) \
		-GK_ELEMENTS=4096 -LDFLAGS $(ARRAY16_TILE_LIB_ARCHIVE) \
		--top-module $(BUFFER_STREAM_TOP) \
		--Mdir $(VERILATOR_DIR)/buffer-stream-long-sim $(BUFFER_STREAM_SOURCES)

sim-buffer-stream-long: $(BUFFER_STREAM_LONG_BIN)
	cd $(THIS_DIR) && $(BUFFER_STREAM_LONG_BIN)

$(HETERO_LONG_BIN): $(HETERO_LONG_SOURCES)
	mkdir -p $(VERILATOR_DIR)/heterogeneous-long-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) $(LARGE_BUILD_FLAGS) -j $(JOBS) \
		--top-module $(HETERO_LONG_TOP) \
		--Mdir $(VERILATOR_DIR)/heterogeneous-long-sim $(HETERO_LONG_SOURCES)

sim-heterogeneous-long: $(HETERO_LONG_BIN)
	cd $(THIS_DIR) && $(HETERO_LONG_BIN)

$(HETERO_GIB_BIN): $(HETERO_LONG_SOURCES)
	mkdir -p $(VERILATOR_DIR)/heterogeneous-gib-sim $(WAVE_DIR) $(REPORT_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) $(LARGE_BUILD_FLAGS) -j $(JOBS) \
		-GTASK_PAIRS=$(GIB_TASK_PAIRS) -GMIN_OPERAND_BYTES=1073741824 \
		--top-module $(HETERO_LONG_TOP) \
		--Mdir $(VERILATOR_DIR)/heterogeneous-gib-sim $(HETERO_LONG_SOURCES)

sim-heterogeneous-gib: $(HETERO_GIB_BIN)
	@status=0; cd $(THIS_DIR) && $(HETERO_GIB_BIN) > $(HETERO_GIB_LOG) 2>&1 || status=$$?; \
		cat $(HETERO_GIB_LOG); exit $$status

$(BOUNDARY_SKEW_BIN): $(BOUNDARY_SKEW_SOURCES)
	mkdir -p $(VERILATOR_DIR)/boundary-skew-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(BOUNDARY_SKEW_TOP) \
		--Mdir $(VERILATOR_DIR)/boundary-skew-sim $(BOUNDARY_SKEW_SOURCES)

sim-boundary-skew: $(BOUNDARY_SKEW_BIN)
	cd $(THIS_DIR) && $(BOUNDARY_SKEW_BIN)

$(PE_EXACT_BIN): $(PE_EXACT_SOURCES)
	mkdir -p $(VERILATOR_DIR)/pe-exact-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(PE_EXACT_TOP) \
		--Mdir $(VERILATOR_DIR)/pe-exact-sim $(PE_EXACT_SOURCES)

sim-pe-exact: $(PE_EXACT_BIN)
	cd $(THIS_DIR) && $(PE_EXACT_BIN)

$(REFERENCE_DIR)/mxfp_decode.hex: $(MODEL_DIR)/mxfp_reference.py
	mkdir -p $(REFERENCE_DIR)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) $(MODEL_DIR)/mxfp_reference.py \
		--output $@

references:
	mkdir -p $(REFERENCE_DIR)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) $(MODEL_DIR)/vector_fp_reference.py \
		--mul-output $(REFERENCE_DIR)/fp32_mul.hex \
		--compare-output $(REFERENCE_DIR)/fp32_compare.hex \
		--fp8-to-fp32-output $(REFERENCE_DIR)/fp8_to_fp32.hex \
		--fp32-to-fp8-output $(REFERENCE_DIR)/fp32_to_fp8.hex --count 128
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$(MODEL_DIR) $(PYTHON) $(MODEL_DIR)/vector_softmax16_reference.py \
		--output $(REFERENCE_DIR)/vector_softmax16.hex --count 64
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$(MODEL_DIR) $(PYTHON) $(MODEL_DIR)/vector_norm16_reference.py \
		--output $(REFERENCE_DIR)/vector_norm16.hex --count 64
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$(MODEL_DIR) $(PYTHON) $(MODEL_DIR)/vector_gelu16_reference.py \
		--output $(REFERENCE_DIR)/vector_gelu16.hex --count 64
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$(MODEL_DIR) $(PYTHON) $(MODEL_DIR)/vector_silu16_reference.py \
		--output $(REFERENCE_DIR)/vector_silu16.hex --count 64
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) $(MODEL_DIR)/mxfp_reference.py \
		--output $(REFERENCE_DIR)/mxfp_decode.hex

test: lint references sim sim-peak sta

synth: synth-pe-ssg synth-output-ssg

$(PE_STA_NETLIST): $(PE_STA_RTL) $(PE_STA_SYNTH_SCRIPT) \
		$(PE_STA_FF_TECHMAP) $(PE_STA_ABC_CONSTR)
	@test -n "$$(command -v "$(YOSYS)")" || { echo "ERROR: YOSYS='$(YOSYS)' is not executable or not on PATH" >&2; exit 2; }
	@test -n "$(LIBERTY_SSG)" || { echo "ERROR: set LIBERTY_SSG to the exact readable SSG Liberty file" >&2; exit 2; }
	@test -r "$(LIBERTY_SSG)" || { echo "ERROR: LIBERTY_SSG is not readable: $(LIBERTY_SSG)" >&2; exit 2; }
	mkdir -p $(SYNTH_DIR) $(REPORT_DIR)
	@status=0; env LIBERTY="$(LIBERTY_SSG)" RTL="$(PE_STA_RTL)" \
		TOP="$(PE_STA_TOP)" ABC_DELAY_PS="$(ABC_DELAY_PS)" \
		ABC_CONSTR="$(PE_STA_ABC_CONSTR)" \
		FF_TECHMAP="$(PE_STA_FF_TECHMAP)" NETLIST="$(PE_STA_NETLIST)" \
		JSON="$(PE_STA_JSON)" $(YOSYS) -c $(PE_STA_SYNTH_SCRIPT) \
		> $(PE_STA_SYNTH_LOG) 2>&1 || status=$$?; \
	cat $(PE_STA_SYNTH_LOG); exit $$status
	sed -i 's/ signed / /g' $(PE_STA_NETLIST)
	@test -s $(PE_STA_NETLIST)

synth-pe-ssg: $(PE_STA_NETLIST)

$(OUTPUT_STA_NETLIST): $(OUTPUT_STA_RTL) $(OUTPUT_STA_SYNTH_SCRIPT) \
		$(PE_STA_FF_TECHMAP) $(PE_STA_ABC_CONSTR)
	@test -n "$$(command -v "$(YOSYS)")" || { echo "ERROR: YOSYS='$(YOSYS)' is not executable or not on PATH" >&2; exit 2; }
	@test -n "$(LIBERTY_SSG)" || { echo "ERROR: set LIBERTY_SSG to the exact readable SSG Liberty file" >&2; exit 2; }
	@test -r "$(LIBERTY_SSG)" || { echo "ERROR: LIBERTY_SSG is not readable: $(LIBERTY_SSG)" >&2; exit 2; }
	mkdir -p $(SYNTH_DIR) $(REPORT_DIR)
	@status=0; env LIBERTY="$(LIBERTY_SSG)" RTL="$(OUTPUT_STA_RTL)" \
		TOP="$(OUTPUT_STA_TOP)" ABC_DELAY_PS="$(ABC_DELAY_PS)" \
		ABC_CONSTR="$(PE_STA_ABC_CONSTR)" \
		FF_TECHMAP="$(PE_STA_FF_TECHMAP)" NETLIST="$(OUTPUT_STA_NETLIST)" \
		JSON="$(OUTPUT_STA_JSON)" $(YOSYS) -c $(OUTPUT_STA_SYNTH_SCRIPT) \
		> $(OUTPUT_STA_SYNTH_LOG) 2>&1 || status=$$?; \
	cat $(OUTPUT_STA_SYNTH_LOG); exit $$status
	sed -i 's/ signed / /g' $(OUTPUT_STA_NETLIST)
	@test -s $(OUTPUT_STA_NETLIST)

synth-output-ssg: $(OUTPUT_STA_NETLIST)

sta: sta-pe-ssg sta-output-ssg

sta-pe-ssg: $(PE_STA_NETLIST) $(PE_STA_SCRIPT) $(PE_STA_SDC)
	@test -n "$$(command -v "$(OPENSTA)")" || { echo "ERROR: OPENSTA='$(OPENSTA)' is not executable or not on PATH" >&2; exit 2; }
	@test -n "$(LIBERTY_SSG)" || { echo "ERROR: set LIBERTY_SSG to the exact readable SSG Liberty file" >&2; exit 2; }
	@test -r "$(LIBERTY_SSG)" || { echo "ERROR: LIBERTY_SSG is not readable: $(LIBERTY_SSG)" >&2; exit 2; }
	mkdir -p $(REPORT_DIR)
	@status=0; env LIBERTY="$(LIBERTY_SSG)" NETLIST="$(PE_STA_NETLIST)" \
		TOP="$(PE_STA_TOP)" SDC="$(PE_STA_SDC)" \
		CLOCK_PERIOD_NS="$(CLOCK_PERIOD_NS)" \
		CLOCK_UNCERTAINTY_NS="$(CLOCK_UNCERTAINTY_NS)" \
		INPUT_DELAY_NS="$(INPUT_DELAY_NS)" \
		OUTPUT_DELAY_NS="$(OUTPUT_DELAY_NS)" \
		OUTPUT_LOAD_PF="$(OUTPUT_LOAD_PF)" \
		$(OPENSTA) -no_init $(PE_STA_SCRIPT) > $(PE_STA_LOG) 2>&1 \
		|| status=$$?; cat $(PE_STA_LOG); exit $$status

sta-output-ssg: $(OUTPUT_STA_NETLIST) $(PE_STA_SCRIPT) $(OUTPUT_STA_SDC)
	@test -n "$$(command -v "$(OPENSTA)")" || { echo "ERROR: OPENSTA='$(OPENSTA)' is not executable or not on PATH" >&2; exit 2; }
	@test -n "$(LIBERTY_SSG)" || { echo "ERROR: set LIBERTY_SSG to the exact readable SSG Liberty file" >&2; exit 2; }
	@test -r "$(LIBERTY_SSG)" || { echo "ERROR: LIBERTY_SSG is not readable: $(LIBERTY_SSG)" >&2; exit 2; }
	mkdir -p $(REPORT_DIR)
	@status=0; env LIBERTY="$(LIBERTY_SSG)" NETLIST="$(OUTPUT_STA_NETLIST)" \
		TOP="$(OUTPUT_STA_TOP)" SDC="$(OUTPUT_STA_SDC)" \
		CLOCK_PERIOD_NS="$(CLOCK_PERIOD_NS)" \
		CLOCK_UNCERTAINTY_NS="$(CLOCK_UNCERTAINTY_NS)" \
		INPUT_DELAY_NS="$(INPUT_DELAY_NS)" \
		OUTPUT_DELAY_NS="$(OUTPUT_DELAY_NS)" \
		OUTPUT_LOAD_PF="$(OUTPUT_LOAD_PF)" \
		$(OPENSTA) -no_init $(PE_STA_SCRIPT) > $(OUTPUT_STA_LOG) 2>&1 \
		|| status=$$?; cat $(OUTPUT_STA_LOG); exit $$status

$(SCHEDULER_WAVE_BIN): $(SCHEDULER_SOURCES)
	mkdir -p $(VERILATOR_DIR)/scheduler-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(SCHEDULER_TOP) --Mdir $(VERILATOR_DIR)/scheduler-waves \
		$(SCHEDULER_SOURCES)

$(VECTOR_WAVE_BIN): $(VECTOR_SOURCES)
	mkdir -p $(VERILATOR_DIR)/vector-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(VECTOR_TOP) --Mdir $(VERILATOR_DIR)/vector-waves \
		$(VECTOR_SOURCES)

$(DESCRIPTOR_WAVE_BIN): $(DESCRIPTOR_SOURCES)
	mkdir -p $(VERILATOR_DIR)/descriptor-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(DESCRIPTOR_TOP) --Mdir $(VERILATOR_DIR)/descriptor-waves \
		$(DESCRIPTOR_SOURCES)

$(SRAM_WAVE_BIN): $(SRAM_SOURCES)
	mkdir -p $(VERILATOR_DIR)/sram-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(SRAM_TOP) --Mdir $(VERILATOR_DIR)/sram-waves \
		$(SRAM_SOURCES)

$(MX_CONVERT_WAVE_BIN): $(MX_CONVERT_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-convert-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(MX_CONVERT_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-convert-waves $(MX_CONVERT_SOURCES)

$(MX_QUANT_WAVE_BIN): $(MX_QUANT_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-quant-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(MX_QUANT_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-quant-waves $(MX_QUANT_SOURCES)

$(MX_ACCUM_WAVE_BIN): $(MX_ACCUM_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-accum-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(MX_ACCUM_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-accum-waves $(MX_ACCUM_SOURCES)

$(MX_FEEDBACK_WAVE_BIN): $(MX_FEEDBACK_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-feedback-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(MX_FEEDBACK_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-feedback-waves $(MX_FEEDBACK_SOURCES)

$(MX_OUTPUT_WAVE_BIN): $(MX_OUTPUT_SOURCES)
	mkdir -p $(VERILATOR_DIR)/mx-output-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(MX_OUTPUT_TOP) \
		--Mdir $(VERILATOR_DIR)/mx-output-waves $(MX_OUTPUT_SOURCES)

$(VECTOR_COUPLER_WAVE_BIN): $(VECTOR_COUPLER_SOURCES)
	mkdir -p $(VERILATOR_DIR)/vector-coupler-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(VECTOR_COUPLER_TOP) \
		--Mdir $(VERILATOR_DIR)/vector-coupler-waves $(VECTOR_COUPLER_SOURCES)

$(LOCAL_BUFFER_WAVE_BIN): $(LOCAL_BUFFER_SOURCES)
	mkdir -p $(VERILATOR_DIR)/local-buffer-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(LOCAL_BUFFER_TOP) \
		--Mdir $(VERILATOR_DIR)/local-buffer-waves $(LOCAL_BUFFER_SOURCES)

$(TILE_MX_WAVE_BIN): $(TILE_MX_SOURCES)
	mkdir -p $(VERILATOR_DIR)/tile-mx-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(TILE_MX_TOP) \
		--Mdir $(VERILATOR_DIR)/tile-mx-waves $(TILE_MX_SOURCES)

$(BOUNDARY_SKEW_WAVE_BIN): $(BOUNDARY_SKEW_SOURCES)
	mkdir -p $(VERILATOR_DIR)/boundary-skew-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(BOUNDARY_SKEW_TOP) \
		--Mdir $(VERILATOR_DIR)/boundary-skew-waves $(BOUNDARY_SKEW_SOURCES)

waves-scheduler: $(SCHEDULER_WAVE_BIN)
	cd $(THIS_DIR) && $(SCHEDULER_WAVE_BIN)

waves-vector: $(VECTOR_WAVE_BIN)
	cd $(THIS_DIR) && $(VECTOR_WAVE_BIN)

waves-descriptor: $(DESCRIPTOR_WAVE_BIN)
	cd $(THIS_DIR) && $(DESCRIPTOR_WAVE_BIN)

waves-sram: $(SRAM_WAVE_BIN)
	cd $(THIS_DIR) && $(SRAM_WAVE_BIN)

waves-mx-convert: $(MX_CONVERT_WAVE_BIN)
	cd $(THIS_DIR) && $(MX_CONVERT_WAVE_BIN)

waves-mx-quant: $(MX_QUANT_WAVE_BIN)
	cd $(THIS_DIR) && $(MX_QUANT_WAVE_BIN)

waves-mx-accum: $(MX_ACCUM_WAVE_BIN)
	cd $(THIS_DIR) && $(MX_ACCUM_WAVE_BIN)

waves-mx-feedback: $(MX_FEEDBACK_WAVE_BIN)
	cd $(THIS_DIR) && $(MX_FEEDBACK_WAVE_BIN)

waves-mx-output: $(MX_OUTPUT_WAVE_BIN)
	cd $(THIS_DIR) && $(MX_OUTPUT_WAVE_BIN)

waves-vector-coupler: $(VECTOR_COUPLER_WAVE_BIN)
	cd $(THIS_DIR) && $(VECTOR_COUPLER_WAVE_BIN)

waves-local-buffer: $(LOCAL_BUFFER_WAVE_BIN)
	cd $(THIS_DIR) && $(LOCAL_BUFFER_WAVE_BIN)

waves-tile-mx: $(TILE_MX_WAVE_BIN)
	cd $(THIS_DIR) && $(TILE_MX_WAVE_BIN)

waves-boundary-skew: $(BOUNDARY_SKEW_WAVE_BIN)
	cd $(THIS_DIR) && $(BOUNDARY_SKEW_WAVE_BIN)

waves: waves-scheduler waves-vector waves-descriptor waves-sram \
	waves-mx-convert waves-mx-quant waves-mx-accum waves-mx-feedback \
	waves-mx-output \
	waves-vector-coupler \
	waves-local-buffer waves-tile-mx waves-boundary-skew

WAVE ?= descriptor_path
view-waves:
	$(GTKWAVE) $(WAVE_DIR)/$(WAVE).vcd $(THIS_DIR)/waves/$(WAVE).gtkw

clean:
	rm -rf $(BUILD_DIR)
