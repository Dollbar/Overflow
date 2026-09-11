# Run: make -f scripts/receive.mk sim-receive DEPTH=5 WIDTH=40 KD28_ROOT=/path/to/authorized/repository
# Outputs: build/receive_*/vectors.mem, compile.log, obj; reports/receive_*.log.
# Next: negative controls, independent review, control proof and separately labelled macro-budget STA.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := sim-receive
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
PYTHON ?= python3
VERILATOR ?= verilator
YOSYS ?= yosys
STA ?= sta
LIB_ROOT ?=
CORNER ?= ssg0p81v125c
PERIOD_NS ?= 0.640
KD28_ROOT ?=
DEPTH ?= 5
WIDTH ?= 32
HALF_PERIOD_PS ?= 320
RX_RUN := $(ROOT_DIR)/build/receive_$(DEPTH)_$(WIDTH)_$(HALF_PERIOD_PS)
RX_SYNTH := $(ROOT_DIR)/build/receive_synth_$(DEPTH)_$(WIDTH)
RX_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(CORNER).lib
SRAM_DIR := $(KD28_ROOT)/Library/models/kd28/sram/rtl
MAP_SOURCE := $(KD28_ROOT)/Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v

# Run: make -f scripts/receive.mk sim-receive-channel PORTS=1 CAP_HEX=50132 KD28_ROOT=/path/to/authorized/repository
# Outputs: separate build/receive_channel_*/ and reports/receive_channel_*.log.
# Next: independent negative controls, channel-level physical budgets and review.
PORTS ?= 1
CREDIT_WIDTH ?= 4
CAP_HEX ?= 50132
RETURN_DEPTH ?= 4
CHANNEL ?= req
CHANNEL_ID := $(if $(filter req,$(CHANNEL)),0,$(if $(filter orig_data,$(CHANNEL)),1,$(if $(filter rd_rsp,$(CHANNEL)),2,3)))
CHANNEL_RUN := $(ROOT_DIR)/build/receive_channel_$(PORTS)_$(WIDTH)_$(CREDIT_WIDTH)_$(CAP_HEX)_$(RETURN_DEPTH)_$(CHANNEL)_$(HALF_PERIOD_PS)
CHANNEL_LOG ?= $(ROOT_DIR)/reports/receive_channel_$(PORTS)_$(WIDTH)_$(CREDIT_WIDTH)_$(CAP_HEX)_$(RETURN_DEPTH)_$(CHANNEL)_$(HALF_PERIOD_PS).log
.PHONY: sim-receive-channel
sim-receive-channel:
	@test -n "$(KD28_ROOT)" && test -f "$(MAP_SOURCE)"
	@test "$(HALF_PERIOD_PS)" = 320 -o "$(HALF_PERIOD_PS)" = 3200
	mkdir -p "$(CHANNEL_RUN)" "$(ROOT_DIR)/reports"
	$(PYTHON) "$(ROOT_DIR)/verification/rtl/receive_channel_vectors.py" --ports $(PORTS) --width $(WIDTH) --credit-width $(CREDIT_WIDTH) --capacity-hex $(CAP_HEX) --return-depth $(RETURN_DEPTH) --channel $(CHANNEL) > "$(CHANNEL_RUN)/vectors.mem"
	$(VERILATOR) --binary --timing --language 1364-2001 -Wall --top-module upli_receive_channel_tb --Mdir "$(CHANNEL_RUN)/obj" -GC_NUM_PORTS=$(PORTS) -GC_PAYLOAD_WIDTH=$(WIDTH) -GC_CREDIT_WIDTH=$(CREDIT_WIDTH) "-GC_CAPACITIES=$$(( $(PORTS)*5*$(CREDIT_WIDTH) ))'h$(CAP_HEX)" -GC_RETURN_DEPTH=$(RETURN_DEPTH) -GC_CHANNEL=$(CHANNEL_ID) -GC_HALF_PERIOD_PS=$(HALF_PERIOD_PS) "$(ROOT_DIR)/config/kd28_verilator.vlt" "$(SRAM_DIR)/kd28_sram_sp_model.v" "$(SRAM_DIR)/kd28_sram_sdp_model.v" "$(SRAM_DIR)/kd28_sram_tdp_model.v" "$(SRAM_DIR)/kd28_sram_cells.v" "$(MAP_SOURCE)" "$(ROOT_DIR)/rtl/upli/upli_receive_fifo.v" "$(ROOT_DIR)/rtl/upli/upli_receive_storage.v" "$(ROOT_DIR)/rtl/upli/upli_credit_initializer.v" "$(ROOT_DIR)/rtl/upli/upli_credit_return_queue.v" "$(ROOT_DIR)/rtl/upli/upli_credit_bank.v" "$(ROOT_DIR)/rtl/upli/upli_receive_channel.v" "$(ROOT_DIR)/verification/rtl/upli_receive_channel_tb.v" > "$(CHANNEL_RUN)/compile.log" 2>&1 || { tail -n 45 "$(CHANNEL_RUN)/compile.log"; exit 1; }
	"$(CHANNEL_RUN)/obj/Vupli_receive_channel_tb" +VECTORS="$(CHANNEL_RUN)/vectors.mem" 2>&1 | tee "$(CHANNEL_LOG)"

# Run: make -f scripts/receive.mk prove-receive DEPTH=5 WIDTH=32
# Outputs: reports/receive_properties_*.log and an observation-only DUT snapshot.
# Next: actual SRAM payload simulation and actual-library controller timing.
.PHONY: prove-receive
prove-receive:
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_DEPTH=$(DEPTH) UALINK_WIDTH=$(WIDTH) UALINK_BUILD_DIR="$(ROOT_DIR)/build/receive_proof_$(DEPTH)_$(WIDTH)" $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/prove_receive.tcl" > "$(ROOT_DIR)/reports/receive_properties_$(DEPTH)_$(WIDTH).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/receive_properties_$(DEPTH)_$(WIDTH).log"; exit 1; }

.PHONY: sim-receive
sim-receive:
	@test -n "$(KD28_ROOT)" && test -f "$(MAP_SOURCE)"
	@test "$(HALF_PERIOD_PS)" = 320 -o "$(HALF_PERIOD_PS)" = 3200
	mkdir -p "$(RX_RUN)" "$(ROOT_DIR)/reports"
	$(PYTHON) "$(ROOT_DIR)/verification/rtl/receive_vectors.py" --depth $(DEPTH) --width $(WIDTH) > "$(RX_RUN)/vectors.mem"
	$(VERILATOR) --binary --timing --language 1364-2001 -Wall --top-module upli_receive_storage_tb --Mdir "$(RX_RUN)/obj" -GC_DEPTH=$(DEPTH) -GC_DATA_WIDTH=$(WIDTH) -GC_HALF_PERIOD_PS=$(HALF_PERIOD_PS) "$(ROOT_DIR)/config/kd28_verilator.vlt" "$(SRAM_DIR)/kd28_sram_sp_model.v" "$(SRAM_DIR)/kd28_sram_sdp_model.v" "$(SRAM_DIR)/kd28_sram_tdp_model.v" "$(SRAM_DIR)/kd28_sram_cells.v" "$(MAP_SOURCE)" "$(ROOT_DIR)/rtl/upli/upli_receive_fifo.v" "$(ROOT_DIR)/rtl/upli/upli_receive_storage.v" "$(ROOT_DIR)/verification/rtl/upli_receive_storage_tb.v" > "$(RX_RUN)/compile.log" 2>&1 || { tail -n 40 "$(RX_RUN)/compile.log"; exit 1; }
	"$(RX_RUN)/obj/Vupli_receive_storage_tb" +VECTORS="$(RX_RUN)/vectors.mem" 2>&1 | tee "$(ROOT_DIR)/reports/receive_$(DEPTH)_$(WIDTH)_$(HALF_PERIOD_PS).log"

# Run synth-receive, equiv-receive, then sta-receive with the same DEPTH/WIDTH.
# Outputs: controller netlist/area under build/, actual-library logs under reports/.
# Next: integrated storage timing with separately identified synthetic memory arcs.
.PHONY: synth-receive equiv-receive sta-receive
synth-receive:
	@test "$(CORNER)" = ssg0p81v125c && test -n "$(LIB_ROOT)" && test -f "$(RX_LIB)"
	mkdir -p "$(RX_SYNTH)" "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(RX_LIB)" UALINK_BUILD_DIR="$(RX_SYNTH)" UALINK_DEPTH=$(DEPTH) UALINK_WIDTH=$(WIDTH) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/synth_receive.tcl" > "$(ROOT_DIR)/reports/receive_synth_$(DEPTH)_$(WIDTH).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/receive_synth_$(DEPTH)_$(WIDTH).log"; exit 1; }

equiv-receive:
	@test "$(CORNER)" = ssg0p81v125c && test -n "$(LIB_ROOT)" && test -f "$(RX_LIB)" && test -f "$(RX_SYNTH)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(RX_LIB)" UALINK_NETLIST="$(RX_SYNTH)/mapped.v" UALINK_DEPTH=$(DEPTH) UALINK_WIDTH=$(WIDTH) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/equiv_receive.tcl" > "$(ROOT_DIR)/reports/receive_equiv_$(DEPTH)_$(WIDTH).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/receive_equiv_$(DEPTH)_$(WIDTH).log"; exit 1; }

sta-receive:
	@test -n "$(LIB_ROOT)" && test -f "$(RX_LIB)" && test -f "$(RX_SYNTH)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(RX_LIB)" UALINK_NETLIST="$(RX_SYNTH)/mapped.v" UALINK_PERIOD_NS=$(PERIOD_NS) $(STA) -exit "$(ROOT_DIR)/scripts/sta_receive.tcl" > "$(ROOT_DIR)/reports/receive_sta_$(DEPTH)_$(WIDTH)_$(CORNER)_$(PERIOD_NS).log" 2>&1 || { tail -n 20 "$(ROOT_DIR)/reports/receive_sta_$(DEPTH)_$(WIDTH)_$(CORNER)_$(PERIOD_NS).log"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/scripts/check_sta_report.py" "$(ROOT_DIR)/reports/receive_sta_$(DEPTH)_$(WIDTH)_$(CORNER)_$(PERIOD_NS).log" --design receive
