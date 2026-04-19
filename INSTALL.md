# Installing Shellfire

## 1. Clone the framework

```bash
git clone git@github.com:lucienboland/shellfire.git ~/.local/share/shellfire
```

## 2. Create your config skeleton

```bash
mkdir -p ~/.config/shellfire/{plugins,conf.d}
touch ~/.config/shellfire/plugins.conf
```

## 3. Update your `~/.bash_profile`

Add (or replace your existing shell config source line) with:

```bash
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_CACHE_HOME="${HOME}/.cache"
export XDG_DATA_HOME="${HOME}/.local/share"

source "${SHELLFIRE_HOME:-${HOME}/.local/share/shellfire}/shellfire.bash"
```

## 4. Open a new terminal

Shellfire loads. The banner shows the status of each loaded module.

## 5. Add plugins

Create plugin files in `~/.config/shellfire/plugins/` and list them in
`~/.config/shellfire/plugins.conf` (one plugin name per line, no `.bash` extension).

## Updating

```bash
git -C ~/.local/share/shellfire pull
```

## Framework development

To develop the framework itself, clone to a separate location:

```bash
git clone git@github.com:lucienboland/shellfire.git ~/code/shellfire
```

Set `SHELLFIRE_HOME=~/code/shellfire` in your `~/.bash_profile` to use your
development clone as the daily driver. Or use the `shellfire-dev` plugin
(personal, not bundled) to open an isolated dev shell.
