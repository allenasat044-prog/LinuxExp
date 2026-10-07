# Linux Administration Practical — macOS README

This practical is originally written for **Ubuntu/Linux**. Some commands can be executed directly in macOS Terminal, while Linux-specific commands need macOS equivalents.

Source: *AUTOMATION SPRINT – UBUNTU PRACTICAL*.

## 1. How to run Bash scripts on macOS

Create a file:

```bash
nano q01.sh
```

Paste the code, save with `Ctrl+O`, press `Enter`, then `Ctrl+X`.

Make it executable:

```bash
chmod +x q01.sh
```

Run it:

```bash
./q01.sh
```

You can also run without `chmod`:

```bash
bash q01.sh
```

> **Important:** Commands involving users, groups, `/srv`, `/etc/shadow`, services, and system administration can change your Mac. Use test directories/files where possible.

---

# Command Compatibility

Legend:

- ✅ = works on macOS
- ⚠️ = works with changes / different output
- ❌ = Linux/Ubuntu command; use the Mac version below

---

## Q1. Employee Account Setup

**Original Ubuntu idea:** `groupadd` + `useradd`

❌ `groupadd` and `useradd` from the Ubuntu script should not be used as the normal macOS method.

macOS uses Directory Services. For a simple practical demonstration, inspect users/groups with:

```bash
dscl . -list /Users
dscl . -list /Groups
```

Creating real macOS accounts is an administrative operation and is different from Ubuntu. For the original practical, use Ubuntu/VM.

---

## Q2. Inactive Employee Detection

Original:

```bash
lastlog -b 30
```

❌ `lastlog` is Linux-specific.

macOS alternative:

```bash
last
```

For a basic login history:

```bash
last | head -20
```

---

## Q3. Department Access

Original:

```bash
sudo groupadd -f development
sudo mkdir -p /srv/development
sudo chown root:development /srv/development
sudo chmod 2770 /srv/development
ls -ld /srv/development
```

⚠️ `mkdir`, `chown`, `chmod`, and `ls` work on macOS, but the Linux group setup does not.

For a safe Mac demonstration:

```bash
mkdir -p "$HOME/development"
chmod 700 "$HOME/development"
ls -ld "$HOME/development"
```

---

## Q4. Permission Audit

Original:

```bash
DIR="/home/ubuntu/project"
find "$DIR" -type f -perm -0002 -ls
```

⚠️ `find` works, but the Ubuntu path does not.

Mac version:

```bash
DIR="$HOME/project"
find "$DIR" -type f -perm -0002 -ls
```

---

## Q5. Ownership Audit

Original:

```bash
DIR="/home/ubuntu/project"
ADMIN="projectadmin"
find "$DIR" -type f ! -user "$ADMIN" -print
```

⚠️ `find` works; use a real macOS username.

```bash
DIR="$HOME/project"
ADMIN="$(whoami)"
find "$DIR" -type f ! -user "$ADMIN" -print
```

---

## Q6. Server Health Check

Original uses:

```bash
top -bn1
free -h
df -h /
uptime -p
who
```

❌ Linux versions of `top`, `free`, and `uptime -p` differ on macOS.

Mac version:

```bash
echo "===== MAC HEALTH CHECK ====="
echo "CPU:"
top -l 1 | head -n 15

echo "Memory:"
vm_stat

echo "Disk:"
df -h /

echo "Uptime:"
uptime

echo "Logged-in users:"
who
```

---

## Q7. Low Disk Space Alert

Original:

```bash
df -hP | awk 'NR>1 {
gsub("%","",$5)
if ($5 >= 80)
print "WARNING: " $6 " is " $5 "% full"
}'
```

✅ `df` and `awk` work on macOS.

Use:

```bash
df -hP | awk 'NR>1 {
gsub("%","",$5)
if ($5 >= 80)
print "WARNING: " $6 " is " $5 "% full"
}'
```

---

## Q8. Large File Detection

Original path is Ubuntu-specific.

Mac version:

```bash
DIR="$HOME"
SIZE="+100M"
find "$DIR" -type f -size "$SIZE" -exec ls -lh {} \;
```

---

## Q9. Temporary File Cleanup

Original:

```bash
DIR="/tmp"
DAYS=7
find "$DIR" -type f -mtime +"$DAYS" -print
find "$DIR" -type f -mtime +"$DAYS" -delete
```

⚠️ The command works, but deleting system temporary files is not recommended for a classroom demo.

Safer Mac demonstration:

```bash
DIR="$HOME/test_tmp"
DAYS=7
mkdir -p "$DIR"

find "$DIR" -type f -mtime +"$DAYS" -print
```

Only add `-delete` after verifying the files.

---

## Q10. Daily Backup

Original:

```bash
mkdir -p "$HOME/backups"
tar -czf "$HOME/backups/project_$(date +%Y%m%d_%H%M%S).tar.gz" "$HOME/project"
ls -lh "$HOME/backups" | tail -n 2
```

⚠️ `tar`, `date`, `mkdir`, `ls`, and `tail` work on macOS.

Recommended Mac version:

```bash
mkdir -p "$HOME/backups"
mkdir -p "$HOME/project"
tar -czf "$HOME/backups/project_$(date +%Y%m%d_%H%M%S).tar.gz" "$HOME/project"
ls -lh "$HOME/backups"
```

---

## Q11. Backup Verification

```bash
LATEST=$(ls -t "$HOME"/backups/*.tar.gz 2>/dev/null | head -n 1)

if [ -n "$LATEST" ] && tar -tzf "$LATEST" >/dev/null 2>&1; then
    echo "Backup Status: SUCCESS"
    echo "Backup File: $LATEST"
    echo "Backup Size: $(du -h "$LATEST" | cut -f1)"
else
    echo "Backup Status: FAILED or NOT FOUND"
fi
```

✅ Works on macOS.

---

## Q12. Old Backup Cleanup

```bash
find "$HOME/backups" -type f -name "*.tar.gz" -mtime +30 -print
```

For safety, inspect first. The original also deletes them:

```bash
find "$HOME/backups" -type f -name "*.tar.gz" -mtime +30 -delete
```

⚠️ `-delete` permanently removes matching files.

---

## Q13. Failed Login Audit

Original:

```bash
journalctl --no-pager | grep -Ei "Failed password|authentication failure" | wc -l
```

❌ `journalctl` does not exist on macOS.

macOS uses unified logging. A basic authentication-related search is:

```bash
log show --last 1d --predicate 'eventMessage CONTAINS[c] "authentication"' --info
```

---

## Q14. Suspicious IP Detection

Original uses `journalctl` and Linux SSH log format.

❌ No direct macOS equivalent.

For SSH-related logs, inspect:

```bash
log show --last 1d --predicate 'process == "sshd"' --info
```

The exact Linux `Failed password from IP` parsing should be demonstrated on Ubuntu.

---

## Q15. Error Log Report

Original:

```bash
journalctl --no-pager -p err..alert -n 20
```

❌ `journalctl` is Linux-specific.

Mac alternative:

```bash
log show --last 1h --predicate 'messageType == "Error"' --info | tail -20
```

---

# Q16. Service Availability Check

Original:

```bash
systemctl is-active --quiet ssh
```

❌ `systemctl` does not exist on macOS.

For SSH:

```bash
sudo systemsetup -getremotelogin
```

For a macOS service/process check, you can also use:

```bash
pgrep -x sshd
```

---

# Q17. Automatic Service Recovery

Original uses:

```bash
systemctl restart ssh
```

❌ No `systemctl` on macOS.

macOS services are normally managed using `launchctl`.

For SSH Remote Login, enable/disable is managed through macOS system settings rather than the Ubuntu `systemctl` command.

Do not blindly run a Linux `systemctl restart` command on macOS.

---

# Q18. Server Process Check

Original:

```bash
PROCESS="sshd"
pgrep -x "$PROCESS"
```

✅ `pgrep` works on macOS.

```bash
PROCESS="sshd"

if pgrep -x "$PROCESS" >/dev/null; then
    echo "$PROCESS is RUNNING"
else
    echo "$PROCESS is NOT RUNNING"
fi
```

---

# Q19. High CPU Process Detection

Original:

```bash
ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6
```

⚠️ macOS `ps` does not support all Linux options.

Mac version:

```bash
ps -Ao pid,comm,%cpu | sort -k3 -nr | head -n 6
```

---

# Q20. High Memory Process Detection

Mac version:

```bash
ps -Ao pid,comm,%mem | sort -k3 -nr | head -n 6
```

---

# Q21. Network Connectivity Check

Original:

```bash
HOST="8.8.8.8"
ping -c 4 -W 2 "$HOST"
```

⚠️ `ping` works, but timeout option behavior differs between Linux and macOS.

Simple Mac version:

```bash
HOST="8.8.8.8"

if ping -c 4 "$HOST" >/dev/null 2>&1; then
    echo "$HOST is REACHABLE"
else
    echo "$HOST is NOT REACHABLE"
fi
```

---

# Q22. Multiple Server Check

Use:

```bash
for HOST in 8.8.8.8 1.1.1.1 google.com; do
    if ping -c 1 "$HOST" >/dev/null 2>&1; then
        echo "$HOST : UP"
    else
        echo "$HOST : DOWN"
    fi
done
```

✅ Works on macOS.

---

# Q23. IP Configuration Report

Original:

```bash
ip -br addr
ip route | grep default
```

❌ Linux `ip` command is not available by default on macOS.

Mac version:

```bash
echo "Hostname: $(hostname)"
echo
echo "IP Addresses:"
ifconfig | grep "inet "
echo
echo "Default Gateway:"
route -n get default | grep gateway
```

---

# Q24. SSH Service Check

Original:

```bash
systemctl is-active --quiet ssh
```

❌ `systemctl` is Linux-specific.

Mac alternative:

```bash
sudo systemsetup -getremotelogin
```

Or process check:

```bash
pgrep -x sshd
```

---

# Q25. Port Availability Check

Original uses:

```bash
timeout 3 bash -c "</dev/tcp/$HOST/$PORT"
```

❌ `timeout` is not normally installed on macOS.

Recommended Mac command:

```bash
nc -zv -G 3 google.com 443
```

If successful, port 443 is reachable/open.

---

# Q26. Package Update Check

Original:

```bash
sudo apt update
apt list --upgradable
```

❌ `apt` is Ubuntu/Debian-specific.

For macOS system updates:

```bash
softwareupdate -l
```

For Homebrew packages:

```bash
brew update
brew outdated
```

---

# Q27. Application Installation

Original uses `apt`.

❌ `apt` does not work on macOS.

If Homebrew is installed:

```bash
brew install curl git vim htop nginx
```

Install one package at a time, for example:

```bash
brew install htop
```

---

# Q28. Package Verification

Original:

```bash
dpkg -s "$p"
```

❌ `dpkg` is Debian/Ubuntu-specific.

Homebrew version:

```bash
for p in curl git vim htop nginx; do
    brew list --formula "$p" >/dev/null 2>&1 && echo "$p: INSTALLED" || echo "$p: MISSING"
done
```

---

# Q29. System Inventory

Original contains Linux-only commands such as `lscpu`, `free`, and `ip`.

Mac version:

```bash
echo "Hostname:"
hostname

echo "macOS:"
sw_vers

echo "Kernel:"
uname -r

echo "CPU:"
sysctl -n machdep.cpu.brand_string
sysctl -n hw.ncpu

echo "Memory:"
sysctl -n hw.memsize

echo "Disk:"
df -h

echo "Network:"
ifconfig
```

---

# Q30. Logged-in User Report

```bash
who
w
```

✅ Works on macOS.

---

# Q31. User Login Audit

```bash
last -n 20
```

✅ Works on macOS.

---

# Q32. File Modification Monitor

```bash
find "$HOME" -type f -mtime -1 -ls
```

✅ Works on macOS.

---

# Q33. Duplicate File Detection

Original:

```bash
find "$HOME" -type f -exec sha256sum {} + | sort | awk '{print $1}' | uniq -d
```

❌ `sha256sum` is Linux-specific.

Mac version uses `shasum`:

```bash
find "$HOME" -type f -exec shasum -a 256 {} + | sort | awk '{print $1}' | uniq -d
```

---

# Q34. File Integrity Check

Original:

```bash
sha256sum important.txt > checksums.sha256
sha256sum -c checksums.sha256
```

Mac version:

```bash
shasum -a 256 important.txt > checksums.sha256
shasum -a 256 -c checksums.sha256
```

---

# Q35. Log Archival

Original uses `/var/log` and Linux-specific assumptions.

Basic Mac-compatible archive command:

```bash
mkdir -p "$HOME/log_archive"
tar -czvf "$HOME/log_archive/logs_$(date +%Y%m%d_%H%M%S).tar.gz" /var/log/*.log
```

⚠️ macOS log storage differs from Ubuntu. For the exact Linux practical, use Ubuntu.

---

# Q36. Cron Maintenance

Original:

```bash
sudo apt update
sudo apt -y autoremove
sudo apt clean
crontab -e
```

`apt` commands are ❌ on macOS.

`crontab -e` is available:

```bash
crontab -e
```

For package maintenance:

```bash
brew update
brew upgrade
brew cleanup
```

---

# Q37. Scheduled Backup

```bash
mkdir -p "$HOME/backups"
tar -czf "$HOME/backups/project_$(date +%Y%m%d_%H%M%S).tar.gz" "$HOME/project"
ls -lh "$HOME/backups"
```

✅ Works on macOS.

---

# Q38. Scheduled Health Report

Original contains Linux-only `free`, `/proc/loadavg`, and `systemctl`.

Mac version:

```bash
mkdir -p "$HOME/health_reports"

{
    date
    echo
    uptime
    echo
    vm_stat
    echo
    df -h
} > "$HOME/health_reports/health_$(date +%Y%m%d_%H%M%S).txt"

ls "$HOME/health_reports"
```

---

# Q39. Disk and Inode Check

Original:

```bash
df -h
df -i
```

⚠️ `df -h` works. macOS does not provide Linux's `/proc`-style environment.

Use:

```bash
df -h
df -i
```

For an 80% warning:

```bash
df -P | awk 'NR>1 && $5+0 >= 80 {print "WARNING:", $0}'
```

---

# Q40. Mounted File System Report

Original:

```bash
df -hT
findmnt
```

`df -hT` and `findmnt` are Linux-oriented.

Mac alternatives:

```bash
df -h
mount
```

---

# Q41. Archive Old Project Files

```bash
SRC="$HOME/project"
ARCH="$HOME/archive"
DAYS=30

mkdir -p "$ARCH"

find "$SRC" -type f -mtime +"$DAYS" -print
```

The original moves the files:

```bash
find "$SRC" -type f -mtime +"$DAYS" -exec mv {} "$ARCH"/ \;
```

⚠️ Test this carefully before executing because it changes file locations.

---

# Q42. Department Folder Creation

Original uses Linux groups and `/srv`.

❌ Exact command is not suitable for normal macOS.

Safe Mac demonstration:

```bash
mkdir -p "$HOME/departments"/{hr,finance,it}
chmod 700 "$HOME/departments"/{hr,finance,it}
ls -ld "$HOME/departments"/*
```

---

# Q43. Employee Offboarding

Original uses Linux `usermod`, `/usr/sbin/nologin`, and `/home`.

❌ Do not execute the Ubuntu command on macOS.

For a safe archive demonstration:

```bash
USER_TO_DISABLE="employee1"
mkdir -p "$HOME/offboarding"

tar -czf "$HOME/offboarding/${USER_TO_DISABLE}_home_$(date +%Y%m%d_%H%M%S).tar.gz" "$HOME/$USER_TO_DISABLE"
```

Use a test directory instead of an actual user account.

---

# Q44. Resource Threshold Monitor

Original relies on Linux `top` and `free`.

Mac version:

```bash
CPU=$(top -l 1 | awk '/CPU usage/ {print 100-$7}')
echo "CPU Usage: ${CPU}%"

MEM=$(vm_stat | awk '/Pages active/ {a=$3} /Pages inactive/ {i=$3} END {gsub("\\.","",a); gsub("\\.","",i); print a+i}')
echo "Memory activity pages: $MEM"
```

The exact Linux percentage calculation should be demonstrated on Ubuntu.

---

# Q45. Server Uptime Report

Original reads `/proc/uptime`.

❌ `/proc/uptime` does not exist on macOS.

Use:

```bash
echo "Uptime: $(uptime)"
```

For a simple 7-day check:

```bash
UPTIME_SECONDS=$(sysctl -n kern.boottime | awk -F'[ ,}]+' '{print systime()-$4}')
echo "Uptime in seconds: $UPTIME_SECONDS"

if [ "$UPTIME_SECONDS" -ge 604800 ]; then
    echo "System has been running continuously for 7 days or more."
else
    echo "System has NOT been running continuously for 7 days."
fi
```

---

# Q46. Service Status Dashboard

Original:

```bash
systemctl is-active ...
```

❌ No `systemctl` on macOS.

For a process-oriented dashboard:

```bash
for PROCESS in sshd launchd; do
    if pgrep -x "$PROCESS" >/dev/null; then
        echo "$PROCESS : RUNNING"
    else
        echo "$PROCESS : STOPPED"
    fi
done
```

---

# Q47. Security Audit Report

Original uses `/etc/shadow` and `journalctl`.

❌ Exact Ubuntu command is not suitable for macOS.

For world-writable files:

```bash
echo "=== World-writable files in /tmp ==="
find /tmp -type f -perm -0002 -ls 2>/dev/null

echo
echo "=== Active users ==="
who
```

For authentication logs, use macOS `log`:

```bash
log show --last 1d --predicate 'eventMessage CONTAINS[c] "authentication"' --info
```

---

# Q48. Administrator Daily Report

Linux version uses `free`, `systemctl`, and Linux `top`.

Mac version:

```bash
echo "===== DAILY ADMIN REPORT ====="
echo "Date: $(date)"
echo

echo "Uptime:"
uptime
echo

echo "CPU:"
top -l 1 | head -n 15
echo

echo "Memory:"
vm_stat
echo

echo "Disk:"
df -h /
echo

echo "Users:"
who
echo

echo "Processes:"
ps -Ao pid,comm,%cpu,%mem | head -n 10
```

---

# Q49. Automated File Synchronization

Original:

```bash
mkdir -p "$HOME/project" "$HOME/project_backup"
rsync -av --delete "$HOME/project/" "$HOME/project_backup/"
echo "Synchronization completed."
```

⚠️ `rsync` is available on many macOS installations, but the bundled version may be older.

Command:

```bash
mkdir -p "$HOME/project" "$HOME/project_backup"
rsync -av --delete "$HOME/project/" "$HOME/project_backup/"
echo "Synchronization completed."
```

**Warning:** `--delete` removes files from the backup if they no longer exist in the source.

---

# Q50. Mini Linux Administration Dashboard

Original depends heavily on Linux commands:

```bash
top -bn1
free -h
systemctl
```

Mac version:

```bash
echo "===== MAC ADMIN DASHBOARD ====="

echo "Hostname:"
hostname

echo
echo "Uptime:"
uptime

echo
echo "CPU:"
sysctl -n machdep.cpu.brand_string
top -l 1 | head -n 10

echo
echo "Memory:"
vm_stat

echo
echo "Disk:"
df -h /

echo
echo "Logged-in users:"
who

echo
echo "Running processes:"
ps -Ao pid,comm,%cpu,%mem | head -n 6
```

---

# Quick Reference — Linux vs macOS

| Ubuntu/Linux command | macOS equivalent |
|---|---|
| `apt` | `brew` / `softwareupdate` |
| `dpkg` | `brew list` |
| `systemctl` | `launchctl` / macOS service tools |
| `journalctl` | `log show` |
| `free -h` | `vm_stat` |
| `ip addr` | `ifconfig` |
| `ip route` | `route` |
| `lscpu` | `sysctl` |
| `sha256sum` | `shasum -a 256` |
| `findmnt` | `mount` |
| `lastlog` | `last` |
| `/proc/uptime` | `sysctl` / `uptime` |
| `timeout` | `nc` for port tests |
| `groupadd/useradd` | Directory Services (`dscl`) |
| Linux service control | `launchctl` / System Settings |

---

# What You Can Safely Demonstrate on Mac

The following practicals are generally suitable for macOS after adjusting paths/options:

- Q4 Permission Audit
- Q5 Ownership Audit
- Q7 Disk Space Alert
- Q8 Large File Detection
- Q9 Temporary File Detection
- Q10–12 Backup operations
- Q18 Process Check
- Q19–20 Process monitoring
- Q21–22 Ping/network checks
- Q30–32 User/file monitoring
- Q33–34 SHA-256 integrity checks
- Q36 `crontab`
- Q37 Backup
- Q39 Disk checks
- Q41 File archival
- Q49 `rsync`
- Q50 Mac dashboard

The following are best executed in **Ubuntu/Linux or an Ubuntu VM** because the practical specifically depends on Linux administration features:

- Q1 User account creation
- Q2 `lastlog`
- Q3 Linux groups
- Q13–17 `journalctl` / `systemctl`
- Q23 Linux `ip`
- Q24 Linux SSH service
- Q26–28 `apt` / `dpkg`
- Q29 Linux system inventory
- Q35 Linux log archival
- Q38 Linux health report
- Q42 Linux department groups
- Q43 Linux offboarding
- Q44 Linux resource calculation
- Q45 `/proc/uptime`
- Q46 `systemctl`
- Q47 `/etc/shadow` + `journalctl`
- Q48 Linux daily report

---

# Recommended Execution Environment

If this is for an **Ubuntu Linux practical/viva**, use an Ubuntu VM rather than changing every command for macOS.

On your Mac, you can use:

1. **Ubuntu in UTM**
2. **Ubuntu in VMware Fusion**
3. **Ubuntu in VirtualBox** (if supported/configured for your Mac)
4. Another Linux virtual machine

Then execute the original commands from the practical inside Ubuntu.

For macOS-only practice, use the Mac alternatives in this README.

---

# Basic Script Workflow

Example:

```bash
nano q07.sh
```

Paste:

```bash
#!/bin/bash
df -hP | awk 'NR>1 {
gsub("%","",$5)
if ($5 >= 80)
print "WARNING: " $6 " is " $5 "% full"
}'
```

Save and run:

```bash
chmod +x q07.sh
./q07.sh
```

Or:

```bash
bash q07.sh
```

