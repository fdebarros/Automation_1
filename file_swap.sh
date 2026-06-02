#!/bin/bash

# ============================================================
# file_swap.sh
# RHEL 8 / bash 4.4
# Usage: ./file_swap.sh DATE_START [DATE_END] [-y] [--prefix PREFIX] [--ext EXT]
#   DATE_START   start date in yyyymmdd format
#   DATE_END     end date in yyyymmdd format (optional, defaults to DATE_START)
#   -y           skip confirmation prompt
#   --prefix     file prefix (default: hardcoded in DEFAULT_PREFIX)
#   --ext        file extension (default: hardcoded in DEFAULT_EXT)
# ============================================================

DEST_DIR="/caminho/para/pasta/original"
TMP_DIR="/tmp"
DEFAULT_PREFIX="something"
DEFAULT_EXT="xpto"

AUTO_CONFIRM=false
DATE_START=""
DATE_END=""
PREFIX=""
EXT=""

# --- parse args ---
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y) AUTO_CONFIRM=true; shift ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        --ext) EXT="$2"; shift 2 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

DATE_START="${POSITIONAL[0]:-}"
DATE_END="${POSITIONAL[1]:-$DATE_START}"

# --- fallback to defaults ---
[[ -z "$PREFIX" ]] && PREFIX="$DEFAULT_PREFIX"
[[ -z "$EXT" ]] && EXT="$DEFAULT_EXT"

# --- date validation ---
if [[ -z "$DATE_START" ]]; then
    echo "ERROR: DATE_START is required. Ex: ./file_swap.sh 20250501 [20250613]" >&2
    exit 1
fi

if ! date -d "$DATE_START" &>/dev/null || ! date -d "$DATE_END" &>/dev/null; then
    echo "ERROR: invalid date. Use yyyymmdd format." >&2
    exit 1
fi

# --- generate date range ---
mapfile -t DATE_LIST < <(
    current="$DATE_START"
    while [[ "$current" -le "$DATE_END" ]]; do
        echo "$current"
        current=$(date -d "$current + 1 day" +%Y%m%d)
    done
)

echo ""
echo "Range: $DATE_START → $DATE_END (${#DATE_LIST[@]} day(s))"
echo "Pattern: ${PREFIX}yyyymmdd.${EXT}"

# --- collect files from tmp matching the range ---
mapfile -t NEW_FILES < <(
    for d in "${DATE_LIST[@]}"; do
        find "$TMP_DIR" -maxdepth 1 -name "${PREFIX}${d}.${EXT}" -type f
    done
)

if [[ ${#NEW_FILES[@]} -eq 0 ]]; then
    echo "ERROR: no files found in $TMP_DIR for the given range." >&2
    exit 1
fi

echo ""
echo "Files found in tmp: ${#NEW_FILES[@]}"
printf '  %s\n' "${NEW_FILES[@]}"

# --- rename old files to .old ---
echo ""
echo "Renaming old files in $DEST_DIR to .old..."
mapfile -t OLD_FILES < <(
    for d in "${DATE_LIST[@]}"; do
        find "$DEST_DIR" -maxdepth 1 -name "${PREFIX}${d}.${EXT}" -type f
    done
)

if [[ ${#OLD_FILES[@]} -gt 0 ]]; then
    for f in "${OLD_FILES[@]}"; do
        mv "$f" "${f}.old"
        echo "  ${f} → ${f}.old"
    done
else
    echo "  No old files found — skipping."
fi

# --- copy new files to destination ---
echo ""
echo "Copying new files to $DEST_DIR..."
if ! cp "${NEW_FILES[@]}" "$DEST_DIR/"; then
    echo "ERROR: cp failed. Rolling back renames..." >&2
    for f in "${OLD_FILES[@]}"; do
        mv "${f}.old" "$f"
    done
    exit 1
fi
echo "Done."

# --- confirmation ---
if [[ "$AUTO_CONFIRM" == false ]]; then
    echo ""
    read -rp "Confirm deletion of .old files and tmp cleanup? [y/N]: " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Aborted. .old files kept in $DEST_DIR." && exit 0
fi

# --- delete .old files ---
echo "Deleting .old files..."
for f in "${OLD_FILES[@]}"; do
    rm -f "${f}.old"
done
echo "Done."

# --- chmod 755 ---
echo "Applying chmod 755..."
for f in "${NEW_FILES[@]}"; do
    chmod 755 "$DEST_DIR/$(basename "$f")"
done
echo "Done."

# --- clean tmp ---
echo "Cleaning tmp..."
rm -f "${NEW_FILES[@]}"
echo "Done."

echo ""
echo "Swap complete. ${#NEW_FILES[@]} file(s) updated."
