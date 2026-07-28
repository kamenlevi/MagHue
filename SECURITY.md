# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/kamenlevi/MagHue/security/advisories/new)
rather than opening a public issue. I'll acknowledge reports within a week.

## What MagHue touches

MagHue is a menu bar app plus a privileged helper, so it's worth being
explicit about what runs with what privileges:

- **The app** (`/Applications/MagHue.app`) runs as your user. It reads battery
  state, writes its own preferences, and writes the helper's config file at
  `/Library/Application Support/MagHue/config.json`. The installer chowns that
  directory to the installing user, so the app needs no privileges to do it.
- **The helper** (`/Library/PrivilegedHelperTools/com.kamenlevi.maghue.helper`)
  is a launchd daemon that runs as root, because writing SMC keys requires it.
  It watches the battery and the config file, and writes:
  - `ACLC` — the MagSafe LED colour. Affects the light only.
  - `bfF0` / `bfD0` / `bfE0` — the firmware charge-limit keys, and only while
    a Charge to Full request is in flight. The helper restores your previous
    limit once the battery reaches 100%.
- **Installation** runs `install-helper.sh` as root via the system's admin
  password prompt. It copies the helper and its launchd plist into place and
  bootstraps the daemon.
- MagHue makes **no network connections**. Sunrise and sunset are computed
  locally from your coordinates; the coordinates never leave your Mac.

The helper resets the LED to system control when it shuts down or is
uninstalled.

## In scope

- Privilege escalation through the helper, its config file, or the installer.
- Anything that lets a non-admin user change what the helper writes.
- The helper writing SMC keys other than those listed above.

## Out of scope

- The LED showing a colour you didn't expect. That's a bug — please open a
  normal issue.
- Physical access attacks, and anything requiring root to begin with.

## Verifying what you install

The app is built from source (`make install`) and signs its binaries ad-hoc;
there's no notarized release yet, so a downloaded build isn't something to
trust blindly. `maghue-helper --probe` prints what the helper can see without
changing anything, and the uninstall steps in the README remove every file it
installs.
