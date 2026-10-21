# SPDX-License-Identifier: GPL-2.0-or-later
#
# macbook91-wireless: out-of-tree entry point for drivers/net/wireless/
# broadcom/brcm80211, in place of the kernel's Makefile there (which also
# builds brcmsmac and brcmutil, both left to the kernel). The DEBUG define is
# the one that Makefile adds for CONFIG_BRCMDBG; brcmfmac's debug.h depends
# on it.
subdir-ccflags-$(CONFIG_BRCMDBG)	+= -DDEBUG
ifneq ($(MACBOOK91_ID),)
subdir-ccflags-y	+= -DMACBOOK91_WIRELESS_ID=\"$(MACBOOK91_ID)\"
endif
obj-$(CONFIG_BRCMFMAC)	+= brcmfmac/
