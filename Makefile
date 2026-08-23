PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
SKILL_NAME := amphetamine
SKILLSDIR ?= $(HOME)/.agents/skills
SKILLDIR := $(SKILLSDIR)/$(SKILL_NAME)
SKILL_MARKER := $(SKILLDIR)/.installed-by-amphetamine-cli
CLAUDE_SKILLSDIR ?= $(HOME)/.claude/skills
CLAUDE_SKILL_LINK := $(CLAUDE_SKILLSDIR)/$(SKILL_NAME)

.PHONY: install install-skill install-claude-skill uninstall uninstall-skill uninstall-claude-skill test lint

install: bin/amphetamine install-skill
	install -d "$(BINDIR)"
	install -m 0755 bin/amphetamine "$(BINDIR)/amphetamine"

install-skill: skill/SKILL.md
	@if [ -L "$(SKILLDIR)" ]; then \
		printf 'refusing to replace symlinked skill directory: %s\n' "$(SKILLDIR)" >&2; \
		exit 1; \
	fi
	@if [ -e "$(SKILLDIR)/SKILL.md" ] && [ ! -f "$(SKILL_MARKER)" ]; then \
		printf 'refusing to overwrite skill not installed by amphetamine-cli: %s\n' "$(SKILLDIR)" >&2; \
		exit 1; \
	fi
	install -d "$(SKILLDIR)"
	install -m 0644 skill/SKILL.md "$(SKILLDIR)/SKILL.md"
	: > "$(SKILL_MARKER)"

install-claude-skill: install-skill
	install -d "$(CLAUDE_SKILLSDIR)"
	@link='$(CLAUDE_SKILL_LINK)'; target='$(SKILLDIR)'; \
	if [ -L "$$link" ]; then \
		current=$$(readlink "$$link"); \
		if [ "$$current" != "$$target" ]; then \
			printf 'refusing to replace existing Claude skill link: %s -> %s\n' "$$link" "$$current" >&2; \
			exit 1; \
		fi; \
	elif [ -e "$$link" ]; then \
		printf 'refusing to replace existing Claude skill: %s\n' "$$link" >&2; \
		exit 1; \
	else \
		ln -s "$$target" "$$link"; \
	fi

uninstall: uninstall-skill
	rm -f "$(BINDIR)/amphetamine"

uninstall-skill: uninstall-claude-skill
	@if [ -f "$(SKILL_MARKER)" ]; then \
		rm -f "$(SKILLDIR)/SKILL.md" "$(SKILL_MARKER)"; \
		rmdir "$(SKILLDIR)" 2>/dev/null || true; \
	elif [ -e "$(SKILLDIR)/SKILL.md" ] || [ -L "$(SKILLDIR)" ]; then \
		printf 'refusing to remove skill not installed by amphetamine-cli: %s\n' "$(SKILLDIR)" >&2; \
		exit 1; \
	fi

uninstall-claude-skill:
	@link='$(CLAUDE_SKILL_LINK)'; target='$(SKILLDIR)'; \
	if [ -f "$(SKILL_MARKER)" ] && [ -L "$$link" ] && [ "$$(readlink "$$link")" = "$$target" ]; then \
		rm -f "$$link"; \
	fi

test:
	./tests/test.sh

lint:
	shellcheck bin/amphetamine tests/test.sh tests/fixtures/bin/osascript tests/fixtures/bin/defaults
