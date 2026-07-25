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
- **Resets on reboot (♻️):** `sysctl` tweaks (GPU limit, TCP buffers, socket backlog,
  window scaling, file descriptors), `nvram`, and `renice` priority changes live in
  memory/firmware. They vanish on restart — reapply if you want them permanent, or
  see **Process priority** below for the login-persistence option.

## Firewall & Stealth Mode — safe, reversible

**Enable Application Firewall** and **Enable Stealth Mode** only flip built-in
`socketfilterfw` state — no daemons removed, no files touched. Both revert cleanly
to their previous state and are marked **safe**. **Block Auto-Allow Signed Apps** is
one notch stricter (**moderate**): it makes every app, including Apple's own, ask
before accepting inbound connections, so expect more prompts until you allow the
apps you use regularly.

## Privacy DNS — plaintext, not encrypted

**Use Privacy DNS (Cloudflare)** changes which resolver your Mac asks, not *how* it
asks. Queries still go out as **plaintext DNS** over UDP/TCP port 53 — anyone on the
network path between you and Cloudflare can still see which domains you're
resolving. macOS has no `networksetup`/`scutil` switch for encrypted DNS-over-HTTPS
or DNS-over-TLS; that requires installing a signed configuration profile, which is
out of scope for a reversible command-line tweak. Treat this as *"a more
privacy-respecting operator"*, not *"encrypted DNS"*. The app applies it to every
active network service; reverting clears all of them back to automatic (DHCP-served)
DNS.

## IPv6 — advanced, can break connectivity

**Disable IPv6** removes an entire protocol from a network interface. On networks
that are IPv6-only or IPv6-preferred (some corporate VPNs, some ISPs, some Docker/
Kubernetes setups) this can silently break connectivity rather than just slow it
down — there's no in-between state. It's marked **advanced** for that reason: verify
with `networksetup -getinfo <service>` and know how to run the revert command
before you apply it, especially on a Mac you can't reach a Terminal on if something
goes wrong.

## Network sysctl tuning — resets on reboot

**Enable TCP Window Scaling** and **Raise Max File Descriptors** (alongside the
existing **Enlarge TCP Buffers** and **Raise Socket Backlog**) are `sysctl -w`
writes — kernel state, not a config file. Like every other `sysctl` tweak on this
page, they **reset to the macOS default on every reboot**; there's no persistence
option for these because they're meant to be low-risk, low-permanence knobs for a
single working session (e.g. before running a load test).

## Process priority (`renice`) — reboot-transient, admin-only, floor at −10

Everything under **Process Priority** runs through `sudo renice`, so it needs an
administrator password like any other `sudo` tweak. A few extra rules apply
specifically to priority:

- **The app enforces a floor of `-10`.** macOS allows nice values down to `-20`, but
  going that low can starve the WindowServer and make the whole UI stutter. The app
  won't let you go past `-10`, and it warns before anything more negative than `-5`.
- **Reboot-transient by default.** `renice` only affects the current process
  instance — a fresh launch (or a reboot) reverts silently to nice `0`. Turn on
  **Apply at login** if you want a target's priority reapplied automatically every
  time you log in (see [TWEAKS.md](TWEAKS.md) for the exact LaunchAgent plist).
- **Emergency reset:** run `sudo renice -n 0` on every process you've raised or
  lowered, then remove any `~/Library/LaunchAgents/com.mactweak.priority.*.plist`
  files and `launchctl unload` them first if still loaded.

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

## Audit trail — every change is logged

MacTweak records each system change you make to macOS's **unified log** (the same
journal `Console.app` reads) under a dedicated `audit` category, so you can always
answer *"what did this app actually change, and did it work?"* — even weeks later,
and even for changes made by its background agents.

Read the trail:
```bash
# everything MacTweak changed in the last hour
log show --last 1h --predicate 'subsystem == "com.tanguy.MacTweak" AND category == "audit"' --style compact

# watch changes live as you toggle things
log stream --predicate 'subsystem == "com.tanguy.MacTweak" AND category == "audit"'
```

Entries are `key=value` pairs, so they're greppable:
```
CHANGE event=tweak.set key=disable-siri-daemon from=notApplied to=applied privilege=admin exit=0 result=ok
CHANGE event=admin.unlock sudoers=/etc/sudoers.d/mactweak exit=0 result=ok
CHANGE event=cleanup.clean item=xcode-derived sizeBefore=564M sizeAfter=0B exit=0 result=ok
CHANGE event=priority.setNice pid=482 process=mDNSResponder from=0 to=-5 result=ok
```

- **`result=`** is `ok` (the probe confirmed the new state), `failed` (ran, but the
  system didn't end up where it was asked — the `error=` field says why),
  `cancelled` (you dismissed the auth prompt), or `skipped` (nothing to do).
- `result=ok` means **verified**, not merely "the command exited 0" — MacTweak
  re-probes the real state and logs `actual=` alongside the intent.
- **Destructive actions log before they act.** Orphaned-leftover deletions write one
  `cleanup.orphaned.delete path=…` line per path *before* the delete runs, so the
  record survives even if the pass dies partway through.
- Only non-sensitive identifiers are logged — tweak keys, states, exit codes, pids.
  Never raw command strings or file contents. Entries are deliberately **public**
  (not `<private>`), because a trail redacted to `<private>` is useless.

The same lines are mirrored to a plain-text file at
`~/Library/Logs/MacTweak/MacTweak.log`, tagged `[CHANGE]`:
```bash
grep CHANGE ~/Library/Logs/MacTweak/MacTweak.log
```

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
