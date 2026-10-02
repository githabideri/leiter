# Install stick: payload hidden behind the ISO

One 8 GB stick does the whole job. Last verified 2026-09-25 (a headless laptop node),
re-verify commands against the current iwd/NetworkManager versions.

## Building the stick

```sh
dd if=nixos-<ver>-x86_64-linux.iso of=/dev/sda   # NOT Ventoy (hit-or-miss with NixOS)
```

The ISO occupies ~1.75 GB; the payload is a **gzip tarball written at the
4 GiB offset** in the free space *after* the image: zero partition
surgery. Verify boot-region integrity before and after with
`sha256sum <(head -c 1750M /dev/sda)` style checks (or dd-compare the first
N MiB against the ISO).

Payload contents (tar.gz):
- `wpa-<SSID>.conf`: **iwd format** (not wpa_supplicant),
  `[Network] SSID=...` + `[Security] Passphrase=...`. **Real PSK: never
  committed anywhere.**
- `<agent_key.pub>`: the agent's ed25519 public key for authorized_keys.
- `provision.sh`: runs at first boot; `modprobe iwlwifi` (and friends),
  copy the key to `/etc/ssh/ssh_keys/authorized_keys`, start sshd, place
  the iwd network file under `/var/lib/iwd/` (iwd 3.x `StateDirectory`).
  placeholder is `wifi`, not
  `wlan`.

Reading it back inside the ISO session:

```sh
dd if=/dev/sda bs=1M skip=4096 count=1 | tar xz
```

## Getting the Wi-Fi PSK (control station)

Connections are often auto-created and never written to disk. Extract from
live NetworkManager state:

```sh
nmcli -t -f 802-11-wireless-security.psk connection show --show-secrets "<name>"
```

The value travels only inside the stick payload and machine-local working
trees: never into git (the settings repo keeps `REPLACE-WIFI-PASSPHRASE`
in `first-contact.nix`; the machine-local `/root/nixos-flake` copy gets the
real value, and the flake *generates* the iwd file from attrs,
`formats.ini`: inlined into the activation script).

## iwd 3.x specifics

- Network files live in `/var/lib/iwd/` (`StateDirectory`).
- **`/etc/iwd/main.conf` must enable network configuration.** With an
  empty main.conf, iwd 3.12 logs `station: Network configuration is
  disabled` and never auto-connects (NixOS 26.05's module generates an
  *empty* main.conf by default). Set via `networking.wireless.iwd.settings`
  in the flake: never by editing `/etc` (read-only).
- A dead NVRAM (`rfid` = `0xd55555d5` in the card's eeprom) means no
  station interface at all: hardware fault, M.2 replacement, not
  configuration.

## Human-input budget

German (and other non-QWERTY) keyboards make `|`, `'`, `&` fragile on the
ISO console. Keep user-typed commands to **1–2 short alphanumeric lines**;
everything else belongs in the stick payload. For wired machines the
human types nothing (the agent just needs the LAN address or the
authkey'd tailnet).
