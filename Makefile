PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin

.PHONY: install test lint

install: bin/amphetamine
	install -d "$(BINDIR)"
	install -m 0755 bin/amphetamine "$(BINDIR)/amphetamine"

test:
	./tests/test.sh

lint:
	shellcheck bin/amphetamine tests/test.sh tests/fixtures/bin/osascript tests/fixtures/bin/defaults
