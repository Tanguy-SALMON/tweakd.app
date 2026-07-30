# Background Services — the guide

Everything the **Services** page does, and the exact `launchctl` command for each, so
you can do all of it in Terminal. Ends with troubleshooting for the errors `launchctl`
gives you.

Every command here is **read-only unless it says otherwise**, and every output shown was
captured on a real Mac (macOS 26) — not invented.

---

## Contents

- [The 60-second version](#the-60-second-version)
- [Concepts you need (and only these)](#concepts-you-need-and-only-these)
- [Tutorial: find and stop something you don't need](#tutorial-find-and-stop-something-you-dont-need)
- [Command reference — app action ↔ Terminal](#command-reference--app-action--terminal)
- [Listing services](#listing-services)
- [Finding *failing* services](#finding-failing-services)
- [Inspecting one service](#inspecting-one-service)
- [What is it costing?](#what-is-it-costing)
- [Stopping, disabling, restarting](#stopping-disabling-restarting)
- [Where the plists live](#where-the-plists-live)
- [What not to touch](#what-not-to-touch)
- [Troubleshooting launchctl errors](#troubleshooting-launchctl-errors)

---

## The 60-second version

```bash
UID=$(id -u)

# 1. What's registered and running for me?  (PID  last-exit  label)
/bin/launchctl print gui/$UID | /usr/bin/awk '/^\tservices = \{/,/^\t\}/' \
  | /usr/bin/egrep -v 'com\.apple\.|application\.|NetworkExtension\.'

# 2. Anything failing?  (column 2 = last exit code)
/bin/launchctl print gui/$UID | /usr/bin/awk '/^\tservices = \{/,/^\t\}/' \
  | /usr/bin/awk '$2 ~ /^[0-9]+$/ && $2 != 0 {print}'

# 3. Stop one now (comes back at next login)
/bin/launchctl bootout gui/$UID/homebrew.mxcl.mysql

# 4. Stop it for good
/bin/launchctl disable gui/$UID/homebrew.mxcl.mysql
/bin/launchctl bootout  gui/$UID/homebrew.mxcl.mysql

# 5. Undo
/bin/launchctl enable    gui/$UID/homebrew.mxcl.mysql
/bin/launchctl bootstrap gui/$UID ~/Library/LaunchAgents/homebrew.mxcl.mysql.plist
```

The rest of this page explains *why* those five steps are the right five.

---

## Concepts you need (and only these)

**launchd runs everything.** Not just Apple's daemons — Homebrew's MySQL, Docker's
helper, Teams' updater, your VPN client. If something starts on its own, launchd started
it.

**Two domains, and the difference matters.**

| Domain | Target syntax | Runs as | Plists in | Needs `sudo`? |
|---|---|---|---|---|
| **User** (agents) | `gui/$(id -u)/<label>` | you, after login | `~/Library/LaunchAgents`, `/Library/LaunchAgents` | **no** |
| **System** (daemons) | `system/<label>` | **root**, from boot | `/Library/LaunchDaemons` | **yes** |

Getting the domain wrong is the single most common reason a `launchctl` command "does
nothing" — see [Troubleshooting](#troubleshooting-launchctl-errors). The app shows the
domain as a **User** / **System** badge on every row precisely because you can't tell
from the label.

**A "label" is the job's ID** — `homebrew.mxcl.nginx`, `com.docker.helper`. It's usually,
but not always, the plist's filename without `.plist`.

**Stop ≠ Disable.** Stopping unloads the job right now; launchd loads it again at your
next login or reboot. Disabling sets a persistent flag so it *stays* off. Both are one
command to undo. The app offers them as two separate buttons for this reason.

**`brew services` is not an alternative here.** On this Mac `brew` refuses to run at all
(`unknown or unsupported macOS version: "26.5.2"`), and even when it works it only knows
about Homebrew's own jobs — which is a small fraction of what's actually running. Talk to
`launchctl`.

---

## Tutorial: find and stop something you don't need

The worked example: **you've stopped doing PHP/MySQL work and want those off.** Five
minutes, and nothing here is irreversible.

### Step 1 — see what's actually registered

```bash
/bin/launchctl print gui/$(id -u) | /usr/bin/awk '/^\tservices = \{/,/^\t\}/' \
  | /usr/bin/egrep -v 'com\.apple\.|application\.|NetworkExtension\.'
```

Read the three columns as **`PID  last-exit  label`**. Real output from this Mac:

```
	services = {
		       0      1 	homebrew.mxcl.nginx
		       0     78 	homebrew.mxcl.ollama
		       0      0 	co.hthai.honcho
		       0     78 	homebrew.mxcl.php
		       0     78 	homebrew.mxcl.mariadb
		       0      - 	com.openssh.ssh-agent
		       0      - 	app.tweakd.adblock
	}
```

- **PID `0`** — registered but **not running** right now.
- **PID non-zero** — running, and that's the process ID.
- **exit `-`** — never run since login. A number is the exit code of its last run.

So above: nothing is currently running; nginx last exited `1`, and php / mariadb /
ollama last exited `78`, which has a specific meaning covered
[below](#finding-failing-services).

Do the same for root daemons — no `sudo` needed to *look*:

```bash
/bin/launchctl print system | /usr/bin/awk '/^\tservices = \{/,/^\t\}/' \
  | /usr/bin/grep -v com.apple.
```

> **Check both.** Homebrew commonly installs the *same* service twice — a user agent
> **and** a root daemon. Looking at only one domain is how you conclude MySQL is off
> while `mysqld` is running happily as root.

### Step 2 — confirm it's really running before you act

The registration list can lie by omission (a job that spawns children shows only the
parent). Check the actual processes:

```bash
/bin/ps -Ao pid=,ppid=,user=,%cpu=,comm= | /usr/bin/grep -Ei 'mysqld|php-fpm|nginx' | /usr/bin/grep -v grep
```

No output means nothing is running, whatever the plists say.

### Step 3 — stop it, and see if you miss it

```bash
/bin/launchctl bootout gui/$(id -u)/homebrew.mxcl.php
```

Silence means success. This is the **safe experiment**: it lasts until your next login,
so the worst case is that you reboot and everything is back.

For a root daemon, same command with the other domain and `sudo`:

```bash
sudo /bin/launchctl bootout system/homebrew.mxcl.mysql
```

### Step 4 — verify, don't assume

`launchctl` returns 0 in situations where nothing happened. Re-check:

```bash
/bin/launchctl print gui/$(id -u) | /usr/bin/grep homebrew.mxcl.php
```

Gone from the list, or PID back to `0` → it's stopped. (This is exactly what the app does
after every action — it re-reads the real domain state rather than trusting the exit
code.)

### Step 5 — make it permanent

Once you've lived without it for a day:

```bash
/bin/launchctl disable gui/$(id -u)/homebrew.mxcl.php
/bin/launchctl bootout  gui/$(id -u)/homebrew.mxcl.php   # also stop it now
```

`disable` only sets the flag; it does **not** stop a running job. That's why both lines
are needed — and why the app's Disable button always runs the pair.

Confirm the flag stuck:

```bash
/bin/launchctl print gui/$(id -u) | /usr/bin/awk '/disabled services = \{/,/\}/' | /usr/bin/grep php
```

```
		"homebrew.mxcl.php" => disabled
```

### Step 6 — the undo

```bash
/bin/launchctl enable    gui/$(id -u)/homebrew.mxcl.php
/bin/launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/homebrew.mxcl.php.plist
```

`enable` clears the flag; `bootstrap` starts it now instead of at next login. Again, the
app runs both.

---

## Command reference — app action ↔ Terminal

`T` = the target, `gui/$(id -u)/<label>` for User rows or `system/<label>` for System
rows (System needs `sudo`).

| Services page | Terminal |
|---|---|
| The list itself | `launchctl print gui/$(id -u)` + `launchctl print system` |
| **Running** / pid | column 1 of the `services = { … }` block |
| **Last exit** badge | column 2 of the same block |
| **Disabled** badge | the `disabled services = { … }` block |
| CPU / memory | `ps -Ao pid=,ppid=,%cpu=,rss=`, summed over the process tree |
| **Ports** | `lsof -nP -iTCP -sTCP:LISTEN` |
| **Stop** | `launchctl bootout T` |
| **Disable** | `launchctl disable T; launchctl bootout T` |
| **Enable** | `launchctl enable T; launchctl bootstrap <domain> <plist>` |
| (no button — see below) **Restart** | `launchctl kickstart -k T` |
| **Stop all in group** | the same `bootout` per label |
| Re-scan | re-run the `print` commands |

---

## Listing services

**Everything registered for your login session:**

```bash
/bin/launchctl print gui/$(id -u)
```

Big output. The parts that matter are the two blocks `services = { … }` (what exists, its
pid and last exit) and `disabled services = { … }` (persistent off-flags).

**Just the third-party ones**, which is what the app shows:

```bash
/bin/launchctl print gui/$(id -u) | /usr/bin/awk '/^\tservices = \{/,/^\t\}/' \
  | /usr/bin/egrep -v 'com\.apple\.|application\.|NetworkExtension\.'
```

Apple also ships a few jobs that *don't* use the `com.apple.` prefix —
`com.openssh.ssh-agent`, `com.vix.cron`, `org.cups.cupsd`. The app treats anything with a
plist under `/System/Library` as Apple's, whatever it calls itself:

```bash
/bin/ls /System/Library/LaunchAgents/<label>.plist /System/Library/LaunchDaemons/<label>.plist 2>/dev/null
```

**Only what's actually running** (pid ≠ 0):

```bash
/bin/launchctl print gui/$(id -u) | /usr/bin/awk '/^\tservices = \{/,/^\t\}/' \
  | /usr/bin/awk '$1 ~ /^[0-9]+$/ && $1 != 0 && $3 !~ /^(com\.apple\.|application\.|NetworkExtension\.)/ {print $1, $3}'
```

> **Why filter `application.`** — every running GUI app gets a synthetic
> `application.<bundle-id>.<n>.<n>` job in your session. They're launchd's bookkeeping
> for open apps, not background services, and they'd otherwise dominate the list. The
> same goes for `NetworkExtension.*` jobs, which are managed by the NE framework and
> System Settings rather than by `launchctl enable`/`disable`. The app hides both.

**Root daemons** — swap the domain. Reading needs **no** `sudo`:

```bash
/bin/launchctl print system | /usr/bin/awk '/^\tservices = \{/,/^\t\}/' | /usr/bin/grep -v com.apple.
```

> **Don't use `launchctl list`.** It merges both domains into one flat table, so a system
> daemon and a user agent with related names blur together and you can read one's state
> off the other's row. `launchctl print <domain>` is per-domain and unambiguous. The app
> was originally built on `list` and this bug is exactly why it isn't any more.

---

## Finding *failing* services

A job that crashes and gets restarted by launchd, over and over, is invisible in Activity
Monitor but very much alive in your battery graph. Column 2 is the last exit code, so
anything non-zero is a job that ended badly:

```bash
for D in gui/$(id -u) system; do
  echo "── $D"
  /bin/launchctl print $D 2>/dev/null | /usr/bin/awk '/^\tservices = \{/,/^\t\}/' \
    | /usr/bin/awk '$2 ~ /^[0-9]+$/ && $2 != 0 {print}'
done
```

Real output from this Mac:

```
── gui/501
	    5726      1 	com.apple.Dock.agent
	       0      1 	homebrew.mxcl.nginx
	       0     78 	homebrew.mxcl.ollama
	       0     78 	homebrew.mxcl.php
	       0     78 	homebrew.mxcl.mariadb
── system
	       0      1 	com.apple.wifiFirmwareLoader
```

**Reading the common exit codes:**

| Code | Means | Usually |
|---|---|---|
| `1` | generic failure | check the job's own log |
| `78` | `EX_CONFIG` — bad configuration | **the port is already taken**, or a config file moved |
| `2` | misuse / bad arguments | the plist's `ProgramArguments` are wrong |
| `127` | command not found | the binary was uninstalled, plist left behind |
| `-9` / `137` | killed | ran out of memory, or something `kill -9`'d it |

The three `78`s above are one story: those Homebrew agents are the **duplicate** copies
of services also installed as root daemons. The daemon binds the port first, the agent
starts, can't bind, and exits `EX_CONFIG`. Nothing is broken — there's just a redundant
copy that will keep failing forever. Disabling the duplicate is the fix.

**A `127` means a leftover plist.** Its app is gone; delete the plist:

```bash
/bin/launchctl bootout gui/$(id -u)/<label>
/bin/rm ~/Library/LaunchAgents/<label>.plist
```

**To see *why* something failed**, its own log is the place:

```bash
/usr/bin/log show --predicate 'process == "nginx"' --last 1h --style compact
```

---

## Inspecting one service

```bash
/bin/launchctl print gui/$(id -u)/homebrew.mxcl.ollama
```

The lines worth finding in that wall of output:

```
	path = /Users/you/Library/LaunchAgents/homebrew.mxcl.ollama.plist
	state = spawn scheduled
	program = /opt/homebrew/opt/ollama/bin/ollama
	stdout path = /opt/homebrew/var/log/ollama.log
	stderr path = /opt/homebrew/var/log/ollama.log
	runs = 1
	last exit code = 78: EX_CONFIG
```

- **`path`** — which plist, so you know what to edit or delete.
- **`state`** — `running`, `not running`, `waiting for initial kickoff`, `spawn scheduled`.
- **`program`** / **`arguments`** — what actually executes. Check the binary still exists.
- **`stdout path` / `stderr path`** — **the fastest route to why it failed.** `tail` it.
- **`runs`** — how many times launchd has started it. A large number on a short uptime
  *is* a crash loop.
- **`last exit code`** — helpfully named here (`78: EX_CONFIG`), unlike in the list view.

```bash
/usr/bin/tail -20 /opt/homebrew/var/log/ollama.log
```

If it says `Could not find service … in domain for user gui`, you're in the wrong domain
— try `system/<label>`. See [Troubleshooting](#troubleshooting-launchctl-errors).

---

## What is it costing?

**Measure the whole process tree, not the pid launchd started.** Many services are a
shell wrapper or a supervisor whose children do all the work — Homebrew's MySQL job is
literally `/bin/sh`, so reading its root pid reports roughly zero and tells you nothing.
The app sums CPU and memory across the tree; by hand:

```bash
# direct children of a service's pid, with cost
PID=99128
/bin/ps -Ao pid=,ppid=,%cpu=,rss=,comm= | /usr/bin/awk -v p=$PID '$1==p || $2==p {printf "%-8s %-8s cpu=%-6s mem=%dMB  %s\n", $1,$2,$3,$4/1024,$5}'
```

**Busiest processes overall:**

```bash
/bin/ps -Ao pid=,%cpu=,%mem=,comm= -r | /usr/bin/head -15
```

> A single `top` or `ps` frame **overstates spikes** — it can report 49% for a process
> that then uses no CPU at all. For an honest number, take a `cputime` delta:
> ```bash
> /bin/ps -o cputime= -p $PID; sleep 10; /bin/ps -o cputime= -p $PID
> ```
> The difference over 10 s, ×10, is the real percentage of one core.

**What ports is it holding?**

```bash
/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN
```

Or the reverse question, "who has port 3306?":

```bash
/usr/sbin/lsof -nP -iTCP:3306 -sTCP:LISTEN
```

---

## Stopping, disabling, restarting

Set `T` once and the rest reads cleanly:

```bash
T=gui/$(id -u)/homebrew.mxcl.redis     # user agent
# T=system/com.example.daemon          # root daemon — prefix commands with sudo
```

**Stop now** (returns at next login/boot):

```bash
/bin/launchctl bootout $T
```

**Disable persistently** (and stop now — `disable` alone won't):

```bash
/bin/launchctl disable $T
/bin/launchctl bootout  $T 2>/dev/null || true
```

The `|| true` is because `bootout` fails when the job isn't loaded, which is a no-op
rather than an error.

**Enable again** (and start now — `enable` alone won't):

```bash
/bin/launchctl enable    $T
/bin/launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/homebrew.mxcl.redis.plist
```

**Restart** — the one thing the app has no button for:

```bash
/bin/launchctl kickstart -k $T
```

`-k` kills it first, then starts it. Without `-k` it only starts a job that isn't
running. This is the right tool for "the service is wedged, bounce it".

**Start a stopped job without restarting the machine:**

```bash
/bin/launchctl kickstart $T
```

---

## Where the plists live

| Path | Domain | Whose |
|---|---|---|
| `~/Library/LaunchAgents` | user | things **you** installed (Homebrew, dev tools) |
| `/Library/LaunchAgents` | user | apps installed for all users |
| `/Library/LaunchDaemons` | system | root daemons — Docker, VPNs, EDR agents |
| `/System/Library/Launch*` | — | **Apple's. SIP-protected. Not yours.** |
| *inside an app bundle* | either | **app-registered** — see below |

```bash
/bin/ls -1 ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons 2>/dev/null
```

**App-registered background items have no plist you can find.** Since macOS 13, apps
register launchd jobs from *inside their own bundle* via `SMAppService`, so scanning
those three directories misses them entirely — Teams' updater is one. launchd knows about
them anyway, which is why the list above starts from `launchctl print` rather than from
the filesystem. You can spot them:

```bash
/bin/launchctl print gui/$(id -u)/<label> | /usr/bin/grep -E 'path|submitted'
```

A `path = … (submitted by smd.N)` line means app-registered. You can `disable` it, but
there's no plist to `bootstrap` — it comes back when its app next registers it, normally
at login. Their user-facing switch is **System Settings → General → Login Items &
Extensions**.

---

## What not to touch

**Apple's own daemons.** The app doesn't list them at all. They're SIP-protected, deeply
interdependent, and switching them off is the classic way to break a Mac in a way that's
hard to diagnose later. The handful genuinely worth disabling — `photoanalysisd`,
`mediaanalysisd`, Siri's agent — ship as **reversible tweaks** in the catalog instead,
where they're documented and undoable in one click. See [TWEAKS.md](TWEAKS.md).

**Security and device-management agents.** Cortex XDR, CrowdStrike, Jamf, Defender,
SentinelOne and friends are listed **read-only** — visible for transparency, never
switchable. On a managed Mac, turning one off is a compliance problem *and* a real loss
of protection, and IT will notice. If one is genuinely misbehaving, that's a conversation
with IT, not a `launchctl` command.

**Anything you can't identify.** Before disabling an unknown label, find out what it is:

```bash
/bin/launchctl print gui/$(id -u)/<label> | /usr/bin/grep -A3 'program'
```

Then look at the binary's path. A job you can't attribute to an app you recognise is
worth researching, not silently killing.

---

## Troubleshooting launchctl errors

**`Could not find service "…" in domain for user gui: 501`**
Wrong domain. It's a root daemon — use `system/<label>` with `sudo`, or find it:
```bash
for D in gui/$(id -u) system; do /bin/launchctl print $D 2>/dev/null | /usr/bin/grep -q "<label>" && echo "found in $D"; done
```

**`Bad request.`**
Malformed target. It's `<domain>/<label>` — `gui/501/foo`, not `gui/foo` or `foo`. Note
`gui/$(id -u)` needs the numeric uid, not your username.

**`Operation not permitted while System Integrity Protection is engaged`**
An Apple service. Not available to you, by design. Don't disable SIP for this.

**`Load failed: 5: Input/output error`**
Usually a plist whose program doesn't exist, or bad permissions on the plist. Validate
it:
```bash
/usr/bin/plutil -lint ~/Library/LaunchAgents/<label>.plist
```

**The command succeeded but nothing changed.**
Expected in two cases: `disable` on an already-running job (it sets the flag but doesn't
stop it — run `bootout` too), and `launchctl disable` on a label that domain doesn't
manage, which **still exits 0**. Always re-read the real state:
```bash
/bin/launchctl print gui/$(id -u) | /usr/bin/grep "<label>"
```

**It came back after a reboot.**
You used `bootout` (stop) rather than `disable` (persist). That's the difference between
the two buttons.

**It came back even though I disabled it.**
An app-registered item — its app re-registers it at launch. Remove it in **System
Settings → General → Login Items & Extensions**, or uninstall the app.

---

## See also

- **[TWEAKS.md](TWEAKS.md)** — the reversible tweak catalog, including Apple daemons.
- **[TOOLS.md](TOOLS.md)** — command-line equivalents for the other panes (Disk Cleanup,
  Process Priority, Thermal, Benchmark).
- **[ARCHITECTURE.md](ARCHITECTURE.md#servicesmanager--detecting-every-background-service)**
  — how the app enumerates services, and how to prove it missed nothing on *your* Mac.
- **[FAQ.md](FAQ.md)** — high CPU, `coreaudiod`, benchmark history.
