# Coolify Backup & Restore

Automated backup and restore scripts for Coolify instances.

## Quick Start

```bash
# One command to backup everything (auto path: backups/SERVER/YYYY-MM-DDTHHMM)
./scripts/backup.sh root@example.com

# Test mode - no confirmation prompts
./scripts/backup.sh root@example.com --test

# Custom folder name
./scripts/backup.sh root@example.com my-custom-folder
```

## Scripts

| Script | Purpose |
|--------|---------|
| [`backup.sh`](scripts/backup.sh) | **Master script** - Backs up config AND database |
| [`backup-coolify.sh`](scripts/backup-coolify.sh) | Backup Coolify config & keys only |
| [`fetch-s3-backup.sh`](scripts/fetch-s3-backup.sh) | Download database from S3 only |
| [`restore-coolify.sh`](scripts/restore-coolify.sh) | Restore Coolify from backup to new server |

## Setup

Copy the example environment file and configure your S3 credentials:

```bash
cp .env.example .env
# Edit .env with your S3 credentials
```

The `.env` file stores:
- S3 endpoint, bucket, and credentials
- `APP_KEY` for Coolify decryption

## Quick Backup

One command backs up **everything** - config, keys, and database:

```bash
./scripts/backup.sh root@example.com
```

This runs both parts:
1. **Config backup** (`backup-coolify.sh`) - SSH keys, APP_KEY, authorized_keys, version
2. **Database backup** (`fetch-s3-backup.sh`) - Latest SQL dump from S3

Backups are organized by server with timestamps:
```
backups/
└── example.com/
    └── 2026-02-18T1207/
        ├── authorized_keys
        ├── .env.backup
        ├── pg-dump-coolify-*.dmp
        ├── sshkeys/
        └── version.txt
```

### Requirements

- SSH access to the Coolify server
- SSH key loaded in your agent
- S3 credentials configured in `.env`
- `rclone` installed (auto-installs if missing)

### Usage

```bash
# Auto path: backups/example.com/YYYY-MM-DDTHHMM
./scripts/backup.sh root@example.com

# Test mode - no confirmation prompts
./scripts/backup.sh root@example.com --test

# Custom folder
./scripts/backup.sh root@example.com my-custom-folder
```

After running, commit the backup:

```bash
git add backups/
git commit -m "Backup Coolify - $(date +%Y-%m-%d)"
```

> **Note:** Don't commit `.env` - it contains your S3 secrets!

---

<details>
<summary><strong>Manual Backup Steps (click to expand)</strong></summary>

If you prefer to backup manually, here's the folder structure and what to collect:

### Folder Structure

Create a backup folder following this pattern:
```bash
mkdir -p backups/example.com/2026-02-18T1207/sshkeys
```

### Required Items

1. **Coolify Version Number**
   - On the server: `docker ps --format '{{.Image}}' | grep coolify`
   - Save to: `backups/example.com/2026-02-18T1207/version.txt`

2. **APP_KEY** environment variable
   - On the server: `cat /data/coolify/source/.env | grep APP_KEY`
   - Save to: `backups/example.com/2026-02-18T1207/.env.backup`

3. **SSH Private Keys**
   - List keys: `ls -l /data/coolify/ssh/keys`
   - Copy each key file to: `backups/example.com/2026-02-18T1207/sshkeys/`
   - Set permissions: `chmod 600 backups/example.com/2026-02-18T1207/sshkeys/*`

4. **SSH Public Keys (authorized_keys)**
   - On the server: `cat ~/.ssh/authorized_keys`
   - Save to: `backups/example.com/2026-02-18T1207/authorized_keys`
   - Set permissions: `chmod 644 backups/example.com/2026-02-18T1207/authorized_keys`

5. **Database Backup**
   - Download from S3 or export manually
   - Save to: `backups/example.com/2026-02-18T1207/pg-dump-coolify-*.dmp`

### Complete Example

```bash
# Create folder structure
SERVER="example.com"
TIMESTAMP=$(date +%Y-%m-%dT%H%M)
mkdir -p backups/${SERVER}/${TIMESTAMP}/sshkeys

# Copy files from server
scp root@${SERVER}:/data/coolify/source/.env backups/${SERVER}/${TIMESTAMP}/.env.backup
scp root@${SERVER}:~/.ssh/authorized_keys backups/${SERVER}/${TIMESTAMP}/
scp root@${SERVER}:/data/coolify/ssh/keys/* backups/${SERVER}/${TIMESTAMP}/sshkeys/

# Set permissions
chmod 600 backups/${SERVER}/${TIMESTAMP}/sshkeys/*
chmod 644 backups/${SERVER}/${TIMESTAMP}/authorized_keys

# Get version
ssh root@${SERVER} "docker ps --format '{{.Image}}' | grep coolify" > backups/${SERVER}/${TIMESTAMP}/version.txt
```

Source: <https://coolify.io/docs/knowledge-base/how-to/backup-restore-coolify#_3-back-up-your-coolify-ssh-private-and-public-key>

</details>

---

## Fetch Database from S3

If your Coolify is configured to backup to S3, fetch the latest database dump:

### Prerequisites

Install `rclone` (if not already installed):
```bash
# Ubuntu/Debian
sudo apt-get install rclone

# macOS
brew install rclone

# Or use the install script
curl https://rclone.org/install.sh | sudo bash
```

### Usage

```bash
# Setup S3 credentials in .env first
cp .env.example .env
# Edit .env with your S3_ACCESS_KEY and S3_SECRET_KEY

# Fetch latest backup to a folder
./scripts/fetch-s3-backup.sh 2026-02-18
```

This downloads the most recent `pg-dump-coolify-*.dmp` file from your S3 bucket to the specified backup folder.

---

## Quick Restore

Use the automated restore script to restore Coolify from a backup:

```bash
./scripts/restore-coolify.sh <target-server> <backup-folder> [database-backup-file]
```

**Example:**
```bash
# Restore everything including database
./scripts/restore-coolify.sh root@1.2.3.4 2026-02-18 /path/to/backup.sql

# Restore without database (config only)
./scripts/restore-coolify.sh root@1.2.3.4 2026-02-18
```

### What the script does:

1. Installs Coolify at the version from your backup
2. Stops Coolify services
3. Restores the database (if backup file provided)
4. Restores SSH private keys
5. Updates authorized_keys
6. Configures APP_PREVIOUS_KEYS for decryption
7. Restarts Coolify

### Complete workflow:

```bash
# 1. Backup everything from old server
./scripts/backup.sh root@example.com

# 2. Restore to new server
./scripts/restore-coolify.sh root@1.2.3.4 \
  backups/example.com/2026-02-18T1207 \
  backups/example.com/2026-02-18T1207/pg-dump-coolify-*.dmp
```

Or run parts separately:

```bash
# Just config (no database)
./scripts/backup-coolify.sh root@example.com

# Just fetch database from S3
./scripts/fetch-s3-backup.sh backups/example.com/2026-02-18T1207
```

---

<details>
<summary><strong>Manual Restore Steps (click to expand)</strong></summary>

If you prefer to restore manually, assuming your backup is at `backups/example.com/2026-02-18T1207/`:

1. Spin up a new VPS
2. Install a fresh copy of Coolify at the correct version:
   ```bash
   curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s 4.0.0-beta.463
   ```
3. Verify the installation
4. **Transfer backup files to new server** (from your local machine):
   ```bash
   # From your local machine
   scp -r backups/example.com/2026-02-18T1207 root@newserver:/tmp/restore/
   ```

5. Stop Coolify:
   ```bash
   docker stop coolify coolify-redis coolify-realtime coolify-proxy
   ```
6. Restore the database:
   ```bash
   cat /tmp/restore/pg-dump-coolify-*.dmp \
     | docker exec -i coolify-db \
       pg_restore --verbose --clean --no-acl --no-owner -U coolify -d coolify
   ```
6. Remove autogenerated keys:
   ```bash
   rm -f /data/coolify/ssh/keys/*
   ```
7. Copy SSH private keys from backup:
   ```bash
   cp /tmp/restore/sshkeys/* /data/coolify/ssh/keys/
   chmod 600 /data/coolify/ssh/keys/*
   ```
8. Update authorized_keys:
   ```bash
   cat /tmp/restore/authorized_keys >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```
9. Configure APP_PREVIOUS_KEYS:
   ```bash
   # Get the old APP_KEY from backup
   APP_KEY=$(cat /tmp/restore/.env.backup | grep APP_KEY | cut -d'=' -f2)
   
   # Add to new server's .env
   echo "APP_PREVIOUS_KEYS=$APP_KEY" >> /data/coolify/source/.env
   ```
10. Restart Coolify:
    ```bash
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s 4.0.0-beta.463
    ```
11. Log in and verify everything is working

</details>
