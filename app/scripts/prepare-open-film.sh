#!/usr/bin/env bash
# Include the publisher's unmodified, CC BY 4.0 H.264/AAC file in offline builds.
set -euo pipefail
cd "$(dirname "$0")/.."
dest="SuperTV/Offline/OpenFilm/wing-it.mp4"
sha=8c23aae165447a26d88e356849b0ea4fd84edaee1be9ccd63f981ed7b08b750c
url=https://video.blender.org/object-storage/web_videos/1be4c93c-1fd2-498d-adc7-50126823033e-480.mp4
check() { [[ "$(shasum -a 256 "$1" | awk '{print $1}')" == "$sha" ]]; }
mkdir -p "$(dirname "$dest")"
if [[ -f "$dest" ]] && check "$dest"; then echo 'WING IT!: verified local file'; exit 0; fi
tmp="$(mktemp "$(dirname "$dest")/.wing-it.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  --retry 2 --max-time 180 "$url" --output "$tmp"
check "$tmp" || { echo 'WING IT!: upstream digest changed; not packaged.' >&2; exit 1; }
chmod 0644 "$tmp"
mv "$tmp" "$dest"
echo 'WING IT!: verified official film, included unchanged.'
