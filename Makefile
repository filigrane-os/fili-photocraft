# fili-photocraft: build and check.
#
#   make          build the release binary
#   make dev      build for development (no link-time optimisation), then `make run` (QML read from the source folders)
#   make test     unit tests, the check of the bar menu and of the ctl catalog
#   sudo make install          install under /usr/local (PREFIX=/usr for a system package)
#   make install DESTDIR=pkg PREFIX=/usr      stage into a directory (packagers)
#   make install-data PREFIX=~/.local         everything but the binary (launcher, icon, licences, what the shell reads)
#
# Everything the application brings to the Filigrane desktop lives here and is installed together: the program, the launcher,
# the icon, and shell/ (the fallback menu of the bar, the catalog of ctl, the brief of Lia), which ends in
# $(DATADIR)/filigrane/shell/ where `fili-bar link-system` finds it.
#
# cxx-qt finds Qt through qmake. QMAKE overrides the search below (Qt 6 only).
PREFIX ?= /usr/local
DESTDIR ?=
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share
CARGO ?= cargo
TARGET_DIR ?= $(if $(CARGO_TARGET_DIR),$(CARGO_TARGET_DIR),target)
QMAKE ?= $(firstword $(wildcard /usr/lib/qt6/bin/qmake6 /usr/lib64/qt6/bin/qmake6) $(shell command -v qmake6 qmake-qt6 2>/dev/null))
export QMAKE

.PHONY: all build dev run test test-tools install install-data uninstall

all: build

build:
	$(CARGO) build --release

# Development. `make dev` builds without link-time optimisation (target/fast); `make run` starts that build with the QML read from
# the source folders (this one and ../fili-ui), so after a change of a .qml file just run it again, no build. `make run ARGS=image.jpg`.
FILI_UI ?= ../fili-ui

dev:
	$(CARGO) build --profile fast

run:
	@test -x $(TARGET_DIR)/fast/fili-photocraft || { echo "run 'make dev' first" >&2; exit 1; }
	FILI_QML_DIR=$(CURDIR)/qml FILI_UI_QML=$(abspath $(FILI_UI))/qml QT_QUICK_BACKEND=software $(TARGET_DIR)/fast/fili-photocraft $(ARGS)

test:
	$(CARGO) test --release
	python3 -I scripts/check-shell-menu.py
	python3 -I scripts/fili-api-lint --app .

# Drives every tool of the window without a mouse (needs `make dev` first): scripts/test-tools.py
test-tools:
	python3 -I scripts/test-tools.py

install: build install-data
	install -Dm755 $(TARGET_DIR)/release/fili-photocraft $(DESTDIR)$(BINDIR)/fili-photocraft

install-data:
	install -Dm644 data/fili-photocraft.desktop $(DESTDIR)$(DATADIR)/applications/fili-photocraft.desktop
	install -Dm644 icons/fili-photocraft.svg $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/fili-photocraft.svg
	install -Dm644 LICENSE $(DESTDIR)$(DATADIR)/licenses/fili-photocraft/LICENSE
	for f in licenses/*; do install -Dm644 $$f $(DESTDIR)$(DATADIR)/licenses/fili-photocraft/$$(basename $$f); done
	mkdir -p $(DESTDIR)$(DATADIR)/filigrane/shell
	cp -r shell/. $(DESTDIR)$(DATADIR)/filigrane/shell/

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/fili-photocraft
	rm -f $(DESTDIR)$(DATADIR)/applications/fili-photocraft.desktop
	rm -f $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/fili-photocraft.svg
	rm -rf $(DESTDIR)$(DATADIR)/licenses/fili-photocraft
	rm -f $(DESTDIR)$(DATADIR)/filigrane/shell/ctl/fili-photocraft.json $(DESTDIR)$(DATADIR)/filigrane/shell/appmenu/fili-photocraft.json $(DESTDIR)$(DATADIR)/filigrane/shell/lia/fili-photocraft.md
