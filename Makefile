.PHONY: all help deps serve build clean

VENV   := .venv
PYTHON := $(VENV)/bin/python
PIP    := $(VENV)/bin/pip
MKDOCS := $(VENV)/bin/mkdocs

HOST ?= 127.0.0.1
PORT ?= 8000

all: serve

help:
	@echo "Targets:"
	@echo "  make deps   — create .venv and install Python dependencies"
	@echo "  make serve  — local preview at http://$(HOST):$(PORT)"
	@echo "  make build  — static site to site/"
	@echo "  make clean  — remove site/ and .venv/"

deps: $(VENV)/bin/mkdocs

$(VENV)/bin/mkdocs: requirements.txt
	$(PYTHON) -m venv $(VENV)
	$(PIP) install -r requirements.txt

serve: deps
	$(MKDOCS) serve -a $(HOST):$(PORT)

build: deps
	$(MKDOCS) build

clean:
	rm -rf site $(VENV)
