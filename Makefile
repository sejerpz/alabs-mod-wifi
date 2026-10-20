# SPDX-License-Identifier: GPL-2.0-only
#
# alabs-mod-wifi binary release for the MOD Dwarf
#
#   make module    build driver/out/rtl8xxxu.ko in the docker container that
#                  has the Dwarf kernel tree (see driver/build.sh)
#   make release   build the module and pack dist/alabs-mod-wifi-<version>-<platform>.tar.gz,
#                  an overlay of the device root filesystem, plus its .sha256
#   make clean     remove dist/
#
#   PLATFORM       moddwarf (default); the archive name carries it, and the aLabs
#                  image downloads the archive of its own platform
#   CONTAINER      running container used to build the module (default: nam)
#   CONTAINER_DIR  this repository inside the container
#
# The release is made from a clean, committed tree: the archive records the
# commit, and the sources of that commit are the sources of the module (GPL).

VERSION       := $(shell cat VERSION)
PLATFORM      ?= moddwarf

# per platform: kernel of the image and firmware missing from it
ifeq ($(PLATFORM),moddwarf)
# image v1.13.5.3315: the firmware already in /lib/firmware-system/rtlwifi/ is
# not replaced, see "Supported chips" in the README
KVER          := 6.1.15-rt7-moddwarf
FIRMWARE_ADD  := rtl8192fufw.bin rtl8710bufw_SMIC.bin rtl8710bufw_UMC.bin
else
$(error PLATFORM=$(PLATFORM) is not supported yet (supported: moddwarf))
endif

NAME          := alabs-mod-wifi-$(VERSION)-$(PLATFORM)
DIST          := dist
STAGE         := $(DIST)/stage
ARCHIVE       := $(DIST)/$(NAME).tar.gz

CONTAINER     ?= nam
CONTAINER_DIR ?= /root/source/alabs-mod-wifi

MODINFO       := $(shell command -v modinfo 2>/dev/null || echo /usr/sbin/modinfo)
MODULE        := driver/out/rtl8xxxu.ko

.PHONY: module release check-clean clean

module:
	docker exec -e PLATFORM=$(PLATFORM) $(CONTAINER) bash -c 'cd $(CONTAINER_DIR)/driver && ./build.sh'

check-clean:
	@git diff --quiet HEAD -- || { echo "uncommitted changes: commit them first, the release records the commit"; exit 1; }
	@[ -z "$$(git ls-files --others --exclude-standard)" ] || { echo "untracked files: commit or remove them first"; exit 1; }

release: check-clean module
	@vermagic="$$($(MODINFO) -F vermagic $(MODULE))"; \
	case "$$vermagic" in "$(KVER) "*) ;; *) echo "wrong vermagic: $$vermagic"; exit 1;; esac
	rm -rf $(STAGE) $(ARCHIVE) $(ARCHIVE).sha256
	install -D -m 644 $(MODULE)                     $(STAGE)/usr/lib/modules/$(KVER)/updates/rtl8xxxu.ko
	install -D -m 644 -t $(STAGE)/usr/lib/firmware-system/rtlwifi \
		$(addprefix firmware/rtlwifi/,$(FIRMWARE_ADD)) firmware/rtlwifi/LICENCE.rtlwifi_firmware.txt
	install -D -m 644 -t $(STAGE)/usr/lib/firmware-system \
		firmware/regulatory.db firmware/regulatory.db.p7s firmware/LICENSE.wireless-regdb
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
	  echo "kernel=$(KVER)"; \
	  echo "vermagic=$$($(MODINFO) -F vermagic $(MODULE))"; \
	  echo "module_sha256=$$(sha256sum $(MODULE) | cut -d' ' -f1)"; \
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
