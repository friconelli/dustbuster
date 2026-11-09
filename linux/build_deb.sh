#!/bin/bash
# Builds .build/dustbuster_<version>_all.deb for Zorin OS / Ubuntu / Debian.
# Usage: linux/build_deb.sh [version]     (default: the version in Resources/Info.plist)
# Needs dpkg-deb: used directly if installed, otherwise run inside an Ubuntu container with Docker.
set -euo pipefail

LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$LINUX_DIR/.." && pwd)"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")}"
OUT_DIR="$ROOT_DIR/.build"
STAGE="$OUT_DIR/deb-stage"
DEB="dustbuster_${VERSION}_all.deb"

rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/bin" "$STAGE/usr/lib/python3/dist-packages" "$STAGE/usr/share/applications"

# Application
cp -R "$LINUX_DIR/dustbuster" "$STAGE/usr/lib/python3/dist-packages/dustbuster"
find "$STAGE" -name "__pycache__" -type d -prune -exec rm -rf {} +
sed -i.bak "s/^__version__ = .*/__version__ = \"$VERSION\"/" "$STAGE/usr/lib/python3/dist-packages/dustbuster/__init__.py"
rm -f "$STAGE/usr/lib/python3/dist-packages/dustbuster/__init__.py.bak"
cat > "$STAGE/usr/bin/dustbuster" <<'LAUNCHER'
#!/usr/bin/python3
from dustbuster.ui import main

main()
LAUNCHER
cp "$LINUX_DIR/data/com.federicomancinelli.dustbuster.desktop" "$STAGE/usr/share/applications/"

# Icons
for size in 16 24 32 48 64 128 256 512; do
    dir="$STAGE/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$dir"
    sips -z $size $size "$LINUX_DIR/data/dustbuster.png" --out "$dir/dustbuster.png" >/dev/null
done

# Package metadata
SIZE_KB=$(du -sk "$STAGE" | cut -f1)
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: dustbuster
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Installed-Size: $SIZE_KB
Depends: python3 (>= 3.8), python3-gi, python3-gi-cairo, gir1.2-gtk-3.0, policykit-1, xdg-utils
Maintainer: Federico Mancinelli <friconelli@gmail.com>
Homepage: https://github.com/friconelli/dustbuster
Description: Libera spazio sul disco in sicurezza
 Dustbuster trova cache, file temporanei e backup lasciati dagli strumenti AI,
 file duplicati, file grandi e vecchi, e mostra una mappa dello spazio occupato.
 I repository git non vengono mai toccati e tutto va nel Cestino, recuperabile.
CONTROL
cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
# Drop stale bytecode from a previous version before compiling the new files.
find /usr/lib/python3/dist-packages/dustbuster -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
python3 -m compileall -q /usr/lib/python3/dist-packages/dustbuster >/dev/null 2>&1 || true
if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true; fi
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database -q || true; fi
exit 0
POSTINST
cat > "$STAGE/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
# Only on removal: dpkg also runs the OLD package's postrm during an upgrade, after the new files
# are in place, and deleting the folder then would destroy the update.
case "$1" in
    remove|purge) rm -rf /usr/lib/python3/dist-packages/dustbuster 2>/dev/null || true ;;
esac
if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true; fi
exit 0
POSTRM

find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/usr/bin/dustbuster" "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

mkdir -p "$OUT_DIR"
if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb --root-owner-group --build "$STAGE" "$OUT_DIR/$DEB"
else
    command -v docker >/dev/null 2>&1 || { echo "Serve dpkg-deb oppure Docker per costruire il .deb" >&2; exit 1; }
    docker run --rm -v "$OUT_DIR":/out ubuntu:22.04 dpkg-deb --root-owner-group --build /out/deb-stage "/out/$DEB"
fi
rm -rf "$STAGE"
echo "==> Built $OUT_DIR/$DEB"
