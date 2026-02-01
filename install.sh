#!/usr/bin/env bash
set -euo pipefail

# Claude Code Installer
# Downloads Claude Code binary from GitHub releases
# Supports gh-proxy.org acceleration for China mainland users

# ============================================================
# Configuration - CHANGE THIS to your GitHub repo
# ============================================================
GITHUB_REPO="hosemorinho/claude-code-releases"
INSTALL_DIR="${CLAUDE_INSTALL_DIR:-$HOME/.local/bin}"
# Build base URLs from parts to prevent gh-proxy.org from
# rewriting them when serving this script through the proxy
_GH="github"
_GITHUB_API="https://api.${_GH}.com"
_GITHUB_DL="https://${_GH}.com"
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

USE_PROXY=false
TARGET_VERSION=""

usage() {
    cat << EOF
Usage: install.sh [OPTIONS]

Options:
    --proxy         Use gh-proxy.org for accelerated download (China mainland)
    --version VER   Install a specific version (e.g., 2.0.30)
    --install-dir   Set custom install directory (default: ~/.local/bin)
    -h, --help      Show this help message

Examples:
    # Standard install (latest version)
    curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh | bash

    # China mainland accelerated install
    curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh | bash -s -- --proxy

    # Install specific version
    curl -fsSL .../install.sh | bash -s -- --version 2.0.30

    # China mainland + specific version
    curl -fsSL .../install.sh | bash -s -- --proxy --version 2.0.30
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --proxy)
                USE_PROXY=true
                shift
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
    # If --proxy is already set, skip detection
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
        info "Detected China mainland environment, auto-enabling proxy acceleration"
        info "You can disable this by setting TZ to a non-China timezone"
        USE_PROXY=true
    fi
}

build_url() {
    local url="$1"
    if [ "$USE_PROXY" = true ]; then
        # Avoid double-proxying if URL already contains proxy
        if [[ "$url" != *"gh-proxy.org"* ]]; then
            echo "https://gh-proxy.org/${url}"
        else
            echo "$url"
        fi
    else
        echo "$url"
    fi
}

get_latest_version() {
    local api_url
    api_url=$(build_url "${_GITHUB_API}/repos/${GITHUB_REPO}/releases/latest")

    info "Fetching latest version info..."
    local response
    response=$(curl -fsSL "$api_url" 2>/dev/null) || {
        error "Failed to fetch release info from GitHub"
        error "URL: $api_url"
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
    local download_url

    download_url=$(build_url "${_GITHUB_DL}/${GITHUB_REPO}/releases/download/v${version}/${filename}")

    info "Downloading Claude Code v${version} for ${platform}..."
    info "URL: ${download_url}"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local tmp_file="${tmp_dir}/claude"

    if ! curl -fSL --progress-bar "$download_url" -o "$tmp_file" 2>&1; then
        rm -rf "$tmp_dir"
        error "Failed to download binary"
        error "URL: $download_url"
        error ""
        error "Possible reasons:"
        error "  - Version v${version} may not have a binary for ${platform}"
        error "  - Network connectivity issues"
        if [ "$USE_PROXY" = false ]; then
            error "  - If you are in China mainland, try: --proxy"
        fi
        exit 1
    fi

    echo "$tmp_file"
}

verify_checksum() {
    local binary_path="$1"
    local version="$2"
    local platform="$3"

    local checksums_url
    checksums_url=$(build_url "${_GITHUB_DL}/${GITHUB_REPO}/releases/download/v${version}/SHA256SUMS.txt")

    info "Verifying checksum..."
    local checksums
    checksums=$(curl -fsSL "$checksums_url" 2>/dev/null) || {
        warn "Could not download checksums file, skipping verification"
        return 0
    }

    local filename="claude-${version}-${platform}"
    local expected
    expected=$(echo "$checksums" | grep "$filename" | awk '{print $1}')

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
        info "Proxy mode enabled: using gh-proxy.org for acceleration"
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
    local binary_path
    binary_path=$(download_binary "$version" "$platform")

    # Verify
    verify_checksum "$binary_path" "$version" "$platform"

    # Install
    install_binary "$binary_path"

    # Ensure PATH
    ensure_path

    # Cleanup temp directory
    local tmp_dir
    tmp_dir=$(dirname "$binary_path")
    rm -rf "$tmp_dir" 2>/dev/null || true

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
