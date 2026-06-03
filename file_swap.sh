#!/bin/bash

# ============================================================
# file_swap.sh
# RHEL 8 / bash 4.4
# Usage: ./file_swap.sh [DATE_START] [DATE_END] [-y] [--mode swap|dump-swap|delete]
#                       [--prefix PREFIX] [--ext EXT]
#
#   DATE_START   start date in yyyymmdd format
#   DATE_END     end date in yyyymmdd format (optional, defaults to DATE_START)
#   -y           skip final confirmation (swap mode only)
#   --mode       operation mode: swap (default), dump-swap, delete
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
MODE=""

# ============================================================
# HELP
# ============================================================
show_help() {
    cat <<EOF

file_swap.sh — File deployment utility for RHEL 8

USAGE:
  ./file_swap.sh [DATE_START] [DATE_END] [OPTIONS]

ARGUMENTS:
  DATE_START          Start date in yyyymmdd format (required for swap/delete)
  DATE_END            End date in yyyymmdd format (optional, defaults to DATE_START)

OPTIONS:
  --mode MODE         Operation mode (default: swap)
                        swap       Rename old files to .old, copy new files from tmp
                        dump-swap  Delete ALL files matching prefix in dest, then swap
                        delete     Delete files matching prefix (date range optional)
  --prefix PREFIX     File prefix (default: $DEFAULT_PREFIX)
  --ext EXT           File extension (default: $DEFAULT_EXT)
  -y                  Skip final confirmation prompt (swap mode only)
  --help              Show this help message

EXAMPLES:
  ./file_swap.sh 20250601
  ./file_swap.sh 20250501 20250613
  ./file_swap.sh 20250501 20250613 -y
  ./file_swap.sh 20250501 20250613 --mode dump-swap
  ./file_swap.sh --mode delete
  ./file_swap.sh 20250501 20250613 --mode delete
  ./file_swap.sh 20250601 --prefix report --ext csv

EOF
    exit 0
}

# ============================================================
# PARSE ARGS
# ============================================================
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)    show_help ;;
        -y)        AUTO_CONFIRM=true; shift ;;
        --mode)    MODE="$2"; shift 2 ;;
        --prefix)  PREFIX="$2"; shift 2 ;;
        --ext)     EXT="$2"; shift 2 ;;
        *)         POSITIONAL+=("$1"); shift ;;
    esac
done

DATE_START="${POSITIONAL[0]:-}"
DATE_END="${POSITIONAL[1]:-}"

# ============================================================
# INTERACTIVE PROMPTS
# ============================================================
prompt_dates() {
    local mode="$1"
    if [[ "$mode" == "dump-swap" ]]; then
        read -rp "Date Start (yyyymmdd): " DATE_START
        DATE_END="$DATE_START"
        read -rp "Date End   (yyyymmdd) [$DATE_START]: " input
        [[ -n "$input" ]] && DATE_END="$input"
    elif [[ "$mode" == "delete" ]]; then
        echo "Date range is optional for delete mode. Leave blank to delete ALL dates."
        read -rp "Date Start (yyyymmdd) [all]: " DATE_START
        if [[ -n "$DATE_START" ]]; then
            read -rp "Date End   (yyyymmdd) [$DATE_START]: " input
            DATE_END="${input:-$DATE_START}"
        fi
    else
        read -rp "Date Start (yyyymmdd): " DATE_START
        DATE_END="$DATE_START"
        read -rp "Date End   (yyyymmdd) [$DATE_START]: " input
        [[ -n "$input" ]] && DATE_END="$input"
    fi
}

run_interactive() {
    echo ""
    echo "=== file_swap.sh ==="
    echo ""

    # mode
    echo "Select mode:"
    echo "  [1] swap       (default)"
    echo "  [2] dump-swap"
    echo "  [3] delete"
    read -rp "Mode [1]: " mode_input
    case "$mode_input" in
        2) MODE="dump-swap" ;;
        3) MODE="delete" ;;
        *) MODE="swap" ;;
    esac

    # dates
    prompt_dates "$MODE"

    # prefix
    read -rp "Prefix [$DEFAULT_PREFIX]: " input
    PREFIX="${input:-$DEFAULT_PREFIX}"

    # ext
    read -rp "Extension [$DEFAULT_EXT]: " input
    EXT="${input:-$DEFAULT_EXT}"

    echo ""
    echo "---"
    echo "Mode      : $MODE"
    [[ -n "$DATE_START" ]] && echo "Date range: $DATE_START → ${DATE_END:-$DATE_START}"
    echo "Pattern   : ${PREFIX}yyyymmdd.${EXT}"
    echo "Dest      : $DEST_DIR"
    echo "---"
}

# ============================================================
# VALIDATE DATES
# ============================================================
validate_dates() {
    if [[ -z "$DATE_START" ]]; then
        echo "ERROR: DATE_START is required for this mode." >&2
        exit 1
    fi
    if ! date -d "$DATE_START" &>/dev/null; then
        echo "ERROR: invalid DATE_START. Use yyyymmdd format." >&2
        exit 1
    fi
    if [[ -n "$DATE_END" ]] && ! date -d "$DATE_END" &>/dev/null; then
        echo "ERROR: invalid DATE_END. Use yyyymmdd format." >&2
        exit 1
    fi
    [[ -z "$DATE_END" ]] && DATE_END="$DATE_START"
}

# ============================================================
# GENERATE DATE LIST
# ============================================================
generate_date_list() {
    mapfile -t DATE_LIST < <(
        current="$DATE_START"
        while [[ "$current" -le "$DATE_END" ]]; do
            echo "$current"
            current=$(date -d "$current + 1 day" +%Y%m%d)
        done
    )
}

# ============================================================
# CONFIRM EXPLICIT (dump-swap / delete — no bypass)
# ============================================================
confirm_explicit() {
    local msg="$1"
    echo ""
    echo "⚠️  WARNING: $msg"
    read -rp "Type YES to confirm: " input
    if [[ "$input" != "YES" ]]; then
        echo "Aborted."
        exit 0
    fi
}

# ============================================================
# MODE: SWAP
# ============================================================
run_swap() {
    validate_dates
    generate_date_list

    echo ""
    echo "Range: $DATE_START → $DATE_END (${#DATE_LIST[@]} day(s))"
    echo "Pattern: ${PREFIX}yyyymmdd.${EXT}"

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

    if [[ "$AUTO_CONFIRM" == false ]]; then
        echo ""
        read -rp "Confirm deletion of .old files and tmp cleanup? [y/N]: " CONFIRM
        [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Aborted. .old files kept in $DEST_DIR." && exit 0
    fi

    echo "Deleting .old files..."
    for f in "${OLD_FILES[@]}"; do rm -f "${f}.old"; done
    echo "Done."

    echo "Applying chmod 755..."
    for f in "${NEW_FILES[@]}"; do chmod 755 "$DEST_DIR/$(basename "$f")"; done
    echo "Done."

    echo "Cleaning tmp..."
    rm -f "${NEW_FILES[@]}"
    echo "Done."

    echo ""
    echo "Swap complete. ${#NEW_FILES[@]} file(s) updated."
}

# ============================================================
# MODE: DUMP+SWAP
# ============================================================
run_dump_swap() {
    validate_dates
    generate_date_list

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

    mapfile -t DUMP_FILES < <(find "$DEST_DIR" -maxdepth 1 -name "${PREFIX}*" -type f)

    echo ""
    echo "Files to be deleted from $DEST_DIR: ${#DUMP_FILES[@]}"
    printf '  %s\n' "${DUMP_FILES[@]}"

    confirm_explicit "This will DELETE ALL ${#DUMP_FILES[@]} file(s) matching prefix '${PREFIX}' in $DEST_DIR."

    echo ""
    echo "Deleting all prefix-matching files in $DEST_DIR..."
    for f in "${DUMP_FILES[@]}"; do rm -f "$f"; done
    echo "Done."

    echo "Copying new files to $DEST_DIR..."
    if ! cp "${NEW_FILES[@]}" "$DEST_DIR/"; then
        echo "ERROR: cp failed." >&2
        exit 1
    fi
    echo "Done."

    echo "Applying chmod 755..."
    for f in "${NEW_FILES[@]}"; do chmod 755 "$DEST_DIR/$(basename "$f")"; done
    echo "Done."

    echo "Cleaning tmp..."
    rm -f "${NEW_FILES[@]}"
    echo "Done."

    echo ""
    echo "Dump+swap complete. ${#NEW_FILES[@]} file(s) deployed."
}

# ============================================================
# MODE: DELETE
# ============================================================
run_delete() {
    local use_dates=false
    [[ -n "$DATE_START" ]] && use_dates=true

    if [[ "$use_dates" == true ]]; then
        validate_dates
        generate_date_list
        mapfile -t DEL_FILES < <(
            for d in "${DATE_LIST[@]}"; do
                find "$DEST_DIR" -maxdepth 1 -name "${PREFIX}${d}.${EXT}" -type f
            done
        )
    else
        mapfile -t DEL_FILES < <(find "$DEST_DIR" -maxdepth 1 -name "${PREFIX}*" -type f)
    fi

    if [[ ${#DEL_FILES[@]} -eq 0 ]]; then
        echo "No files found to delete."
        exit 0
    fi

    echo ""
    echo "Files to be deleted: ${#DEL_FILES[@]}"
    printf '  %s\n' "${DEL_FILES[@]}"

    confirm_explicit "This will permanently DELETE ${#DEL_FILES[@]} file(s) from $DEST_DIR."

    echo ""
    echo "Deleting files..."
    for f in "${DEL_FILES[@]}"; do rm -f "$f"; done
    echo "Done."

    echo ""
    echo "Delete complete. ${#DEL_FILES[@]} file(s) removed."
}

# ============================================================
# ENTRYPOINT
# ============================================================

# se nenhum arg foi passado, roda interativo
if [[ ${#POSITIONAL[@]} -eq 0 && -z "$MODE" && -z "$PREFIX" && -z "$EXT" ]]; then
    run_interactive
fi

# fallback defaults
[[ -z "$PREFIX" ]] && PREFIX="$DEFAULT_PREFIX"
[[ -z "$EXT" ]]    && EXT="$DEFAULT_EXT"
[[ -z "$MODE" ]]   && MODE="swap"

case "$MODE" in
    swap)      run_swap ;;
    dump-swap) run_dump_swap ;;
    delete)    run_delete ;;
    *)
        echo "ERROR: unknown mode '$MODE'. Use swap, dump-swap or delete." >&2
        exit 1
        ;;
esac
