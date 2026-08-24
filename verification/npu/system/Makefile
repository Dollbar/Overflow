VERILATOR ?= verilator
YOSYS ?= yosys

THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(THIS_DIR)/../../..)
BUILD_DIR := $(THIS_DIR)/build
RTL := $(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_egress.sv
TB := $(THIS_DIR)/tb/tb_npu_dma_hbm_egress.sv
TOP := tb_npu_dma_hbm_egress
SIM_DIR := $(BUILD_DIR)/verilator/$(TOP)
SIM_BIN := $(SIM_DIR)/V$(TOP)
FLAGS := --language 1800-2017 -Wall --timing

.PHONY: lint synth-readiness sim test clean

lint:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(TOP) $(RTL) $(TB)

synth-readiness:
	$(YOSYS) -q -p 'read_verilog -sv $(RTL); hierarchy -top npu_dma_hbm_egress; proc; opt; check; stat'

$(SIM_BIN): $(RTL) $(TB)
	@mkdir -p $(SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(TOP) \
		--Mdir $(SIM_DIR) $(RTL) $(TB)

sim: $(SIM_BIN)
	$(SIM_BIN)

test: lint synth-readiness sim

clean:
	rm -rf $(BUILD_DIR)
