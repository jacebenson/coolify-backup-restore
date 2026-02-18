#!/bin/bash
# restore-coolify.sh - Restore Coolify instance from backup
# Usage: ./scripts/restore-coolify.sh <target-server> <backup-folder> [database-backup-file]
# Example: ./scripts/restore-coolify.sh root@1.2.3.4 2026-02-18 /path/to/backup.sql

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <target-server> <backup-folder> [database-backup-file]"
    echo ""
    echo "Examples:"
    echo "  $0 root@1.2.3.4 2026-02-18"
    echo "  $0 root@1.2.3.4 2026-02-18 /path/to/coolify-backup.sql"
    exit 1
fi

SERVER="$1"
BACKUP_DIR="$2"
DB_BACKUP="${3:-}"

# Extract IP from server (remove root@ prefix if present)
SERVER_IP=$(echo "$SERVER" | sed 's/^[^@]*@//')

# Validate backup directory exists locally
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}Error: Backup directory '$BACKUP_DIR' not found${NC}"
    exit 1
fi

# Check required files exist
if [ ! -f "$BACKUP_DIR/.env.backup" ]; then
    echo -e "${RED}Error: $BACKUP_DIR/.env.backup not found${NC}"
    exit 1
fi

if [ ! -d "$BACKUP_DIR/sshkeys" ]; then
    echo -e "${RED}Error: $BACKUP_DIR/sshkeys/ directory not found${NC}"
    exit 1
fi

# Get version from backup
if [ -f "$BACKUP_DIR/version.txt" ]; then
    VERSION=$(cat "$BACKUP_DIR/version.txt")
    # Extract just the version number if it's a full image path
    VERSION=$(echo "$VERSION" | sed 's/.*://')
else
    VERSION="4.0.0-beta.463"
    echo -e "${YELLOW}Warning: version.txt not found, using default: $VERSION${NC}"
fi

# Get APP_KEY from backup
APP_KEY=$(grep '^APP_KEY=' "$BACKUP_DIR/.env.backup" | cut -d'=' -f2)

echo "======================================"
echo "Coolify Restore Script"
echo "======================================"
echo ""
echo "Target Server: $SERVER"
echo "Server IP: $SERVER_IP"
echo "Backup Folder: $BACKUP_DIR"
echo "Coolify Version: $VERSION"
echo "Database Backup: ${DB_BACKUP:-'(not provided - will skip DB restore)'}"
echo ""
echo -e "${YELLOW}This will OVERWRITE the Coolify instance on $SERVER${NC}"
echo ""
read -r -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "======================================"
echo "Step 1: Testing SSH connectivity..."
echo "======================================"
# First try with strict host key checking disabled (for new servers)
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$SERVER" "echo 'OK'" > /dev/null 2>&1; then
    # Fallback to no checking at all
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$SERVER" "echo 'OK'" > /dev/null 2>&1; then
        echo -e "${RED}FAILED${NC}"
        echo ""
        echo "SSH connection failed. Please ensure:"
        echo "1. SSH key is added to ssh-agent"
        echo "2. The server is reachable at $SERVER"
        exit 1
    fi
fi
echo -e "${GREEN}OK${NC}"

echo ""
echo "======================================"
echo "Step 2: Installing Coolify $VERSION..."
echo "======================================"
ssh "$SERVER" "curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s $VERSION"
echo -e "${GREEN}Installation complete${NC}"

echo ""
echo "======================================"
echo "Step 3: Stopping Coolify services..."
echo "======================================"
ssh "$SERVER" "docker stop coolify coolify-redis coolify-realtime coolify-proxy 2>/dev/null || true"
echo -e "${GREEN}Services stopped${NC}"

# Database restore (if provided)
if [ -n "$DB_BACKUP" ] && [ -f "$DB_BACKUP" ]; then
    echo ""
    echo "======================================"
    echo "Step 4: Restoring database..."
    echo "======================================"
    echo "Copying database backup to server..."
    scp "$DB_BACKUP" "$SERVER:/tmp/coolify_restore_backup.sql"
    echo "Restoring database (this may take a while)..."
    # Suppress verbose output, only show errors
    if ssh "$SERVER" "cat /tmp/coolify_restore_backup.sql | docker exec -i coolify-db pg_restore --clean --no-acl --no-owner -U coolify -d coolify 2>&1 | grep -E '(ERROR|WARNING|pg_restore:.*FAILED)'" > /tmp/restore_errors_$$.txt 2>&1; then
        if [ -s /tmp/restore_errors_$$.txt ]; then
            echo -e "${YELLOW}Restore completed with warnings/errors:${NC}"
            cat /tmp/restore_errors_$$.txt
        fi
    fi
    rm -f /tmp/restore_errors_$$.txt
    ssh "$SERVER" "rm -f /tmp/coolify_restore_backup.sql"
    echo -e "${GREEN}Database restored${NC}"
fi

echo ""
echo "======================================"
echo "Step 5: Removing auto-generated SSH keys..."
echo "======================================"
ssh "$SERVER" "rm -f /data/coolify/ssh/keys/*"
echo -e "${GREEN}Auto-generated keys removed${NC}"

echo ""
echo "======================================"
echo "Step 6: Restoring SSH private keys..."
echo "======================================"
KEY_COUNT=0
for keyfile in "$BACKUP_DIR"/sshkeys/ssh_key@*; do
    if [ -f "$keyfile" ]; then
        keyname=$(basename "$keyfile")
        echo "  Copying $keyname..."
        scp "$keyfile" "$SERVER:/data/coolify/ssh/keys/$keyname"
        ssh "$SERVER" "chmod 600 /data/coolify/ssh/keys/$keyname"
        KEY_COUNT=$((KEY_COUNT + 1))
    fi
done
echo -e "${GREEN}Restored $KEY_COUNT SSH key(s)${NC}"

echo ""
echo "======================================"
echo "Step 7: Restoring authorized_keys..."
echo "======================================"
if [ -f "$BACKUP_DIR/authorized_keys" ]; then
    # Backup existing authorized_keys first
    ssh "$SERVER" "cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup.$(date +%Y%m%d) 2>/dev/null || true"
    # Append our keys
    scp "$BACKUP_DIR/authorized_keys" "$SERVER:/tmp/authorized_keys_restore"
    ssh "$SERVER" "cat /tmp/authorized_keys_restore >> ~/.ssh/authorized_keys && rm -f /tmp/authorized_keys_restore"
    ssh "$SERVER" "chmod 600 ~/.ssh/authorized_keys"
    echo -e "${GREEN}authorized_keys updated${NC}"
else
    echo -e "${YELLOW}No authorized_keys file found in backup${NC}"
fi

echo ""
echo "======================================"
echo "Step 8: Configuring environment..."
echo "======================================"
# Get current env file
ssh "$SERVER" "cp /data/coolify/source/.env /data/coolify/source/.env.backup.$(date +%Y%m%d)"

# Check if APP_PREVIOUS_KEYS already exists
CURRENT_PREVIOUS_KEYS=$(ssh "$SERVER" "grep '^APP_PREVIOUS_KEYS=' /data/coolify/source/.env 2>/dev/null | cut -d'=' -f2 || echo ''")

if [ -n "$CURRENT_PREVIOUS_KEYS" ]; then
    # Append to existing
    NEW_PREVIOUS_KEYS="${CURRENT_PREVIOUS_KEYS},${APP_KEY}"
    # Use | as delimiter instead of / to avoid issues with base64 encoding
    ssh "$SERVER" "sed -i 's|^APP_PREVIOUS_KEYS=.*|APP_PREVIOUS_KEYS=$NEW_PREVIOUS_KEYS|' /data/coolify/source/.env"
else
    # Add new line
    ssh "$SERVER" "echo 'APP_PREVIOUS_KEYS=$APP_KEY' >> /data/coolify/source/.env"
fi

echo -e "${GREEN}APP_PREVIOUS_KEYS configured${NC}"

echo ""
echo "======================================"
echo "Step 9: Restarting Coolify..."
echo "======================================"
ssh "$SERVER" "curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s $VERSION"
echo -e "${GREEN}Coolify restarted${NC}"

# Verify Coolify is running
echo ""
echo "Verifying Coolify is healthy..."
sleep 5
if ssh "$SERVER" "docker ps --format '{{.Names}}' | grep -q '^coolify$'"; then
    echo -e "${GREEN}Coolify container is running${NC}"
else
    echo -e "${YELLOW}Warning: Coolify container status unknown${NC}"
fi

echo ""
echo "======================================"
echo -e "${GREEN}Restore Complete!${NC}"
echo "======================================"
echo ""
echo -e "${BLUE}🚀 Your Coolify instance is ready!${NC}"
echo ""
echo -e "   Login URL: ${GREEN}http://${SERVER_IP}:8000${NC}"
echo ""
echo "Next steps:"
echo "  1. Visit http://${SERVER_IP}:8000 and log in"
echo "  2. Verify all your projects and servers are accessible"
echo "  3. Test SSH connections to managed servers"
echo "  4. Check that encrypted data is readable (API keys, etc.)"
echo ""
echo "If you encounter issues:"
echo "  - Check logs: ssh $SERVER 'docker logs coolify'"
echo "  - Original env backup: ssh $SERVER 'cat /data/coolify/source/.env.backup.*'"
echo "  - Authorized keys backup: ssh $SERVER 'cat ~/.ssh/authorized_keys.backup.*'"
echo ""
echo "======================================"
