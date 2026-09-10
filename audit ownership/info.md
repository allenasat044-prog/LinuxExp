
```bash
cd "/Users/shashank/Downloads/linuxCheat/audit ownership"
mkdir sample_ownership_test
cd sample_ownership_test
touch admin_file.txt
sudo touch root_owned_file.txt
cd ..
sudo ./audit_ownership.sh ./sample_ownership_test shashank ~/Desktop
```
