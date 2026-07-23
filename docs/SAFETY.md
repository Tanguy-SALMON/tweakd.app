# MacTweak — Privileges, SIP & Safety

Everything MacTweak does is **reversible**. This page explains the ground rules so
nothing surprises you — whether you use the app or the [manual commands](TWEAKS.md).

## Privilege levels

| Marker | Meaning |
|---|---|
| 🔓 **no sudo** | User-level (`defaults`, per-user `launchctl`). Applies instantly, no password. |
| 🔐 **sudo** | Touches system state. In Terminal, prefix with `sudo`; the app uses the native password dialog. |

- **In the app:** user tweaks apply with no prompt. Admin tweaks trigger the macOS
  password dialog once — or, if you've unlocked passwordless admin, run silently.
- **By hand:** run the `sudo` lines in Terminal. Your keystrokes are invisible while
  typing the password — that's expected.

## System Integrity Protection (SIP)

SIP is Apple's kernel-level protection that guards system files, system daemons and
NVRAM from modification — **even by root**. It's on by default and protects most
Macs well.

Check your status:
```bash
csrutil status
# → "System Integrity Protection status: enabled."  (or "disabled.")
```

A handful of tweaks are marked 🧱 **SIP off** — they modify protected system daemons
or boot-args and **silently do nothing while SIP is on**:

- **Disable Diagnostics & Analytics** (`com.apple.analyticsd`)
- **Server Performance Mode** (`nvram boot-args`)

In the app these show as **Unavailable** (greyed out) when SIP is enabled, so you
can't half-apply them.

### Disabling SIP (only if you understand the trade-off)

1. Reboot into **Recovery** (Apple Silicon: hold the power button → *Options*).
2. Open **Terminal** → `csrutil disable` → reboot.

Disabling SIP lowers your Mac's defenses against malware and rootkits. **Most people
should leave it on** and simply skip the two SIP-off tweaks.

## Reversibility

- **Every tweak has a revert.** In the app: the row toggle, or **Revert All** on the
  Dashboard restores stock in one click. By hand: the **Revert** command in
  [TWEAKS.md](TWEAKS.md).
- Reverts use **`defaults delete`** to restore the macOS *default behavior* rather
  than guessing a specific value — the cleanest possible undo.
- **Resets on reboot (♻️):** `sysctl` tweaks (GPU limit, TCP buffers, socket backlog)
  and `nvram` live in memory/firmware. They vanish on restart — reapply if you want
  them permanent.

## The emergency revert script

If a tweak ever makes the system misbehave and the app won't open, MacTweak can write
a standalone script (**Quick Actions → Create Emergency Revert Script**) to:

```
~/Documents/MacTweak_Revert.sh
```

Run it from Terminal to undo everything:
```bash
bash ~/Documents/MacTweak_Revert.sh
```

It reverts every user-level tweak, then every admin tweak (prompting for `sudo`),
and restarts Dock & Finder. You can also just work through the **Revert** commands in
[TWEAKS.md](TWEAKS.md) by hand.

## Verify anything yourself

Trust nothing — read the value before and after with the same tool:
```bash
defaults read -g NSWindowResizeTime                 # snappiness
pmset -g | grep powernap                             # power
sysctl -n kern.ipc.somaxconn                         # network
mdutil -s /                                           # spotlight
launchctl print-disabled gui/$(id -u) | grep photoanalysisd
```

This is exactly what MacTweak does after every change — which is why it only marks a
tweak *Applied* when the system truly reports the new state.

## Passwordless admin — the trade-off

**Unlock** on the Dashboard's *Admin Access* card authenticates **once** and installs
a sudoers rule so later admin tweaks apply without a prompt:

- Lives at `/etc/sudoers.d/mactweak` (root-owned, `0440`, validated with `visudo -c`).
- Grants your user passwordless root via `NOPASSWD: /bin/zsh`.
- **Lock** removes it. Manual removal: `sudo rm /etc/sudoers.d/mactweak`.

This is a genuine convenience-for-safety trade: any process running as you can then
reach root without a password. Fine for a personal machine — **lock it when you're
done tuning** if that matters to you.

## What "not sandboxed / ad-hoc signed" means

MacTweak is **not** in the App Sandbox and is **locally (ad-hoc) signed**. It has to
be: driving `pmset`/`mdutil`/`launchctl`/`sysctl`/`nvram` and escalating through the
native password prompt is impossible inside the sandbox. Everything it runs is listed
in [TWEAKS.md](TWEAKS.md) — nothing is hidden, and you can run all of it by hand.

See also: [TWEAKS.md](TWEAKS.md) · [FAQ.md](FAQ.md) · [ARCHITECTURE.md](ARCHITECTURE.md)
