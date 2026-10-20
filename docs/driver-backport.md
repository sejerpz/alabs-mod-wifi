# How USB Wi-Fi support was added to the MOD Dwarf

This page explains how USB Wi-Fi dongles based on Realtek chips were made to work on the
MOD Dwarf (kernel `6.1.15-rt7-moddwarf`), what did not work, and how to rebuild the driver.

To check a dongle and install the driver by hand, see [USB Wi-Fi dongles](usb-wifi-dongles.md).
End users should read the [Wi-Fi page](https://github.com/sejerpz/alabs-mod-custom-images/wiki/WiFi) of the wiki instead.

## Summary

- The driver is **`rtl8xxxu` taken from Linux 6.6**, backported to 6.1 and built as an
  out-of-tree module.
- It is installed in `/lib/modules/6.1.15-rt7-moddwarf/updates/`, so it takes precedence over
  the stock `rtl8xxxu` without replacing it. The kernel image is not touched.
- Tested hardware: **Realtek RTL8188EUS, USB ID `0bda:8179`**: association, DHCP and traffic
  work.
- Sources, patches and build script: `driver/` (see [Repository layout](#repository-layout)).

## Why a backport was needed

The test dongle was a Realtek RTL8188EUS (`0bda:8179`). In kernel 6.1 there are two possible
drivers for it, and neither works:

| Driver | Problem on the Dwarf |
|---|---|
| `rtl8xxxu` (stock 6.1) | The RTL8188EU support exists in the code, but `0bda:8179` is not in its USB ID table, not even with `CONFIG_RTL8XXXU_UNTESTED`. The module loads and never binds to the dongle. |
| `r8188eu` (staging, 6.1) | Binds and loads the firmware, then **freezes the whole Dwarf** (ssh, USB networking, everything) a few seconds later. No Oops is printed. Disabling power saving (`rtw_power_mgnt=0 rtw_ips_mode=0 rtw_led_enable=0`) does not help. This is most likely a busy-wait loop that starves the system on the `PREEMPT_RT` kernel. Unplugging the dongle unfreezes the device. |

In Linux 6.3+ the RTL8188EU support in `rtl8xxxu` was reworked and `0bda:8179` was added to the
tested ID table. `r8188eu` was later removed from staging in favour of `rtl8xxxu`. The 6.6
version of `rtl8xxxu` was therefore backported.

## Pitfall: the official kernel config is not the one in mod-plugin-builder

The official Dwarf kernel is **not** built with
`mod-plugin-builder/kernel/board/moddwarf/linux.config`. The running kernel config
(`/proc/config.gz`) differs, notably:

- `CONFIG_JUMP_LABEL=y` is set on the device;
- several ARM64 options (PAN, SVE, PTR_AUTH, MTE, …), `SCHED_CORE`, `RAS` and `USB_IPHETH` are not set.

These options change the layout of `struct module`. The version string is the same, so the
module loads, but the kernel crashes with an Oops in `mod_sysfs_setup` when a module built with
the repository config is loaded.

**Modules for the Dwarf must be built with the config taken from the device.** It is saved in
`driver/dwarf/config-6.1.15-rt7-moddwarf`. To get it again:

```bash
scp -O root@192.168.51.1:/proc/config.gz .
```

The kernel *sources* do match: `rtl8xxxu.ko` rebuilt from the sources below with the device
config is identical, instruction by instruction, to the official one.

## Pitfall: the kernel commit is no longer on any branch

`kernel/configs/moddwarf_defconfig` points to commit `cbce1363d7f6a66636123dcae3de20db8c9429d2`
of `moddevices/linux-mainline`. That repository has moved to `mod-audio/linux-mainline`, and the
commit is no longer reachable from any branch. Buildroot's git download fails with
`fatal: not a tree object`.

GitHub still serves the commit as an archive. Put it in the buildroot download directory with
the name buildroot expects:

```bash
S=cbce1363d7f6a66636123dcae3de20db8c9429d2
wget https://github.com/mod-audio/linux-mainline/archive/$S.tar.gz -O src.tar.gz
tar xzf src.tar.gz && mv linux-mainline-$S linux-$S
tar czf $WORKDIR/download/linux-$S.tar.gz linux-$S
```

The `git@github.com:` URL also needs an ssh key. Inside a container without one, either use
the archive above or run
`git config --global url."https://github.com/".insteadOf git@github.com:`.

## Changes to the 6.6 driver

The 6.6 sources are used with the patches in `driver/patches/`. The first one,
`0001-rtl8xxxu-build-on-6.1-and-retry-usb-writes.patch`, is the one that makes the driver work on 6.1:

1. **`wake_tx_queue`**: `ieee80211_handle_wake_tx_queue` does not exist in 6.1. It became
   mandatory in 6.2. The `.wake_tx_queue` op is now set only on kernels >= 6.2. On 6.1, mac80211
   uses the legacy `.tx` path, which the driver implements.
2. **USB write retries**: `rtl8xxxu_writeN()` gave up at the first failed control transfer.
   During one test, the firmware upload failed once at block `0x1f00` (`probe ... failed with
   error -11`). Each block is now retried up to 5 times, and the USB error code is logged.

Nothing else was needed to run the driver on 6.1. The other patches (experimental AP mode for the
RTL8188EU, firmware download retries, beacon fixes) are described in the [README](../README.md#driver).

The module compiles without warnings and only depends on `mac80211`
and `cfg80211`, both already on the device. Every symbol it needs is exported by the running
kernel.

## Building

The build runs inside the mod-plugin-builder docker container.

1. Prepare the kernel tree once (see [Build a custom image](https://github.com/sejerpz/alabs-mod-custom-images/wiki/Build-a-custom-image)
   for the container setup, and the pitfall above for the kernel archive):

   ```bash
   cd mod-plugin-builder
   ./bootstrap.sh moddwarf kernel
   ./build moddwarf kernel
   ```

2. Build the module:

   ```bash
   cd driver
   ./build.sh
   ```

   `build.sh` copies the device config into the kernel tree (`olddefconfig` + `modules_prepare`
   if it changed), builds the module and writes `driver/out/rtl8xxxu.ko`. Override `KDIR` and
   `TOOLCHAIN_BIN` if your paths differ.

Check the result:

```bash
strings driver/out/rtl8xxxu.ko | grep vermagic
```

It must print `vermagic=6.1.15-rt7-moddwarf SMP preempt_rt mod_unload aarch64`.

## Installing during development

```bash
# on the Dwarf, dongle unplugged
mount / -o remount,rw
mkdir -p /lib/modules/6.1.15-rt7-moddwarf/updates /lib/firmware/rtlwifi

# from the PC
scp -O driver/out/rtl8xxxu.ko root@192.168.51.1:/lib/modules/6.1.15-rt7-moddwarf/updates/
scp -O firmware/rtlwifi/* root@192.168.51.1:/lib/firmware/rtlwifi/
scp -O firmware/regulatory.db firmware/regulatory.db.p7s root@192.168.51.1:/lib/firmware/

# on the Dwarf
depmod -a
modinfo -n rtl8xxxu      # must print .../updates/rtl8xxxu.ko
modprobe rtl8xxxu
```

Plug the dongle in and check `dmesg`, `iw dev` and `ip addr show wlan0`.

To revert, delete `updates/rtl8xxxu.ko` and run `depmod -a`.

## Repository layout

```
driver/
├── rtl8xxxu_*.c, *.h, Makefile        driver sources from Linux v6.6, with the patches applied
├── patches/                            changes against v6.6
├── dwarf/config-6.1.15-rt7-moddwarf    kernel config of the official Dwarf kernel
└── build.sh                            build script (run inside the docker container)
firmware/                               firmware from linux-firmware, regulatory db from wireless-regdb
```

The rest of the repository (access point scripts, systemd units, diagnostics) is described in
the [README](../README.md#layout).

## Sources

- Driver: `drivers/net/wireless/realtek/rtl8xxxu/` from Linux `v6.6`
- Firmware: `rtlwifi/` from [linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git)
- Regulatory database: [wireless-regdb](https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git)
