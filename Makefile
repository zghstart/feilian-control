SHELL := /bin/bash

ROOT  := $(CURDIR)
BUILD := $(ROOT)/build
SWIFTC := xcrun swiftc
SWIFTFLAGS := -swift-version 5 -O

VERSION := 0.3.0
APP := $(BUILD)/飞连控制.app
PKGROOT := $(BUILD)/pkgroot
COMPONENT := $(BUILD)/component.pkg
PKG := $(BUILD)/FeiLianControl-$(VERSION).pkg

.PHONY: all build app install apps legacy-apps pkg uninstall clean check test check-tag print-version

all: build

build: $(BUILD)/feilian-daemon $(BUILD)/feilian-auth $(APP)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/feilian-daemon: src/feilian-daemon.swift Makefile | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -target arm64-apple-macosx13.0 -o $@ $<

$(BUILD)/feilian-auth: src/feilian-auth.swift Makefile | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -target arm64-apple-macosx13.0 -framework LocalAuthentication -o $@ $<

$(BUILD)/FeiLianControl: src/FeiLianControlApp.swift Makefile | $(BUILD)
	$(SWIFTC) $(SWIFTFLAGS) -target arm64-apple-macosx13.0 -parse-as-library -o $@ $<

$(APP): $(BUILD)/FeiLianControl app/Info.plist
	rm -rf "$@"
	mkdir -p "$@/Contents/MacOS" "$@/Contents/Resources"
	cp "$(BUILD)/FeiLianControl" "$@/Contents/MacOS/FeiLianControl"
	cp app/Info.plist "$@/Contents/Info.plist"
	codesign --force --sign - "$@"

app: $(APP)

print-version:
	@printf '%s\n' "$(VERSION)"

check-tag:
	@test -n "$(TAG)" || { echo "请通过 TAG=v$(VERSION) 指定发布 tag"; exit 1; }
	@test "$(TAG)" = "v$(VERSION)" || { echo "tag $(TAG) 与工程版本 v$(VERSION) 不一致"; exit 1; }

check:
	bash -n scripts/*.sh
	bash -n scripts/feilianctl
	bash -n pkg/scripts/*
	bash -n tests/*.sh
	plutil -lint launchd/com.feiliancontrol.helper.plist
	plutil -lint app/Info.plist
	plutil -lint pkg/component.plist
	$(SWIFTC) $(SWIFTFLAGS) -typecheck src/feilian-daemon.swift
	$(SWIFTC) $(SWIFTFLAGS) -typecheck -framework LocalAuthentication src/feilian-auth.swift
	$(SWIFTC) $(SWIFTFLAGS) -typecheck -parse-as-library src/FeiLianControlApp.swift
	bash tests/cli.sh
	bash tests/services.sh

test: check

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
	mkdir -p "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control" "$(PKGROOT)/usr/local/bin" "$(PKGROOT)/Library/LaunchDaemons" "$(PKGROOT)/Applications"
	install -m 755 "$(BUILD)/feilian-daemon" "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control/feilian-daemon"
	install -m 755 "$(BUILD)/feilian-auth" "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control/feilian-auth"
	install -m 755 scripts/auth-common.sh "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control/auth-common.sh"
	install -m 755 scripts/service-common.sh "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control/service-common.sh"
	install -m 755 scripts/stop.sh "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control/stop.sh"
	install -m 755 scripts/start.sh "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control/start.sh"
	install -m 755 scripts/status.sh "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control/status.sh"
	install -m 755 scripts/doctor.sh "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control/doctor.sh"
	install -m 755 scripts/uninstall-helper.sh "$(PKGROOT)/Library/PrivilegedHelperTools/feilian-control/uninstall-helper.sh"
	install -m 755 scripts/feilianctl "$(PKGROOT)/usr/local/bin/feilianctl"
	install -m 644 launchd/com.feiliancontrol.helper.plist "$(PKGROOT)/Library/LaunchDaemons/com.feiliancontrol.helper.plist"
	ditto "$(APP)" "$(PKGROOT)/Applications/飞连控制.app"
	codesign --verify --deep --strict "$(APP)"
	@for binary in "$(BUILD)/feilian-daemon" "$(BUILD)/feilian-auth" "$(APP)/Contents/MacOS/FeiLianControl"; do \
		arches="$$(lipo -archs "$$binary")"; \
		test "$$arches" = "arm64" || { echo "架构不符合 Apple Silicon 限定：$$binary ($$arches)"; exit 1; }; \
	done
	xattr -cr "$(PKGROOT)"
	pkgbuild --root "$(PKGROOT)" --component-plist pkg/component.plist --identifier com.feiliancontrol.pkg --version $(VERSION) --scripts pkg/scripts --ownership recommended "$(COMPONENT)"
	productbuild --distribution pkg/Distribution --resources pkg/resources --package-path "$(BUILD)" "$(PKG)"
	shasum -a 256 "$(PKG)" | awk -v name="$(notdir $(PKG))" '{print $$1 "  " name}' > "$(PKG).sha256"
	@cd "$(BUILD)" && shasum -a 256 -c "$(notdir $(PKG)).sha256"
	@echo "已生成：$(PKG)"
	@cat "$(PKG).sha256"

uninstall:
	@test "$$(id -u)" -eq 0 || { echo "请用 sudo make uninstall"; exit 1; }
	./scripts/uninstall-helper.sh

clean:
	rm -rf "$(BUILD)"
