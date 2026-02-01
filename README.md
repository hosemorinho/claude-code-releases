# Claude Code Releases

Auto-sync Claude Code CLI binaries from upstream and distribute via GitHub Releases.

Automatically checks for new Claude Code versions daily and publishes multi-architecture binaries to GitHub Releases. Includes an installation script with **proxy acceleration** for China mainland users.

---

## Quick Install

### Standard

```bash
curl -fsSL https://raw.githubusercontent.com/hosemorinho/claude-code-releases/main/install.sh | bash
```

### China Mainland (default proxy: gh-proxy.org)

```bash
curl -fsSL https://raw.githubusercontent.com/hosemorinho/claude-code-releases/main/install.sh | bash -s -- --proxy
```

### China Mainland (custom mirror)

```bash
# Use any GitHub proxy/mirror you prefer
curl -fsSL https://raw.githubusercontent.com/hosemorinho/claude-code-releases/main/install.sh | bash -s -- --mirror https://ghfast.top

# Or via environment variable
CLAUDE_MIRROR=https://ghfast.top bash install.sh
```

### Install Specific Version

```bash
# Standard
curl -fsSL https://raw.githubusercontent.com/hosemorinho/claude-code-releases/main/install.sh | bash -s -- --version 2.0.30

# With proxy
curl -fsSL https://raw.githubusercontent.com/hosemorinho/claude-code-releases/main/install.sh | bash -s -- --proxy --version 2.0.30
```

## Supported Platforms

| Platform | Architecture | Binary Name |
|----------|-------------|-------------|
| macOS | x64 (Intel) | `claude-{ver}-darwin-x64` |
| macOS | arm64 (Apple Silicon) | `claude-{ver}-darwin-arm64` |
| Linux | x64 (glibc) | `claude-{ver}-linux-x64` |
| Linux | arm64 (glibc) | `claude-{ver}-linux-arm64` |
| Linux | x64 (musl/Alpine) | `claude-{ver}-linux-x64-musl` |
| Linux | arm64 (musl/Alpine) | `claude-{ver}-linux-arm64-musl` |

## How It Works

1. A GitHub Actions workflow runs daily at 08:00 UTC
2. It queries the upstream Claude Code distribution for the latest version
3. If a new version is detected, it downloads binaries for all 6 platforms
4. SHA256 checksums are verified against the upstream manifest
5. A new GitHub Release is created with all binaries attached

## Install Script Options

```
Options:
    --proxy              Use default proxy (gh-proxy.org) for download acceleration
    --mirror URL         Use a custom mirror/proxy URL for download acceleration
    --version VER        Install a specific version (e.g., 2.0.30)
    --install-dir DIR    Set custom install directory (default: ~/.local/bin)
    -h, --help           Show help message
```

## Install Script Features

- Auto-detects OS and CPU architecture (including musl/glibc on Linux)
- Auto-detects China mainland environment (via timezone/locale) and enables proxy
- Supports custom proxy/mirror via `--mirror URL` or `CLAUDE_MIRROR` env
- GitHub API is always called directly (no proxy), only binary downloads use proxy
- SHA256 checksum verification
- Supports custom install directory via `--install-dir` or `CLAUDE_INSTALL_DIR` env
- Adds install path to shell rc file (bash/zsh/fish)
- Detects existing Claude Code installations

## Manual Download

Go to the [Releases](https://github.com/hosemorinho/claude-code-releases/releases) page and download the binary for your platform, then:

```bash
chmod +x claude-*-linux-x64
mv claude-*-linux-x64 ~/.local/bin/claude
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_INSTALL_DIR` | Custom install directory | `~/.local/bin` |
| `CLAUDE_MIRROR` | Custom mirror/proxy URL | (none) |

## License

This project only redistributes official Claude Code binaries from Anthropic. Claude Code is proprietary software by [Anthropic](https://anthropic.com). All rights to the Claude Code binary belong to Anthropic.
