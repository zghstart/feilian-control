SHELL := /bin/bash

ROOT  := $(CURDIR)
BUILD := $(ROOT)/build
SWIFTC := xcrun swiftc
SWIFTFLAGS := -swift-version 5 -O

.PHONY: all build install apps uninstall clean check

all: build

build: $(BUILD)/feilian-daemon $(BUILD)/feilian-auth

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/feilian-daemon: src/feilian-daemon.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<

$(BUILD)/feilian-auth: src/feilian-auth.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -framework LocalAuthentication -o $@ $<

check:
	bash -n scripts/*.sh
	plutil -lint launchd/com.feiliancontrol.helper.plist
	$(SWIFTC) $(SWIFTFLAGS) -typecheck src/feilian-daemon.swift
	$(SWIFTC) $(SWIFTFLAGS) -typecheck -framework LocalAuthentication src/feilian-auth.swift

install:
	@test "$$(id -u)" -eq 0 || { echo "请用 sudo make install"; exit 1; }
	@test -x "$(BUILD)/feilian-daemon" && test -x "$(BUILD)/feilian-auth" || { echo "请先运行 make build"; exit 1; }
	./scripts/install-helper.sh "$(BUILD)"

apps:
	@test "$$(id -u)" -ne 0 || { echo "请以当前用户运行 make apps（不要 sudo）"; exit 1; }
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/退出飞连.app" "$(HOME)/Applications/恢复飞连.app" "$(HOME)/Applications/飞连状态.app"
	osacompile -o "$(HOME)/Applications/退出飞连.app" applescript/quit.applescript
	osacompile -o "$(HOME)/Applications/恢复飞连.app" applescript/restore.applescript
	osacompile -o "$(HOME)/Applications/飞连状态.app" applescript/status.applescript

uninstall:
	@test "$$(id -u)" -eq 0 || { echo "请用 sudo make uninstall"; exit 1; }
	./scripts/uninstall-helper.sh

clean:
	rm -rf "$(BUILD)"
