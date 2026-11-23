# fili-photocraft: build and check.
#
#   make          build the release binary
#   make test     unit tests, the check of the bar menu and of the ctl catalog
#
# cxx-qt finds Qt through qmake. QMAKE overrides the search below (Qt 6 only).
CARGO ?= cargo
QMAKE ?= $(firstword $(wildcard /usr/lib/qt6/bin/qmake6 /usr/lib64/qt6/bin/qmake6) $(shell command -v qmake6 qmake-qt6 2>/dev/null))
export QMAKE

.PHONY: all build test

all: build

build:
	$(CARGO) build --release

test:
	$(CARGO) test --release
	python3 -I scripts/check-shell-menu.py
	python3 -I scripts/fili-api-lint --app .
