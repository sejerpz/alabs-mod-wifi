# SPDX-License-Identifier: GPL-2.0-only
#
# alabs-mod-wifi binary release for the MOD Dwarf and the MOD Duo X
#
#   make module    build driver/out/<kernel>/rtl8xxxu.ko for the kernels of the
#                  platform, in the mod-plugin-builder docker container (see driver/build.sh)
#   make release   build the module and pack dist/alabs-mod-wifi-<version>-<platform>.tar.gz,
#                  an overlay of the device root filesystem, plus its .sha256
#   make clean     remove dist/
#
#   PLATFORM       moddwarf (default) or modduox; the archive name carries it, and
#                  the aLabs image downloads the archive of its own platform
#   CONTAINER      running container used to build the module (default: nam)
#   CONTAINER_DIR  this repository inside the container
#
# The release is made from a clean, committed tree: the archive records the
# commit, and the sources of that commit are the sources of the module (GPL).

VERSION       := $(shell cat VERSION)
PLATFORM      ?= moddwarf

# per platform: kernels of the image, firmware missing from it, regulatory database.
# The firmware already in /lib/firmware-system/rtlwifi/ is not replaced, see
# "Supported chips" in the README
ifeq ($(PLATFORM),moddwarf)
# image v1.13.5.3315
KVERS         := 6.1.15-rt7-moddwarf
FIRMWARE_ADD  := rtl8192fufw.bin rtl8710bufw_SMIC.bin rtl8710bufw_UMC.bin
REGDB         := yes
else ifeq ($(PLATFORM),modduox)
# image v1.13.5.3316: one kernel per board (gr-rk3399, cl-imx8mq), same firmware
# as the Dwarf image; kernels older than 4.15 don't load regulatory.db (and the
# image has no crda): they keep the world regulatory domain
KVERS         := 4.4.167-rt176-duox 4.9.123-rt125-duox
FIRMWARE_ADD  := rtl8192fufw.bin rtl8710bufw_SMIC.bin rtl8710bufw_UMC.bin
REGDB         := no
else
$(error PLATFORM=$(PLATFORM) is not supported (supported: moddwarf modduox))
endif

NAME          := alabs-mod-wifi-$(VERSION)-$(PLATFORM)
DIST          := dist
STAGE         := $(DIST)/stage
ARCHIVE       := $(DIST)/$(NAME).tar.gz

CONTAINER     ?= nam
CONTAINER_DIR ?= /root/source/alabs-mod-wifi

MODINFO       := $(shell command -v modinfo 2>/dev/null || echo /usr/sbin/modinfo)
# module built for a kernel
module = driver/out/$(1)/rtl8xxxu.ko

.PHONY: module release check-clean clean

module:
	docker exec -e PLATFORM=$(PLATFORM) $(CONTAINER) bash -c 'cd $(CONTAINER_DIR)/driver && ./build.sh'

check-clean:
	@git diff --quiet HEAD -- || { echo "uncommitted changes: commit them first, the release records the commit"; exit 1; }
	@[ -z "$$(git ls-files --others --exclude-standard)" ] || { echo "untracked files: commit or remove them first"; exit 1; }

release: check-clean module
	@for k in $(KVERS); do \
		vermagic="$$($(MODINFO) -F vermagic driver/out/$$k/rtl8xxxu.ko)"; \
		case "$$vermagic" in "$$k "*) ;; *) echo "wrong vermagic for $$k: $$vermagic"; exit 1;; esac; \
	done
	rm -rf $(STAGE) $(ARCHIVE) $(ARCHIVE).sha256
	$(foreach k,$(KVERS),install -D -m 644 $(call module,$(k)) $(STAGE)/usr/lib/modules/$(k)/updates/rtl8xxxu.ko;)
	install -D -m 644 -t $(STAGE)/usr/lib/firmware-system/rtlwifi \
		$(addprefix firmware/rtlwifi/,$(FIRMWARE_ADD)) firmware/rtlwifi/LICENCE.rtlwifi_firmware.txt
ifeq ($(REGDB),yes)
	install -D -m 644 -t $(STAGE)/usr/lib/firmware-system \
		firmware/regulatory.db firmware/regulatory.db.p7s firmware/LICENSE.wireless-regdb
endif
	install -D -m 755 scripts/wifi-ap               $(STAGE)/usr/bin/wifi-ap
	install -D -m 755 scripts/wifi-ap-helper        $(STAGE)/usr/lib/alabs-mod-wifi/wifi-ap-helper
	install -D -m 644 -t $(STAGE)/usr/lib/alabs-mod-wifi VERSION LICENSE
	install -D -m 644 -t $(STAGE)/etc/systemd/system systemd/wifi-ap.path systemd/wifi-ap.service
	mkdir -p $(STAGE)/etc/systemd/system/multi-user.target.wants
	ln -s /etc/systemd/system/wifi-ap.path  $(STAGE)/etc/systemd/system/multi-user.target.wants/wifi-ap.path
	install -D -m 644 tmpfiles.d/wifi-ap.conf      $(STAGE)/etc/tmpfiles.d/wifi-ap.conf
	install -D -m 755 diagnostics/50-wifi          $(STAGE)/usr/lib/diagnostics-logs/providers.d/50-wifi
	{ echo "name=alabs-mod-wifi"; \
	  echo "version=$(VERSION)"; \
	  echo "commit=$$(git rev-parse HEAD)"; \
	  echo "describe=$$(git describe --tags --always)"; \
	  echo "source=https://github.com/sejerpz/alabs-mod-wifi/tree/$$(git rev-parse HEAD)"; \
	  echo "platform=$(PLATFORM)"; \
	  for k in $(KVERS); do \
	    echo "kernel=$$k"; \
	    echo "vermagic=$$($(MODINFO) -F vermagic driver/out/$$k/rtl8xxxu.ko)"; \
	    echo "module_sha256=$$(sha256sum driver/out/$$k/rtl8xxxu.ko | cut -d' ' -f1)"; \
	  done; \
	} > $(STAGE)/usr/lib/alabs-mod-wifi/BUILDINFO
	chmod 644 $(STAGE)/usr/lib/alabs-mod-wifi/BUILDINFO
	find $(STAGE) -type d -exec chmod 755 {} +
	tar -C $(STAGE) --owner=0 --group=0 --numeric-owner --sort=name \
		--mtime="@$$(git log -1 --format=%ct)" -cf - . | gzip -9n > $(ARCHIVE)
	cd $(DIST) && sha256sum $(NAME).tar.gz > $(NAME).tar.gz.sha256
	rm -rf $(STAGE)
	@git describe --tags --exact-match >/dev/null 2>&1 || echo "note: HEAD is not tagged, tag it v$(VERSION) for the GitHub release"
	@echo "Release: $(ARCHIVE)"
	@cat $(ARCHIVE).sha256

clean:
	rm -rf $(DIST)
