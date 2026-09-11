# Run: make -f scripts/content.mk prove-content DEPTH=3 WIDTH=8 KD28_ROOT=/path/to/authorized/repository
# Outputs: reports/receive_content_TAG.log and build/receive_content_TAG/{instrumented.v,properties.json}.
# Next: review data counterexamples, channel metadata integration and separate physical budgets.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := prove-content
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
YOSYS ?= yosys
KD28_ROOT ?=
DEPTH ?= 3
WIDTH ?= 8
TAG ?= $(DEPTH)_$(WIDTH)
CONTENT_RUN := $(ROOT_DIR)/build/receive_content_$(TAG)
CONTENT_LOG := $(ROOT_DIR)/reports/receive_content_$(TAG).log
.PHONY: prove-content
prove-content:
	@test -n "$(KD28_ROOT)"
	mkdir -p "$(ROOT_DIR)/reports" "$(CONTENT_RUN)"
	UALINK_DEPTH=$(DEPTH) UALINK_WIDTH=$(WIDTH) UALINK_KD28_ROOT="$(KD28_ROOT)" UALINK_BUILD_DIR="$(CONTENT_RUN)" $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/prove_receive_content.tcl" > "$(CONTENT_LOG)" 2>&1 || { tail -n 30 "$(CONTENT_LOG)"; exit 1; }
