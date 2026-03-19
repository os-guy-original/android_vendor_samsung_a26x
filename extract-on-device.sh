#!/bin/bash
#
# Extract proprietary blobs by running a script on the device
#

DEVICE=a26x
VENDOR=samsung
OUT_DIR="proprietary"
ARCHIVE_NAME="a26x_blobs.tar.gz"

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

check_adb() {
    if ! adb get-state 2>/dev/null | grep -q "device"; then
        log_error "No device connected"
        exit 1
    fi
    
    if ! adb shell su -c "id" 2>/dev/null | grep -q "uid=0"; then
        log_error "Root access required"
        exit 1
    fi
    
    log_info "Device: $(adb get-serialno) - Root OK"
}

create_device_script() {
    cat > /tmp/extract_blobs.sh << 'DEVSCRIPT'
#!/system/bin/sh
ARCHIVE_FILE="/sdcard/a26x_blobs.tar.gz"
TMP_DIR="/data/local/tmp/blobs_extract"
MISSING_LOG="/sdcard/missing_files.txt"
FILES_INPUT="/data/local/tmp/files.txt"

rm -rf "$TMP_DIR" "$ARCHIVE_FILE" "$MISSING_LOG" 2>/dev/null
mkdir -p "$TMP_DIR"

echo "Processing files from $FILES_INPUT..."

count=0
total=0
missing=0

# Count total lines first
total=$(grep -c '^[^#]' "$FILES_INPUT" 2>/dev/null || echo "0")
echo "Total entries to process: $total"

# Process each file
while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments, empty lines, and lines starting with -
    case "$line" in
        \#*|"") continue ;;
        -*) continue ;;
    esac
    
    # Trim whitespace
    line=$(echo "$line" | tr -d '[:space:]')
    [ -z "$line" ] && continue
    
    # Determine source path
    case "$line" in
        vendor/*) src="/$line" ;;
        system_ext/*) src="/$line" ;;
        product/*) src="/$line" ;;
        odm/*) src="/$line" ;;
        etc/*) src="/system/$line" ;;
        lib/*) src="/system/$line" ;;
        lib64/*) src="/system/$line" ;;
        bin/*) src="/system/$line" ;;
        framework/*) src="/system/$line" ;;
        *) src="/vendor/$line" ;;
    esac
    
    # Determine dest path
    case "$line" in
        vendor/*) dest="$line" ;;
        system_ext/*) dest="$line" ;;
        product/*) dest="$line" ;;
        odm/*) dest="$line" ;;
        etc/*) dest="system/$line" ;;
        lib/*) dest="system/$line" ;;
        lib64/*) dest="system/$line" ;;
        bin/*) dest="system/$line" ;;
        framework/*) dest="system/$line" ;;
        *) dest="vendor/$line" ;;
    esac
    
    count=$((count + 1))
    
    if [ -f "$src" ]; then
        dest_dir="$TMP_DIR/$(dirname "$dest")"
        mkdir -p "$dest_dir"
        cp -L -f "$src" "$TMP_DIR/$dest" 2>/dev/null && \
            printf "\r[%d/%d] %-50s" "$count" "$total" "$(basename "$src")" || \
            printf "\r[%d/%d] FAILED: %-40s" "$count" "$total" "$(basename "$src")"
    else
        missing=$((missing + 1))
        echo "$src" >> "$MISSING_LOG"
    fi
done < "$FILES_INPUT"

echo ""
echo ""
echo "Creating archive..."
cd "$TMP_DIR"
tar -czf "$ARCHIVE_FILE" . 2>/dev/null

if [ -f "$ARCHIVE_FILE" ]; then
    size=$(ls -lh "$ARCHIVE_FILE" | awk '{print $5}')
    echo "Archive: $ARCHIVE_FILE ($size)"
    echo "Copied: $((count - missing))"
    echo "Missing: $missing"
else
    echo "ERROR: Failed to create archive"
fi

rm -rf "$TMP_DIR"
DEVSCRIPT
}

push_and_run() {
    log_info "Pushing extraction script..."
    adb push /tmp/extract_blobs.sh /data/local/tmp/
    adb shell chmod 755 /data/local/tmp/extract_blobs.sh
    
    log_info "Pushing file list..."
    adb push proprietary-files.txt /data/local/tmp/files.txt
    
    log_info "Running extraction on device (this takes several minutes)..."
    adb shell su -c "/data/local/tmp/extract_blobs.sh"
    
    log_info "Pulling archive..."
    adb pull /sdcard/a26x_blobs.tar.gz .
    
    log_info "Extracting..."
    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR"
    tar -xzf a26x_blobs.tar.gz -C "$OUT_DIR"
    
    adb pull /sdcard/missing_files.txt . 2>/dev/null || true
    
    log_info "Cleaning up..."
    adb shell rm -rf /sdcard/a26x_blobs.tar.gz /sdcard/missing_files.txt /data/local/tmp/extract_blobs.sh /data/local/tmp/files.txt
}

main() {
    echo "=========================================="
    echo "  On-Device Blob Extraction Tool"
    echo "  Device: $DEVICE"
    echo "=========================================="
    echo ""
    
    check_adb
    create_device_script
    push_and_run
    
    file_count=$(find "$OUT_DIR" -type f 2>/dev/null | wc -l)
    log_info "Done! Extracted $file_count files to $OUT_DIR/"
    
    [ -f missing_files.txt ] && log_info "Missing files saved to missing_files.txt"
}

main "$@"
