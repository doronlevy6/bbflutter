#!/bin/bash

# Script to build Flutter Web and deploy to the GitHub Pages repository folder

# Define paths
FLUTTER_PROJECT_DIR=$(pwd)
WEB_REPO_DIR="../BB_web" # Adjust this if your web repo is elsewhere

echo "🚀 Starting Web Deployment Process..."

# 1. Build Flutter Web
echo "🔨 Building Flutter Web..."
flutter build web --release

if [ $? -ne 0 ]; then
    echo "❌ Build failed! Aborting."
    exit 1
fi

echo "✅ Build successful."

# 2. Clean destination directory (keep .git and README if needed)
echo "🧹 Cleaning destination directory ($WEB_REPO_DIR)..."
# Ensure we don't delete the .git folder!
find "$WEB_REPO_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name 'README.md' -exec rm -rf {} +

# 3. Copy build files
echo "📂 Copying build files to $WEB_REPO_DIR..."
cp -r "$FLUTTER_PROJECT_DIR/build/web/"* "$WEB_REPO_DIR/"

echo "✅ Files copied successfully."

# 4. Git commands (Optional - Uncomment to auto-push)
# cd "$WEB_REPO_DIR"
# git add .
# git commit -m "Deploy web build: $(date)"
# git push origin main

echo "🎉 Deployment preparation complete!"
echo "👉 Go to $WEB_REPO_DIR to review changes and push to GitHub."
