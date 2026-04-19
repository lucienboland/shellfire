# AGENTS.md — Shellfire Framework

## What this is

**Shellfire** — a modular bash configuration framework. This repo contains the
framework code only: the orchestrator (`shellfire.bash`), shared libraries (`lib/`),
and core modules (`core/`). No personal plugins or config live here.

## Structure

```
shellfire.bash          Orchestrator: sources lib/, core/, then plugins from config layer
lib/
  colours.bash          ANSI colour arrays and palette viewer
  logging.bash          _printf, _log_*, _status_set, _sc, _sr, _require_command
  banner.bash           TUI startup banner renderer
core/
  01_history.bash       Shell history configuration
  02_path.bash          Homebrew detection, PATH construction → __homebrew_dir
  03_environment.bash   EDITOR, CLICOLOR, shell options
  04_completions.bash   Bash tab-completion (Homebrew)
  05_ssh-agent.bash     SSH agent discovery, reuse, auto key loading
tests/
  test_shellfire.bash   Framework test suite (lib/ and core/ only)
```

## Key variables

| Variable | How set | Purpose |
|----------|---------|---------|
| `__shellfire_home` | `BASH_SOURCE[0]` (auto) | Framework installation directory |
| `__shellfire_config_home` | `SHELLFIRE_CONFIG_HOME` env or `~/.config/shellfire` | User config directory |

## Testing

```bash
bash tests/test_shellfire.bash           # all tests
bash tests/test_shellfire.bash -s banner # one section
```

## Working directories

- Framework development: `~/code/shellfire/`
- Personal config/plugins: `~/.config/shellfire/` (separate chezmoi-managed repo)
- AI sessions for framework development: run from `~/code/shellfire/`
- AI sessions for plugin development: run from `~/.config/shellfire/`
