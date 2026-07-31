# MagHue

Choose when your MagSafe charger's LED turns green.

Out of the box, macOS keeps the MagSafe LED amber until the battery hits 100%.
MagHue is a tiny menu bar app that lets you pick the percentage instead. Set it
to 80% and the LED turns green the moment your battery reaches 80% while
charging, and back to amber if it ever drops below. Perfect if you use a
charge limit and your Mac never *reaches* 100%.

<p align="center">
  <img src="docs/popover-light.png?v=2" alt="MagHue's popover: LED mode picker, threshold slider and options" width="356">
  <img src="docs/popover-automation.png?v=2" alt="MagHue's Automation tab: light off from sunset to sunrise" width="356">
</p>

## Requirements

- Apple Silicon MacBook with a MagSafe 3 port (2021 or later MacBook Pro / Air).
- macOS 14 Sonoma or later.
- Any charge cable with a MagSafe LED (the stock Apple ones).

## Install

Paste this into Terminal (⌘-Space, type "Terminal") and press Enter:

```sh
curl -fsSL https://raw.githubusercontent.com/kamenlevi/MagHue/main/scripts/install.sh | bash
```

It downloads the latest release, puts MagHue.app into /Applications and opens
it. Nothing to build, no Xcode tools needed, and no macOS security dialog:
command-line downloads skip the quarantine that browser downloads get.

Then click the MagHue icon in the menu bar, press **Install Helper…** and
enter your admin password once. That's it.

### Or download it yourself

Grab `MagHue.zip` from the [latest release](https://github.com/kamenlevi/MagHue/releases/latest),
unzip it and drag MagHue.app into Applications. Because browsers quarantine
downloads and MagHue isn't notarized (that costs $99/year), the first launch
shows "Apple could not verify…". Click **Done**, open **System Settings →
Privacy & Security**, scroll down and press **Open Anyway**. It's a one-time
step.

### Or build it from source

```sh
xcode-select --install    # only if you've never installed the CLT
git clone https://github.com/kamenlevi/MagHue.git
cd MagHue
make install              # builds and copies MagHue.app to /Applications
open /Applications/MagHue.app
```

If the build fails, the script prints which step broke and the Swift version it
used. Capture it and send the last 40 lines, which is the useful part. No need
for the whole log:

```sh
make install > /tmp/maghue-build.log 2>&1
tail -40 /tmp/maghue-build.log
```

[Open an issue](https://github.com/kamenlevi/MagHue/issues/new/choose) with
that output. It's usually a toolchain difference rather than anything about
your Mac.

## Features

- **Threshold slider**: pick the battery percentage (10-100%) at which the LED
  turns green while on power; below it the LED shows the usual amber.
- **Three LED modes**: *Custom* (green at your chosen level, amber below it),
  *Off* (dark while plugged in), or *System* (stock macOS behavior). Each has a
  one-line explanation in the app.
- **Charge to Full once**: a one-shot button that lifts the macOS charge limit
  so the battery fills to 100% this time (handy before travel), then restores
  your limit automatically once it's full. Shown only on Macs whose firmware
  exposes the charge-limit keys.
- **Automation**: an Automation tab where you schedule the light to change at
  set times: pick the days, a start and end (a clock time, or **sunset** /
  **sunrise**), and what the light does in that window (Off, Green, Amber,
  System, or Custom). For example, keep the light off from sunset to sunrise
  every day. Sunrise/sunset are computed locally from your location, with
  no network access.
- Optional extras: a notification when the threshold is reached (off by
  default). Launch at login is on by default and can be turned off.
- Works even when the app is closed: a tiny background helper keeps the LED
  correct at all times.

## How it works

Apple Silicon Macs expose an SMC key called `ACLC` that selects the MagSafe LED
color (`0` system, `1` off, `3` green, `4` amber). Writing SMC keys requires
root, so MagHue installs a small launchd daemon
(`com.kamenlevi.maghue.helper`) that watches the battery and the config file
and writes that one key. The menu bar app is just the UI; the daemon does the
work, which is why the LED stays correct even when the app isn't running.

**Charge to Full** works through the firmware charge-limit keys (`bfF0`/`bfD0`/
`bfE0`), the same mechanism macOS's own Charge Limit uses. MagHue lifts the
limit, waits for 100%, then restores your exact previous setting. If your Mac's
firmware doesn't expose the full key set, the button simply doesn't appear and
MagHue never touches charging at all.

### Is this safe?

Yes. `ACLC` only changes what the LED *indicates*. It has no effect on
charging current, voltage, battery management, or anything else. It's the same
mechanism macOS itself uses to drive the LED, and value `0` hands control
straight back to the system. Open-source tools like
[batt](https://github.com/charlie0129/batt) and
[BatFi](https://github.com/rurza/BatFi) have written this key for years. The
helper resets the LED to system control whenever it shuts down or is
uninstalled.

[SECURITY.md](SECURITY.md) spells out what runs with which privileges, every
SMC key the helper writes, and how to report a problem privately.

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

## Development

- `make app` builds `dist/MagHue.app`, `make install` copies it to
  `/Applications`, `make zip` packages it.
- `dist/MagHue.app/Contents/MacOS/MagHue --screenshot docs` re-renders the
  README images above from the live interface. It draws into an offscreen
  bitmap (no screen-recording permission needed) and writes nothing to your
  settings or the helper's config file.

## Credits

[Peter Levi](https://github.com/peterlevi), author of Variety, took part in
developing MagHue. The **Donate** button in the app goes to his PayPal for that
reason.

## License

MagHue: choose when your MagSafe charger's LED turns green.
Copyright © 2026 Kamen Levi.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE).

In short: fork it, change it, ship it, but anything you distribute that's
built on it has to stay under the GPL, with its source available. It can't be
folded into a closed-source app.
