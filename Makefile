APP      := .build/SpaceKeys.app
DEST     := $(HOME)/Applications/SpaceKeys.app
# Ad-hoc signing loses the Accessibility permission on every rebuild. Set
# IDENTITY to a signing certificate in local.mk (untracked) to keep it.
-include local.mk
IDENTITY ?= -

.PHONY: build app test install uninstall logs

# macOS draws an app in the current system style only if the binary
# records the SDK it was built with. SwiftPM's default build system writes
# the deployment target there instead, so the linker gets both explicitly.
# MACOS_MIN must match platforms in Package.swift and LSMinimumSystemVersion.
MACOS_MIN := 15.0
SDK_VERSION = $(shell xcrun --sdk macosx --show-sdk-version)

build:
	swift build -c release \
		-Xlinker -platform_version -Xlinker macos \
		-Xlinker $(MACOS_MIN) -Xlinker $(SDK_VERSION)

test:
	swift test

app: build
	rm -rf $(APP)
	install -d $(APP)/Contents/MacOS $(APP)/Contents/Resources
	install -m 755 .build/release/SpaceKeys $(APP)/Contents/MacOS/SpaceKeys
	install -m 644 App/Info.plist $(APP)/Contents/Info.plist
	install -m 644 App/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --options runtime --timestamp=none --sign "$(IDENTITY)" $(APP)
	codesign --verify --strict $(APP)

install: app
	@osascript -e 'quit app id "de.alt-f4.spacekeys"' >/dev/null 2>&1 || true
	install -d $(dir $(DEST))
	rm -rf $(DEST)
	ditto $(APP) $(DEST)
	open $(DEST)

uninstall:
	@osascript -e 'quit app id "de.alt-f4.spacekeys"' >/dev/null 2>&1 || true
	rm -rf $(DEST)

logs:
	log stream --level info --predicate 'subsystem == "de.alt-f4.spacekeys"'
