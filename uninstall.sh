#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/etc/rpi-modbus-gateway"
UDEV_RULES="/etc/udev/rules.d/99-rpi-modbus-gateway.rules"
SYSTEMD_TEMPLATE="/etc/systemd/system/mbusd@.service"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Bitte mit sudo/root ausführen:"
  echo "  sudo ./uninstall.sh"
  exit 1
fi

echo "Vorhandene Gateway-Configs:"
if [[ -d "$CONFIG_DIR" ]]; then
  find "$CONFIG_DIR" -maxdepth 1 -type f -name "*.env" -printf "  %f\n" | sed 's/.env$//'
else
  echo "  keine"
fi

read -r -p "Gateway-Name entfernen oder 'all': " name

if [[ "$name" == "all" ]]; then
  if [[ -d "$CONFIG_DIR" ]]; then
    for env in "$CONFIG_DIR"/*.env; do
      [[ -e "$env" ]] || continue
      gw="$(basename "$env" .env)"
      systemctl disable --now "mbusd@${gw}.service" || true
    done
  fi
  rm -rf "$CONFIG_DIR"
  rm -f "$UDEV_RULES"
  rm -f "$SYSTEMD_TEMPLATE"
else
  systemctl disable --now "mbusd@${name}.service" || true
  rm -f "$CONFIG_DIR/${name}.env"

  if [[ -f "$UDEV_RULES" ]]; then
    tmp="$(mktemp)"
    grep -v "SYMLINK+=\"${name}\"" "$UDEV_RULES" > "$tmp" || true
    cat "$tmp" > "$UDEV_RULES"
    rm -f "$tmp"
  fi
fi

systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger

echo "Entfernt."
