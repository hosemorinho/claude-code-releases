#!/usr/bin/env bash
set -euo pipefail

# Claude Code Installer
# Downloads Claude Code binary from GitHub releases
# Supports proxy acceleration for China mainland users

# ============================================================
# Configuration
# ============================================================
GITHUB_REPO="hosemorinho/claude-code-releases"
INSTALL_DIR="${CLAUDE_INSTALL_DIR:-$HOME/.local/bin}"
# Build base URLs from parts to prevent proxy services from
# rewriting them when serving this script through the proxy
_GH="github"
_GITHUB_API="https://api.${_GH}.com"
_GITHUB_DL="https://${_GH}.com"
DEFAULT_PROXY="https://gh-proxy.org"
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*" >&2; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

USE_PROXY=false
PROXY_URL=""
TARGET_VERSION=""

usage() {
    cat << 'EOF'
Usage: install.sh [OPTIONS]

Options:
    --proxy              Use default proxy (gh-proxy.org) for download acceleration
    --mirror URL         Use a custom mirror/proxy URL for download acceleration
                         e.g. --mirror https://ghfast.top
                         e.g. --mirror https://gh-proxy.org
    --version VER        Install a specific version (e.g., 2.0.30)
    --install-dir DIR    Set custom install directory (default: ~/.local/bin)
    -h, --help           Show this help message

Environment variables:
    CLAUDE_INSTALL_DIR   Custom install directory (same as --install-dir)
    CLAUDE_MIRROR        Custom mirror URL (same as --mirror)

Examples:
    # Standard install (latest version)
    bash install.sh

    # Use default proxy (gh-proxy.org)
    bash install.sh --proxy

    # Use custom mirror
    bash install.sh --mirror https://ghfast.top

    # Install specific version with proxy
    bash install.sh --proxy --version 2.0.30
EOF
}

parse_args() {
    # Check environment variable first
    if [ -n "${CLAUDE_MIRROR:-}" ]; then
        USE_PROXY=true
        PROXY_URL="${CLAUDE_MIRROR%/}"
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --proxy)
                USE_PROXY=true
                if [ -z "$PROXY_URL" ]; then
                    PROXY_URL="$DEFAULT_PROXY"
                fi
                shift
                ;;
            --mirror)
                USE_PROXY=true
                PROXY_URL="${2%/}"
                shift 2
                ;;
            --version)
                TARGET_VERSION="$2"
                shift 2
                ;;
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done

    # Set default proxy URL if --proxy was used without --mirror
    if [ "$USE_PROXY" = true ] && [ -z "$PROXY_URL" ]; then
        PROXY_URL="$DEFAULT_PROXY"
    fi
}

detect_platform() {
    local os arch platform

    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Darwin)
            os="darwin"
            ;;
        Linux)
            os="linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            error "Windows is not supported by this installer."
            error "Please use the official installer: irm https://claude.ai/install.ps1 | iex"
            exit 1
            ;;
        *)
            error "Unsupported operating system: $os"
            exit 1
            ;;
    esac

    case "$arch" in
        x86_64|amd64)
            arch="x64"
            ;;
        arm64|aarch64)
            arch="arm64"
            ;;
        *)
            error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    # Detect musl libc on Linux
    local libc_suffix=""
    if [ "$os" = "linux" ]; then
        if ldd --version 2>&1 | grep -qi musl 2>/dev/null; then
            libc_suffix="-musl"
        elif [ -f /etc/alpine-release ]; then
            libc_suffix="-musl"
        fi
    fi

    platform="${os}-${arch}${libc_suffix}"
    echo "$platform"
}

auto_detect_china() {
    # If proxy is already set, skip detection
    if [ "$USE_PROXY" = true ]; then
        return
    fi

    # Check common China locale/timezone indicators
    local tz="${TZ:-}"
    if [ -z "$tz" ] && [ -f /etc/timezone ]; then
        tz=$(cat /etc/timezone 2>/dev/null || true)
    fi
    if [ -z "$tz" ]; then
        tz=$(readlink /etc/localtime 2>/dev/null | grep -o '[^/]*$' || true)
    fi

    local lang="${LANG:-}"

    if [[ "$tz" == *"Shanghai"* ]] || [[ "$tz" == *"Chongqing"* ]] || [[ "$tz" == "CST"* ]] || [[ "$lang" == zh_CN* ]]; then
        info "Detected China mainland environment, auto-enabling proxy"
        info "To disable: set TZ to a non-China timezone, or use --mirror ''"
        USE_PROXY=true
        PROXY_URL="$DEFAULT_PROXY"
    fi
}

# Proxy only for github.com downloads, NOT for api.github.com
proxy_download_url() {
    local url="$1"
    if [ "$USE_PROXY" = true ] && [ -n "$PROXY_URL" ]; then
        echo "${PROXY_URL}/${url}"
    else
        echo "$url"
    fi
}

get_latest_version() {
    # Always call GitHub API directly (small JSON, works fine without proxy)
    local api_url="${_GITHUB_API}/repos/${GITHUB_REPO}/releases/latest"

    info "Fetching latest version info..."
    local response
    response=$(curl -fsSL "$api_url" 2>/dev/null) || {
        error "Failed to fetch release info from GitHub API"
        error "URL: $api_url"
        if [ "$USE_PROXY" = true ]; then
            info "Note: API calls go directly to GitHub (no proxy needed)"
            info "If this fails, your network may not be able to reach api.github.com"
        fi
        exit 1
    }

    local version
    version=$(echo "$response" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"v\?\([^"]*\)".*/\1/')

    if [ -z "$version" ]; then
        error "Failed to parse version from GitHub API response"
        exit 1
    fi

    echo "$version"
}

download_binary() {
    local version="$1"
    local platform="$2"
    local filename="claude-${version}-${platform}"
    local raw_url="${_GITHUB_DL}/${GITHUB_REPO}/releases/download/v${version}/${filename}"
    local download_url

    download_url=$(proxy_download_url "$raw_url")

    info "Downloading Claude Code v${version} for ${platform}..."
    info "URL: ${download_url}"

    BINARY_TMP_DIR=$(mktemp -d)
    BINARY_TMP_FILE="${BINARY_TMP_DIR}/claude"

    if ! curl -fSL --progress-bar "$download_url" -o "$BINARY_TMP_FILE"; then
        rm -rf "$BINARY_TMP_DIR"
        error "Failed to download binary"
        error "URL: $download_url"
        error ""
        error "Possible reasons:"
        error "  - Version v${version} may not have a binary for ${platform}"
        error "  - Network connectivity issues"
        if [ "$USE_PROXY" = false ]; then
            error "  - If you are in China mainland, try: --proxy"
        else
            error "  - Try a different mirror: --mirror https://ghfast.top"
        fi
        exit 1
    fi
}

verify_checksum() {
    local binary_path="$1"
    local version="$2"
    local platform="$3"

    local raw_url="${_GITHUB_DL}/${GITHUB_REPO}/releases/download/v${version}/SHA256SUMS.txt"
    local checksums_url
    checksums_url=$(proxy_download_url "$raw_url")

    info "Verifying checksum..."
    local checksums
    checksums=$(curl -fsSL "$checksums_url" 2>/dev/null) || {
        warn "Could not download checksums file, skipping verification"
        return 0
    }

    local filename="claude-${version}-${platform}"
    local expected
    expected=$(echo "$checksums" | grep -F " ${filename}$" | awk '{print $1}' | head -1)

    if [ -z "$expected" ]; then
        warn "No checksum found for $filename, skipping verification"
        return 0
    fi

    local actual
    if command -v sha256sum &>/dev/null; then
        actual=$(sha256sum "$binary_path" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actual=$(shasum -a 256 "$binary_path" | awk '{print $1}')
    else
        warn "No sha256sum or shasum available, skipping verification"
        return 0
    fi

    if [ "$actual" = "$expected" ]; then
        success "Checksum verified"
    else
        error "Checksum verification failed!"
        error "  Expected: $expected"
        error "  Actual:   $actual"
        exit 1
    fi
}

install_binary() {
    local binary_path="$1"

    mkdir -p "$INSTALL_DIR"
    chmod +x "$binary_path"
    mv "$binary_path" "${INSTALL_DIR}/claude"

    success "Claude Code installed to ${INSTALL_DIR}/claude"
}

ensure_path() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")

    # Check if INSTALL_DIR is already in PATH
    if echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        return
    fi

    local shell_rc=""
    case "$shell_name" in
        bash)
            shell_rc="$HOME/.bashrc"
            ;;
        zsh)
            shell_rc="$HOME/.zshrc"
            ;;
        fish)
            shell_rc="$HOME/.config/fish/config.fish"
            ;;
        *)
            shell_rc="$HOME/.profile"
            ;;
    esac

    if [ -n "$shell_rc" ]; then
        local path_line="export PATH=\"${INSTALL_DIR}:\$PATH\""
        if [ "$shell_name" = "fish" ]; then
            path_line="set -gx PATH ${INSTALL_DIR} \$PATH"
        fi

        if ! grep -qF "$INSTALL_DIR" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "# Claude Code" >> "$shell_rc"
            echo "$path_line" >> "$shell_rc"
            info "Added ${INSTALL_DIR} to PATH in ${shell_rc}"
            info "Run 'source ${shell_rc}' or restart your terminal to use 'claude'"
        fi
    fi
}

check_existing_installation() {
    local existing
    existing=$(command -v claude 2>/dev/null || true)
    if [ -n "$existing" ]; then
        local current_version
        current_version=$("$existing" --version 2>/dev/null || echo "unknown")
        warn "Existing Claude Code installation found: $existing (version: $current_version)"
        warn "This installer will install/overwrite to: ${INSTALL_DIR}/claude"
    fi
}

main() {
    echo ""
    echo "========================================="
    echo "    Claude Code Installer"
    echo "========================================="
    echo ""

    parse_args "$@"
    auto_detect_china

    if [ "$USE_PROXY" = true ]; then
        info "Download proxy: ${PROXY_URL}"
    fi

    # Detect platform
    local platform
    platform=$(detect_platform)
    info "Detected platform: ${platform}"

    # Check existing installation
    check_existing_installation

    # Get version
    local version
    if [ -n "$TARGET_VERSION" ]; then
        version="$TARGET_VERSION"
        info "Target version: v${version}"
    else
        version=$(get_latest_version)
        info "Latest version: v${version}"
    fi

    # Download
    download_binary "$version" "$platform"

    # Verify
    verify_checksum "$BINARY_TMP_FILE" "$version" "$platform"

    # Install
    install_binary "$BINARY_TMP_FILE"

    # Ensure PATH
    ensure_path

    # Cleanup temp directory
    rm -rf "$BINARY_TMP_DIR" 2>/dev/null || true

    echo ""
    success "Claude Code v${version} installed successfully!"
    echo ""
    info "Run 'claude' to get started"
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        info "Note: You may need to restart your terminal or run:"
        echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi
    echo ""
}

main "$@"
