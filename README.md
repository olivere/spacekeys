# SpaceKeys

A menu bar app that maps the buttons of a
[3Dconnexion](https://3dconnexion.com/)
[SpaceMouse Pro](https://3dconnexion.com/us/product/spacemouse-pro/) to
keyboard shortcuts on macOS, without 3DxWare. It reads only the button
reports and opens the device without seizing it, so a motion driver such as
[Space Glider](https://apps.metaebene.me/en/space-glider) keeps working
alongside it.

## Install

```sh
make install
```

This builds `SpaceKeys.app`, signs it, copies it to `~/Applications` and
starts it. Without further setup the app is signed ad-hoc, and macOS asks
for the Accessibility permission again after every rebuild. To sign with
your own certificate, name it in an untracked `local.mk`:

```make
IDENTITY := Developer ID Application: Your Name (TEAMID)
```

`security find-identity -v -p codesigning` lists the certificates you have.

Tick "Open at Login" in the app's menu to start it with your session.

On first start macOS asks for the Accessibility permission, which SpaceKeys
needs to send keystrokes. Grant it in System Settings → Privacy & Security →
Accessibility; the app picks it up within two seconds. With a stable signing
identity the permission survives rebuilds.

```sh
make logs        # follow the app's log
make uninstall
make test
```

## Settings

Open Settings… from the menu bar icon. "All Apps" holds the mapping used
everywhere. Add an app with + to give it its own mapping; any button you
leave alone there falls back to All Apps.

Click a field and press a key combination to record it. Pressing and
releasing a modifier on its own (say ⌃) records "hold ⌃": the modifier stays
down for as long as the SpaceMouse button does, so holding SpaceMouse Ctrl
and clicking the mouse is a ctrl-click. The × next to a field unmaps the
button, or for an app, returns it to the All Apps mapping.

Pressing a SpaceMouse button while Settings is open lights up its row.
While a field is recording, SpaceMouse buttons send nothing.

An app with its own SpaceMouse support can take the device exclusively
while it is in front; Kugelblitz does this through its Space Juggler
helper. No button reaches SpaceKeys then, and the menu says "in use by"
that app until it lets go. Every button press is logged with the app in
front and what was sent (`make logs`).

Characters follow the active keyboard layout, so ⌘Z is the key labelled Z
on QWERTZ too. A shortcut stays down as long as the button does, but macOS
does not repeat it.

## Config file

Settings are stored in `~/.config/spacekeys/config.json`. SpaceKeys reads
the file at launch and rewrites it on every change, so quit the app before
editing it by hand.

```json
{
  "apps" : {
    "com.apple.Preview" : {
      "fit" : "cmd+9"
    }
  },
  "buttons" : {
    "1" : "cmd+c",
    "ctrl" : "ctrl",
    "fit" : "cmd+0"
  }
}
```

Button names: `menu`, `fit`, `top`, `right`, `front`, `roll`, `1`–`4`,
`esc`, `alt`, `shift`, `ctrl`, `lock` (rotation lock).

An action is either modifiers alone, held while the button is down (`ctrl`,
`ctrl+shift`), or modifiers plus a key (`cmd+shift+z`). Modifiers are `cmd`,
`shift`, `alt` (or `option`) and `ctrl`. A key is a single character, `plus`
for `+`, or one of `escape`, `return`, `tab`, `space`, `delete`,
`forwarddelete`, `home`, `end`, `pageup`, `pagedown`, `left`, `right`,
`up`, `down`, `f1`–`f20`.

## License

MIT, see [LICENSE](LICENSE).

SpaceKeys is not affiliated with or endorsed by 3Dconnexion. 3Dconnexion
and SpaceMouse are trademarks of 3Dconnexion.
