# AGENTS.md - Coolify Backup/Restore Utility

## Purpose

This directory facilitates backups and restores of Coolify instances. It stores:
- SSH private keys for managed servers
- `authorized_keys` for server access
- `APP_KEY` (critical for data decryption)
- Version-specific backup snapshots

## Directory Structure

```
coolify/
├── .env                          # Current Coolify environment variables
├── README.md                     # Backup/restore procedures
├── AGENTS.md                     # This file
└── YYYY-MM-DD/                   # Date-stamped backup snapshots
    ├── sshkeys/                  # SSH private keys
    │   ├── ssh_key@<server-id>   # Named by Coolify server ID
    │   └── ...
    └── authorized_keys           # SSH public keys
```

## Naming Conventions

- **Backup directories**: `YYYY-MM-DD/` format (e.g., `2026-02-18/`)
- **SSH private keys**: `ssh_key@<server-id>` where server-id is Coolify's internal ID
- **Environment file**: Always `.env` at repository root (most recent)

## Backup Workflow

### 1. Collect from Running Coolify Server

```bash
# SSH into the Coolify server and collect data

# Get APP_KEY from environment (only critical variable needed)
cat /data/coolify/source/.env | grep APP_KEY

# List and copy SSH private keys
ls -la /data/coolify/ssh/keys/
# Copy each key file

# Get authorized keys
cat ~/.ssh/authorized_keys

# Note the Coolify version
docker ps --format "table {{.Image}}" | grep coolify
```

### 2. Store in This Repository

```bash
# Create dated directory
mkdir -p $(date +%Y-%m-%d)/sshkeys

# Save environment file
cp .env $(date +%Y-%m-%d)/.env.backup

# Copy SSH keys to sshkeys/ directory
# Copy authorized_keys to dated directory
```

### 3. Commit with Clear Message

```bash
git add YYYY-MM-DD/
git commit -m "Backup Coolify v4.0.0-beta.463 - $(date +%Y-%m-%d)"
```

## Restore Workflow

### 1. Prepare New Server

```bash
# Install specific Coolify version
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s <VERSION>

# Stop Coolify services
docker stop coolify coolify-redis coolify-realtime coolify-proxy
```

### 2. Restore Database

```bash
# From Coolify backup file (uses built-in 'coolify' user, no password needed)
cat /path/to/backup.sql | docker exec -i coolify-db \
  pg_restore --verbose --clean --no-acl --no-owner -U coolify -d coolify
```

### 3. Restore Keys and Config

```bash
# Remove auto-generated keys
rm -f /data/coolify/ssh/keys/*

# Copy backed-up private keys
cp sshkeys/ssh_key@* /data/coolify/ssh/keys/

# Update authorized_keys
cat authorized_keys >> ~/.ssh/authorized_keys

# Edit environment file to add APP_PREVIOUS_KEYS
# This allows the new instance to decrypt data encrypted with the old APP_KEY
# Example: APP_PREVIOUS_KEYS=base64:your-old-app-key-here
```

### 4. Restart Coolify

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s <VERSION>
```

## Critical Environment Variables

| Variable | Purpose | Restore Needed? |
|----------|---------|-----------------|
| `APP_KEY` | Laravel encryption key - **CRITICAL** | YES |
| `APP_PREVIOUS_KEYS` | Previous keys for data migration | Set during restore |

**Note:** DB_PASSWORD, REDIS_PASSWORD, and PUSHER_APP_SECRET are auto-generated on fresh install and do NOT need to be backed up. Only `APP_KEY` is required to decrypt existing data.

## Security Guidelines

- **Never commit secrets** - `.env` and backup directories are gitignored
- **Keep this repo private if it contains real backups** - SSH keys are sensitive
- **Use strong file permissions**: `chmod 600 sshkeys/*` and `chmod 644 authorized_keys`
- **Rotate keys periodically** - Update APP_PREVIOUS_KEYS when rotating APP_KEY
- **Verify server IDs** - Ensure SSH keys match correct Coolify server records
- **Secure transfer** - Use `scp` or other encrypted methods to move keys between servers

## Quick Commands

```bash
# Check current Coolify version on server
docker ps --format "table {{.Names}}\t{{.Image}}" | grep coolify

# List all backup dates
ls -d */ | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}/$'

# Compare two backups
diff -r 2026-02-01/ 2026-02-18/

# Archive old backups (keep last 3)
ls -d */ | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}/$' | sort | head -n -3 | xargs rm -rf
```

## Coolify Version Reference

- Current: `4.0.0-beta.463`
- Install script: `https://cdn.coollabs.io/coolify/install.sh`
- Docs: https://coolify.io/docs/knowledge-base/how-to/backup-restore-coolify

## Troubleshooting

| Issue | Solution |
|-------|----------|
| SSH key permissions | `chmod 600 sshkeys/*` |
| Can't connect to managed servers | Verify correct SSH keys in `/data/coolify/ssh/keys/` |
| Database restore fails | Ensure Coolify services are stopped first |
| APP_KEY mismatch | Add old key to APP_PREVIOUS_KEYS |
