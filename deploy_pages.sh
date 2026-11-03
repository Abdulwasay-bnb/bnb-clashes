#!/usr/bin/env bash
# Build the web version and publish it to the gh-pages branch, then turn on GitHub Pages.
set -euo pipefail
cd "$(dirname "$0")"
GD="$HOME/Applications/godot/Godot_v4.3-stable_linux.x86_64"
REPO="Abdulwasay-bnb/bnb-clashes"
mkdir -p build && touch build/.gdignore
"$GD" --headless --path . --export-release "Web" build/web/index.html
touch build/web/.nojekyll
tmp=$(mktemp -d)
cp -r build/web/. "$tmp"
cd "$tmp"
git init -q -b gh-pages
git add -A
git -c user.name="Abdulwasay-bnb" -c user.email="abdul.wasay@bitandbytes.net" commit -q -m "Deploy web build"
git push -f "https://github.com/$REPO.git" gh-pages
cd - >/dev/null
rm -rf "$tmp"
gh api -X POST "repos/$REPO/pages" -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null 2>&1 || \
  gh api -X PUT "repos/$REPO/pages" -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null
echo "Deployed: https://abdulwasay-bnb.github.io/bnb-clashes/ (first publish can take 1-2 minutes)"
