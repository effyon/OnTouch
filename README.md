# OnTouch

A tiny macOS menu-bar app that adds Jitouch-style **anchored trackpad gestures**
for navigating Safari tabs. It reads raw finger data from Apple's private
`MultitouchSupport.framework` (the same approach Jitouch used) and posts keyboard
shortcuts to Safari.

## Gestures

| Gesture | Action |
| --- | --- |
| Hold one finger, **tap to its left** with another | Previous tab (Ctrl-Shift-Tab) |
| Hold one finger, **tap to its right** with another | Next tab (Ctrl-Tab) |
| Hold one finger, **swipe down with two others** | Close current tab (Cmd-W) |

Gestures only fire while **Safari is frontmost** (configurable), so they never
interfere with other apps.

## Build & run

```sh
./build.sh        # compiles + assembles OnTouch.app (ad-hoc signed)
open OnTouch.app
```

Or run in the foreground to watch logs (`./run.sh`). The app lives in the menu
bar (hand icon + "OnTouch" label); there is no Dock icon.

> **Can't see the menu-bar item?** On MacBooks with a notch, menu-bar icons can
> hide *behind the notch* when the bar is crowded. Quit some other menu-bar apps,
> or use a menu-bar manager (e.g. Bartender/Ice) to reveal it. The "OnTouch"
> text label makes it easier to spot.

## Permissions (first launch)

macOS will prompt for two permissions. Grant both, then **quit and relaunch**:

1. **Accessibility** — lets the app post keystrokes to Safari.
   System Settings → Privacy & Security → Accessibility.
2. **Input Monitoring** — lets it read raw multitouch data.
   System Settings → Privacy & Security → Input Monitoring.

The menu has shortcuts to open both panes. Add `OnTouch.app` and toggle it on.

> The app is ad-hoc signed, so its permission grants survive rebuilds (same
> bundle identifier `com.local.ontouch`). If you move the `.app`, re-grant.

## Tuning

Recognition thresholds live in `Sources/OnTouch/Config.swift`. To change them
without rebuilding, create `~/.config/trackpad-tabs/config.json` with any subset
of keys, e.g.:

```json
{
  "swipeDownDist": 0.08,
  "tapMaxDuration": 0.40,
  "targetBundleIDs": ["com.apple.Safari", "com.google.Chrome"]
}
```

Distances are normalized trackpad units (0–1); times are in seconds.

## How it works

- `CMultitouch` — C shim declaring the private MT API and linking the framework.
- `MultitouchReader` — opens every MT device and streams frames via a C callback.
- `GestureEngine` — tracks finger contacts, identifies a held *anchor* finger,
  and recognizes taps (left/right of the anchor) and two-finger down-swipes.
- `ActionRunner` — posts the mapped keyboard shortcut, but only when a target
  app is frontmost.
- `AppDelegate` — menu-bar UI, enable/disable toggle, permission shortcuts.

## Credits

OnTouch is an independent project, written from scratch. It was inspired by and
learned from these excellent open-source projects (no code was copied from
either):

- [**Jitouch**](https://github.com/sukolsak/jitouch) — the original trackpad
  gesture utility whose "hold an anchor finger, act with another" interaction
  model this app reproduces. Jitouch is GPLv3; OnTouch shares none of its source.
- [**pqrs-org/osx-event-observer-examples**](https://github.com/pqrs-org/osx-event-observer-examples)
  — reference for the macOS event-observer permission model (Input Monitoring /
  Accessibility).

The `MultitouchSupport.framework` struct layout used here is reverse-engineered
public knowledge reproduced across many open-source multitouch readers.

## License

[MIT](LICENSE) — do whatever you like, just keep the copyright notice. Remember
to put your name in the `LICENSE` file.

## Caveats / next steps

- If a tap accidentally triggers macOS two-finger secondary-click, disable
  "two-finger secondary click" or tune `tapMaxDuration` down.
- "Close all" is wired in `ActionRunner` (Cmd-Shift-W) but not yet bound to a
  gesture — easy to add (e.g. anchor + three-finger swipe down).
- Multi-app support: add bundle IDs to `targetBundleIDs`. Tab shortcuts differ
  per browser.
