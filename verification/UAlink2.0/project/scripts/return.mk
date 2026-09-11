# Run: make -f scripts/return.mk sim-return PORTS=4 DEPTH=5
# Outputs: build/return_*/vectors.mem, compile.log, obj; reports/return_*.log.
# Next: independent RTL review, conservation, actual-library synthesis/equivalence/STA.
SHELL := /bin/bash
.DEFAULT_GOAL := sim-return
.SHELLFLAGS := -eu -o pipefail -c
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
PYTHON ?= python3
VERILATOR ?= verilator
YOSYS ?= yosys
STA ?= sta
LIB_ROOT ?=
CORNER ?= ssg0p81v125c
PERIOD_NS ?= 0.640
PORTS ?= 1
DEPTH ?= 4
HALF_PERIOD_PS ?= 320
RETURN_RUN := $(ROOT_DIR)/build/return_$(PORTS)_$(DEPTH)_$(HALF_PERIOD_PS)
RETURN_SYNTH := $(ROOT_DIR)/build/return_synth_$(PORTS)
RETURN_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(CORNER).lib

.PHONY: sim-return
sim-return:
	@test "$(HALF_PERIOD_PS)" = 320 -o "$(HALF_PERIOD_PS)" = 3200
	mkdir -p "$(RETURN_RUN)" "$(ROOT_DIR)/reports"
	$(PYTHON) "$(ROOT_DIR)/verification/rtl/return_vectors.py" --ports $(PORTS) --depth $(DEPTH) > "$(RETURN_RUN)/vectors.mem"
	$(VERILATOR) --binary --timing --language 1364-2001 -Wall --top-module upli_credit_return_tb --Mdir "$(RETURN_RUN)/obj" -GC_NUM_PORTS=$(PORTS) -GC_DEPTH=$(DEPTH) -GC_HALF_PERIOD_PS=$(HALF_PERIOD_PS) "$(ROOT_DIR)/rtl/upli/upli_credit_return_queue.v" "$(ROOT_DIR)/verification/rtl/upli_credit_return_tb.v" > "$(RETURN_RUN)/compile.log" 2>&1 || { tail -n 30 "$(RETURN_RUN)/compile.log"; exit 1; }
	"$(RETURN_RUN)/obj/Vupli_credit_return_tb" +VECTORS="$(RETURN_RUN)/vectors.mem" 2>&1 | tee "$(ROOT_DIR)/reports/return_$(PORTS)_$(DEPTH)_$(HALF_PERIOD_PS).log"

# Run: make -f scripts/return.mk synth-return PORTS=4 LIB_ROOT=/path/to/authorized/NLDM
# Outputs: build/return_synth_*/mapped.v, mapped.json, area.json and reports/return_synth_*.log.
# Next: equiv-return then five corners/two periods of sta-return on this exact netlist.
.PHONY: synth-return equiv-return sta-return
.PHONY: prove-return
prove-return:
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_PORTS=$(PORTS) UALINK_DEPTH=$(DEPTH) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/prove_return.tcl" > "$(ROOT_DIR)/reports/return_properties_$(PORTS)_$(DEPTH).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/return_properties_$(PORTS)_$(DEPTH).log"; exit 1; }

synth-return:
	@test "$(DEPTH)" = 4 && test "$(CORNER)" = ssg0p81v125c
	@test -n "$(LIB_ROOT)" && test -f "$(RETURN_LIB)"
	mkdir -p "$(RETURN_SYNTH)" "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(RETURN_LIB)" UALINK_BUILD_DIR="$(RETURN_SYNTH)" UALINK_PORTS=$(PORTS) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/synth_return.tcl" > "$(ROOT_DIR)/reports/return_synth_$(PORTS).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/return_synth_$(PORTS).log"; exit 1; }

equiv-return:
	@test "$(DEPTH)" = 4 && test "$(CORNER)" = ssg0p81v125c
	@test -n "$(LIB_ROOT)" && test -f "$(RETURN_LIB)" && test -f "$(RETURN_SYNTH)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(RETURN_LIB)" UALINK_NETLIST="$(RETURN_SYNTH)/mapped.v" UALINK_PORTS=$(PORTS) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/equiv_return.tcl" > "$(ROOT_DIR)/reports/return_equiv_$(PORTS).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/return_equiv_$(PORTS).log"; exit 1; }

sta-return:
	@test "$(DEPTH)" = 4
	@test -n "$(LIB_ROOT)" && test -f "$(RETURN_LIB)" && test -f "$(RETURN_SYNTH)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(RETURN_LIB)" UALINK_NETLIST="$(RETURN_SYNTH)/mapped.v" UALINK_PERIOD_NS=$(PERIOD_NS) $(STA) -exit "$(ROOT_DIR)/scripts/sta_return.tcl" > "$(ROOT_DIR)/reports/return_sta_$(PORTS)_$(CORNER)_$(PERIOD_NS).log" 2>&1 || { tail -n 15 "$(ROOT_DIR)/reports/return_sta_$(PORTS)_$(CORNER)_$(PERIOD_NS).log"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/scripts/check_sta_report.py" "$(ROOT_DIR)/reports/return_sta_$(PORTS)_$(CORNER)_$(PERIOD_NS).log" --design return
