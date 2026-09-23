# Storage Monitor

A lightweight, dependency-free Bash toolkit for Linux (and macOS) that monitors
disk space, inode usage, storage growth, and verifies data migrations — no
server, database, or login required. Everything runs from the terminal or
via cron/systemd, and results can be viewed as a local HTML report.

## Why a CLI toolkit instead of a web app

Sysadmins need monitoring that works unattended, over SSH, on headless
servers, and without standing up extra infrastructure (auth, hosting, a
database) just to check `df -h`. This toolkit is a single `git clone` +
`install.sh` away from running, and it produces reports as plain files you
can view locally, email, or archive — no service to keep online.

## Features

- **Disk usage monitoring** — checks every mounted filesystem against
  configurable WARN/CRIT thresholds.
- **Inode usage monitoring** — catches "disk shows free space but you're
  out of inodes" failures (Linux).
- **Storage growth tracking** — periodic snapshots of chosen directories,
  with alerts when growth between snapshots exceeds a configurable limit.
- **Migration verification** — captures a `before` snapshot (file count,
  total size, aggregate checksum) of a source directory and an `after`
  snapshot of the destination, then produces a PASS/FAIL report.
- **Alerting** — syslog (default, zero-config), email (via `mail`), and
  webhook (Slack-compatible JSON payload), each independently toggleable.
- **HTML reporting** — a single self-contained report file, no server.
- **Cross-platform scripts** — Linux and macOS supported natively via
  POSIX `df`/`du`; see the Windows note below.

## Requirements

- Bash 4+
- Coreutils: `df`, `du`, `find`, `md5sum`/`sha256sum`, `numfmt`
  (all standard on Linux; macOS users may need `brew install coreutils`
  for `numfmt` — the scripts fall back gracefully if it's missing)
- Optional: `mail` (email alerts), `curl` (webhook alerts), `logger` (syslog)

## Installation

```bash
git clone <this-repo> storage-monitor
cd storage-monitor
sudo ./install.sh
```

This installs to `/opt/storage-monitor` and symlinks the following commands
onto your `PATH` (`/usr/local/bin`):

```
storage-monitor      # disk + inode check
growth-tracker        # storage growth snapshots / trend
generate-report       # HTML report
migration-verify       # migration before/after verification
```

Prefer not to install system-wide? Just run the scripts directly from
`bin/` — no installation step is required.

## Configuration

Edit `conf/storage-monitor.conf`:

```bash
DISK_WARN_THRESHOLD=75
DISK_CRIT_THRESHOLD=90
INODE_WARN_THRESHOLD=75
INODE_CRIT_THRESHOLD=90
GROWTH_ALERT_MB=500
MONITORED_DIRS=("/var/log" "/home" "/tmp")

ALERT_EMAIL_ENABLED=false
ALERT_WEBHOOK_ENABLED=false
ALERT_SYSLOG_ENABLED=true
```

## Usage

**Check disk + inode usage now:**
```bash
storage-monitor
storage-monitor --json     # machine-readable output for other tooling
storage-monitor --quiet    # suppress table, only alert on issues
```
Exit codes: `0` = all OK, `1` = a WARN threshold was hit, `2` = a CRIT
threshold was hit — convenient for chaining in cron or CI.

**Take a growth snapshot / view a trend:**
```bash
growth-tracker snapshot
growth-tracker trend /var/log
```

**Generate an HTML report:**
```bash
generate-report
# -> reports/storage-report_<timestamp>.html
```

**Verify a migration:**
```bash
# Before moving/copying data:
migration-verify before /data/old-location my_migration

# ... perform the migration ...

# After:
migration-verify after /data/new-location my_migration
# -> reports/migration-report_my_migration_<timestamp>.txt
# exit code 0 = PASS, 2 = FAIL (and a CRIT alert is fired)
```

The migration check compares file count, total size, and an aggregate
checksum (sorted `md5sum` of every file, hashed with `sha256sum`), so it
catches missing files, extra files, and silently corrupted content —
not just a size match.

## Scheduling

**cron** (add via `crontab -e`):
```cron
*/15 * * * * /opt/storage-monitor/bin/storage-monitor.sh --quiet
0 0  * * *   /opt/storage-monitor/bin/growth-tracker.sh snapshot
```

**systemd** (preferred on modern distros): unit/timer files are provided
in `systemd/`.
```bash
sudo cp systemd/*.service systemd/*.timer /etc/systemd/system/
sudo systemctl enable --now storage-monitor.timer growth-tracker.timer
```

## Windows

Storage/inode semantics differ enough on Windows (NTFS has no inode
concept; `df`/`du` don't exist natively) that this toolkit targets
Linux/macOS. On Windows, run it inside **WSL2** (a real Linux userspace),
where it works unmodified.

## Project layout

```
storage-monitor/
├── bin/
│   ├── storage-monitor.sh     # disk + inode checks, alerting
│   ├── growth-tracker.sh      # growth snapshots + trend
│   ├── generate-report.sh     # HTML report
│   └── migration-verify.sh    # migration before/after verification
├── lib/
│   └── common.sh              # shared logging/alerting/helpers
├── conf/
│   └── storage-monitor.conf   # thresholds + alert config
├── systemd/                   # unit + timer files
├── install.sh
└── README.md
```

## Design notes / assumptions

- Thresholds are percentage-based and apply per-filesystem, not globally,
  so one full mount doesn't mask headroom on another.
- Alerts are rate-limited only by how often you schedule the checks (e.g.
  every 15 min) — there's no separate de-duplication layer; this keeps
  the tool simple and stateless, and is a natural place to extend.
- Growth tracking uses `du -sk`, which walks the directory tree; for very
  large trees, consider a longer snapshot interval.
- The migration checksum approach is O(n) in file count/size — for huge
  datasets, a smarter approach (e.g. sampling or `rsync --checksum`
  dry-run diffing) would be a next step.
