# Run: make -f scripts/channel_content.mk prove-channel-content KD28_ROOT=/path/to/authorized/repository
# Outputs: reports/channel_content_TAG.log and build/channel_content_TAG/{instrumented.v,properties.json}.
# Next: inspect counterexamples and run finite profiles; actual-memory SAT expansion is not ASIC synthesis.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := prove-channel-content
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
YOSYS ?= yosys
KD28_ROOT ?=
PORTS ?= 1
WIDTH ?= 5
CREDIT_WIDTH ?= 4
CAP_HEX ?= 30000
RETURN_DEPTH ?= 3
TAG ?= $(PORTS)_$(WIDTH)_$(CREDIT_WIDTH)_$(CAP_HEX)_$(RETURN_DEPTH)
CONTENT_RUN := $(ROOT_DIR)/build/channel_content_$(TAG)
CONTENT_LOG := $(ROOT_DIR)/reports/channel_content_$(TAG).log
.PHONY: prove-channel-content
prove-channel-content:
	@test -n "$(KD28_ROOT)"
	mkdir -p "$(ROOT_DIR)/reports" "$(CONTENT_RUN)"
	UALINK_PORTS=$(PORTS) UALINK_WIDTH=$(WIDTH) UALINK_CREDIT_WIDTH=$(CREDIT_WIDTH) UALINK_CAP_HEX=$(CAP_HEX) UALINK_RETURN_DEPTH=$(RETURN_DEPTH) UALINK_KD28_ROOT="$(KD28_ROOT)" UALINK_BUILD_DIR="$(CONTENT_RUN)" $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/prove_channel_content.tcl" > "$(CONTENT_LOG)" 2>&1 || { tail -n 30 "$(CONTENT_LOG)"; exit 1; }
