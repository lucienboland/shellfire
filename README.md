# Shellfire

A modular bash configuration framework for macOS.

Shellfire provides the infrastructure for a structured, testable shell startup
environment. It loads shared libraries, core modules, and your personal plugins
from a separate config directory — keeping framework code and personal config
in distinct, independently-managed locations.

## What Shellfire provides

- `lib/` — Shared utilities: colour helpers, logging, startup banner renderer
- `core/` — Always-loaded baseline: history, PATH, environment, completions, SSH agent
- A plugin loader that reads `~/.config/shellfire/plugins.conf`
- A TUI startup banner with per-module status reporting

## What Shellfire does NOT provide

No plugins are bundled. Your plugins live in `~/.config/shellfire/plugins/`.

## Install

See [INSTALL.md](INSTALL.md).

## Requirements

- macOS (tested on Apple Silicon)
- bash 5+ (`brew install bash`)
- Homebrew
