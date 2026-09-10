 Make it executable (only needed once):

```bash
chmod +x setup_department_access.sh
```
4. Run it with sudo, replacing finance, /Shared/Finance, and alice bob with your actual group name, folder path, and usernames:

```bash
sudo ./setup_department_access.sh finance /Shared/Finance alice bob
```
It'll prompt for your Mac login password (the one you use to unlock your computer) since sudo needs admin rights to create groups and change permissions.

5. Double check it worked:

```bash
ls -lde /Shared/Finance
```