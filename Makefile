SHELL := /bin/bash

ROOT  := $(CURDIR)
BUILD := $(ROOT)/build
SWIFTC := xcrun swiftc
SWIFTFLAGS := -swift-version 5 -O

VERSION := 0.2.0
APP := $(BUILD)/飞连控制.app
PKGROOT := $(BUILD)/pkgroot
COMPONENT := $(BUILD)/component.pkg
PKG := $(BUILD)/FeiLianControl-$(VERSION).pkg

.PHONY: all build app install apps legacy-apps pkg uninstall clean check

all: build

build: $(BUILD)/feilian-daemon $(BUILD)/feilian-auth $(APP)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/feilian-daemon-arm64: src/feilian-daemon.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -target arm64-apple-macosx13.0 -o $@ $<

$(BUILD)/feilian-daemon-x86_64: src/feilian-daemon.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -target x86_64-apple-macosx13.0 -o $@ $<

$(BUILD)/feilian-daemon: $(BUILD)/feilian-daemon-arm64 $(BUILD)/feilian-daemon-x86_64
	lipo -create $^ -output $@

$(BUILD)/feilian-auth-arm64: src/feilian-auth.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -target arm64-apple-macosx13.0 -framework LocalAuthentication -o $@ $<

$(BUILD)/feilian-auth-x86_64: src/feilian-auth.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -target x86_64-apple-macosx13.0 -framework LocalAuthentication -o $@ $<

$(BUILD)/feilian-auth: $(BUILD)/feilian-auth-arm64 $(BUILD)/feilian-auth-x86_64
	lipo -create $^ -output $@

$(BUILD)/FeiLianControl-arm64: src/FeiLianControlApp.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -target arm64-apple-macosx13.0 -parse-as-library -o $@ $<

$(BUILD)/FeiLianControl-x86_64: src/FeiLianControlApp.swift | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -target x86_64-apple-macosx13.0 -parse-as-library -o $@ $<

$(APP): $(BUILD)/FeiLianControl-arm64 $(BUILD)/FeiLianControl-x86_64 app/Info.plist
	rm -rf "$@"
	mkdir -p "$@/Contents/MacOS" "$@/Contents/Resources"
	lipo -create "$(BUILD)/FeiLianControl-arm64" "$(BUILD)/FeiLianControl-x86_64" -output "$@/Contents/MacOS/FeiLianControl"
	cp app/Info.plist "$@/Contents/Info.plist"
	codesign --force --sign - "$@"

app: $(APP)

check:
	bash -n scripts/*.sh
	bash -n scripts/feilianctl
	bash -n pkg/scripts/*
	plutil -lint launchd/com.feiliancontrol.helper.plist
	plutil -lint app/Info.plist
	plutil -lint pkg/component.plist
	$(SWIFTC) $(SWIFTFLAGS) -typecheck src/feilian-daemon.swift
	$(SWIFTC) $(SWIFTFLAGS) -typecheck -framework LocalAuthentication src/feilian-auth.swift
	$(SWIFTC) $(SWIFTFLAGS) -typecheck -parse-as-library src/FeiLianControlApp.swift

install:
	@test "$$(id -u)" -eq 0 || { echo "请用 sudo make install"; exit 1; }
	@test -x "$(BUILD)/feilian-daemon" && test -x "$(BUILD)/feilian-auth" || { echo "请先运行 make build"; exit 1; }
	./scripts/install-helper.sh "$(BUILD)"

apps: $(APP)
	@test "$$(id -u)" -ne 0 || { echo "请以当前用户运行 make apps（不要 sudo）"; exit 1; }
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/飞连控制.app"
	ditto "$(APP)" "$(HOME)/Applications/飞连控制.app"
	@echo "已安装菜单栏 App：$(HOME)/Applications/飞连控制.app"

legacy-apps:
	@test "$$(id -u)" -ne 0 || { echo "请以当前用户运行 make legacy-apps（不要 sudo）"; exit 1; }
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/退出飞连.app" "$(HOME)/Applications/恢复飞连.app" "$(HOME)/Applications/飞连状态.app"
	osacompile -o "$(HOME)/Applications/退出飞连.app" applescript/quit.applescript
	osacompile -o "$(HOME)/Applications/恢复飞连.app" applescript/restore.applescript
	osacompile -o "$(HOME)/Applications/飞连状态.app" applescript/status.applescript

pkg: build
	@test "$$(id -u)" -ne 0 || { echo "请不要用 sudo 运行 make pkg；安装时才需要管理员密码"; exit 1; }
	rm -rf "$(PKGROOT)" "$(COMPONENT)" "$(PKG)" "$(PKG).sha256"
	mkdir -p "$(PKGROOT)/usr/local/libexec/feilian" "$(PKGROOT)/usr/local/bin" "$(PKGROOT)/Library/LaunchDaemons" "$(PKGROOT)/Applications"
	install -m 755 "$(BUILD)/feilian-daemon" "$(PKGROOT)/usr/local/libexec/feilian/feilian-daemon"
	install -m 755 "$(BUILD)/feilian-auth" "$(PKGROOT)/usr/local/libexec/feilian/feilian-auth"
	install -m 755 scripts/stop.sh "$(PKGROOT)/usr/local/libexec/feilian/stop.sh"
	install -m 755 scripts/start.sh "$(PKGROOT)/usr/local/libexec/feilian/start.sh"
	install -m 755 scripts/status.sh "$(PKGROOT)/usr/local/libexec/feilian/status.sh"
	install -m 755 scripts/feilianctl "$(PKGROOT)/usr/local/bin/feilianctl"
	install -m 644 launchd/com.feiliancontrol.helper.plist "$(PKGROOT)/Library/LaunchDaemons/com.feiliancontrol.helper.plist"
	ditto "$(APP)" "$(PKGROOT)/Applications/飞连控制.app"
	xattr -cr "$(PKGROOT)"
	pkgbuild --root "$(PKGROOT)" --component-plist pkg/component.plist --identifier com.feiliancontrol.pkg --version $(VERSION) --scripts pkg/scripts --ownership recommended "$(COMPONENT)"
	productbuild --distribution pkg/Distribution --resources pkg/resources --package-path "$(BUILD)" "$(PKG)"
	shasum -a 256 "$(PKG)" > "$(PKG).sha256"
	@echo "已生成：$(PKG)"
	@cat "$(PKG).sha256"

uninstall:
	@test "$$(id -u)" -eq 0 || { echo "请用 sudo make uninstall"; exit 1; }
	./scripts/uninstall-helper.sh

clean:
	rm -rf "$(BUILD)"
