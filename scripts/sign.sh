#!/bin/zsh
set -euo pipefail
signing_dir="$HOME/Library/Application Support/MacBar/Signing"
if [[ ! -f "$signing_dir/identity.sha1" ]]; then
  print -u2 'MacBar signing identity is missing. Run scripts/setup-signing.sh once; do not recreate an existing identity.'
  exit 1
fi
signing_identity=$(<"$signing_dir/identity.sha1")
if [[ ${#signing_identity} != 40 || "$signing_identity" == *[^0-9A-Fa-f]* ]]; then
  print -u2 'Invalid MacBar certificate fingerprint.'
  exit 1
fi
codesign --force --sign "$signing_identity" --timestamp=none \
  --identifier dev.local.MacBar \
  --requirements "=designated => identifier \"dev.local.MacBar\" and certificate leaf = H\"$signing_identity\"" "$1"
codesign --verify --strict "$1"
