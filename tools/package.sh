#!/usr/bin/env bash
# Packages a desktop build from ./out into ./dist for a release.
#
# Usage: tools/package.sh <platform>, such as x86_64-linux or x86_64-windows.
# Names the package after $VERSION, or the short commit SHA when it is empty.
set -euo pipefail

platform=$1
commit=${COMMIT:-$(git rev-parse HEAD)}
version=${VERSION:-${commit::7}}
dir=falling-$version-$platform

case $platform in
*-windows) exe=falling.exe ;;
*) exe=falling ;;
esac

mkdir -p dist "$dir"
cp "out/bin/$exe" README.md portmaster/falling/licenses/LICENSE.SDL3.txt "$dir"

# Windows users expect a zip; tar keeps the executable bit for everyone else.
case $platform in
*-windows) zip -r "dist/$dir.zip" "$dir" ;;
# COPYFILE_DISABLE stops macOS tar adding ._* files for extended attributes.
*) COPYFILE_DISABLE=1 tar czf "dist/$dir.tar.gz" "$dir" ;;
esac
