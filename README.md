# MagHue

Choose when your MagSafe charger's LED turns green.

Out of the box, macOS keeps the MagSafe LED red until the battery hits 100%.
MagHue is a tiny menu bar app that lets you pick the percentage instead — set it
to 80% and the LED turns green the moment your battery reaches 80% while
charging, and back to red if it ever drops below. Perfect if you use a
charge limit and your Mac never *reaches* 100%.

## Features

- **Threshold slider** — pick the battery percentage (10–100%) at which the LED
  turns green while on power; below it the LED shows the usual red.
- **Three LED modes** — Automatic (threshold), always **Off** (sleep-friendly),
  or **System** (stock macOS behavior).
- Optional extras, all off by default: launch at login, battery percentage in
  the menu bar, and a notification when the threshold is reached.
- Works even when the app is closed — a tiny background helper keeps the LED
  correct at all times.

## Requirements

- Apple Silicon MacBook with a MagSafe 3 port (2021 or later MacBook Pro / Air).
- macOS 14 Sonoma or later.
- Any charge cable with a MagSafe LED (the stock Apple ones).

## Install

```sh
git clone https://github.com/kamenlevi/MagHue.git
cd MagHue
make install        # builds and copies MagHue.app to /Applications
open /Applications/MagHue.app
```

Click the MagSafe icon in the menu bar, then **Install Helper…** — you'll be
asked for your admin password once. That's it.

## How it works

Apple Silicon Macs expose an SMC key called `ACLC` that selects the MagSafe LED
color (`0` system, `1` off, `3` green, `4` red — the standard reddish-amber
"charging" color). Writing SMC keys requires
root, so MagHue installs a small launchd daemon
(`com.kamenlevi.maghue.helper`) that watches the battery and the config file
and writes that one key. The menu bar app is just the UI; the daemon does the
work, which is why the LED stays correct even when the app isn't running.

### Is this safe?

Yes. `ACLC` only changes what the LED *indicates* — it has no effect on
charging current, voltage, battery management, or anything else. It's the same
mechanism macOS itself uses to drive the LED, and value `0` hands control
straight back to the system. Open-source tools like
[batt](https://github.com/charlie0129/batt) and
[BatFi](https://github.com/rurza/BatFi) have written this key for years. The
helper resets the LED to system control whenever it shuts down or is
uninstalled.

## Uninstall

Click **Uninstall Helper** in the popover (asks for your password, removes the
daemon, and returns the LED to macOS), then delete `/Applications/MagHue.app`.

Manual removal, if you ever need it:

```sh
sudo launchctl bootout system/com.kamenlevi.maghue.helper
sudo /Library/PrivilegedHelperTools/com.kamenlevi.maghue.helper --reset
sudo rm /Library/PrivilegedHelperTools/com.kamenlevi.maghue.helper \
        /Library/LaunchDaemons/com.kamenlevi.maghue.helper.plist
sudo rm -rf "/Library/Application Support/MagHue" /Library/Logs/MagHue
```

## Troubleshooting

- `maghue-helper --probe` (in `Contents/Resources` of the app, or
  `.build/debug` after `swift build`) prints whether your Mac exposes the
  `ACLC` key and what the current battery state is.
- Helper logs: `/Library/Logs/MagHue/helper.log` and
  `log show --predicate 'subsystem == "com.kamenlevi.maghue"' --last 1h`.

## License

MIT
