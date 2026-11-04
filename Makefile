APP      := .build/SpaceKeys.app
DEST     := $(HOME)/Applications/SpaceKeys.app
# Ad-hoc signing loses the Accessibility permission on every rebuild. Set
# IDENTITY to a signing certificate in local.mk (untracked) to keep it.
-include local.mk
IDENTITY ?= -
# A notarytool keychain profile, see "Releases" in the README.
NOTARY_PROFILE ?= spacekeys

RELEASE  = .build/release-$(VERSION)
DMG      = $(RELEASE)/SpaceKeys-$(VERSION).dmg

.PHONY: build app test install uninstall logs release publish

# macOS draws an app in the current system style only if the binary
# records the SDK it was built with. SwiftPM's default build system writes
# the deployment target there instead, so the linker gets both explicitly.
# MACOS_MIN must match platforms in Package.swift and LSMinimumSystemVersion.
MACOS_MIN := 15.0
SDK_VERSION = $(shell xcrun --sdk macosx --show-sdk-version)
LINK_FLAGS = -Xlinker -platform_version -Xlinker macos \
	-Xlinker $(MACOS_MIN) -Xlinker $(SDK_VERSION)

# $(call bundle,binary,app): lays out an unsigned app bundle.
define bundle
	rm -rf $(2)
	install -d $(2)/Contents/MacOS $(2)/Contents/Resources
	install -m 755 $(1) $(2)/Contents/MacOS/SpaceKeys
	install -m 644 App/Info.plist $(2)/Contents/Info.plist
	install -m 644 App/AppIcon.icns $(2)/Contents/Resources/AppIcon.icns
endef

build:
	swift build -c release $(LINK_FLAGS)

test:
	swift test

app: build
	$(call bundle,.build/release/SpaceKeys,$(APP))
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

# A universal, notarized DMG of the checked-out commit. Notarization needs
# a secure timestamp on every signature, unlike the local `app` build.
release:
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "usage: make release VERSION=0.1.0" >&2; exit 1; }
	@case "$(IDENTITY)" in "Developer ID Application:"*) ;; *) echo "release needs a Developer ID Application IDENTITY in local.mk" >&2; exit 1;; esac
	@test -z "$$(git status --porcelain)" || { echo "release needs a clean checkout" >&2; exit 1; }
	swift build -c release --arch arm64 --arch x86_64 $(LINK_FLAGS)
	rm -rf $(RELEASE)
	$(call bundle,.build/out/Products/Release/SpaceKeys,$(RELEASE)/dmg/SpaceKeys.app)
	plutil -replace CFBundleShortVersionString -string $(VERSION) $(RELEASE)/dmg/SpaceKeys.app/Contents/Info.plist
	plutil -replace CFBundleVersion -string $$(git rev-list --count HEAD) $(RELEASE)/dmg/SpaceKeys.app/Contents/Info.plist
	codesign --force --options runtime --timestamp --sign "$(IDENTITY)" $(RELEASE)/dmg/SpaceKeys.app
	codesign --verify --strict $(RELEASE)/dmg/SpaceKeys.app
	ln -s /Applications $(RELEASE)/dmg/Applications
	diskutil image create from --format UDZO --volumeName SpaceKeys $(RELEASE)/dmg $(DMG)
	codesign --timestamp --sign "$(IDENTITY)" $(DMG)
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)
	spctl --assess --type open --context context:primary-signature -v $(DMG)
	cd $(RELEASE) && shasum -a 256 $(notdir $(DMG)) > $(notdir $(DMG)).sha256
	git rev-parse HEAD > $(RELEASE)/commit

# Tags the commit the DMG was built from, which must be on GitHub. GitHub
# ignores --target when the tag exists, so an existing tag must already
# point at that commit.
publish:
	@test -n "$(VERSION)" || { echo "usage: make publish VERSION=0.1.0" >&2; exit 1; }
	@test -f $(DMG).sha256 -a -s $(RELEASE)/commit || { echo "run make release VERSION=$(VERSION) first" >&2; exit 1; }
	@tagged=$$(git ls-remote --tags origin refs/tags/v$(VERSION) | cut -f1); \
		test -z "$$tagged" -o "$$tagged" = "$$(cat $(RELEASE)/commit)" || \
		{ echo "v$(VERSION) on origin is $$tagged, but the DMG was built from $$(cat $(RELEASE)/commit)" >&2; exit 1; }
	gh release create v$(VERSION) $(DMG) $(DMG).sha256 \
		--target $$(cat $(RELEASE)/commit) --title v$(VERSION) --generate-notes
