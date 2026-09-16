```bash
chmod +x suspicious_ip_detection.sh

sudo ./suspicious_ip_detection.sh
````

```bash
# other options 
sudo ./suspicious_ip_detection.sh -t 3                                   # more sensitive (flag at 3+ attempts)
sudo ./suspicious_ip_detection.sh -b blocked_ips.txt                     # export a blocklist file
sudo ./suspicious_ip_detection.sh -s "7 days ago" -o weekly_report.txt   # wider window + saved report
````
