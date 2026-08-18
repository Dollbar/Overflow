.PHONY: list model unit subsystem system rtl all clean

PYTHON ?= python3
RUNNER := scripts/run.py

list:
	$(PYTHON) $(RUNNER) --list

model:
	$(PYTHON) $(RUNNER) --model

unit:
	$(PYTHON) $(RUNNER) --group unit

subsystem:
	$(PYTHON) $(RUNNER) --group subsystem

system:
	$(PYTHON) $(RUNNER) --group system

rtl:
	$(PYTHON) $(RUNNER) --group all

all: model rtl

clean:
	$(PYTHON) $(RUNNER) --clean
