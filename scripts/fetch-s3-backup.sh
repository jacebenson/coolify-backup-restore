#!/bin/bash
# fetch-s3-backup.sh - Download the latest Coolify backup from S3 using rclone
# Usage: ./scripts/fetch-s3-backup.sh [backup-folder]
# Example: ./scripts/fetch-s3-backup.sh 2026-02-18

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load S3 credentials
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
else
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please copy .env.example to .env and configure your S3 credentials"
    exit 1
fi

# Validate required variables
if [ -z "$S3_ENDPOINT" ] || [ -z "$S3_BUCKET" ] || [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
    echo -e "${RED}Error: Missing S3 credentials in .env file${NC}"
    echo "Required: S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY, S3_SECRET_KEY"
    exit 1
fi

# Determine backup folder
if [ -n "$1" ]; then
    BACKUP_DIR="$1"
else
    BACKUP_DIR=$(date +%Y-%m-%d)
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "======================================"
echo "Fetching Latest S3 Backup"
echo "======================================"
echo ""
echo "S3 Bucket: $S3_BUCKET"
echo "Endpoint: $S3_ENDPOINT"
echo "Backup Folder: $BACKUP_DIR"
echo ""

# Check for rclone
if ! command -v rclone &> /dev/null; then
    echo -e "${YELLOW}rclone not found. Installing...${NC}"
    
    # Install rclone
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y rclone
    elif command -v yum &> /dev/null; then
        yum install -y rclone
    elif command -v brew &> /dev/null; then
        brew install rclone
    else
        # Install via official script
        curl https://rclone.org/install.sh | bash
    fi
fi

# Create temporary rclone config
RCLONE_CONFIG_DIR=$(mktemp -d)
export RCLONE_CONFIG="$RCLONE_CONFIG_DIR/rclone.conf"

# Write rclone config
cat > "$RCLONE_CONFIG" << EOF
[coolify-s3]
type = s3
provider = Other
env_auth = false
access_key_id = $S3_ACCESS_KEY
secret_access_key = $S3_SECRET_KEY
endpoint = $S3_ENDPOINT
region = ${S3_REGION:-us-east-1}
EOF

echo "Listing backups in S3..."

# List all backup files and get the latest one
# Note: Coolify stores backups under data/coolify/backups/
LATEST_BACKUP=$(rclone ls coolify-s3:$S3_BUCKET/data/coolify/backups/coolify/coolify-db-hostdockerinternal/ 2>/dev/null | \
    grep "pg-dump-coolify" | \
    sort -k2 | \
    tail -1 | \
    awk '{print $2}')

if [ -z "$LATEST_BACKUP" ]; then
    echo -e "${RED}Error: No backup files found in S3${NC}"
    echo "Checked: coolify-s3:$S3_BUCKET/data/coolify/backups/coolify/coolify-db-hostdockerinternal/"
    rm -rf "$RCLONE_CONFIG_DIR"
    exit 1
fi

echo -e "${GREEN}Found latest backup: $LATEST_BACKUP${NC}"

# Extract filename
FILENAME=$(basename "$LATEST_BACKUP")
LOCAL_PATH="$BACKUP_DIR/$FILENAME"

echo ""
echo "Downloading to: $LOCAL_PATH"

# Download the file
rclone copy \
    "coolify-s3:$S3_BUCKET/data/coolify/backups/coolify/coolify-db-hostdockerinternal/$LATEST_BACKUP" \
    "$BACKUP_DIR/"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Download complete!${NC}"
    echo ""
    echo "File: $LOCAL_PATH"
    echo "Size: $(du -h "$LOCAL_PATH" | cut -f1)"
    echo ""
    echo "You can now restore with:"
    echo "  ./restore-coolify.sh root@<server> $BACKUP_DIR $LOCAL_PATH"
else
    echo -e "${RED}Download failed!${NC}"
    rm -rf "$RCLONE_CONFIG_DIR"
    exit 1
fi

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"
