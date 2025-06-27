#!/bin/bash

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

# Create the zip file
mkdir -p release
zip -r release/newrelic-oci-terraform.zip . -x ".git/*" ".github/*"

# Create the new tag and push it
git tag "$next_tag"
git push origin "$next_tag"

# Create a release using GitHub CLI
gh release create "$next_tag" release/newrelic-oci-terraform.zip --title "Release $next_tag" --notes "Automated release"
