.PHONY: list model unit subsystem system rtl all clean

PYTHON ?= python3
RUNNER := scripts/run.py
JOBS ?= 4
TIMEOUT ?= 1200

list:
	$(PYTHON) $(RUNNER) --list

model:
	$(PYTHON) $(RUNNER) --model --timeout $(TIMEOUT)

unit:
	$(PYTHON) $(RUNNER) --group unit --jobs $(JOBS) --timeout $(TIMEOUT)

subsystem:
	$(PYTHON) $(RUNNER) --group subsystem --jobs $(JOBS) --timeout $(TIMEOUT)

system:
	$(PYTHON) $(RUNNER) --group system --jobs $(JOBS) --timeout $(TIMEOUT)

rtl:
	$(PYTHON) $(RUNNER) --group all --jobs $(JOBS) --timeout $(TIMEOUT)

all: model rtl

clean:
	$(PYTHON) $(RUNNER) --clean
