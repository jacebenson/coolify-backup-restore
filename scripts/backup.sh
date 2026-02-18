#!/bin/bash
# backup - Master backup script that runs both config and database backups
# Usage: ./scripts/backup.sh [user@server] [backup-folder] [--test]
# Examples:
#   ./scripts/backup.sh                                    # Auto: backups/coolify.jace.pro/YYYY-MM-DDTHHMM
#   ./scripts/backup.sh root@example.com                   # Auto: backups/example.com/YYYY-MM-DDTHHMM
#   ./scripts/backup.sh root@example.com custom-folder     # Use custom folder
#   ./scripts/backup.sh root@example.com --test            # Auto path, no confirmation

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load and export environment variables for child scripts
if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    source "$REPO_ROOT/.env"
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SERVER="${1:-root@coolify.jace.pro}"

# Extract server name (remove user@ prefix if present)
SERVER_NAME=$(echo "$SERVER" | sed 's/^[^@]*@//')

# Default backup path: backups/coolify.jace.pro/2026-02-18T1156
DEFAULT_BACKUP_DIR="backups/${SERVER_NAME}/$(date +%Y-%m-%dT%H%M)"

# Check for --test flag
TEST_MODE=false
BACKUP_DIR=""

# Process remaining arguments
shift  # Remove server from args
for arg in "$@"; do
    if [ "$arg" = "--test" ]; then
        TEST_MODE=true
    elif [ -z "$BACKUP_DIR" ]; then
        BACKUP_DIR="$arg"
    fi
done

# Use default if no backup dir specified
if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR="$DEFAULT_BACKUP_DIR"
fi

echo "======================================"
echo "Coolify Complete Backup"
echo "======================================"
echo ""
echo "Server: $SERVER"
echo "Server Name: $SERVER_NAME"
echo "Backup Folder: $BACKUP_DIR"
echo "Test Mode: $TEST_MODE"
echo ""

# Create backups directory structure
mkdir -p "$REPO_ROOT/$BACKUP_DIR"

# Check required scripts exist
if [ ! -f "$SCRIPT_DIR/backup-coolify.sh" ]; then
    echo -e "${RED}Error: backup-coolify.sh not found${NC}"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/fetch-s3-backup.sh" ]; then
    echo -e "${RED}Error: fetch-s3-backup.sh not found${NC}"
    exit 1
fi

# Make scripts executable
chmod +x "$SCRIPT_DIR/backup-coolify.sh" "$SCRIPT_DIR/fetch-s3-backup.sh"

echo "======================================"
echo "Step 1: Backup Configuration & Keys"
echo "======================================"
echo ""

# Run config backup
"$SCRIPT_DIR/backup-coolify.sh" "$SERVER" "$REPO_ROOT/$BACKUP_DIR"

echo ""
echo "======================================"
echo "Step 2: Fetch Database from S3"
echo "======================================"
echo ""

# Run S3 database fetch
"$SCRIPT_DIR/fetch-s3-backup.sh" "$REPO_ROOT/$BACKUP_DIR"

echo ""
echo "======================================"
echo -e "${GREEN}Complete Backup Finished!${NC}"
echo "======================================"
echo ""
echo "Backup location: $BACKUP_DIR/"
echo ""
echo "Contents:"
ls -la "$REPO_ROOT/$BACKUP_DIR/" 2>/dev/null || echo "  (folder contents)"
echo ""
echo "Next steps:"
echo "  1. Review the backup: ls -la $BACKUP_DIR/"
echo "  2. Commit to git: git add backups/ && git commit -m \"Backup Coolify - $BACKUP_DIR\""
echo ""
echo "To restore:"
echo "  ./scripts/restore-coolify.sh root@<new-server> $BACKUP_DIR $BACKUP_DIR/pg-dump-coolify-*.dmp"
