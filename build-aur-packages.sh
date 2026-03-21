#!/usr/bin/env bash
#
# Build AUR packages into a local repo for inclusion in the ISO.
# Runs inside an arch-chroot during CI.
#
set -euo pipefail

AUR_PACKAGES=(
    ssd-flash-id-git
    intel-mas-cli-tool
    kingston_fw_updater
    ocz-ssd-utility
    ocztoolbox
    oczclout
    samsung_magician-consumer-ssd
    hdsentinel
    python-wd-fw-update-git
)

REPO_DIR="/tmp/aur-repo"
BUILD_USER="builduser"

mkdir -p "$REPO_DIR"

# Create a non-root user for makepkg
if ! id "$BUILD_USER" &>/dev/null; then
    useradd -m "$BUILD_USER"
    echo "$BUILD_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# Install paru (AUR helper) as builduser
if ! command -v paru &>/dev/null; then
    cd /tmp
    sudo -u "$BUILD_USER" git clone https://aur.archlinux.org/paru-bin.git
    cd paru-bin
    sudo -u "$BUILD_USER" makepkg -si --noconfirm
    cd /
    rm -rf /tmp/paru-bin
fi

# Build each AUR package
for pkg in "${AUR_PACKAGES[@]}"; do
    echo "==> Building AUR package: $pkg"
    cd /tmp
    sudo -u "$BUILD_USER" git clone "https://aur.archlinux.org/${pkg}.git" || {
        echo "WARNING: Failed to clone $pkg, skipping..."
        continue
    }
    cd "$pkg"

    # Build the package (skip PGP checks since we're in a build env)
    sudo -u "$BUILD_USER" makepkg -s --noconfirm --skippgpcheck || {
        echo "WARNING: Failed to build $pkg, skipping..."
        cd /
        rm -rf "/tmp/${pkg}"
        continue
    }

    # Move built packages to repo dir
    cp ./*.pkg.tar.zst "$REPO_DIR/" 2>/dev/null || \
    cp ./*.pkg.tar.xz "$REPO_DIR/" 2>/dev/null || true

    cd /
    rm -rf "/tmp/${pkg}"
done

# Create the local repo database
cd "$REPO_DIR"
repo-add custom.db.tar.gz ./*.pkg.tar.* 2>/dev/null || echo "WARNING: No packages built for local repo"

echo "==> AUR package build complete. Packages in $REPO_DIR:"
ls -la "$REPO_DIR/"
