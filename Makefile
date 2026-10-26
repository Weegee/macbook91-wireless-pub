# SPDX-License-Identifier: GPL-3.0-or-later
#
# Package targets. Run from the repository root; the modules themselves are
# built by src/macbook91-wireless/Makefile (DKMS), not here.
#
#   make help            the targets and variables (the default goal: a bare
#                        `make` installs nothing)
#   make dist            assemble the kernel sources of every series at the
#                        newest tag the lockfile records for it, then write the
#                        reproducible source tarball dist/NAME-VERSION.tar
#   make install         what the package installs; packaging/arch/PKGBUILD's
#                        package() is exactly `make PREFIX=/usr DESTDIR="$pkgdir"
#                        install`, run from that tarball
#   make srcinfo         regenerate packaging/arch/.SRCINFO
#   make arch-pkg        release build: the tarball's SHA256 must be the one
#                        pinned in packaging/arch/PKGBUILD
#   make arch-pkg-dev    build of an unreleased tree: tracked files as they are
#                        on disk, the pin replaced in the build copy only
#   make test            tests/run-tests.sh (hermetic, no hardware)
#
# Packages are built in build/arch and copied to dist/. FETCH_ARGS overrides
# the fetcher's options (default: none, i.e. the newest tag of every series
# in the lockfile); MAKEPKG_FLAGS
# passes options to makepkg (e.g. --syncdeps in CI).
#
# Messages (house text HIG): "make TARGET: error: text" on stderr, hints
# indented below; the output of the tools they run is theirs.

NAME := macbook91-wireless-dkms
MODNAME := macbook91-wireless
VERSION := $(shell cat VERSION)
MODULE := src/macbook91-wireless

PREFIX ?= /usr
DESTDIR ?=
MAKEPKG_FLAGS ?=
FETCH_ARGS ?=

SRCDIR = $(DESTDIR)$(PREFIX)/src/$(MODNAME)-$(VERSION)

.DEFAULT_GOAL := help
.PHONY: help install dist srcinfo arch-pkg arch-pkg-dev test

help:
	@printf '%s\n' \
	  'Usage: make TARGET [VARIABLE=VALUE ...]' \
	  '' \
	  'Targets:' \
	  '  dist           assemble the kernel sources of every series, write dist/$(NAME)-$(VERSION).tar' \
	  '  install        install the package files into DESTDIR and PREFIX (what the PKGBUILD runs)' \
	  '  srcinfo        regenerate packaging/arch/.SRCINFO' \
	  '  arch-pkg       release build: the tarball must be the one the PKGBUILD pins' \
	  '  arch-pkg-dev   build of an unreleased tree, the pin replaced in the build copy only' \
	  '  test           run tests/run-tests.sh (no hardware, no root)' \
	  '' \
	  'Variables:' \
	  '  PREFIX=/usr   DESTDIR=   FETCH_ARGS=   MAKEPKG_FLAGS=' \
	  '' \
	  'Docs and bug reports: https://github.com/Weegee/macbook91-wireless-pub'

install:
	@test -r "$(MODULE)/KERNEL-SERIES" || { echo "make install: error: $(MODULE) is not assembled" >&2; echo "  Assemble it with: make dist" >&2; exit 1; }
	install -dm755 "$(SRCDIR)"
	cp -a "$(MODULE)/." "$(SRCDIR)/"
	rm -f "$(SRCDIR)/.gitignore"
	rm -rf "$(SRCDIR)/modprobe.d" "$(SRCDIR)/build"

	# Build artifacts must never reach the package.
	find "$(SRCDIR)" \( -name '*.o' -o -name '*.ko' -o -name '*.mod' -o -name '*.mod.c' \
		-o -name '.*.cmd' -o -name 'Module.symvers' -o -name 'modules.order' \) -delete

	# dkms.conf carries the version and the kernel series of this tarball,
	# the series from KERNEL-SERIES through the script the pacman hook, the
	# install scriptlet and the verifier ask, so they cannot name different
	# series.
	sed -i "s/@PKGVER@/$(VERSION)/" "$(SRCDIR)/dkms.conf"
	re=$$(bash tools/kernel-series --dkms-regex --series-file "$(SRCDIR)/KERNEL-SERIES") && \
	sed -i "s|@SERIES_RE@|$$(printf '%s' "$$re" | sed 's/[\\&|]/\\&/g')|" "$(SRCDIR)/dkms.conf" && \
	grep -q '^BUILD_EXCLUSIVE_KERNEL="^(' "$(SRCDIR)/dkms.conf"

	install -Dm644 "$(MODULE)/modprobe.d/macbook91-wireless.conf" \
		"$(DESTDIR)$(PREFIX)/lib/modprobe.d/macbook91-wireless.conf"
	install -Dm755 tools/macbook91-wireless-verify \
		"$(DESTDIR)$(PREFIX)/bin/macbook91-wireless-verify"
	sed -i "s/@PKGVER@/$(VERSION)/" "$(DESTDIR)$(PREFIX)/bin/macbook91-wireless-verify"
	install -Dm755 tools/kernel-series "$(DESTDIR)$(PREFIX)/lib/$(MODNAME)/kernel-series"
	sed -i "s/@PKGVER@/$(VERSION)/" "$(DESTDIR)$(PREFIX)/lib/$(MODNAME)/kernel-series"
	install -Dm644 tools/macbook91-wireless-series.hook \
		"$(DESTDIR)$(PREFIX)/share/libalpm/hooks/71-macbook91-wireless-series.hook"
	install -Dm644 README.md "$(DESTDIR)$(PREFIX)/share/doc/$(NAME)/README.md"
	install -Dm644 LICENSES/ISC "$(DESTDIR)$(PREFIX)/share/licenses/$(NAME)/ISC"
	install -Dm644 LICENSES/MIT "$(DESTDIR)$(PREFIX)/share/licenses/$(NAME)/MIT"

	find "$(DESTDIR)$(PREFIX)/src" -type f -exec chmod 644 {} +
	find "$(DESTDIR)$(PREFIX)/src" -type d -exec chmod 755 {} +

dist:
	packaging/fetch-upstream.sh $(FETCH_ARGS)
	python3 packaging/mkdist.py

srcinfo:
	cd packaging/arch && makepkg --printsrcinfo > .SRCINFO

test:
	tests/run-tests.sh

# The release build. The tarball holds no PKGBUILD, so pinning its checksum
# there does not change the tarball.
arch-pkg: dist
	@want=$$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" packaging/arch/PKGBUILD); \
	have=$$(cut -d' ' -f1 dist/$(NAME)-$(VERSION).tar.sha256); \
	if [ "$$want" != "$$have" ]; then \
		echo "make arch-pkg: error: the tarball is not the one the PKGBUILD pins" >&2; \
		echo "  PKGBUILD sha256sums: $$want" >&2; \
		echo "  tarball:             $$have" >&2; \
		echo "  Pin the tarball: set sha256sums in packaging/arch/PKGBUILD to $$have, run make srcinfo, commit (--amend), then run make arch-pkg again" >&2; \
		exit 1; \
	fi
	$(MAKE) --no-print-directory _arch-build

arch-pkg-dev:
	packaging/fetch-upstream.sh $(FETCH_ARGS)
	python3 packaging/mkdist.py --allow-dirty
	$(MAKE) --no-print-directory _arch-build PIN=$$(cut -d' ' -f1 dist/$(NAME)-$(VERSION).tar.sha256)

# makepkg extracts into $$srcdir without clearing it, so build/arch is
# recreated every time and makepkg runs with --cleanbuild.
_arch-build:
	rm -rf build/arch
	mkdir -p build/arch
	cp packaging/arch/PKGBUILD packaging/arch/$(MODNAME).install dist/$(NAME)-$(VERSION).tar build/arch/
	if [ -n "$(PIN)" ]; then \
		sed -i "s/^sha256sums=('[0-9a-f]*')/sha256sums=('$(PIN)')/" build/arch/PKGBUILD; \
	fi
	cd build/arch && makepkg --cleanbuild --force --noconfirm $(MAKEPKG_FLAGS)
	cp build/arch/$(NAME)-$(VERSION)-*.pkg.tar.zst dist/
