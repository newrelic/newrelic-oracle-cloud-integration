#!/bin/bash

# Define the directory to be zipped
TARGET_DIR="newrelic-oci-terraform"
ZIP_FILE="newrelic-oci-terraform.zip"

# Check if the target directory exists
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Directory $TARGET_DIR does not exist."
  exit 1
fi

# Create the zip file containing only the target directory's contents
echo "Creating zip file: $ZIP_FILE"
zip -r "$ZIP_FILE" "$TARGET_DIR"

# Fetch the latest tags
git fetch --tags

# Get the latest tag or default to v0.0.0
latest_tag=$(git describe --tags $(git rev-list --tags --max-count=1) || echo "v0.0.0")

# Parse the version components
IFS='.' read -r major minor patch <<< "${latest_tag#v}"

# Increment the patch version, or minor if patch reaches 9
if [ "$patch" -lt 9 ]; then
  patch=$((patch + 1))
else
  patch=0
  minor=$((minor + 1))
fi

# Construct the next tag
next_tag="v${major}.${minor}.${patch}"

# Get the latest commit message
latest_commit_message=$(git log -1 --pretty=%B)

# Create the new tag and push it
git tag "$next_tag"
git push origin "$next_tag"

# Create a release using GitHub CLI
release_heading="newrelic-oci - ${next_tag}"
release_notes="Features

${latest_commit_message}"
gh release create "$next_tag" "$ZIP_FILE" --title "$release_heading" --notes "$release_notes"

echo "Release created successfully with tag: $next_tag"
