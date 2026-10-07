#!/bin/bash
# Regenerates every app icon PNG from tools/AppIcon.svg, keeping each
# file's existing pixel size. Requires rsvg-convert and ImageMagick.
set -e
cd "$(dirname "$0")/.."

SVG="tools/AppIcon.svg"

for png in Resources/Icon*.png Resources/iTunesArtwork.png \
           Jeeves/Resources/Icon*.png Jeeves/Resources/iTunesArtwork.png \
           Jeeves/Assets.xcassets/AppIcon.appiconset/Icon-*.png; do
    size=$(magick identify -format "%w" "$png")
    # iOS icons must be opaque RGB
    rsvg-convert -w "$size" -h "$size" "$SVG" | magick - -background black -alpha remove -alpha off -type TrueColor "PNG24:$png"
    echo "$png (${size}px)"
done
