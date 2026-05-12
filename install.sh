#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/rpi-modbus-gateway"
UDEV_RULES="/etc/udev/rules.d/99-rpi-modbus-gateway.rules"
SYSTEMD_TEMPLATE="/etc/systemd/system/mbusd@.service"

source "$REPO_DIR/lib/yaml.sh"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Bitte mit sudo/root ausführen:"
    echo "  sudo ./install.sh"
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Fehlt: $1"
    exit 1
  }
}

install_dependencies() {
  need_cmd systemctl
  need_cmd udevadm
  need_cmd python3

  if ! command -v mbusd >/dev/null 2>&1 && [[ ! -x /usr/local/bin/mbusd ]]; then
    echo "mbusd wurde nicht gefunden."

    if command -v apt-get >/dev/null 2>&1; then
      read -r -p "Soll versucht werden, mbusd per apt zu installieren? [Y/n] " ans
      ans="${ans:-Y}"
      if [[ "$ans" =~ ^[YyJj]$ ]]; then
        apt-get update
        apt-get install -y mbusd || {
          echo "apt konnte mbusd nicht installieren."
          echo "Installiere mbusd manuell nach /usr/local/bin/mbusd und starte den Installer erneut."
          exit 1
        }
      else
        echo "Abbruch. Installiere mbusd zuerst."
        exit 1
      fi
    else
      echo "Kein apt-get vorhanden. Installiere mbusd manuell."
      exit 1
    fi
  fi

  if [[ ! -x /usr/local/bin/mbusd ]] && command -v mbusd >/dev/null 2>&1; then
    MBUSD_BIN="$(command -v mbusd)"
    echo "mbusd gefunden: $MBUSD_BIN"
    if [[ "$MBUSD_BIN" != "/usr/local/bin/mbusd" ]]; then
      read -r -p "Systemd-Template auf $MBUSD_BIN anpassen? [Y/n] " ans
      ans="${ans:-Y}"
      if [[ "$ans" =~ ^[YyJj]$ ]]; then
        tmp="$(mktemp)"
        sed "s#/usr/local/bin/mbusd#$MBUSD_BIN#g" "$REPO_DIR/templates/mbusd@.service" > "$tmp"
        install -m 0644 "$tmp" "$SYSTEMD_TEMPLATE"
        rm -f "$tmp"
        return
      fi
    fi
  fi

  install -m 0644 "$REPO_DIR/templates/mbusd@.service" "$SYSTEMD_TEMPLATE"
}

list_profiles() {
  mapfile -t PROFILES < <(find "$REPO_DIR/gateways" -maxdepth 1 -type f -name "*.yaml" | sort)

  if [[ "${#PROFILES[@]}" -eq 0 ]]; then
    echo "Keine Profile in gateways/*.yaml gefunden."
    exit 1
  fi

  echo
  echo "Verfügbare Gateway-Profile:"
  echo

  local i=1
  for p in "${PROFILES[@]}"; do
    local id desc
    id="$(yaml_get "$p" id 2>/dev/null || basename "$p" .yaml)"
    desc="$(yaml_get "$p" description 2>/dev/null || true)"
    printf "  [%d] %s" "$i" "$id"
    [[ -n "$desc" ]] && printf " - %s" "$desc"
    echo
    ((i++))
  done

  echo
  read -r -p "Profil auswählen: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#PROFILES[@]} )); then
    echo "Ungültige Auswahl."
    exit 1
  fi

  PROFILE="${PROFILES[$((choice-1))]}"
}

detect_adapters() {
  echo
  echo "Erkannte serielle USB-Adapter:"
  echo

  mapfile -t ADAPTERS < <(find /dev/serial/by-id -maxdepth 1 -type l 2>/dev/null | sort || true)

  if [[ "${#ADAPTERS[@]}" -eq 0 ]]; then
    echo "Keine Adapter unter /dev/serial/by-id gefunden."
    echo "Steckt der RS485-USB-Stick?"
    exit 1
  fi

  local i=1
  for dev in "${ADAPTERS[@]}"; do
    local target tty serial vendor model udev_props
    target="$(readlink -f "$dev")"
    tty="$(basename "$target")"

    udev_props="$(udevadm info -q property -n "$target")"
    serial="$(echo "$udev_props" | awk -F= '$1=="ID_SERIAL_SHORT"{print $2}')"
    vendor="$(echo "$udev_props" | awk -F= '$1=="ID_VENDOR_ID"{print $2}')"
    model="$(echo "$udev_props" | awk -F= '$1=="ID_MODEL_ID"{print $2}')"

    printf "  [%d] %s -> %s" "$i" "$(basename "$dev")" "$tty"
    [[ -n "$vendor" || -n "$model" ]] && printf "  [%s:%s]" "$vendor" "$model"
    [[ -n "$serial" ]] && printf " serial=%s" "$serial"
    echo
    ((i++))
  done

  echo
  read -r -p "Adapter auswählen: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#ADAPTERS[@]} )); then
    echo "Ungültige Auswahl."
    exit 1
  fi

  SELECTED_DEV="$(readlink -f "${ADAPTERS[$((choice-1))]}")"
  local selected_props
  selected_props="$(udevadm info -q property -n "$SELECTED_DEV")"
  SELECTED_SERIAL="$(echo "$selected_props" | awk -F= '$1=="ID_SERIAL_SHORT"{print $2}')"
  SELECTED_VENDOR="$(echo "$selected_props" | awk -F= '$1=="ID_VENDOR_ID"{print $2}')"
  SELECTED_MODEL="$(echo "$selected_props" | awk -F= '$1=="ID_MODEL_ID"{print $2}')"

  if [[ -z "$SELECTED_VENDOR" || -z "$SELECTED_MODEL" ]]; then
    echo "Vendor/Product konnte nicht gelesen werden."
    exit 1
  fi

  if [[ -z "$SELECTED_SERIAL" ]]; then
    echo "Warnung: Adapter hat keine Seriennummer."
    echo "Regel wird nur über Vendor/Product erstellt und ist nicht eindeutig, falls mehrere gleiche Adapter stecken."
    read -r -p "Trotzdem fortfahren? [y/N] " ans
    [[ "$ans" =~ ^[YyJj]$ ]] || exit 1
  fi
}

validate_uint() {
  local val="$1" label="$2" min="${3:-1}" max="${4:-65535}"
  if ! [[ "$val" =~ ^[0-9]+$ ]] || (( val < min || val > max )); then
    echo "Ungültiger Wert für ${label}: '${val}' (erwartet: ganze Zahl ${min}–${max})"
    exit 1
  fi
}

ask_config() {
  local default_name default_port default_baud default_mode default_v default_r default_w

  default_name="$(yaml_get "$PROFILE" defaults.gateway_name 2>/dev/null || yaml_get "$PROFILE" id)"
  default_port="$(yaml_get "$PROFILE" mbusd.tcp_port 2>/dev/null || echo 502)"
  default_baud="$(yaml_get "$PROFILE" mbusd.baudrate 2>/dev/null || echo 9600)"
  default_mode="$(yaml_get "$PROFILE" mbusd.mode 2>/dev/null || echo 8N1)"
  default_v="$(yaml_get "$PROFILE" mbusd.verbosity 2>/dev/null || echo 2)"
  default_r="$(yaml_get "$PROFILE" mbusd.slave_timeout_ms 2>/dev/null || echo 100)"
  default_w="$(yaml_get "$PROFILE" mbusd.response_timeout_ms 2>/dev/null || echo 500)"

  echo
  read -r -p "Gateway-Name [${default_name}]: " GATEWAY_NAME
  GATEWAY_NAME="${GATEWAY_NAME:-$default_name}"

  if ! [[ "$GATEWAY_NAME" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "Ungültiger Name. Erlaubt: Buchstaben, Zahlen, ., _, -"
    exit 1
  fi

  read -r -p "Modbus TCP-Port [${default_port}]: " TCP_PORT
  TCP_PORT="${TCP_PORT:-$default_port}"
  validate_uint "$TCP_PORT" "TCP-Port" 1 65535

  if [[ -d "$CONFIG_DIR" ]]; then
    for existing_env in "$CONFIG_DIR"/*.env; do
      [[ -e "$existing_env" ]] || continue
      local existing_port
      existing_port="$(grep -E '^TCP_PORT=' "$existing_env" | cut -d= -f2)"
      if [[ "$existing_port" == "$TCP_PORT" ]]; then
        echo "Warnung: Port ${TCP_PORT} wird bereits von $(basename "$existing_env" .env) verwendet."
        read -r -p "Trotzdem fortfahren? [y/N] " ans
        [[ "$ans" =~ ^[YyJj]$ ]] || exit 1
        break
      fi
    done
  fi

  read -r -p "Baudrate [${default_baud}]: " BAUDRATE
  BAUDRATE="${BAUDRATE:-$default_baud}"
  validate_uint "$BAUDRATE" "Baudrate" 1 4000000

  read -r -p "Mode [${default_mode}]: " MODE
  MODE="${MODE:-$default_mode}"

  read -r -p "Verbosity [${default_v}]: " VERBOSITY
  VERBOSITY="${VERBOSITY:-$default_v}"
  validate_uint "$VERBOSITY" "Verbosity" 0 9

  read -r -p "Slave timeout -R ms [${default_r}]: " SLAVE_TIMEOUT_MS
  SLAVE_TIMEOUT_MS="${SLAVE_TIMEOUT_MS:-$default_r}"
  validate_uint "$SLAVE_TIMEOUT_MS" "Slave-Timeout" 1 60000

  read -r -p "Response timeout -W ms [${default_w}]: " RESPONSE_TIMEOUT_MS
  RESPONSE_TIMEOUT_MS="${RESPONSE_TIMEOUT_MS:-$default_w}"
  validate_uint "$RESPONSE_TIMEOUT_MS" "Response-Timeout" 1 60000
}

write_files() {
  mkdir -p "$CONFIG_DIR"

  local env_file="$CONFIG_DIR/${GATEWAY_NAME}.env"

  cat > "$env_file" <<EOF
TCP_PORT=${TCP_PORT}
BAUDRATE=${BAUDRATE}
MODE=${MODE}
VERBOSITY=${VERBOSITY}
SLAVE_TIMEOUT_MS=${SLAVE_TIMEOUT_MS}
RESPONSE_TIMEOUT_MS=${RESPONSE_TIMEOUT_MS}
EOF

  chmod 0644 "$env_file"

  touch "$UDEV_RULES"

  if grep -q "SYMLINK+=\"${GATEWAY_NAME}\"" "$UDEV_RULES"; then
    echo "udev-Regel für ${GATEWAY_NAME} existiert bereits. Sie wird ersetzt."
    tmp="$(mktemp)"
    grep -v "SYMLINK+=\"${GATEWAY_NAME}\"" "$UDEV_RULES" > "$tmp" || true
    cat "$tmp" > "$UDEV_RULES"
    rm -f "$tmp"
  fi

  if [[ -n "$SELECTED_SERIAL" ]]; then
    cat >> "$UDEV_RULES" <<EOF
SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="${SELECTED_VENDOR}", ENV{ID_MODEL_ID}=="${SELECTED_MODEL}", ENV{ID_SERIAL_SHORT}=="${SELECTED_SERIAL}", SYMLINK+="${GATEWAY_NAME}", MODE="0660", GROUP="dialout"
EOF
  else
    cat >> "$UDEV_RULES" <<EOF
SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="${SELECTED_VENDOR}", ENV{ID_MODEL_ID}=="${SELECTED_MODEL}", SYMLINK+="${GATEWAY_NAME}", MODE="0660", GROUP="dialout"
EOF
  fi
}

reload_and_start() {
  systemctl daemon-reload
  udevadm control --reload-rules
  udevadm trigger
  udevadm settle --timeout=5

  if [[ ! -e "/dev/${GATEWAY_NAME}" ]]; then
    echo
    echo "Hinweis: /dev/${GATEWAY_NAME} ist noch nicht sichtbar."
    echo "Stick kurz abziehen/anstecken oder neu starten."
  fi

  systemctl enable --now "mbusd@${GATEWAY_NAME}.service"

  echo
  echo "Fertig."
  echo
  echo "Status:"
  systemctl --no-pager --full status "mbusd@${GATEWAY_NAME}.service" || true
  echo
  echo "Gerät:"
  ls -l "/dev/${GATEWAY_NAME}" 2>/dev/null || true
}

main() {
  require_root
  install_dependencies
  list_profiles
  detect_adapters
  ask_config
  write_files
  reload_and_start
}

main "$@"
