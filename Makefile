DESTDIR =
PREFIX  = /usr/local
BINDIR  = $(PREFIX)/bin

install:
        install -Dm755 gravity.sh $(DESTDIR)$(BINDIR)/gravity.sh
        install -Dm755 ./advanced/Scripts/chronometer.sh $(DESTDIR)$(BINDIR)/chronometer.sh
        install -Dm755 ./advanced/Scripts/whitelist.sh $(DESTDIR)$(BINDIR)/whitelist.sh
        install -Dm755 ./advanced/Scripts/piholeLogFlush.sh $(DESTDIR)$(BINDIR)/piholeLogFlush.sh

.PHONY : install
