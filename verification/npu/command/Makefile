VERILATOR ?= verilator
YOSYS ?= yosys
JOBS ?= 1

THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(THIS_DIR)/../../..)
BUILD_DIR := $(THIS_DIR)/build
RTL_DIR := $(REPO_ROOT)/rtl/npu
TOP := tb_npu_pod_command_gateway
SIM_DIR := $(BUILD_DIR)/verilator/$(TOP)
SIM_BIN := $(SIM_DIR)/V$(TOP)
FLAGS := --language 1800-2017 -Wall --timing

SOURCES := \
	$(RTL_DIR)/common/fp8_pkg.sv \
	$(RTL_DIR)/common/mxfp_pkg.sv \
	$(RTL_DIR)/vector/vector_pkg.sv \
	$(RTL_DIR)/scheduler/npu_scheduler_pkg.sv \
	$(RTL_DIR)/dma/npu_dma_pkg.sv \
	$(RTL_DIR)/pod/npu_pod_pkg.sv \
	$(RTL_DIR)/command/npu_command_pkg.sv \
	$(THIS_DIR)/pkg/npu_command_tb_pkg.sv \
	$(RTL_DIR)/command/npu_pod_command_gateway.sv \
	$(THIS_DIR)/vip/npu_decoded_command_source_vip.sv \
	$(THIS_DIR)/vip/npu_unified_completion_sink_vip.sv \
	$(THIS_DIR)/tb/$(TOP).sv

SYNTH_SOURCES := \
	$(THIS_DIR)/models/npu_scheduler_pkg_synth.sv \
	$(RTL_DIR)/dma/npu_dma_pkg.sv \
	$(RTL_DIR)/pod/npu_pod_pkg.sv \
	$(THIS_DIR)/models/npu_command_pkg_synth.sv \
	$(RTL_DIR)/command/npu_pod_command_gateway.sv

.PHONY: lint synth sim test clean

lint:
	mkdir -p $(BUILD_DIR)/verilator/lint
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(TOP) \
		--Mdir $(BUILD_DIR)/verilator/lint $(SOURCES)

synth:
	$(YOSYS) -q -p 'read_verilog -sv -D SYNTHESIS $(SYNTH_SOURCES); hierarchy -top npu_pod_command_gateway; proc; opt; check; stat'

$(SIM_BIN): $(SOURCES)
	mkdir -p $(SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) --top-module $(TOP) \
		--Mdir $(SIM_DIR) $(SOURCES)

sim: $(SIM_BIN)
	$(SIM_BIN)

test: lint synth sim

clean:
	rm -rf $(BUILD_DIR)
