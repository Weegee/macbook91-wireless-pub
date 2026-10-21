// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Host test of bcm_fixup_le_adv_report() from the assembled hci_bcm.c. The
 * function body is extracted by tests/run-tests.sh into le_adv_fixup.inc and
 * compiled here against minimal stand-ins for the kernel types.
 */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned char u8;
struct sk_buff { u8 *data; unsigned int len; };
#define HCI_EV_LE_META			0x3e
#define HCI_EV_LE_ADVERTISING_REPORT	0x02
#define LE_ADV_IND			0x00
#define LE_ADV_SCAN_RSP			0x04

#include "le_adv_fixup.inc"

/* event, plen, subevent, num, then per report: type, addr type, addr[6],
 * data len, data[len], rssi */
static unsigned int report(u8 *p, u8 type, u8 dlen)
{
	p[0] = type;
	p[1] = 0;
	memset(p + 2, 0xaa, 6);
	p[8] = dlen;
	memset(p + 9, 0x55, dlen);
	p[9 + dlen] = 0xc0;
	return 10 + dlen;
}

/* On an exactly sized heap copy, so that the sanitizer catches any access
 * beyond len (run-tests.sh builds with -fsanitize=address,undefined). */
static void run(u8 *buf, unsigned int len)
{
	u8 *copy = malloc(len);
	struct sk_buff skb = { copy, len };

	assert(copy);
	memcpy(copy, buf, len);
	bcm_fixup_le_adv_report(&skb);
	memcpy(buf, copy, len);
	free(copy);
}

int main(void)
{
	u8 b[256];
	unsigned int off;

	/* Reserved bits on all three reports are cleared, data is untouched. */
	memset(b, 0, sizeof(b));
	b[0] = HCI_EV_LE_META; b[2] = HCI_EV_LE_ADVERTISING_REPORT; b[3] = 3;
	off = 4;
	unsigned int r1 = off; off += report(b + off, 0x10, 3);
	unsigned int r2 = off; off += report(b + off, 0x24, 0);
	unsigned int r3 = off; off += report(b + off, 0x03, 31);
	b[1] = off - 2;
	run(b, off);
	assert(b[r1] == 0x00 && b[r2] == 0x04 && b[r3] == 0x03);
	assert(b[r1 + 9] == 0x55 && b[r3 + 9 + 30] == 0x55);

	/* A low type that is not a legacy PDU (5..7) keeps its reserved bits:
	 * clearing them would invent a type. */
	b[r1] = 0x15;
	run(b, off);
	assert(b[r1] == 0x15);

	/* Other events and other LE subevents are not touched. */
	b[r1] = 0x10; b[2] = 0x0d;
	run(b, off);
	assert(b[r1] == 0x10);
	b[2] = HCI_EV_LE_ADVERTISING_REPORT; b[0] = 0x0e;
	run(b, off);
	assert(b[r1] == 0x10);
	b[0] = HCI_EV_LE_META;

	/* A num_reports larger than the buffer, or a data length running past
	 * its end, stops at the buffer: nothing beyond len is read or written. */
	u8 t[64], before[64];
	memset(t, 0xee, sizeof(t));
	t[0] = HCI_EV_LE_META; t[2] = HCI_EV_LE_ADVERTISING_REPORT; t[3] = 200;
	report(t + 4, 0x13, 40);	/* claims 40 bytes, buffer ends earlier */
	memcpy(before, t, sizeof(t));
	run(t, 20);
	assert(t[4] == 0x03);		/* the first header is complete */
	assert(memcmp(t + 5, before + 5, sizeof(t) - 5) == 0);
	u8 s[3] = { HCI_EV_LE_META, 1, HCI_EV_LE_ADVERTISING_REPORT };
	run(s, 3);
	u8 h[13] = { HCI_EV_LE_META, 11, HCI_EV_LE_ADVERTISING_REPORT, 1, 0x10 };
	run(h, 13);			/* header one byte short of 10 */
	assert(h[4] == 0x10);

	puts("le_adv_fixup: ok");
	return 0;
}
