#!/usr/bin/env bash
#
# Main ISO build script. Runs inside an Arch Linux environment.
# Usage: ./build.sh [output_dir]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-${SCRIPT_DIR}/out}"
WORK_DIR="/build-work"
PROFILE_DIR="/build-profile"
AUR_REPO_DIR="/build-aur-repo"

echo "==> Preparing archiso profile"

# Install archiso and grub (grub needed for mkarchiso UEFI support)
pacman -Sy --noconfirm archiso grub

# Copy the releng profile as our base
cp -r /usr/share/archiso/configs/releng/ "$PROFILE_DIR"

# Overlay our customizations
cp "$SCRIPT_DIR/profiledef.sh" "$PROFILE_DIR/"
cp "$SCRIPT_DIR/packages.x86_64" "$PROFILE_DIR/"
cp "$SCRIPT_DIR/pacman.conf" "$PROFILE_DIR/"

# Copy boot menu customizations (GRUB + syslinux)
cp "$SCRIPT_DIR/grub/grub.cfg" "$PROFILE_DIR/grub/"
cp "$SCRIPT_DIR/syslinux/archiso_head.cfg" "$PROFILE_DIR/syslinux/"
cp "$SCRIPT_DIR/syslinux/archiso_sys.cfg" "$PROFILE_DIR/syslinux/"
cp "$SCRIPT_DIR/syslinux/archiso_sys-linux.cfg" "$PROFILE_DIR/syslinux/"

# Copy airootfs overlay
cp -r "$SCRIPT_DIR/airootfs/"* "$PROFILE_DIR/airootfs/" 2>/dev/null || true

# If AUR packages were built, add the custom repo
if [ -d "$AUR_REPO_DIR" ] && ls "$AUR_REPO_DIR"/*.pkg.tar.* &>/dev/null; then
    echo "==> Adding custom AUR repo to profile"

    # Copy repo into airootfs so it's available during build
    mkdir -p "$PROFILE_DIR/airootfs/tmp/aur-repo"
    cp "$AUR_REPO_DIR"/* "$PROFILE_DIR/airootfs/tmp/aur-repo/"

    # Add the custom repo to pacman.conf used during build
    cat >> "$PROFILE_DIR/pacman.conf" <<'EOF'

[custom]
SigLevel = Optional TrustAll
Server = file:///tmp/aur-repo
EOF

    # Add AUR package names to packages list
    for pkg_file in "$AUR_REPO_DIR"/*.pkg.tar.*; do
        # Extract package name from filename (name-version-rel-arch.pkg.tar.zst)
        pkg_name=$(basename "$pkg_file" | sed 's/-[0-9].*//' | sed 's/-r[0-9].*//')
        # Use a more reliable method: query the package
        pkg_name=$(tar -xf "$pkg_file" .PKGINFO -O 2>/dev/null | grep '^pkgname' | cut -d= -f2 | tr -d ' ') || continue
        if [ -n "$pkg_name" ]; then
            echo "$pkg_name" >> "$PROFILE_DIR/packages.x86_64"
        fi
    done
fi

echo "==> Building ISO"
mkdir -p "$OUTPUT_DIR" "$WORK_DIR"

mkarchiso -v -w "$WORK_DIR" -o "$OUTPUT_DIR" "$PROFILE_DIR"

echo "==> ISO built successfully:"
ls -lh "$OUTPUT_DIR"/*.iso
