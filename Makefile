#! /usr/bin/env make
prefix ?= /usr/local
bindir ?= ${prefix}/bin
libexec ?= ${prefix}/libexec
share ?= ${prefix}/share

.PHONY: install uninstall check
install:
	mkdir -p ${DESTDIR}${bindir} ${DESTDIR}${libexec} ${DESTDIR}${share}
	install daemon.py ${DESTDIR}${libexec}
	install schema.sql ${DESTDIR}${share}
	install hag.bash hagd.bash hag_import_history.bash ${DESTDIR}${bindir}

uninstall:
	rm -f ${DESTDIR}${libexec}/{daemon.sh,daemon.py}
	rm -f ${DESTDIR}${share}/schema.sql
	rm -f ${DESTDIR}${bindir}/{hag.bash,hag_import_history.bash}

# excluding SC1091 (finding a sourced file) for now because it requires shellswain to be on the path
check:
	shellcheck -x -e SC1091 ./hag.bash ./daemon.sh ./hag_import_history.bash
	bats tests
