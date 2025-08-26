# `zsh` built from git src

A Homebrew formula for building `zsh` from any Git source with customizable repository, branch/tag/commit reference, and version.

## Installation

> **Note:** `zsh` is already provided in `homebrew-core`. To use this custom build, you need to:
> 1. Uninstall the existing version: `brew uninstall zsh`
> 2. Unlink it: `brew unlink zsh`
> 3. Install this custom build: `brew install --build-from-source jseifeddine/homebrew-tap/zsh`


### Basic Installation

By default, this formula builds from the official zsh repository `(HEAD -> master)` on `https://git.code.sf.net/p/zsh/code`:

```bash
brew install --build-from-source jseifeddine/homebrew-tap/zsh
```

### Default Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| `DEFAULT_REPO` | `https://git.code.sf.net/p/zsh/code` | The default repository URL |
| `DEFAULT_REF` | `master` | The default branch/tag/commit reference |

### Examples

**Build from a specific branch:**
```bash
HOMEBREW_ZSH_REF=master brew install --build-from-source jseifeddine/homebrew-tap/zsh
```

**Build from a specific tag:**
```bash
HOMEBREW_ZSH_REF=zsh-5.9 brew install --build-from-source jseifeddine/homebrew-tap/zsh
```

**Build from a specific commit:**
```bash
HOMEBREW_ZSH_REF=a1b2c3d4 brew install --build-from-source jseifeddine/homebrew-tap/zsh
```

**Build from a fork:**
```bash
HOMEBREW_ZSH_REPO=https://github.com/jseifeddine/zsh \
HOMEBREW_ZSH_REF=feature-branch \
brew install --build-from-source jseifeddine/homebrew-tap/zsh
```

**Override the automatically detected version:**
```bash
HOMEBREW_ZSH_VERSION_OVERRIDE=5.9.1-custom \
brew install --build-from-source jseifeddine/homebrew-tap/zsh
```

## Environment Variables

- `HOMEBREW_ZSH_REPO`: Git repository URL (default: https://git.code.sf.net/p/zsh/code)
- `HOMEBREW_ZSH_REF`: Branch, tag, or commit SHA (default: master)
- `HOMEBREW_ZSH_VERSION_OVERRIDE`: Override the automatically detected version from Config/version.mk

## Version Detection

The formula automatically detects the version from `Config/version.mk` in the zsh source repository. This file contains a line like `VERSION=5.9.0.3-test` which is parsed to determine the correct version.

If automatic detection fails or you want to override it, use the `HOMEBREW_ZSH_VERSION_OVERRIDE` environment variable.

## Setting as Default Shell

After installation, to use this zsh as your default shell:

```bash
# Add to allowed shells
echo "$(brew --prefix)/bin/zsh" | sudo tee -a /etc/shells

# Set as default
chsh -s "$(brew --prefix)/bin/zsh"
```

## Uninstallation

```bash
brew uninstall zsh
```

## License

This formula is provided as-is. Zsh itself is licensed under the MIT-like license.