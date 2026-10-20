#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the rtl8xxxu (v6.6 backport) module for the MOD Dwarf kernel 6.1.15-rt7-moddwarf.
#
# Run inside the mod-plugin-builder docker container, after
# "./bootstrap.sh moddwarf kernel" and "./build moddwarf kernel" have prepared the kernel tree.
#
#   KDIR           kernel source tree (default: buildroot moddwarf-kernel tree)
#   TOOLCHAIN_BIN  directory of the aarch64-modaudio-linux-gnu- toolchain

set -e

cd "$(dirname "${0}")"

KDIR=${KDIR:=$(ls -d /root/mod-workdir/moddwarf-kernel/build/linux-cbce1363d7f6a66636123dcae3de20db8c9429d2)}
TOOLCHAIN_BIN=${TOOLCHAIN_BIN:=/root/mod-workdir/moddwarf-new/toolchain/bin}
DWARF_CONFIG=dwarf/config-6.1.15-rt7-moddwarf

export PATH="${TOOLCHAIN_BIN}:${PATH}"
MAKE="make -C ${KDIR} ARCH=arm64 CROSS_COMPILE=aarch64-modaudio-linux-gnu- -j$(nproc)"

# the official Dwarf kernel is NOT built with mod-plugin-builder's linux.config:
# modules must be built against the config taken from the device (/proc/config.gz)
if ! cmp -s "${DWARF_CONFIG}" "${KDIR}/.config"; then
  cp "${DWARF_CONFIG}" "${KDIR}/.config"
  ${MAKE} olddefconfig
  ${MAKE} modules_prepare
fi

${MAKE} M="$(pwd)" CONFIG_RTL8XXXU=m modules

mkdir -p out
cp rtl8xxxu.ko out/
echo "Built: $(pwd)/out/rtl8xxxu.ko"
