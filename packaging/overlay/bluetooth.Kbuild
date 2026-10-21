# SPDX-License-Identifier: GPL-2.0-only
#
# Out-of-tree build of hci_uart only, with the protocol set of the in-tree
# module (the CONFIG_ values come from the target kernel's auto.conf).
# Copied as Kbuild into drivers/bluetooth of the assembled tree. The
# hci_uart-* lines are those of the kernel's drivers/bluetooth/Makefile
# (GPL-2.0), hence the license.
ifneq ($(MACBOOK91_ID),)
ccflags-y	+= -DMACBOOK91_WIRELESS_ID=\"$(MACBOOK91_ID)\"
endif
obj-m := hci_uart.o
hci_uart-y				:= hci_ldisc.o
hci_uart-$(CONFIG_BT_HCIUART_SERDEV)	+= hci_serdev.o
hci_uart-$(CONFIG_BT_HCIUART_H4)	+= hci_h4.o
hci_uart-$(CONFIG_BT_HCIUART_BCSP)	+= hci_bcsp.o
hci_uart-$(CONFIG_BT_HCIUART_LL)	+= hci_ll.o
hci_uart-$(CONFIG_BT_HCIUART_ATH3K)	+= hci_ath.o
hci_uart-$(CONFIG_BT_HCIUART_3WIRE)	+= hci_h5.o
hci_uart-$(CONFIG_BT_HCIUART_INTEL)	+= hci_intel.o
hci_uart-$(CONFIG_BT_HCIUART_BCM)	+= hci_bcm.o
hci_uart-$(CONFIG_BT_HCIUART_QCA)	+= hci_qca.o
hci_uart-$(CONFIG_BT_HCIUART_AG6XX)	+= hci_ag6xx.o
hci_uart-$(CONFIG_BT_HCIUART_MRVL)	+= hci_mrvl.o
hci_uart-$(CONFIG_BT_HCIUART_AML)	+= hci_aml.o
