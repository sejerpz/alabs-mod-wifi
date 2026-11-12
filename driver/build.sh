#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the rtl8xxxu (v6.6 backport) module for the kernels of a MOD platform.
#
#   PLATFORM=moddwarf  kernel 6.1.15-rt7-moddwarf (default)
#   PLATFORM=modduox   kernels 4.4.167-rt176-duox (gr-rk3399 board) and
#                      4.9.123-rt125-duox (cl-imx8mq board): the Duo X image
#                      has both and boots the one of its board
#
# Run inside the mod-plugin-builder docker container. For moddwarf, after
# "./bootstrap.sh moddwarf kernel" and "./build moddwarf kernel" have prepared the
# kernel tree; for modduox the kernel sources (mod-audio/linux-rk3399 and
# mod-audio/linux-imx) are downloaded in ${WORKDIR}/modduox-kernel on the first run.
#
#   KDIR           kernel source tree, moddwarf only (default: buildroot moddwarf-kernel tree)
#   TOOLCHAIN_BIN  directory of the aarch64-modaudio-linux-gnu- toolchain
#   WORKDIR        mod-plugin-builder workdir (default: /root/mod-workdir)
#
# Output: out/<kernel version>/rtl8xxxu.ko

set -e

cd "$(dirname "${0}")"

PLATFORM=${PLATFORM:=moddwarf}
WORKDIR=${WORKDIR:=/root/mod-workdir}
TOOLCHAIN_BIN=${TOOLCHAIN_BIN:=${WORKDIR}/moddwarf-new/toolchain/bin}

export PATH="${TOOLCHAIN_BIN}:${PATH}"

# extra make arguments of the kernel build
KMAKE_ARGS=

# build_module <kernel version> <kernel tree> <config taken from the device>
build_module() {
  local kver=${1} kdir=${2} config=${3}
  local make="make -C ${kdir} ARCH=arm64 CROSS_COMPILE=aarch64-modaudio-linux-gnu- -j$(nproc) ${KMAKE_ARGS}"

  # the official kernels are NOT built with mod-plugin-builder's linux.config:
  # modules must be built against the config taken from the device (/proc/config.gz)
  if ! cmp -s "${config}" "${kdir}/.config.device"; then
    cp "${config}" "${kdir}/.config"
    ${make} olddefconfig
    # the options set must be exactly the ones of the device
    if ! diff <(grep '^CONFIG_' "${config}") <(grep '^CONFIG_' "${kdir}/.config"); then
      echo "the kernel tree ${kdir} changes the config of the device"
      exit 1
    fi
    ${make} modules_prepare
    cp "${config}" "${kdir}/.config.device"
  fi

  local release=$(${make} -s kernelrelease)
  if [ "${release}" != "${kver}" ]; then
    echo "kernel tree ${kdir} is ${release}, not ${kver}"
    exit 1
  fi

  # objects of the previous kernel (not "make clean": it removes out/ too)
  rm -f -- *.o *.ko *.mod *.mod.c .*.cmd Module.symvers modules.order
  ${make} M="$(pwd)" CONFIG_RTL8XXXU=m modules

  mkdir -p "out/${kver}"
  cp rtl8xxxu.ko "out/${kver}/"
  echo "Built: $(pwd)/out/${kver}/rtl8xxxu.ko"
}

# fetch_kernel <github repository> <commit> [<rt patch path> <sha256>]: source tree of
# a Duo X kernel, with the PREEMPT_RT patch from kernel.org when it is not in the
# repository (it changes the layout of the kernel structures).
# The official kernels have CONFIG_EXPERT=y without CONFIG_DEBUG_KERNEL: the
# "select DEBUG_KERNEL" of EXPERT was not in the tree they were built from
# (with it, DEBUG_PREEMPT changes the preempt_count inlines of the module)
fetch_kernel() {
  local repo=${1} commit=${2} rt_patch=${3} rt_sha256=${4}
  local dir="${WORKDIR}/modduox-kernel/${repo#*/}-${commit}"

  if [ ! -f "${dir}/Makefile" ]; then
    mkdir -p "${WORKDIR}/modduox-kernel"
    curl -fL "https://codeload.github.com/${repo}/tar.gz/${commit}" | tar -xz -C "${WORKDIR}/modduox-kernel" >&2
    # no .git: the release must not get a "+" from scripts/setlocalversion
    touch "${dir}/.scmversion"
    sed -i '/^menuconfig EXPERT/,/help/{/select DEBUG_KERNEL/d}' "${dir}/init/Kconfig"
  fi
  if [ -n "${rt_patch}" ] && [ ! -f "${dir}/.rt-patched" ]; then
    local file="${WORKDIR}/modduox-kernel/$(basename "${rt_patch}")"
    curl -fL -o "${file}" "https://cdn.kernel.org/pub/linux/kernel/projects/rt/${rt_patch}" >&2
    echo "${rt_sha256}  ${file}" | sha256sum -c --quiet >&2
    xz -dc "${file}" | patch -d "${dir}" -p1 -f -s >&2
    touch "${dir}/.rt-patched"
  fi
  echo "${dir}"
}

case "${PLATFORM}" in
moddwarf)
  KDIR=${KDIR:=$(ls -d ${WORKDIR}/moddwarf-kernel/build/linux-cbce1363d7f6a66636123dcae3de20db8c9429d2)}
  build_module 6.1.15-rt7-moddwarf "${KDIR}" moddwarf/config-6.1.15-rt7-moddwarf
  ;;
modduox)
  # host tools of 4.x kernels (dtc) don't link with gcc >= 10 without -fcommon;
  # the gcc 9 warnings unknown to the gcc 4.9 the kernels were built with must
  # not stop the build (scripts/gcc-wrapper.py of the rk3399 tree)
  KMAKE_ARGS="HOSTCFLAGS=-fcommon CC=aarch64-modaudio-linux-gnu-gcc"
  # heads of the branches of the Duo X kernels (last commits: Jul 2023, the image
  # v1.13.5.3316 kernels were built in Oct 2024). linux-rk3399 develop-4.4-rt176
  # has the RT patch, linux-imx rel_imx_4.9.123_2.3.0_8mm_ga-duox has not: the
  # 4.9.146-rt125 patch applies to it without conflicts, and gives the "-rt125"
  # of the official kernel
  build_module 4.4.167-rt176-duox \
    "$(fetch_kernel mod-audio/linux-rk3399 6fd55d50ceca41667fc1deab3c416bbb4d833f61)" \
    modduox/config-4.4.167-rt176-duox
  build_module 4.9.123-rt125-duox \
    "$(fetch_kernel mod-audio/linux-imx 2b67b871ada15624dd70662fc02b510eefc495b3 \
       4.9/older/patch-4.9.146-rt125.patch.xz 925106e44f4bd5213bd38d29bcc0cfdda670fca20600357b15ac576d286ab445)" \
    modduox/config-4.9.123-rt125-duox
  ;;
*)
  echo "PLATFORM=${PLATFORM} is not supported (supported: moddwarf modduox)"
  exit 1
  ;;
esac
