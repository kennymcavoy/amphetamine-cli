PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
SKILL_NAME := amphetamine
SKILL_DATA_ROOT ?= $(HOME)/.local/share/amphetamine-cli
SKILL_STORE := $(SKILL_DATA_ROOT)/skills/$(SKILL_NAME)
CODEX_SKILLSDIR ?= $(HOME)/.agents/skills
CODEX_SKILL_LINK := $(CODEX_SKILLSDIR)/$(SKILL_NAME)
CLAUDE_SKILLSDIR ?= $(HOME)/.claude/skills
CLAUDE_SKILL_LINK := $(CLAUDE_SKILLSDIR)/$(SKILL_NAME)

.PHONY: install install-skill install-codex-skill install-claude-skill uninstall test lint

install: bin/amphetamine skill/SKILL.md scripts/install
	@SOURCE_BINARY="$(CURDIR)/bin/amphetamine" \
	SOURCE_SKILL="$(CURDIR)/skill/SKILL.md" \
	INSTALLED_BINARY="$(BINDIR)/amphetamine" \
	SKILL_STORE="$(SKILL_STORE)" \
	CODEX_SKILL_LINK="$(CODEX_SKILL_LINK)" \
	CLAUDE_SKILL_LINK="$(CLAUDE_SKILL_LINK)" \
	/bin/bash scripts/install

install-skill install-codex-skill: bin/amphetamine skill/SKILL.md scripts/install
	@INSTALL_CODEX_SKILL=yes INSTALL_CLAUDE_SKILL=no \
	SOURCE_BINARY="$(CURDIR)/bin/amphetamine" \
	SOURCE_SKILL="$(CURDIR)/skill/SKILL.md" \
	INSTALLED_BINARY="$(BINDIR)/amphetamine" \
	SKILL_STORE="$(SKILL_STORE)" \
	CODEX_SKILL_LINK="$(CODEX_SKILL_LINK)" \
	CLAUDE_SKILL_LINK="$(CLAUDE_SKILL_LINK)" \
	/bin/bash scripts/install

install-claude-skill: bin/amphetamine skill/SKILL.md scripts/install
	@INSTALL_CODEX_SKILL=no INSTALL_CLAUDE_SKILL=yes \
	SOURCE_BINARY="$(CURDIR)/bin/amphetamine" \
	SOURCE_SKILL="$(CURDIR)/skill/SKILL.md" \
	INSTALLED_BINARY="$(BINDIR)/amphetamine" \
	SKILL_STORE="$(SKILL_STORE)" \
	CODEX_SKILL_LINK="$(CODEX_SKILL_LINK)" \
	CLAUDE_SKILL_LINK="$(CLAUDE_SKILL_LINK)" \
	/bin/bash scripts/install

uninstall: scripts/uninstall
	@INSTALLED_BINARY="$(BINDIR)/amphetamine" \
	SKILL_STORE="$(SKILL_STORE)" \
	SKILL_DATA_ROOT="$(SKILL_DATA_ROOT)" \
	CODEX_SKILL_LINK="$(CODEX_SKILL_LINK)" \
	CLAUDE_SKILL_LINK="$(CLAUDE_SKILL_LINK)" \
	/bin/bash scripts/uninstall

test:
	./tests/test.sh

lint:
	shellcheck bin/amphetamine scripts/install scripts/uninstall tests/test.sh tests/fixtures/bin/osascript tests/fixtures/bin/defaults
