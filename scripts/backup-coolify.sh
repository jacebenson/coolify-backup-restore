#!/bin/bash
# backup-coolify.sh - Backup Coolify instance to local repository
# Usage: ./scripts/backup-coolify.sh [user@host] [backup-folder]

set -e  # Exit on any error

# Configuration
SERVER="${1:-root@example.com}"
BACKUP_DIR="${2:-$(date +%Y-%m-%d)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "Coolify Backup Script"
echo "Target: $SERVER"
echo "Date: $DATE"
echo "======================================"
echo ""

# Test SSH connectivity first
echo -n "Testing SSH connection to $SERVER..."
# First try with strict host key checking disabled (for new servers)
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$SERVER" "echo 'OK'" > /dev/null 2>&1; then
    # Fallback to no checking at all
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$SERVER" "echo 'OK'" > /dev/null 2>&1; then
        echo -e "${RED}FAILED${NC}"
        echo ""
        echo "SSH connection failed. Please ensure:"
        echo "1. SSH key is added to ssh-agent: eval \$(ssh-agent -s) && ssh-add ~/.ssh/your_key"
        echo "2. Or specify a key: ./scripts/backup-coolify.sh -i ~/.ssh/your_key root@example.com"
        echo "3. The server is reachable at $SERVER"
        exit 1
    fi
fi
echo -e "${GREEN}OK${NC}"
echo ""

# Create backup directory
echo "Creating backup directory: $BACKUP_DIR/"
mkdir -p "$BACKUP_DIR/sshkeys"

# Fetch APP_KEY (the critical one)
echo -n "Fetching APP_KEY..."
if ssh "$SERVER" "test -f /data/coolify/source/.env"; then
    ssh "$SERVER" "grep '^APP_KEY=' /data/coolify/source/.env" > "$BACKUP_DIR/.env.backup"
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}WARNING${NC} - .env file not found"
fi

# Fetch SSH private keys
echo "Fetching SSH private keys..."
KEY_COUNT=0

# Get list of keys and save to temp file to avoid stdin issues
ssh "$SERVER" "ls -1 /data/coolify/ssh/keys/ 2>/dev/null" > /tmp/coolify_keys_$$.txt

if [ ! -s /tmp/coolify_keys_$$.txt ]; then
    echo -e "  ${YELLOW}No SSH keys found${NC}"
else
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        echo -n "  Copying $key..."
        ssh -n "$SERVER" "cat /data/coolify/ssh/keys/$key" > "$BACKUP_DIR/sshkeys/$key"
        chmod 600 "$BACKUP_DIR/sshkeys/$key"
        echo -e "${GREEN}OK${NC}"
        KEY_COUNT=$((KEY_COUNT + 1))
    done < /tmp/coolify_keys_$$.txt
    rm -f /tmp/coolify_keys_$$.txt
    echo "  Copied $KEY_COUNT key(s)"
fi

# Fetch authorized_keys
echo -n "Fetching authorized_keys..."
if ssh "$SERVER" "test -f ~/.ssh/authorized_keys"; then
    ssh "$SERVER" "cat ~/.ssh/authorized_keys" > "$BACKUP_DIR/authorized_keys"
    chmod 644 "$BACKUP_DIR/authorized_keys"
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}WARNING${NC} - authorized_keys not found"
fi

# Get Coolify version
echo -n "Fetching Coolify version..."
VERSION=$(ssh "$SERVER" "docker ps --format '{{.Image}}' 2>/dev/null | grep coolify | head -1 || echo 'unknown'")
echo "$VERSION" > "$BACKUP_DIR/version.txt"
echo -e "${GREEN}OK${NC} ($VERSION)"

# Verify backup
echo ""
echo "======================================"
echo -e "${GREEN}Backup Complete!${NC}"
echo "======================================"
echo ""
echo "Backup location: $BACKUP_DIR/"
echo ""
echo "Contents:"
ls -la "$BACKUP_DIR/"
echo ""
echo "Next steps:"
echo "  1. Review the backup: ls -la $BACKUP_DIR/"
echo "  2. Commit to git: git add $BACKUP_DIR/ && git commit -m \"Backup Coolify $VERSION - $DATE\""
echo "  3. Push to remote: git push"
