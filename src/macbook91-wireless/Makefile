# SPDX-License-Identifier: GPL-2.0-or-later
#
# Out-of-tree build of brcmfmac (with its vendor modules brcmfmac-wcc, -cyw and
# -bca) and hci_uart for the MacBook9,1 (BCM4350 WLAN, BCM4350C0 Bluetooth).
#
# The modules keep their in-tree names. DKMS installs them under
# /lib/modules/<kver>/updates/, which depmod prefers over kernel/, so they
# shadow the stock drivers. Removing the DKMS module and running depmod
# restores the stock drivers with no other change.
#
# All four brcmfmac modules are built because the patched brcmfmac changes
# struct brcmf_bus and exports a new symbol: a stock vendor module next to it
# would not match. brcmutil and btbcm stay the kernel's own.
#
# Nothing under series/ is tracked in the project's repository:
# packaging/fetch-upstream.sh assembles one tree per kernel series, series/<S>/
# (kernel.org stable files from packaging/files.list, patches/ applied, two
# Kbuild overlays), lists the series in KERNEL-SERIES and checks every tree
# against packaging/upstream.lock. This Makefile never fetches anything, so a
# DKMS rebuild during a kernel upgrade runs offline.
#
# The series to build is the one of the target kernel (UTS_RELEASE in its
# utsrelease.h). A kernel of a series that is not listed in KERNEL-SERIES is
# skipped with a message and a zero exit status: it keeps its stock drivers.
# dkms.conf limits DKMS to the listed series in the first place; this covers a
# manual build.
#
# Messages (house text HIG): "macbook91-wireless: error: text" and
# "macbook91-wireless: note: text" on stderr, hints indented below. DKMS shows
# the output of a failed build as it is.

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)
PKGVER ?= 0

# Kernel series of the target (X.Y of UTS_RELEASE), and the series this tree
# carries (KERNEL-SERIES, one per line).
SERIES  := $(shell sed -n 's/.*UTS_RELEASE "\([0-9]*\.[0-9]*\).*/\1/p' $(KDIR)/include/generated/utsrelease.h 2>/dev/null)
SHIPPED := $(shell cat $(PWD)/KERNEL-SERIES 2>/dev/null)
ifneq ($(and $(SERIES),$(filter $(SERIES),$(SHIPPED))),)
  BUILD := yes
endif

TREE := $(PWD)/series/$(SERIES)
WLAN := $(TREE)/kernel/drivers/net/wireless/broadcom/brcm80211
BT   := $(TREE)/kernel/drivers/bluetooth
OUT  := $(PWD)/build

# Source identity, baked into the modules (modinfo macbook91_wireless, and
# MODULE_VERSION of brcmfmac): the package version and the start of the hash
# of the series' UPSTREAM.sha256, which is what packaging/upstream.lock records
# as derived:tree of the series' tag. The verifier compares it with the loaded
# module. Another series changes only its own modules' identity.
SRCID := $(shell sha256sum $(TREE)/UPSTREAM.sha256 2>/dev/null | cut -c1-16)
ID    := $(PKGVER)+$(SRCID)

# The compiler family comes from the target kernel's .config: a clang-built
# kernel (CachyOS) takes clang-only flags, which GCC rejects.
KCONFIG := $(KDIR)/.config
ifeq ($(shell grep -qx 'CONFIG_CC_IS_CLANG=y' $(KCONFIG) 2>/dev/null && echo clang),clang)
  LLVM ?= 1
  export LLVM
endif

ifeq ($(BUILD),yes)
all: check check-build
	$(MAKE) -C $(KDIR) M=$(WLAN) MACBOOK91_ID=$(ID) modules
	$(MAKE) -C $(KDIR) M=$(BT) MACBOOK91_ID=$(ID) modules
# One flat directory for DKMS (dkms.conf: BUILT_MODULE_LOCATION="build/"), so
# it need not know the series.
	rm -rf $(OUT)
	mkdir -p $(OUT)
	cp $(WLAN)/brcmfmac/brcmfmac.ko $(WLAN)/brcmfmac/wcc/brcmfmac-wcc.ko \
	   $(WLAN)/brcmfmac/cyw/brcmfmac-cyw.ko $(WLAN)/brcmfmac/bca/brcmfmac-bca.ko \
	   $(BT)/hci_uart.ko $(OUT)/
else
all: check
	@echo "macbook91-wireless: note: the kernel is Linux $(SERIES), this tree carries $(SHIPPED); nothing built, the kernel keeps its stock drivers" >&2
endif

check:
	@test -r "$(PWD)/KERNEL-SERIES" || \
	  { echo "macbook91-wireless: error: the kernel sources are not assembled" >&2; \
	    echo "  This tree is a checkout, not a package. Assemble it once with: packaging/fetch-upstream.sh" >&2; \
	    echo "  A tree installed from the package is complete." >&2; exit 1; }
	@test -r "$(KDIR)/include/generated/utsrelease.h" || \
	  { echo "macbook91-wireless: error: cannot read $(KDIR)/include/generated/utsrelease.h" >&2; \
	    echo "  Install the headers of the kernel you build for, or set KDIR to its build directory" >&2; exit 1; }
	@test -n "$(SERIES)" || { echo "macbook91-wireless: error: no kernel series in $(KDIR)/include/generated/utsrelease.h" >&2; exit 1; }

# Only for a series this tree carries.
check-build:
	@test -r "$(TREE)/UPSTREAM.sha256" -a -r "$(BT)/Kbuild" || \
	  { echo "macbook91-wireless: error: series/$(SERIES) is not assembled" >&2; \
	    echo "  Assemble it with: packaging/fetch-upstream.sh" >&2; exit 1; }
	@test -r "$(KCONFIG)" || { echo "macbook91-wireless: error: cannot read $(KCONFIG)" >&2; exit 1; }
	@test -r "$(KDIR)/Module.symvers" || { echo "macbook91-wireless: error: cannot read $(KDIR)/Module.symvers" >&2; exit 1; }
# Integrity of the installed copy (truncated tarball, edits in /usr/src), not
# provenance: that is established at package build time against upstream.lock.
	@cd $(TREE) && sha256sum --quiet -c UPSTREAM.sha256 || \
	  { echo "macbook91-wireless: error: the sources do not match series/$(SERIES)/UPSTREAM.sha256" >&2; exit 1; }
	@test "$$(cat $(TREE)/KERNEL-SERIES)" = "$(SERIES)" || \
	  { echo "macbook91-wireless: error: series/$(SERIES) holds sources of Linux $$(cat $(TREE)/KERNEL-SERIES)" >&2; exit 1; }
	@grep -qx 'CONFIG_BRCMFMAC=m' $(KCONFIG) && grep -qx 'CONFIG_BRCMFMAC_PCIE=y' $(KCONFIG) || \
	  { echo "macbook91-wireless: error: the kernel does not build brcmfmac as a module with PCIe" >&2; exit 1; }
	@grep -qx 'CONFIG_BT_HCIUART=m' $(KCONFIG) && grep -qx 'CONFIG_BT_HCIUART_BCM=y' $(KCONFIG) || \
	  { echo "macbook91-wireless: error: the kernel does not build hci_uart as a module with Broadcom support" >&2; exit 1; }
	@if grep -qx 'CONFIG_CC_IS_CLANG=y' $(KCONFIG); then \
	   command -v clang >/dev/null || { echo "macbook91-wireless: error: the kernel is built with clang (CONFIG_CC_IS_CLANG=y), which is not installed" >&2; echo "  Install it with: sudo pacman -S clang lld llvm" >&2; exit 1; }; \
	 elif grep -qx 'CONFIG_CC_IS_GCC=y' $(KCONFIG); then \
	   command -v gcc >/dev/null || { echo "macbook91-wireless: error: the kernel is built with gcc (CONFIG_CC_IS_GCC=y), which is not installed" >&2; echo "  Install it with: sudo pacman -S gcc" >&2; exit 1; }; \
	 else \
	   echo "macbook91-wireless: error: $(KCONFIG) declares neither CONFIG_CC_IS_CLANG nor CONFIG_CC_IS_GCC" >&2; exit 1; \
	 fi

clean:
	rm -rf $(OUT)
ifeq ($(BUILD),yes)
	$(MAKE) -C $(KDIR) M=$(WLAN) clean
	$(MAKE) -C $(KDIR) M=$(BT) clean
endif

.PHONY: all clean check check-build
