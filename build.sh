#!/bin/bash
# Pre-deployment build script for Cloudflare Pages
# Updates buildTime and _deploy_version.txt to force asset re-upload

NEW_VERSION=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Update _deploy_version.txt
echo "$NEW_VERSION" > "_deploy_version.txt"

# Update buildTime in index.html
sed -i.bak "s/const buildTime = '[^']*'/const buildTime = '$NEW_VERSION'/" "index.html"
rm -f "index.html.bak"

echo "✓ Updated buildTime and _deploy_version.txt to $NEW_VERSION"
