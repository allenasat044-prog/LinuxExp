```bash
chmod +x failed_login_audit.sh

sudo ./failed_login_audit.sh          # auto-detects auth.log or journalctl, needs sudo to read

sudo ./failed_login_audit.sh -t 20                          # show top 20 instead of top 10
sudo ./failed_login_audit.sh -s "7 days ago"                 # wider journalctl window (systemd-only systems)
sudo ./failed_login_audit.sh -f /var/log/auth.log.1 -o report.txt   # scan a rotated/archived log file, save report
````
