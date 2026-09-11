# Run: make -f scripts/storage.mk synth-storage DEPTH=5 WIDTH=32 KD28_ROOT=/path/to/authorized/repository LIB_ROOT=/path/to/authorized/NLDM
# Outputs: build/storage_synth_*/mapped.v, mapped.json, area.json; reports/storage_*.log.
# Next: sta-storage with each declared standard-cell corner and synthetic macro view.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := synth-storage
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
PYTHON ?= python3
YOSYS ?= yosys
STA ?= sta
LIB_ROOT ?=
KD28_ROOT ?=
DEPTH ?= 5
WIDTH ?= 32
CORNER ?= ssg0p81v125c
MACRO_VIEW ?= slow
PERIOD_NS ?= 0.640
STORAGE_BUILD := $(ROOT_DIR)/build/storage_synth_$(DEPTH)_$(WIDTH)
CELL_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(CORNER).lib
MACRO_LIB := $(KD28_ROOT)/Library/timing/kd28/sram/kd28_sram_$(MACRO_VIEW).lib
STORAGE_LOG := $(ROOT_DIR)/reports/storage_sta_$(DEPTH)_$(WIDTH)_$(CORNER)_$(MACRO_VIEW)_$(PERIOD_NS).log

.PHONY: synth-storage equiv-storage sta-storage
synth-storage:
	@test "$(CORNER)" = ssg0p81v125c && test -n "$(LIB_ROOT)" && test -f "$(CELL_LIB)" && test -n "$(KD28_ROOT)"
	mkdir -p "$(STORAGE_BUILD)" "$(ROOT_DIR)/reports"
	UALINK_PYTHON="$(PYTHON)" UALINK_LIBERTY="$(CELL_LIB)" UALINK_KD28_ROOT="$(KD28_ROOT)" UALINK_BUILD_DIR="$(STORAGE_BUILD)" UALINK_DEPTH=$(DEPTH) UALINK_WIDTH=$(WIDTH) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/synth_storage.tcl" > "$(ROOT_DIR)/reports/storage_synth_$(DEPTH)_$(WIDTH).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/storage_synth_$(DEPTH)_$(WIDTH).log"; exit 1; }

# Run after synthesis; compare macro transaction ports, not unmodelled SRAM contents.
# Outputs: reports/storage_equiv_*.log; next: STA and actual-memory simulation.
equiv-storage:
	@test "$(CORNER)" = ssg0p81v125c && test -n "$(LIB_ROOT)" && test -f "$(CELL_LIB)" && test -n "$(KD28_ROOT)" && test -f "$(STORAGE_BUILD)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(CELL_LIB)" UALINK_KD28_ROOT="$(KD28_ROOT)" UALINK_NETLIST="$(STORAGE_BUILD)/mapped.v" UALINK_DEPTH=$(DEPTH) UALINK_WIDTH=$(WIDTH) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/equiv_storage.tcl" > "$(ROOT_DIR)/reports/storage_equiv_$(DEPTH)_$(WIDTH).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/storage_equiv_$(DEPTH)_$(WIDTH).log"; exit 1; }

sta-storage:
	@test -n "$(LIB_ROOT)" && test -n "$(KD28_ROOT)" && test -f "$(CELL_LIB)" && test -f "$(MACRO_LIB)" && test -f "$(STORAGE_BUILD)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(CELL_LIB)" UALINK_MACRO_LIBERTY="$(MACRO_LIB)" UALINK_NETLIST="$(STORAGE_BUILD)/mapped.v" UALINK_DEPTH=$(DEPTH) UALINK_WIDTH=$(WIDTH) UALINK_MACRO_VIEW=$(MACRO_VIEW) UALINK_PERIOD_NS=$(PERIOD_NS) $(STA) -exit "$(ROOT_DIR)/scripts/sta_storage.tcl" > "$(STORAGE_LOG)" 2>&1 || { tail -n 30 "$(STORAGE_LOG)"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/scripts/check_storage_report.py" "$(STORAGE_LOG)" --depth $(DEPTH) --width $(WIDTH) --macro-view $(MACRO_VIEW)
