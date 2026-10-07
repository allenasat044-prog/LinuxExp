# Linux Shell Scripting: 50 Real-World Tasks

Save each script as the file named in its heading (e.g. `01.sh`). Run with the commands under **Run**.

---

## 1. Employee Account Setup
**Question:** Create Linux user accounts from an employee list and assign each to the appropriate department group.

**Script (01.sh):**
```bash
#!/bin/bash
# employees.txt lines -> username:department
while IFS=: read u d; do
  groupadd -f "$d"; useradd -m -G "$d" "$u" && echo "$u -> $d"
done < "$1"
```
**Run:**
```bash
printf "alice:hr\nbob:it\ncarol:finance\n" > employees.txt
sudo bash 01.sh employees.txt
```

---

## 2. Inactive Employee Detection
**Question:** Display user accounts that have not logged in recently.

**Script (02.sh):**
```bash
#!/bin/bash
lastlog -b ${1:-30} | tail -n +2
```
**Run:**
```bash
bash 02.sh 30
```

---

## 3. Department Access
**Question:** Create a department group and a shared directory accessible only to that group.

**Script (03.sh):**
```bash
#!/bin/bash
g=${1:-hr}; d=/srv/$g
groupadd -f $g; mkdir -p $d; chgrp $g $d; chmod 2770 $d; ls -ld $d
```
**Run:**
```bash
sudo bash 03.sh hr
```

---

## 4. Permission Audit
**Question:** Identify all world-writable files in a specified directory and generate an audit report.

**Script (04.sh):**
```bash
#!/bin/bash
find "${1:-.}" -type f -perm -0002 | tee world_writable_report.txt
```
**Run:**
```bash
bash 04.sh /home
```

---

## 5. Ownership Audit
**Question:** Find files in a project directory that are not owned by the designated project administrator.

**Script (05.sh):**
```bash
#!/bin/bash
find "$1" ! -user "$2" -ls
```
**Run:**
```bash
bash 05.sh /srv/project admin
```

---

## 6. Server Health Check
**Question:** Quick report showing CPU, memory, disk usage, uptime, and logged-in users.

**Script (06.sh):**
```bash
#!/bin/bash
echo "== CPU =="; top -bn1 | grep "Cpu"
echo "== MEM =="; free -h | sed -n 2p
echo "== DISK =="; df -h /
echo "== UPTIME =="; uptime -p
echo "== USERS =="; who
```
**Run:**
```bash
bash 06.sh
```

---

## 7. Low Disk Space Alert
**Question:** Display file systems that crossed 80% utilization with a warning.

**Script (07.sh):**
```bash
#!/bin/bash
df -hP | awk 'NR>1 && $5+0>80 {print "WARNING: "$6" is "$5" full"}'
```
**Run:**
```bash
bash 07.sh
```

---

## 8. Large File Detection
**Question:** Identify files larger than a specified size and display their locations and sizes.

**Script (08.sh):**
```bash
#!/bin/bash
find "${1:-/}" -type f -size +${2:-100M} -exec ls -lh {} + 2>/dev/null | awk '{print $5, $9}'
```
**Run:**
```bash
sudo bash 08.sh /var 100M
```

---

## 9. Temporary File Cleanup
**Question:** Identify and remove temporary files older than a specified number of days from a directory.

**Script (09.sh):**
```bash
#!/bin/bash
find "$1" -type f -mtime +${2:-7} -print -delete
```
**Run:**
```bash
bash 09.sh /tmp 7
```

---

## 10. Daily Backup
**Question:** Create a compressed, timestamped backup of a project directory.

**Script (10.sh):**
```bash
#!/bin/bash
mkdir -p ~/backups
tar -czf ~/backups/backup_$(date +%F_%H%M%S).tar.gz "$1" && echo "Backup done"
```
**Run:**
```bash
bash 10.sh ~/project
```

---

## 11. Backup Verification
**Question:** Verify the latest backup was created successfully; report its status and size.

**Script (11.sh):**
```bash
#!/bin/bash
f=$(ls -t ~/backups/*.tar.gz 2>/dev/null | head -1)
[ -s "$f" ] && tar -tzf "$f" >/dev/null && echo "OK: $f ($(du -h "$f" | cut -f1))" || echo "FAILED or MISSING"
```
**Run:**
```bash
bash 11.sh
```

---

## 12. Old Backup Cleanup
**Question:** Retain recent backups and delete backups older than a specified number of days.

**Script (12.sh):**
```bash
#!/bin/bash
find ~/backups -name "*.tar.gz" -mtime +${1:-7} -print -delete
```
**Run:**
```bash
bash 12.sh 7
```

---

## 13. Failed Login Audit
**Question:** Count failed SSH login attempts from system logs and generate a report.

**Script (13.sh):**
```bash
#!/bin/bash
(grep "Failed password" /var/log/auth.log 2>/dev/null || journalctl -u ssh --no-pager | grep "Failed password") | wc -l | xargs echo "Failed SSH logins:"
```
**Run:**
```bash
sudo bash 13.sh
```

---

## 14. Suspicious IP Detection
**Question:** Identify IP addresses responsible for repeated failed SSH login attempts.

**Script (14.sh):**
```bash
#!/bin/bash
(grep "Failed password" /var/log/auth.log 2>/dev/null || journalctl -u ssh --no-pager | grep "Failed password") \
| grep -oE 'from [0-9.]+' | awk '{print $2}' | sort | uniq -c | sort -rn | awk -v t=${1:-3} '$1>=t'
```
**Run:**
```bash
sudo bash 14.sh 3
```

---

## 15. Error Log Report
**Question:** Extract and summarize error messages from a Linux log file.

**Script (15.sh):**
```bash
#!/bin/bash
f=${1:-/var/log/syslog}
echo "Total errors: $(grep -ci error $f)"
echo "Last 10:"; grep -i error $f | tail -10
```
**Run:**
```bash
sudo bash 15.sh /var/log/syslog
```

---

## 16. Service Availability Check
**Question:** Check whether a critical web service is active and display a status message.

**Script (16.sh):**
```bash
#!/bin/bash
systemctl is-active --quiet ${1:-nginx} && echo "$1 is RUNNING" || echo "$1 is NOT running"
```
**Run:**
```bash
bash 16.sh nginx
```

---

## 17. Automatic Service Recovery
**Question:** Check a specified service and restart it automatically if it is not running.

**Script (17.sh):**
```bash
#!/bin/bash
systemctl is-active --quiet "$1" || { echo "Restarting $1"; systemctl restart "$1"; }
```
**Run:**
```bash
sudo bash 17.sh nginx
```

---

## 18. Server Process Check
**Question:** Verify whether a particular application process is running and report its status.

**Script (18.sh):**
```bash
#!/bin/bash
pgrep -x "$1" >/dev/null && echo "$1 is running" || echo "$1 is not running"
```
**Run:**
```bash
bash 18.sh sshd
```

---

## 19. High CPU Process Detection
**Question:** Identify the top five processes consuming CPU.

**Script (19.sh):**
```bash
#!/bin/bash
ps -eo pid,comm,%cpu --sort=-%cpu | head -6
```
**Run:**
```bash
bash 19.sh
```

---

## 20. High Memory Process Detection
**Question:** Identify the top five processes consuming memory.

**Script (20.sh):**
```bash
#!/bin/bash
ps -eo pid,comm,%mem --sort=-%mem | head -6
```
**Run:**
```bash
bash 20.sh
```

---

## 21. Network Connectivity Check
**Question:** Use ping to verify connectivity to a gateway/server and report whether it is reachable.

**Script (21.sh):**
```bash
#!/bin/bash
ping -c 2 -W 2 ${1:-8.8.8.8} >/dev/null && echo "$1 is REACHABLE" || echo "$1 is UNREACHABLE"
```
**Run:**
```bash
bash 21.sh 8.8.8.8
```

---

## 22. Multiple Server Check
**Question:** Check connectivity to every server in a list and report UP/DOWN.

**Script (22.sh):**
```bash
#!/bin/bash
while read h; do ping -c1 -W2 $h >/dev/null 2>&1 && echo "$h UP" || echo "$h DOWN"; done < "$1"
```
**Run:**
```bash
printf "8.8.8.8\n1.1.1.1\n10.255.255.1\n" > servers.txt
bash 22.sh servers.txt
```

---

## 23. IP Configuration Report
**Question:** Display hostname, IP address, active interfaces, and default gateway.

**Script (23.sh):**
```bash
#!/bin/bash
echo "Host: $(hostname)"; echo "IP: $(hostname -I)"
echo "Interfaces:"; ip -br a | grep UP
echo "Gateway: $(ip route | awk '/default/{print $3}')"
```
**Run:**
```bash
bash 23.sh
```

---

## 24. SSH Service Check
**Question:** Verify whether SSH is running and display the current service status.

**Script (24.sh):**
```bash
#!/bin/bash
systemctl is-active ssh; systemctl status ssh --no-pager | head -5
```
**Run:**
```bash
bash 24.sh
```

---

## 25. Port Availability Check
**Question:** Verify whether a specified server port is accessible.

**Script (25.sh):**
```bash
#!/bin/bash
timeout 2 bash -c "</dev/tcp/$1/$2" 2>/dev/null && echo "$1:$2 OPEN" || echo "$1:$2 CLOSED"
```
**Run:**
```bash
bash 25.sh localhost 22
```

---

## 26. Package Update Check
**Question:** Check whether system packages require updates and display the update status.

**Script (26.sh):**
```bash
#!/bin/bash
apt-get update -qq
echo "$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l) package(s) can be updated"
```
**Run:**
```bash
sudo bash 26.sh
```

---

## 27. Application Installation
**Question:** Menu-driven script to select and install one of several approved packages.

**Script (27.sh):**
```bash
#!/bin/bash
select p in nginx git curl htop quit; do
  [ "$p" = quit ] && break
  apt-get install -y "$p"
done
```
**Run:**
```bash
sudo bash 27.sh
```

---

## 28. Package Verification
**Question:** Check whether a list of required applications is installed and report missing packages.

**Script (28.sh):**
```bash
#!/bin/bash
for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 && echo "OK: $p" || echo "MISSING: $p"; done
```
**Run:**
```bash
bash 28.sh nginx git curl htop
```

---

## 29. System Inventory
**Question:** Generate a report containing hostname, OS, kernel, CPU, RAM, disk, and network information.

**Script (29.sh):**
```bash
#!/bin/bash
echo "Host: $(hostname)"; . /etc/os-release; echo "OS: $PRETTY_NAME"
echo "Kernel: $(uname -r)"; lscpu | grep "Model name"
free -h | sed -n 2p; df -h /; ip -br a
```
**Run:**
```bash
bash 29.sh
```

---

## 30. Logged-in User Report
**Question:** Display currently logged-in users with login time, terminal, and source information.

**Script (30.sh):**
```bash
#!/bin/bash
who -H
```
**Run:**
```bash
bash 30.sh
```

---

## 31. User Login Audit
**Question:** Generate a report of recent user login activities.

**Script (31.sh):**
```bash
#!/bin/bash
last -n ${1:-10}
```
**Run:**
```bash
bash 31.sh 10
```

---

## 32. File Modification Monitor
**Question:** Identify files in a project directory modified within the last 24 hours.

**Script (32.sh):**
```bash
#!/bin/bash
find "$1" -type f -mtime -1 -ls
```
**Run:**
```bash
bash 32.sh ~/project
```

---

## 33. Duplicate File Detection
**Question:** Identify duplicate files in a directory using checksums.

**Script (33.sh):**
```bash
#!/bin/bash
find "$1" -type f -exec md5sum {} + | sort | uniq -w32 -dD
```
**Run:**
```bash
bash 33.sh ~/project
```

---

## 34. File Integrity Check
**Question:** Verify with checksums whether important files have been modified.

**Script (34.sh):**
```bash
#!/bin/bash
if [ "$1" = init ]; then sha256sum "${@:2}" > base.sha256; echo "Baseline saved"
else sha256sum -c base.sha256; fi
```
**Run:**
```bash
bash 34.sh init file1.txt file2.txt
bash 34.sh check
```

---

## 35. Log Archival
**Question:** Compress selected old log files with a timestamp.

**Script (35.sh):**
```bash
#!/bin/bash
mkdir -p ~/logarchive
for f in "$@"; do gzip -c "$f" > ~/logarchive/$(basename "$f")_$(date +%F_%H%M%S).gz && echo "Archived $f"; done
```
**Run:**
```bash
sudo bash 35.sh /var/log/syslog /var/log/dpkg.log
```

---

## 36. Cron Maintenance
**Question:** Create a routine server maintenance script and schedule it using Cron.

**Script (36.sh):**
```bash
#!/bin/bash
apt-get -y autoremove; apt-get clean
find /tmp -type f -mtime +7 -delete
echo "Maintenance done $(date)" >> /var/log/maint.log
```
**Run:**
```bash
(sudo crontab -l 2>/dev/null; echo "0 2 * * * /bin/bash $PWD/36.sh") | sudo crontab -
sudo crontab -l
```

---

## 37. Scheduled Backup
**Question:** Create a Cron-based automated backup for a project directory.

**Script (37.sh):**
```bash
#!/bin/bash
mkdir -p ~/backups
tar -czf ~/backups/proj_$(date +%F).tar.gz "$1"
```
**Run:**
```bash
(crontab -l 2>/dev/null; echo "0 1 * * * /bin/bash $PWD/37.sh $HOME/project") | crontab -
crontab -l
```

---

## 38. Scheduled Health Report
**Question:** Configure a Cron job to periodically generate a system health report.

**Script (38.sh):**
```bash
#!/bin/bash
bash "$(dirname "$0")/06.sh" > ~/health_$(date +%F_%H%M).txt
```
**Run:**
```bash
(crontab -l 2>/dev/null; echo "0 * * * * /bin/bash $PWD/38.sh") | crontab -
crontab -l
```

---

## 39. Disk and Inode Check
**Question:** Check disk space and inode utilization; report file systems exceeding a threshold.

**Script (39.sh):**
```bash
#!/bin/bash
t=${1:-80}
df -P  | awk -v t=$t 'NR>1 && $5+0>t {print "DISK  >"t"%: "$6" "$5}'
df -iP | awk -v t=$t 'NR>1 && $5+0>t {print "INODE >"t"%: "$6" "$5}'
```
**Run:**
```bash
bash 39.sh 80
```

---

## 40. Mounted File System Report
**Question:** Display all mounted file systems with total, used, and available space.

**Script (40.sh):**
```bash
#!/bin/bash
df -h --output=source,size,used,avail,target
```
**Run:**
```bash
bash 40.sh
```

---

## 41. Archive Old Project Files
**Question:** Identify project files older than a specified number of days and move them to an archive directory.

**Script (41.sh):**
```bash
#!/bin/bash
mkdir -p "$3"; find "$1" -type f -mtime +$2 -exec mv -v {} "$3" \;
```
**Run:**
```bash
bash 41.sh ~/project 30 ~/archive
```

---

## 42. Department Folder Creation
**Question:** Automatically create folders for multiple departments and assign group ownership.

**Script (42.sh):**
```bash
#!/bin/bash
for d in "$@"; do groupadd -f $d; mkdir -p /srv/$d; chgrp $d /srv/$d; chmod 770 /srv/$d; echo "Created /srv/$d"; done
```
**Run:**
```bash
sudo bash 42.sh hr it finance
```

---

## 43. Employee Offboarding
**Question:** Disable a user account and preserve the user's home-directory data.

**Script (43.sh):**
```bash
#!/bin/bash
usermod -L -e 1 "$1"
tar -czf /root/${1}_home_$(date +%F).tar.gz /home/$1 && echo "$1 disabled, data saved"
```
**Run:**
```bash
sudo bash 43.sh alice
```

---

## 44. Resource Threshold Monitor
**Question:** Check CPU and memory usage and display warnings when either exceeds a threshold.

**Script (44.sh):**
```bash
#!/bin/bash
t=${1:-80}
c=$(vmstat 1 2 | tail -1 | awk '{print 100-$15}')
m=$(free | awk '/Mem/{print int($3*100/$2)}')
echo "CPU: $c%  MEM: $m%"
[ $c -gt $t ] && echo "WARNING: CPU above $t%"
[ $m -gt $t ] && echo "WARNING: MEMORY above $t%"
```
**Run:**
```bash
bash 44.sh 80
```

---

## 45. Server Uptime Report
**Question:** Report server uptime and whether the system has been running continuously beyond a specified period.

**Script (45.sh):**
```bash
#!/bin/bash
d=$(awk '{print int($1/86400)}' /proc/uptime)
uptime -p
[ $d -gt ${1:-30} ] && echo "Running $d days (> ${1:-30}): consider reboot" || echo "Uptime within limit"
```
**Run:**
```bash
bash 45.sh 30
```

---

## 46. Service Status Dashboard
**Question:** Simple Bash dashboard displaying the status of SSH, web server, and other specified services.

**Script (46.sh):**
```bash
#!/bin/bash
for s in ssh nginx cron "$@"; do printf "%-12s %s\n" "$s" "$(systemctl is-active $s)"; done
```
**Run:**
```bash
bash 46.sh mysql
```

---

## 47. Security Audit Report
**Question:** Report passwordless accounts, world-writable files, failed logins, and active users.

**Script (47.sh):**
```bash
#!/bin/bash
echo "== Passwordless =="; awk -F: '$2==""{print $1}' /etc/shadow
echo "== World-writable =="; find /home /etc -type f -perm -0002 2>/dev/null
echo "== Failed logins =="; lastb 2>/dev/null | head -5
echo "== Active users =="; who
```
**Run:**
```bash
sudo bash 47.sh
```

---

## 48. Administrator Daily Report
**Question:** Generate a daily report containing system uptime, CPU, memory, disk usage, users, and services.

**Script (48.sh):**
```bash
#!/bin/bash
echo "Date: $(date)"; uptime -p
top -bn1 | grep Cpu; free -h | sed -n 2p; df -h /
echo "Users:"; who
echo "Services:"; systemctl list-units --type=service --state=running --no-pager | head -10
```
**Run:**
```bash
bash 48.sh > daily_report_$(date +%F).txt
cat daily_report_$(date +%F).txt
```

---

## 49. Automated File Synchronization
**Question:** Synchronize a source project directory with a backup directory using rsync.

**Script (49.sh):**
```bash
#!/bin/bash
rsync -av --delete "$1"/ "$2"/
```
**Run:**
```bash
sudo apt install -y rsync
bash 49.sh ~/project ~/project_backup
```

---

## 50. Mini Linux Administration Dashboard
**Question:** Bash-based dashboard displaying CPU usage, memory usage, disk usage, logged-in users, running services, and system uptime in a single report.

**Script (50.sh):**
```bash
#!/bin/bash
echo "===== DASHBOARD ====="; echo "Uptime: $(uptime -p)"
echo "CPU: $(vmstat 1 2 | tail -1 | awk '{print 100-$15}')%"
echo "MEM: $(free | awk '/Mem/{print int($3*100/$2)}')%"
echo "DISK: $(df -h / | awk 'NR==2{print $5}')"
echo "Users:"; who
echo "Services:"; systemctl list-units --type=service --state=running --no-pager | head -8
```
**Run:**
```bash
bash 50.sh
```
