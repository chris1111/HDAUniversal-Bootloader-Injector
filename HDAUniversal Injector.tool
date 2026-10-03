#!/bin/bash
# HDAUniversal Bootloader Injector Copyright © 2026 chris1111. All rights reserved.
#
# ================================================================
#  HDAUniversal Bootloader Injector — Patch Script
#  Creates a ready-to-inject aliased IOAudioFamily.kext next to
#  the HDAUniversal.kext, using the ORIGINAL kext from the
#  ORIG-HDAUniversal folder shipped in THIS script's directory.
#  Then copy BOTH kexts to EFI/OC/Kexts (or Clover kexts/Other)
#
#  HDAUniversal (org.olarila.driver.HDAUniversal by Daniel Maldonado)
#  depends on IOAudioFamily — NOT in the boot kernel collection
#  since Big Sur → direct injection fails. The alias solves it.
#
#  Guards:
#   0. HDAUniversal in /Library/Extensions -> EXIT (cannot coexist)
#   1. ORIG-HDAUniversal folder must exist with the ORIGINAL kext
#   2. Working HDAUniversal.kext ALWAYS regenerated fresh (no double patch)
#   3. IOAudioFamily.kext in folder        -> deleted, always regenerated
#
#  NO PYTHON NEEDED — uses only tools shipped with macOS
# ================================================================
set -eu

# Folder containing the ORIGINAL unpatched HDAUniversal.kext
ORIG_FOLDER="ORIG-HDAUniversal"

# Always run from the script's own folder
cd "$(dirname "$0")" || exit 1
WORKDIR="$(pwd)"

echo "=================================================="
echo " HDAUniversal Bootloader Injection - Patch Builder"
echo " Working folder: $WORKDIR"
echo "=================================================="

# --- DEPENDENCY CHECK (all ship with macOS — no python needed) ---
for CMD in curl hdiutil pkgutil lipo codesign plutil perl sw_vers grep sed strings; do
    command -v "$CMD" >/dev/null 2>&1 || {
        echo "ERROR: required tool '$CMD' not found (ships with macOS — system incomplete?)"
        exit 1
    }
done
echo "==> Dependencies OK"

# --- GUARD 0: HDAUniversal must not be installed in /Library/Extensions ---
if [ -d "/Library/Extensions/HDAUniversal.kext" ]; then
    echo ""
    echo "!! WARNING: HDAUniversal.kext found in /Library/Extensions !!"
    echo ""
    echo "   Bootloader injection and an already-installed kext CANNOT coexist"
    echo "   (duplicate identifier — the injection will silently fail)."
    echo ""
    echo "   Fix: delete it:"
    echo ""
    echo "   sudo rm -rf /Library/Extensions/HDAUniversal.kext"
    echo "   Reboot and retry"
    echo ""
    exit 1
fi
if find /Library/Extensions -maxdepth 4 -type d -name "HDAUniversal.kext" 2>/dev/null | grep -q .; then
    echo ""
    echo "!! WARNING: a nested HDAUniversal.kext was found under /Library/Extensions !!"
    echo "   Run: find /Library/Extensions -name 'HDAUniversal.kext' to locate and remove it."
    echo ""
    exit 1
fi
echo "==> Guard: /Library/Extensions clean"

# --- CHECK 1: ORIG folder present with the ORIGINAL kext? ---
if [ ! -d "$ORIG_FOLDER/HDAUniversal.kext" ]; then
    echo ""
    echo "ERROR: $ORIG_FOLDER/HDAUniversal.kext not found in $WORKDIR"
    echo ""
    echo "This script needs the ORIGINAL unpatched HDAUniversal.kext shipped"
    echo "inside the '$ORIG_FOLDER' folder next to the script:"
    echo ""
    echo "   $WORKDIR/$ORIG_FOLDER/HDAUniversal.kext"
    echo ""
    exit 1
fi

# --- CHECK 2: ORIG kext is a real kext (binary inside)? ---
if [ ! -d "$ORIG_FOLDER/HDAUniversal.kext/Contents/MacOS" ] || [ -z "$(ls "$ORIG_FOLDER/HDAUniversal.kext/Contents/MacOS/" 2>/dev/null)" ]; then
    echo ""
    echo "ERROR: $ORIG_FOLDER/HDAUniversal.kext has no executable inside (not a valid kext)."
    echo "The $ORIG_FOLDER folder must contain the COMPLETE original HDAUniversal.kext."
    exit 1
fi

# --- CHECK 3: ORIG source must NOT be already patched ---
if /usr/libexec/PlistBuddy -c "Print :OSBundleLibraries:net.olarila.IOAudioFamily" \
     "$ORIG_FOLDER/HDAUniversal.kext/Contents/Info.plist" >/dev/null 2>&1; then
    echo ""
    echo "!! ERROR: the kext inside $ORIG_FOLDER is ALREADY PATCHED"
    echo "!!        (it links to net.olarila.IOAudioFamily)."
    echo ""
    echo "The $ORIG_FOLDER folder must contain the ORIGINAL UNPATCHED HDAUniversal.kext."
    echo "Replace it with a fresh original, then run again."
    exit 1
fi
echo "==> Original kext found in $ORIG_FOLDER: OK (unpatched)"

# --- DELETE any existing IOAudioFamily.kext (always regenerate fresh) ---
if [ -d "IOAudioFamily.kext" ]; then
    echo "==> Existing IOAudioFamily.kext deleted (will regenerate fresh)"
    rm -rf "IOAudioFamily.kext"
fi

# --- ALWAYS regenerate working HDAUniversal.kext from ORIG (pristine every run) ---
if [ -d "HDAUniversal.kext" ]; then
    echo "==> Existing HDAUniversal.kext in working folder deleted (regenerating from $ORIG_FOLDER)"
    rm -rf "HDAUniversal.kext"
fi
cp -R "$ORIG_FOLDER/HDAUniversal.kext" ./HDAUniversal.kext
echo "==> Fresh original HDAUniversal.kext staged from $ORIG_FOLDER"

# --- locate a real IOAudioFamily.kext ---
SRC=""
KEEP_TMP=""

if [ -f "/System/Library/Extensions/IOAudioFamily.kext/Contents/MacOS/IOAudioFamily" ]; then
    SRC="/System/Library/Extensions/IOAudioFamily.kext"
fi

if [ -z "$SRC" ]; then
    BUILD=$(sw_vers -buildVersion)
    echo "==> System IOAudioFamily is a stub — fetching KDK for build $BUILD"

    API_JSON=$(curl -sf "https://api.github.com/repos/dortania/KdkSupportPkg/releases" || true)
    [ -n "$API_JSON" ] || { echo "ERROR: cannot reach GitHub API"; exit 1; }

    DMG_URL=$(echo "$API_JSON" \
        | tr ',' '\n' | grep '"browser_download_url"' | grep '\.dmg' | grep "$BUILD" \
        | head -1 | sed -E 's/.*"(https[^"]+)".*/\1/' || true)

    if [ -z "$DMG_URL" ]; then
        CLOSEST=$(echo "$API_JSON" \
            | tr ',' '\n' | grep '"browser_download_url"' | grep '\.dmg' \
            | head -1 | sed -E 's/.*"(https[^"]+)".*/\1/' || true)
        if [ -z "$CLOSEST" ]; then
            echo "ERROR: no KDK dmg found at all on Dortania releases"
            exit 1
        fi
        echo ""
        echo "⚠️  No KDK found for build $BUILD in Dortania releases."
        echo "    Closest available: $CLOSEST"
        echo ""
        echo "    Options:"
        echo "     [1] Use this closest build anyway (RISKY: kernel symbol mismatch possible)"
        echo "     [2] Abort — install the EXACT KDK manually from"
        echo "         https://developer.apple.com/download/all/ then re-run"
        echo ""
        printf "    Choice [1/2]: "
        read -r ANSWER
        [ "$ANSWER" = "1" ] || { echo "Aborted. Install exact KDK and re-run."; exit 1; }
        DMG_URL="$CLOSEST"
        echo "==> Proceeding with closest build (user accepted the risk)"
    fi

    TMP=$(mktemp -d /private/tmp/kdk.XXXXXX)
    echo "==> Downloading: $DMG_URL"
    curl -L --progress-bar -o "$TMP/kdk.dmg" "$DMG_URL"

    mkdir -p "$TMP/mnt"
    hdiutil attach "$TMP/kdk.dmg" -nobrowse -mountpoint "$TMP/mnt" || { echo "ERROR: dmg mount failed"; rm -rf "$TMP"; exit 1; }
    echo "==> [1/4] dmg mounted"

    PKG=$(find "$TMP/mnt" -name "*.pkg" -maxdepth 3 | head -1)
    if [ -z "$PKG" ]; then
        echo "ERROR: no .pkg inside dmg"; hdiutil detach "$TMP/mnt" -quiet; rm -rf "$TMP"; exit 1
    fi
    echo "==> [2/4] pkg found: $(basename "$PKG")"

    pkgutil --expand-full "$PKG" "$TMP/expanded"
    hdiutil detach "$TMP/mnt" -quiet
    echo "==> [3/4] pkg expanded"

    SRC=$(find "$TMP/expanded" -type d -name "IOAudioFamily.kext" | head -1)
    if [ -z "$SRC" ] || [ ! -f "$SRC/Contents/MacOS/IOAudioFamily" ]; then
        echo "ERROR: IOAudioFamily.kext not found in expanded pkg"
        rm -rf "$TMP"; exit 1
    fi
    echo "==> [4/4] IOAudioFamily.kext found"
    KEEP_TMP="$TMP"
fi
echo "==> IOAudioFamily source: $SRC"

# --- stage fresh copy ---
cd "$WORKDIR"
cp -R "$SRC" ./IOAudioFamily.kext
if [ -n "${KEEP_TMP:-}" ]; then
    rm -rf "${KEEP_TMP}"
    echo "==> temp files cleaned"
fi

# --- thin ---
cd "$WORKDIR/IOAudioFamily.kext/Contents/MacOS"
if lipo -info IOAudioFamily | grep -q "fat file"; then
    lipo -thin x86_64 IOAudioFamily -output t && mv t IOAudioFamily
    echo "==> thinned to x86_64"
fi

# --- alias binary (perl — byte-safe, keeps length: 29 chars -> 25 chars + 4 NULs) ---
perl -0777 -pi -e 's/com\.apple\.iokit\.IOAudioFamily/net.olarila.IOAudioFamily\x00\x00\x00\x00/g' IOAudioFamily
if strings IOAudioFamily | grep -q "net.olarila.IOAudioFamily"; then
    echo "==> binary patched OK"
else
    echo "ERROR: alias patch failed"
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.olarila.IOAudioFamily" ../Info.plist

# --- point HDAUniversal at the alias ---
cd "$WORKDIR"
V="$WORKDIR/HDAUniversal.kext/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :OSBundleLibraries:com.apple.iokit.IOAudioFamily" "$V" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :OSBundleLibraries:net.olarila.IOAudioFamily string 1.0.0" "$V"
echo "==> HDAUniversal links to net.olarila.IOAudioFamily"

# --- sign both ---
codesign --force --deep --sign - "$WORKDIR/IOAudioFamily.kext"
codesign --force --deep --sign - "$WORKDIR/HDAUniversal.kext"
codesign -dv "$WORKDIR/IOAudioFamily.kext" 2>&1 | grep Identifier || true

echo ""
echo "=================================================="
echo " DONE. Both kexts ready in: $WORKDIR"
echo "   IOAudioFamily.kext  (aliased: net.olarila.IOAudioFamily)"
echo "   HDAUniversal.kext   (links to alias — regenerated from $ORIG_FOLDER)"
echo ""
echo " 1. Copy BOTH to EFI/OC/Kexts (or EFI/CLOVER/kexts/Other)"
echo " 2. OC config.plist: Kernel -> Add: IOAudioFamily ABOVE HDAUniversal"
echo " 3. No Block entries needed. No SIP changes. Reboot."
echo "=================================================="