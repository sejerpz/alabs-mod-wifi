# USB Wi-Fi dongles: manual setup

The MOD Dwarf has no built-in Wi-Fi, but it can use a **USB Wi-Fi dongle** plugged into its USB
host port. This page explains how to check whether a dongle is supported, and how to install and
configure the driver **by hand**, from a shell on the Dwarf.

The Starless image already includes the driver, and the Wi-Fi is configured from the web
interface: see the [Wi-Fi page](https://github.com/sejerpz/alabs-mod-custom-images/wiki/WiFi) of
the wiki. This page is for development, and for images that don't include the driver.

> **Experimental.** Wi-Fi on the Dwarf is not an official MOD feature. Network traffic uses some
> CPU. Test your pedalboards with Wi-Fi active before relying on it on stage.
>
> So far the driver has been tested with the **Realtek RTL8188EUS (`0bda:8179`)** only. The other
> IDs come from the driver's list of devices tested upstream, not on the Dwarf.

## 1. Find out which chipset your dongle uses

Every USB device has an ID made of two hex numbers, `vendor:product` (for example `0bda:8179`).
The ID tells you which chipset is inside, whatever brand is printed on the dongle.

### On a Linux PC

Plug the dongle into the PC and run:

```bash
lsusb
```

Look for the new line, for example:

```
Bus 001 Device 007: ID 0bda:8179 Realtek Semiconductor Corp. RTL8188EUS 802.11n Wireless Network Adapter
```

Here the ID is `0bda:8179`. To see which driver the PC uses for it (useful to identify the chip family):

```bash
lsusb -t
```

### On the Dwarf

Plug the dongle into the Dwarf's USB host port, connect to the Dwarf via ssh (see
[Developer mode](https://github.com/sejerpz/alabs-mod-custom-images/wiki/Developer-mode-features)),
and run:

```bash
lsusb
```

Then ask the kernel whether a driver for each device exists:

```bash
for id in $(lsusb | awk '{print $6}'); do v=${id%:*}; p=${id#*:}; m=$(grep -i "usb:v${v}p${p}" /lib/modules/$(uname -r)/modules.alias | awk '{print $3}' | sort -u | tr '\n' ' '); echo "$id ${m:-no driver}"; done
```

Example output with the driver installed:

```
1d6b:0002 no driver
0bda:8179 rtl8xxxu
```

(`1d6b:*` are the Dwarf's own USB controllers, ignore them.)

- **`rtl8xxxu`**: supported by the driver of this repository.
- **another driver name** (for example `mt7601u`, `rt2800usb`, `ath9k_htc`): the Dwarf kernel already
  has a driver, but its firmware is probably missing on the Dwarf. It is not covered by this repository.
- **`no driver`**: not supported.

The supported IDs, with the known commercial devices, are listed in
[Supported chips](../README.md#supported-chips).

> Be careful when buying: the same commercial model is sometimes sold with different chipsets
> (look for "v1", "v2", "v3" on the label). Always check the ID.

## 2. Install the driver

The module is built for the Dwarf kernel `6.1.15-rt7-moddwarf`
(see [Building](driver-backport.md#building)). Files to install:

| File | Installed to |
|---|---|
| `driver/out/rtl8xxxu.ko` | `/lib/modules/6.1.15-rt7-moddwarf/updates/` |
| `firmware/rtlwifi/rtl8192fufw.bin`, `rtl8710bufw_SMIC.bin`, `rtl8710bufw_UMC.bin` and the licence | `/lib/firmware-system/rtlwifi/` |
| `firmware/regulatory.db`, `regulatory.db.p7s` and the licence | `/lib/firmware-system/` |

The other firmware files are already in the image, in `/lib/firmware-system/rtlwifi/`:
don't replace them (see *Supported chips* in the README). `/lib/firmware` is a
link to `/data/firmware`, on the data partition: don't put the firmware there.

First check that your Dwarf runs the right kernel:

```bash
uname -r
```

It must print `6.1.15-rt7-moddwarf`. With any other kernel the module will not load.

1. **Unplug the dongle.**
2. On the Dwarf, make the root filesystem writable and create the directories:

   ```bash
   mount / -o remount,rw
   mkdir -p /lib/modules/$(uname -r)/updates
   ```

3. From your PC, in the repository root, copy the files:

   ```bash
   scp -O driver/out/rtl8xxxu.ko root@192.168.51.1:/lib/modules/6.1.15-rt7-moddwarf/updates/
   scp -O firmware/rtlwifi/rtl8192fufw.bin firmware/rtlwifi/rtl8710bufw_SMIC.bin firmware/rtlwifi/rtl8710bufw_UMC.bin \
       firmware/rtlwifi/LICENCE.rtlwifi_firmware.txt root@192.168.51.1:/lib/firmware-system/rtlwifi/
   scp -O firmware/regulatory.db firmware/regulatory.db.p7s firmware/LICENSE.wireless-regdb root@192.168.51.1:/lib/firmware-system/
   ```

4. On the Dwarf, update the module list and load the driver:

   ```bash
   depmod -a
   modprobe rtl8xxxu
   ```

The original kernel driver is not deleted: the version in `updates/` simply takes precedence.
`modinfo -n rtl8xxxu` must print `.../updates/rtl8xxxu.ko`.

To use the access point and the web interface settings, install the `wifi-ap` scripts too:
see [Use from the HMI](../README.md#use-from-the-hmi).

### Check

Plug the dongle in, wait a few seconds, then:

```bash
dmesg | tail -15
iw dev
```

`dmesg` should show the chip and the firmware being loaded, for example:

```
usb 2-1: RTL8188EU rev D (TSMC) romver 0, 1T1R, TX queues 2, WiFi=1, BT=0, GPS=0, HI PA=0
usb 2-1: rtl8xxxu: Loading firmware rtlwifi/rtl8188eufw.bin
usb 2-1: Firmware revision 11.1 (signature 0x88e1)
```

and `iw dev` should list an interface named **`wlan0`**.

## 3. Connect to your Wi-Fi network

The client units of the image (`wpa-supplicant-wlan0` and `dhcpcd-wlan0`) start only when
`/data/wpa_supplicant.conf` exists. Create it on the Dwarf with your network name and password:

```bash
cp /etc/wpa_supplicant.conf /data/wpa_supplicant.conf
wpa_passphrase "YourNetworkName" "YourPassword" | grep -v '#psk=' >> /data/wpa_supplicant.conf
echo "country=IT" >> /data/wpa_supplicant.conf
sync
```

`grep -v` removes the line where `wpa_passphrase` writes the password in clear text.
Replace `IT` with your country's two-letter code: it enables the right channels and power
limits for your country.

Then unplug and replug the dongle, or reboot. The Dwarf connects to the network and gets an
IP address automatically. Check with:

```bash
iw dev wlan0 link
ip addr show wlan0
```

The `inet` line shows the Dwarf's address on your Wi-Fi network (for example `192.168.0.151`).
You can then open the MOD web interface from any device on the same network at
`http://<that address>`.

The USB cable connection (`192.168.51.1`) keeps working as before.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `modprobe rtl8xxxu` fails with `Invalid module format` | The module does not match your kernel: check `uname -r`. |
| No `wlan0`, `dmesg` shows `probe of ... failed` | Unplug and replug the dongle. Some dongles need more current than the port gives: try a powered USB hub. |
| `Direct firmware load for rtlwifi/... failed with error -2` | Firmware missing: copy the file named in the message from `firmware/rtlwifi/` to `/lib/firmware-system/rtlwifi/`. |
| `cfg80211: failed to load regulatory.db` | Harmless. Copy `firmware/regulatory.db*` to `/lib/firmware-system/` to install the regulatory database. |
| `wlan0` exists but does not connect | Check SSID and password in `/data/wpa_supplicant.conf`. `iw dev wlan0 scan \| grep SSID` lists the networks the dongle sees. |
| Audio dropouts with Wi-Fi active | Wi-Fi traffic uses CPU. Avoid heavy transfers while playing, or unplug the dongle on stage. |

## Uninstall

On the Dwarf, with the dongle unplugged:

```bash
mount / -o remount,rw
rm -f /lib/modules/$(uname -r)/updates/rtl8xxxu.ko
depmod -a
```

Technical details on how the driver was built:
[How USB Wi-Fi support was added to the MOD Dwarf](driver-backport.md).
