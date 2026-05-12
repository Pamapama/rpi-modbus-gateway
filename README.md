# Raspberry Pi Modbus TCP Gateway Installer

Geführter Installer für `mbusd` auf einem Raspberry Pi.

Er kann einen oder mehrere USB-RS485-Adapter erkennen, daraus stabile `/dev/...`-Namen per `udev` erzeugen und je Adapter einen eigenen `mbusd`-Systemdienst starten.

Beispiel:

```bash
git clone https://github.com/Pamapama/rpi-modbus-gateway.git
cd rpi-modbus-gateway
sudo ./install.sh
```

## Was wird erzeugt?

Pro Gateway:

- `/etc/udev/rules.d/99-rpi-modbus-gateway.rules`
- `/etc/rpi-modbus-gateway/<name>.env`
- `mbusd@<name>.service`
- stabiler Gerätename wie `/dev/goodwe485`

## Beispiel

Aus einem Profil wie:

```yaml
id: goodwe
description: GoodWe Wechselrichter RS485
defaults:
  gateway_name: goodwe485
mbusd:
  tcp_port: 502
  baudrate: 9600
  mode: 8N1
  slave_timeout_ms: 100
  response_timeout_ms: 500
```

und einem Adapter mit Seriennummer `B0036RQF` wird z. B.:

```text
/dev/goodwe485
```

und:

```text
systemctl enable --now mbusd@goodwe485
```

## Profile

Neue Geräte werden als YAML-Datei in `gateways/` angelegt.

Der Installer scannt automatisch:

```text
gateways/*.yaml
```

## Adapter erkennen

Ohne Installation listet `detect-adapters.sh` alle angesteckten USB-Seriell-Adapter mit ihren udev-Eigenschaften auf:

```bash
sudo ./detect-adapters.sh

usb-FTDI_FT232R_USB_UART_BG03CSA8-if00-port0 -> /dev/ttyUSB0
ID_MODEL=FT232R_USB_UART
ID_MODEL_ID=6001
ID_SERIAL_SHORT=BG03CSA8
ID_VENDOR=FTDI
ID_VENDOR_ID=0403

```

## Deinstallation

```bash
sudo ./uninstall.sh
```

