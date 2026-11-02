APP      := .build/SpaceKeys.app
DEST     := $(HOME)/Applications/SpaceKeys.app
# Ad-hoc signing loses the Accessibility permission on every rebuild. Set
# IDENTITY to a signing certificate in local.mk (untracked) to keep it.
-include local.mk
IDENTITY ?= -

.PHONY: build app test install uninstall logs

build:
	swift build -c release

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
