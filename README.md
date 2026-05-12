# Raspberry Pi Modbus TCP Gateway Installer

Geführter Installer für `mbusd` auf einem Raspberry Pi.

Er kann einen oder mehrere USB-RS485-Adapter erkennen, daraus stabile `/dev/...`-Namen per `udev` erzeugen und je Adapter einen eigenen `mbusd`-Systemdienst starten.

Beispiel:

```bash
git clone https://github.com/<user>/rpi-modbus-gateway.git
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
mbusd:
  tcp_port: 502
  baudrate: 9600
  mode: 8N1
  response_timeout_ms: 500
  slave_timeout_ms: 100
usb:
  vendor_id: "0403"
  product_id: "6001"
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

## Deinstallation

```bash
sudo ./uninstall.sh
```

