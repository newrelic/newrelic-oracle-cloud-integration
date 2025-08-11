#!/bin/bash

# Define the directories to be zipped
METRICS_DIR="newrelic-metrics-setup"
POLICY_DIR="newrelic-policy-setup"
METRICS_ZIP="newrelic-metrics-setup.zip"
POLICY_ZIP="newrelic-policy-setup.zip"

# Check if the directories exist
if [ ! -d "$METRICS_DIR" ]; then
  echo "Error: Directory $METRICS_DIR does not exist."
  exit 1
fi

if [ ! -d "$POLICY_DIR" ]; then
  echo "Error: Directory $POLICY_DIR does not exist."
  exit 1
fi

# Create the zip files
echo "Creating metrics zip file: $METRICS_ZIP"
zip -r "$METRICS_ZIP" "$METRICS_DIR"

echo "Creating policy zip file: $POLICY_ZIP"
zip -r "$POLICY_ZIP" "$POLICY_DIR"

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

# Create a release using GitHub CLI with both zip files
release_heading="newrelic-oci - ${next_tag}"
release_notes="Features

${latest_commit_message}"
gh release create "$next_tag" "$METRICS_ZIP" "$POLICY_ZIP" --title "$release_heading" --notes "$release_notes"

echo "Release created successfully with tag: $next_tag"
