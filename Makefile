#! /usr/bin/env make
prefix ?= /usr/local
bindir ?= ${prefix}/bin

.PHONY: install uninstall check
install:
	mkdir -p ${DESTDIR}${bindir}
	install hag.bash daemon.sh daemon.py schema.sql ${DESTDIR}${prefix}
	install hag.bash hag_import_history.bash ${DESTDIR}${bindir}

uninstall:
	rm -f ${DESTDIR}${prefix}/{hag.bash,daemon.sh,daemon.py,schema.sql}
	rm -f ${DESTDIR}${bindir}/{hag.bash,hag_import_history.bash}

# excluding SC1091 (finding a sourced file) for now because it requires shellswain to be on the path
check:
	shellcheck -x -e SC1091 ./hag.bash ./daemon.sh ./hag_import_history.bash
