#!/usr/bin/env bash
# wsl/ubuntu-setup.sh
# Runs INSIDE Ubuntu 24.04 (WSL2) to set up your Linux dev environment.
# Idempotent -- safe to re-run.

set -euo pipefail

echo "=== Updating apt ==="
sudo apt update
sudo apt upgrade -y

echo "=== Installing apt essentials ==="
sudo apt install -y \
    build-essential \
    curl \
    wget \
    git \
    unzip \
    zip \
    jq \
    pkg-config \
    libssl-dev \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    htop \
    tree \
    ripgrep \
    fd-find \
    bat \
    zsh

# bat and fd are installed under different names on Ubuntu -- symlink
mkdir -p ~/.local/bin
ln -sf "$(which batcat)" ~/.local/bin/bat 2>/dev/null || true
ln -sf "$(which fdfind)" ~/.local/bin/fd 2>/dev/null || true

echo "=== Installing uv (Python toolchain) ==="
if ! command -v uv >/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
uv python install 3.12

echo "=== Installing fnm (Node version manager) ==="
if ! command -v fnm >/dev/null; then
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env)"
fi
fnm install --lts
fnm default lts-latest

echo "=== Installing rustup (Rust) ==="
if ! command -v rustup >/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    export PATH="$HOME/.cargo/bin:$PATH"
fi

echo "=== Installing Go ==="
if ! command -v go >/dev/null; then
    GO_VERSION="1.23.4"
    curl -LO "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
    rm "go${GO_VERSION}.linux-amd64.tar.gz"
fi

echo "=== Configuring shell (~/.bashrc additions) ==="
# Add stuff to .bashrc only if not already there
add_to_bashrc() {
    local marker="$1"
    local content="$2"
    if ! grep -qF "$marker" ~/.bashrc; then
        echo -e "\n$content" >> ~/.bashrc
    fi
}

add_to_bashrc "# machine-setup: PATH" \
'# machine-setup: PATH
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/go/bin:$PATH"'

add_to_bashrc "# machine-setup: fnm" \
'# machine-setup: fnm
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd)"'

echo
echo "=== WSL/Ubuntu setup complete. ==="
echo "Open a new shell or run:  source ~/.bashrc"
echo "Verify:  uv --version && fnm --version && rustc --version && go version"
