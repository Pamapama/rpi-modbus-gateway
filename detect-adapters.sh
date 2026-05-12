#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d /dev/serial/by-id ]]; then
  echo "Keine /dev/serial/by-id Geräte gefunden."
  exit 0
fi

for dev in /dev/serial/by-id/*; do
  [[ -e "$dev" ]] || continue
  target="$(readlink -f "$dev")"
  echo
  echo "$(basename "$dev") -> $target"
  udevadm info -q property -n "$target" | grep -E '^(ID_VENDOR_ID|ID_MODEL_ID|ID_SERIAL_SHORT|ID_VENDOR|ID_MODEL)=' || true
done
