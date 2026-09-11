# Run: make -f scripts/channel.mk channel-check KD28_ROOT=/authorized/repository LIB_ROOT=/authorized/lib
# Outputs: channel_synth_* mapped/area/identity JSON and reports/channel_* tool logs.
# Next: repeat declared profiles/corners/views and functional regression; not full IP signoff.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := channel-check
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
PYTHON ?= python3
YOSYS ?= yosys
STA ?= sta
KD28_ROOT ?=
LIB_ROOT ?=
PORTS ?= 1
WIDTH ?= 32
CREDIT_WIDTH ?= 4
CAP_HEX ?= 50132
RETURN_DEPTH ?= 4
HOLD ?= 1
READ_CONTROL_BUFFERS ?= 0
MAPPING_CORNER ?= ssg0p81vm40c
CORNER ?= $(MAPPING_CORNER)
MACRO_VIEW ?= slow
PERIOD_NS ?= 0.640
TAG := $(PORTS)_$(WIDTH)_$(CREDIT_WIDTH)_$(CAP_HEX)_$(RETURN_DEPTH)_hold$(HOLD)_rbuf$(READ_CONTROL_BUFFERS)_$(MAPPING_CORNER)
RUN_DIR := $(ROOT_DIR)/build/channel_synth_$(TAG)
CELL_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(CORNER).lib
MAPPING_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(MAPPING_CORNER).lib
MACRO_LIB := $(KD28_ROOT)/Library/timing/kd28/sram/kd28_sram_$(MACRO_VIEW).lib
COMMON_ENV = UALINK_PORTS=$(PORTS) UALINK_WIDTH=$(WIDTH) UALINK_CREDIT_WIDTH=$(CREDIT_WIDTH) UALINK_CAP_HEX=$(CAP_HEX) UALINK_RETURN_DEPTH=$(RETURN_DEPTH) UALINK_READ_CONTROL_BUFFERS=$(READ_CONTROL_BUFFERS) UALINK_HOLD=$(HOLD) UALINK_MAPPING_CORNER=$(MAPPING_CORNER) UALINK_YOSYS="$(YOSYS)" UALINK_MAPPING_LIBERTY="$(MAPPING_LIB)" UALINK_BUILD_DIR="$(RUN_DIR)" UALINK_KD28_ROOT="$(KD28_ROOT)" UALINK_LIBERTY="$(CELL_LIB)"
.PHONY: synth-channel equiv-channel sta-channel channel-check
synth-channel:
	@test "$(MAPPING_CORNER)" = ssg0p81vm40c -o "$(MAPPING_CORNER)" = ssg0p81v125c
	@test "$(CORNER)" = "$(MAPPING_CORNER)" && test -n "$(LIB_ROOT)" && test -n "$(KD28_ROOT)" && test -f "$(CELL_LIB)"
	mkdir -p "$(RUN_DIR)" "$(ROOT_DIR)/reports"
	$(COMMON_ENV) UALINK_PYTHON="$(PYTHON)" $(PYTHON) "$(ROOT_DIR)/scripts/build_identity.py" synth -- $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/synth_channel.tcl" > "$(ROOT_DIR)/reports/channel_synth_$(TAG).log" 2>&1 || { tail -n 40 "$(ROOT_DIR)/reports/channel_synth_$(TAG).log"; exit 1; }

equiv-channel:
	@test "$(MAPPING_CORNER)" = ssg0p81vm40c -o "$(MAPPING_CORNER)" = ssg0p81v125c
	@test "$(CORNER)" = "$(MAPPING_CORNER)" && test -n "$(LIB_ROOT)" && test -n "$(KD28_ROOT)" && test -f "$(RUN_DIR)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	$(COMMON_ENV) UALINK_NETLIST="$(RUN_DIR)/mapped.v" $(PYTHON) "$(ROOT_DIR)/scripts/build_identity.py" equiv -- $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/equiv_channel.tcl" > "$(ROOT_DIR)/reports/channel_equiv_$(TAG).log" 2>&1 || { tail -n 40 "$(ROOT_DIR)/reports/channel_equiv_$(TAG).log"; exit 1; }

sta-channel:
	@test -n "$(LIB_ROOT)" && test -n "$(KD28_ROOT)" && test -f "$(RUN_DIR)/mapped.v" && test -f "$(CELL_LIB)" && test -f "$(MACRO_LIB)"
	mkdir -p "$(ROOT_DIR)/reports"
	$(COMMON_ENV) UALINK_NETLIST="$(RUN_DIR)/mapped.v" UALINK_MACRO_LIBERTY="$(MACRO_LIB)" UALINK_MACRO_VIEW=$(MACRO_VIEW) UALINK_PERIOD_NS=$(PERIOD_NS) $(PYTHON) "$(ROOT_DIR)/scripts/build_identity.py" sta -- $(STA) -exit "$(ROOT_DIR)/scripts/sta_channel.tcl" > "$(ROOT_DIR)/reports/channel_sta_$(TAG)_$(CORNER)_$(MACRO_VIEW)_$(PERIOD_NS).log" 2>&1 || { tail -n 50 "$(ROOT_DIR)/reports/channel_sta_$(TAG)_$(CORNER)_$(MACRO_VIEW)_$(PERIOD_NS).log"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/scripts/check_channel_report.py" "$(ROOT_DIR)/reports/channel_sta_$(TAG)_$(CORNER)_$(MACRO_VIEW)_$(PERIOD_NS).log" --ports $(PORTS) --width $(WIDTH) --credit-width $(CREDIT_WIDTH) --cap-hex $(CAP_HEX) --return-depth $(RETURN_DEPTH) --macro-view $(MACRO_VIEW) --period-ns $(PERIOD_NS)

# Ordered even under make -j; measured cold SSG critical paths drive default
# mapping. Analysis corners never silently replace the explicit mapping corner.
channel-check:
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/scripts/channel.mk" synth-channel CORNER=$(MAPPING_CORNER)
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/scripts/channel.mk" equiv-channel CORNER=$(MAPPING_CORNER)
	$(MAKE) --no-print-directory -f "$(ROOT_DIR)/scripts/channel.mk" sta-channel
