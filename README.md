# alabs-mod-wifi

WiFi access point support for the MOD Dwarf (aLabs custom image).

With a USB WiFi dongle the Dwarf can either join a WiFi network (stock image
behaviour) or become an access point, so a phone or tablet can reach mod-ui
without a router.

## Layout

| Path | Content |
|---|---|
| `driver/` | `rtl8xxxu` driver backported from Linux 6.6 to the Dwarf kernel (6.1.15-rt7), with the patches in `driver/patches/` already applied |
| `firmware/` | firmware for all the supported Realtek dongles (from linux-firmware) and `regulatory.db` (from wireless-regdb), with their licences and `SHA256SUMS`: see [Licensing](#licensing) |
| `scripts/wifi-ap` | switches `wlan0` between client mode and access point mode |
| `scripts/wifi-ap-helper` | data commands of `wifi-ap` (Python 3.4), installed in `/usr/lib/alabs-mod-wifi/` |
| `diagnostics/50-wifi` | WiFi section of the diagnostics report, for [alabs-mod-diagnostics-logs](../alabs-mod-diagnostics-logs), installed in `/usr/lib/diagnostics-logs/providers.d/` |
| `VERSION` | alabs-mod-wifi version, installed in `/usr/lib/alabs-mod-wifi/` |
| `Makefile` | `make release`: binary release for the aLabs image, see [Binary release](#binary-release) |
| `systemd/` | `wifi-ap.path` + `wifi-ap.service`: run the requests of the HMI as root |
| `tmpfiles.d/` | creates `/run/wifi-ap/request`, writable by the HMI |
| `docs/` | [manual setup of a USB dongle](docs/usb-wifi-dongles.md) and [how the driver was backported](docs/driver-backport.md) |

User documentation (supported dongles, web interface and device settings) is in the
[Wi-Fi page](https://github.com/sejerpz/alabs-mod-custom-images/wiki/WiFi) of the
aLabs custom images wiki.

## Driver

`driver/patches/` documents the changes applied on top of the plain v6.6
sources (the `.c`/`.h` files in `driver/` already include them):

- `0001` builds on kernel 6.1 and retries failed USB register writes.
- `0002` **experimental** AP mode for the RTL8188EU (e.g. `0bda:8179`), limited
  to one connected station. Upstream rtl8xxxu has no AP mode for this chip
  because its rate adaptation is done in software for a single station.
- `0003` retries the whole firmware download when it fails: a USB error
  during the download corrupts the chip's checksum and the probe would fail,
  leaving the device without `wlan0`.
- `0004` waits longer (up to ~20 ms) for the chip to confirm a new beacon:
  under load the beacon reaches the chip after the ~2 ms the driver waited.
- `0005` sends the beacon again (up to 3 attempts) when the chip did not get
  it, instead of leaving the AP without beacons until the next update.

### Supported chips

USB IDs built into the module (the Dwarf kernel config has
`CONFIG_RTL8XXXU_UNTESTED` disabled, so RTL8188CU, RTL8192CU, RTL8188RU and
the other "untested" IDs of the driver are not included).

| Chip | USB IDs and known devices | AP mode | Max AP clients | Firmware (included) | Tested on the Dwarf |
|---|---|---|---|---|---|
| RTL8188EU / 8188ETV / 8188EUS | `0bda:8179`, `0bda:0179` (8188ETV), `0bda:ffef` Rosewill USB-N150 Nano, `0df6:0076` Sitecom, `2001:3311` D-Link USB-GO-N150, `2001:330f` D-Link DWA-125 rev D1, `2001:3310` D-Link DWA-123 rev D1, `2001:331b` D-Link DWA-121 rev B1, `07b8:8179` Abocom, `056e:4008` Elecom WDC-150SU2M, `2357:010c` TP-Link TL-WN722N v2, `2357:0111` TP-Link TL-WN727N v5.21, `2c4e:0102` Mercusys MW150US v2, `0b05:18f0` ASUS USB-N10 Nano B1, `7392:b811` Edimax EW-7811Un V2 | yes, **experimental** (`0002`) | 1 | [rtl8188eufw.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8188eufw.bin) | yes (`0bda:8179`) |
| RTL8188FU / 8188FTV | `0bda:f179` | yes | 15 | [rtl8188fufw.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8188fufw.bin) | no |
| RTL8192EU | `0bda:818b`, `2357:0108` TP-Link TL-WN822N v4, `2357:0109` TP-Link, `2001:3319` D-Link DWA-131 rev E1 | yes | 127 | [rtl8192eu_nic.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8192eu_nic.bin) | no |
| RTL8192FU | `0bda:f192` Comfast CF-826F, `0bda:318b`, `0b05:18f1` ASUS USB-N13 rev C1, `7392:b722` Edimax | yes | 127 | [rtl8192fufw.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8192fufw.bin) | no |
| RTL8710BU (8188GU) | `0bda:b711`, `0bda:2005` TOTOLINK N150UA V5 / N150UA-B | yes | 15 | [rtl8710bufw_SMIC.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8710bufw_SMIC.bin), [rtl8710bufw_UMC.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8710bufw_UMC.bin) (both: chosen by the chip vendor) | no |
| RTL8723BU | `0bda:b720`, `7392:a611` Edimax | yes | 127 | [rtl8723bu_nic.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8723bu_nic.bin) | no |
| RTL8723AU | `0bda:8724`, `0bda:1724`, `0bda:0724` | no | - | [rtl8723aufw_A.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8723aufw_A.bin), [rtl8723aufw_B.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8723aufw_B.bin), [rtl8723aufw_B_NoBT.bin](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtlwifi/rtl8723aufw_B_NoBT.bin) | no |

- *Max AP clients* is what the driver reports to mac80211
  (`max_macid_num - 1`); for the RTL8188EU it is limited to 1 by `0002`.
- Firmware location on the Dwarf: the kernel also looks in
  `/lib/firmware-system/`, where the image keeps its firmware; `/lib/firmware`
  is a link to `/data/firmware`, on the data partition, and is left to the user.
  Without its firmware the module binds the device but the probe fails.
- The Dwarf image (v1.13.5.3315) already has most of the files above in
  `/lib/firmware-system/rtlwifi/`, compared with `firmware/rtlwifi/`:

  | File | Dwarf image | `firmware/rtlwifi/` |
  |---|---|---|
  | `rtl8188eufw.bin` | v11.1 | v28.0, **not tested on the Dwarf** |
  | `rtl8188fufw.bin`, `rtl8192eu_nic.bin`, `rtl8723aufw_A.bin`, `rtl8723aufw_B.bin`, `rtl8723aufw_B_NoBT.bin`, `rtl8723bu_nic.bin` | identical | identical |
  | `rtl8192fufw.bin`, `rtl8710bufw_SMIC.bin`, `rtl8710bufw_UMC.bin` | missing | included |

  All the tests on the Dwarf, and the patches `0003`-`0005`, were done with
  the v11.1 RTL8188EU firmware of the image: install only the missing files,
  don't replace the existing ones.
- The image has no `regulatory.db` either (`failed to load regulatory.db` in
  the kernel log at boot): `firmware/regulatory.db` and its signature go in
  `/lib/firmware-system/`. It is the 2023.09.01 release on purpose: the Dwarf
  kernel (6.1) only trusts the signing key of the former maintainer
  (`sforshee`), the later releases are signed by the new one (`wens`) and the
  kernel rejects them (`loaded regulatory.db is malformed or signature is
  missing/invalid`).
- The firmware files are unmodified copies from
  [linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/rtlwifi),
  where `WHENCE` lists all of them as "Redistributable". They are distributed
  under the Realtek licence in `firmware/rtlwifi/LICENCE.rtlwifi_firmware.txt`
  (from `LICENSES/` in linux-firmware): binary redistribution without
  modification is allowed, the copyright notice and disclaimer must be
  reproduced with the distribution, so install the licence file together with
  the firmware.
- `rtl8723bu_bt.bin` is not needed: the driver never enables Bluetooth, so the
  RTL8723BU always loads `rtl8723bu_nic.bin`.

### Build

The module must be built against the Dwarf kernel tree, inside the
mod-plugin-builder docker container, after the kernel has been prepared with
`./bootstrap.sh moddwarf kernel` and `./build moddwarf kernel`:

```
cd driver
./build.sh
```

The module is written to `driver/out/rtl8xxxu.ko`. `KDIR` and `TOOLCHAIN_BIN`
can be overridden from the environment.

### Install

The module goes in `updates/`, which takes precedence over the original
`rtl8xxxu.ko` of the image; the firmware missing from the image and the
regulatory database go in `/lib/firmware-system/` (see the notes above):

```
scp -O driver/out/rtl8xxxu.ko root@192.168.51.1:/lib/modules/6.1.15-rt7-moddwarf/updates/
ssh root@192.168.51.1 depmod -a
cd firmware
scp -O rtlwifi/rtl8192fufw.bin rtlwifi/rtl8710bufw_SMIC.bin rtlwifi/rtl8710bufw_UMC.bin \
    rtlwifi/LICENCE.rtlwifi_firmware.txt root@192.168.51.1:/lib/firmware-system/rtlwifi/
scp -O regulatory.db regulatory.db.p7s LICENSE.wireless-regdb root@192.168.51.1:/lib/firmware-system/
```

The root filesystem of the Dwarf is read only: `mount / -o remount,rw` first.

On the Dwarf, `iw list` must show `* AP` among the supported interface modes.

### Binary release

The aLabs image doesn't build the driver: it installs a binary release of this
repository, so the image always gets exactly the module and the files
published on GitHub.

```
make release
```

builds the module (`make module`: `driver/build.sh` run with `docker exec` in
the container that has the Dwarf kernel tree, `CONTAINER=nam` by default) and
packs `dist/alabs-mod-wifi-<version>-<platform>.tar.gz` and its `.sha256`
(`PLATFORM=moddwarf` by default, the only one supported for now; the image
downloads the archive of its own platform). It
refuses to run with uncommitted or untracked files: the archive records the
commit it was made from, whose sources are the sources of the module.

The archive is an overlay of the Dwarf root filesystem (owner root, final
paths and permissions), to be extracted with `tar -xpf` and followed by
`depmod`:

| Path | Content |
|---|---|
| `usr/lib/modules/6.1.15-rt7-moddwarf/updates/` | `rtl8xxxu.ko` |
| `usr/lib/firmware-system/rtlwifi/` | the firmware missing from the image and its licence |
| `usr/lib/firmware-system/` | `regulatory.db`, `regulatory.db.p7s` and their licence |
| `usr/bin/` | `wifi-ap` |
| `usr/lib/alabs-mod-wifi/` | `wifi-ap-helper`, `VERSION`, `LICENSE`, `BUILDINFO` (commit, kernel, vermagic, sha256 of the module) |
| `etc/systemd/system/` | `wifi-ap.path`, `wifi-ap.service`, enabled in `multi-user.target.wants/` |
| `etc/tmpfiles.d/` | `wifi-ap.conf` |
| `usr/lib/diagnostics-logs/providers.d/` | `50-wifi` |

To publish a version: update `VERSION`, commit, tag it `v<version>`, run
`make release`, push the tag and attach the two files of `dist/` to the GitHub
release of that tag.

## wifi-ap

```
wifi-ap on [-b]    start the access point
wifi-ap off [-b]   stop the access point and go back to client mode
wifi-ap status     print the current state
wifi-ap info       WiFi adapter information, as JSON
wifi-ap info --text   the same, as text
```

`info` (run as root) reports: USB device, chip and firmware version (from the
kernel log), driver and module path (`alabs-mod-wifi` when loaded from `updates/`),
MAC, supported modes, AP support and max clients, channels, current mode,
network, signal/bitrate or connected clients, and the number of recoveries
done by the driver patches (USB write and firmware load retries, resent and
lost beacons).

Data commands used by the mod-ui settings page (as root, JSON):

```
wifi-ap state          status, adapter info, client networks, access point settings
wifi-ap networks-set   save the client networks: JSON list on stdin, highest priority first
wifi-ap scan           visible networks (not while the access point is on)
wifi-ap ap-set         save the access point settings: JSON on stdin
wifi-ap names          configured network names, one per line (diagnostics redaction)
```

- `networks-set` takes `[{"ssid": "...", "password": null | "" | "..."}, ...]`:
  `null` keeps the stored key of an existing network, `""` is an open
  network. Passwords are stored as the PSK computed by wpa_passphrase
  (PBKDF2), never in clear; names with special characters are stored in hex.
  Entries of `/data/wpa_supplicant.conf` without an ssid (e.g. "any open
  network") are kept untouched. Hidden networks are not supported.
- `ap-set` takes `{"ssid", "password", "channel"}` and writes
  `/data/wifi-ap.conf` (shell syntax, values single-quoted), keeping its other
  settings; the channel must be one an AP can use (`ap_channels` of `info`).
- `scan` uses wpa_supplicant when it is running, `iw` otherwise (no client
  network configured yet).

`on`, `off` and `status` print exactly one line, so they can be called by the
HMI through the serial console:

| Output | Meaning |
|---|---|
| `on <ip> <ssid>` | access point running |
| `off <ip\|none> <ap\|noap> [<error>]` | client mode: `wlan0` address if connected, whether the adapter supports AP mode, error of the last `on`/`off` if it failed |
| `starting` / `stopping` | `on` / `off` in progress |
| `error <reason>` | the command failed (exit code 1) |

With `-b`, `on` and `off` run in background and answer `starting` /
`stopping` right away: the HMI waits only 200 ms for an answer, while starting
the access point takes a few seconds. `status` doesn't take the lock, so it
answers immediately also while `on`/`off` are running.

### Use from the HMI

The HMI serial console is logged in as the unprivileged `hmi` user. When
`wifi-ap on|off` is not run as root it only writes `on`/`off` to
`/run/wifi-ap/request` and answers `starting`/`stopping`; `wifi-ap.path`
notices the change and `wifi-ap.service` runs `wifi-ap request` as root.
`wifi-ap status` works as any user. A request not picked up within 10 s
(`wifi-ap.path` not running) is reported as
`off <ip> <ap|noap> request-not-processed`.

Install:

```
cp scripts/wifi-ap /usr/bin/
mkdir -p /usr/lib/alabs-mod-wifi
cp scripts/wifi-ap-helper VERSION /usr/lib/alabs-mod-wifi/
cp systemd/wifi-ap.path systemd/wifi-ap.service /etc/systemd/system/
cp tmpfiles.d/wifi-ap.conf /etc/tmpfiles.d/
systemd-tmpfiles --create /etc/tmpfiles.d/wifi-ap.conf
systemctl daemon-reload
systemctl enable wifi-ap.path
systemctl start wifi-ap.path      # systemd 219: no "enable --now"

```

`WIFI_AP_DEBUG=1` can also be set in `/data/wifi-ap.conf`, to get the debug
log for requests coming from the HMI.

Details are logged to the journal: `journalctl -t wifi-ap`.

- **AP mode**: the client units (`wpa-supplicant-wlan0`, `dhcpcd-wlan0`) are
  stopped and masked at runtime, `wpa_supplicant` runs in AP mode (`mode=2`,
  WPA2-PSK) on `192.168.60.1/24`, and `dnsmasq` is restarted through a runtime
  drop-in with a config that also serves DHCP on `wlan0`
  (`192.168.60.50-150`). The image files are not modified.
- **Client mode**: everything above is undone and the client units are started
  again (they only run if `/data/wpa_supplicant.conf` exists).
- Nothing is persistent: after a reboot `wlan0` is in client mode.

Optional settings in `/data/wifi-ap.conf`:

```
AP_SSID="moddwarf"
AP_PSK="moddwarf"     # WPA2 passphrase, 8..63 characters
AP_CHANNEL=6          # 2.4 GHz channel, 1..11
```

The default passphrase is the same on every device: change it.

### Connecting a phone

- mod-ui is at `http://192.168.60.1`. avahi also publishes the device name on
  the access point, so `http://moddwarf.local` works where the browser
  supports mDNS.
- The access point has no internet access (no gateway or DNS is announced):
  when the phone asks, choose to stay connected to the network.
- If the phone also knows a WiFi network with internet that is in range (e.g.
  the home network), it may switch to it on its own, typically while the
  screen is off. Disable the automatic connection to that network while using
  the Dwarf.
- A phone in power save stays connected (tested with the screen off for
  ~18 minutes); after `wifi-ap off` + `on` it reconnects on its own.

### Debugging

```
wifi-ap off
WIFI_AP_DEBUG=1 wifi-ap on
```

runs `wpa_supplicant` with debug output in `/run/wifi-ap/wpa_supplicant.log`
(kept after `wifi-ap off`). Useful lines:

```
grep -E "AP-STA|inactiv|deauth|disassoc" /run/wifi-ap/wpa_supplicant.log
```

The log grows quickly and lives in RAM: don't leave debug mode on.

## Licensing

| Files | Licence |
|---|---|
| `driver/` | GPL-2.0-only, as the Linux `rtl8xxxu` driver it comes from (`SPDX-License-Identifier` in each file); the patches in `driver/patches/` are derived work under the same licence |
| `scripts/`, `diagnostics/`, `systemd/`, `tmpfiles.d/`, `driver/build.sh` | GPL-2.0-only |
| `firmware/rtlwifi/*.bin` | Realtek licence, in `firmware/rtlwifi/LICENCE.rtlwifi_firmware.txt`: redistribution in binary form and without modification, with that copyright notice and disclaimer; no reverse engineering |
| `firmware/regulatory.db`, `firmware/regulatory.db.p7s` | ISC licence of wireless-regdb, in `firmware/LICENSE.wireless-regdb` |

The firmware and the regulatory database are not covered by the GPL: they are
third-party files, redistributed unmodified under their own licences.

- `firmware/rtlwifi/`: copies of `rtlwifi/` in
  [linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/rtlwifi)
  (main branch, 2026-10-16; `WHENCE` lists them as "Redistributable"), the
  licence is `LICENSES/LICENCE.rtlwifi_firmware.txt` of the same repository.
- `firmware/regulatory.db` and `.p7s`: from the
  [wireless-regdb](https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git)
  release 2023.09.01, the last one signed with the key the Dwarf kernel trusts
  (see *Supported chips*); the licence is its `LICENSE`.
- `firmware/SHA256SUMS` lists the checksums of all of them
  (`cd firmware && sha256sum -c SHA256SUMS`), to compare them with the
  upstream files.

When the image is built, each licence file is installed with its files:
`LICENCE.rtlwifi_firmware.txt` in `/lib/firmware-system/rtlwifi/`,
`LICENSE.wireless-regdb` in `/lib/firmware-system/` next to `regulatory.db`.
