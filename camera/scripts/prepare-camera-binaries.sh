#!/bin/sh

set -eu

SOURCE_DIR=${CAMERA_SOURCE_DIR:-/odm/lib64/camera}
PROJECT_DIR=${CAMERA_PROJECT_DIR:-/root/sailfish-xperia-10v-tweaks}
OUTPUT_DIR=${CAMERA_OUTPUT_DIR:-$PROJECT_DIR/binaries}
TELE=com.sony.sensormodule.murray_tele.bin
TUNING=com.qti.tuned.blair_lce_hi847.bin
DEFAULT_TUNING=$PROJECT_DIR/$TUNING
ORIGINAL_TELE_SHA=762c311c4dc009db271231f45bdb127f849e16a2d784cc72789ef2103e202f87
PATCHED_TELE_SHA=dd8249c928dd0bb799e71f183f979f69e96821cadb2ea83ab8a2ebe114eeb7fb
TUNING_SHA=fae940dd8cb3bf567a854cab3dd8cd474ae97b7219b6c9e022cc9d9a7e10b141

fail() {
    printf 'ERROR: %s\n' "$*" >&2; exit 1; 
}
info() {
    printf '%s\n' "$*";
}

file_hash() {
    [ -f "$1" ] || return 1
    hash_line=$(sha256sum "$1") || return 1
    printf '%s\n' "${hash_line%% *}"
}

verify_file() {
    actual=$(file_hash "$1") || { printf 'Missing/unreadable file: %s\n' "$1" >&2; return 1; }
    if [ "$actual" != "$2" ]; then
        printf 'Wrong SHA-256: %s\n  expected %s\n  actual   %s\n' "$1" "$2" "$actual" >&2
        return 1
    fi
}

verify_camera_tree() {
    directory=$1
    tele_sha=$2
    verify_file "$directory/com.qti.tuned.default.bin" "a53b78f5d10ff97b97f640469ef3c330817ba143bf5655d4699755453ae95a72" || return 1
    verify_file "$directory/com.sony.sensor.hi846.so" "18b7183980bf2380ee3568ca589e0b8f2a1b5f22ef9026bb0ed245992e545cb2" || return 1
    verify_file "$directory/com.sony.sensor.hi847.so" "388401aae7b232605cdf44c0e16d8d8164e4e912dc9f640177dc7a7eb98d5b4a" || return 1
    verify_file "$directory/com.sony.sensor.imx582.so" "774784c3e3e30e2e2da8bebb42db7cab712b577563ab243d2bb36c91ee2b31cd" || return 1
    verify_file "$directory/com.sony.sensormodule.murray_front.bin" "b6891c7e331af0349bc2c3dabcf01a12b27d8ec35b48e461010ad5c148a2de38" || return 1
    verify_file "$directory/com.sony.sensormodule.murray_tele.bin" "$tele_sha" || return 1
    verify_file "$directory/com.sony.sensormodule.murray_uwide.bin" "1bc0bc891e70441d85ac0790ef0ccf116de3cbd30d0fb546c9885b3f6b8b141f" || return 1
    verify_file "$directory/com.sony.sensormodule.murray_wide.bin" "19177e4784d372b78416171a2e15e0022f217f78738e886c82e4721847f8160d" || return 1
    verify_file "$directory/com.sony.sensormodule.zambezi_wide.bin" "d6bfb399446382ea1ea7a1f09b8be5abba6b1874ee8efd0dc43dbc597d5f7451" || return 1
}

verify_output() {
    [ -d "$OUTPUT_DIR" ] || { info "Not prepared: $OUTPUT_DIR"; return 1; }
    verify_camera_tree "$OUTPUT_DIR" "$PATCHED_TELE_SHA" || return 1
    verify_file "$OUTPUT_DIR/$TUNING" "$TUNING_SHA" || return 1
    info "Prepared binaries verified: $OUTPUT_DIR"
}

# Shell octal escapes are POSIX-compliant with printf %b. The writes are
# at fixed offsets of the SHA-256-verified original binary. No external
# hex editor, Perl or Python is needed on the phone.
patch_at() {
    offset=$1
    octal_bytes=$2
    if ! printf '%b' "$octal_bytes" | dd of="$STAGING/$TELE" bs=1 seek="$offset" conv=notrunc 2>/dev/null; then
        fail "Cannot patch $TELE at offset $offset"
    fi
}

apply_patch() {
    [ "$(wc -c < "$STAGING/$TELE" | tr -d ' ')" = "410099" ] || fail "Unexpected original tele binary size"

    # Parser header offsets / metadata, GT9769 settings, and tuning reference.
    patch_at 28 '\0013\0102'
    patch_at 188 '\0223'
    patch_at 196 '\0367'
    patch_at 1484 '\0203\0102\0001'
    patch_at 1488 '\0020'
    patch_at 324324 '\0173\0102\0001'
    patch_at 324492 '\0177\0102'
    patch_at 328120 '\0034'
    patch_at 328122 '\0001'
    patch_at 328188 '\0264'
    patch_at 328292 '\0023'
    patch_at 328304 '\0021'
    patch_at 329032 '\0041'
    patch_at 329044 '\0043'
    patch_at 329056 '\0045'
    patch_at 329072 '\0047'
    patch_at 329084 '\0341\0010'
    patch_at 329114 '\0243'
    patch_at 329674 '\0066\0071'
    patch_at 329694 '\0020'
    patch_at 409375 '\0000'
    patch_at 409415 '\0002'
    patch_at 409455 '\0006'
    patch_at 409495 '\0007'
    patch_at 409527 '\0000'
    patch_at 409531 '\0000'
    patch_at 409535 '\0002'
    patch_at 409563 '\0350\0003'
    patch_at 409971 '\0235'
    patch_at 409983 '\0237'
    patch_at 409995 '\0241'
    patch_at 410079 '\0141\0000\0000\0000\0071\0000\0000\0000\0142\0154\0141\0151\0162\0137\0154\0143\0145\0137\0150\0151\0070\0064\0067\0000\0000\0000\0000\0000\0000\0000\0000\0000\0000\0000\0000\0000\0000\0000\0000\0000\0377\0377\0377\0377'

    [ "$(wc -c < "$STAGING/$TELE" | tr -d ' ')" = "410123" ] || fail "Unexpected patched tele binary size"
    verify_file "$STAGING/$TELE" "$PATCHED_TELE_SHA" || fail "Tele binary patch verification failed"
}

usage() {
    printf '%s\n' "Usage: $0 status | apply [path/to/stock/$TUNING]"
}

case "${1:-}" in
    status)
        info 'Checking unmodified Sony v4b source files...'
        if verify_camera_tree "$SOURCE_DIR" "$ORIGINAL_TELE_SHA"; then
            info 'Source: correct Sony v4b files'
        else
            info 'Source: missing, modified or wrong Sony version'
        fi
        if [ -d "$OUTPUT_DIR" ]; then
            verify_output || fail 'Output directory exists but does not match the tested patched files'
        else
            info "Output not yet created: $OUTPUT_DIR"
        fi
        exit 0
        ;;
    apply)
        [ "$#" -le 2 ] || { usage; exit 2; }
        [ "$(id -u)" -eq 0 ] || fail 'Run as root (devel-su)'
        for program in sha256sum dd cp mv mktemp wc tr; do
            command -v "$program" >/dev/null 2>&1 || fail "Missing command: $program"
        done
        tuning_file=${2:-$DEFAULT_TUNING}
        [ -f "$tuning_file" ] || fail "Missing original stock tuning file: $tuning_file. Extract it from your own Xperia 10 V stock firmware."
        verify_file "$tuning_file" "$TUNING_SHA" || fail 'Unsupported stock tuning file'

        if [ -e "$OUTPUT_DIR" ] || [ -L "$OUTPUT_DIR" ]; then
            if verify_output; then
                info 'Already prepared: no changes made.'
                exit 0
            fi
            fail "Output exists but differs. Move it away manually before retrying: $OUTPUT_DIR"
        fi

        [ -d "$SOURCE_DIR" ] || fail "Missing source camera directory: $SOURCE_DIR"
        # A source directory already bind-mounted to patched data must not be
        # used as a new source. Require exactly the known original directory.
        verify_camera_tree "$SOURCE_DIR" "$ORIGINAL_TELE_SHA" || fail 'Source is not the expected unmodified Sony v4b camera directory'

        mkdir -p "$PROJECT_DIR"
        STAGING=$(mktemp -d "$PROJECT_DIR/.camera-binaries.XXXXXXXX") || fail 'Could not create staging directory'
        trap 'rm -rf "$STAGING"' EXIT HUP INT TERM
        cp -a "$SOURCE_DIR"/. "$STAGING"/ || fail 'Could not copy source camera directory'
        verify_camera_tree "$STAGING" "$ORIGINAL_TELE_SHA" || fail 'Copied data does not match source'
        info 'Patching GT9769 telephoto configuration...'
        apply_patch
        cp -p "$tuning_file" "$STAGING/$TUNING" || fail 'Could not copy stock tuning file'
        verify_camera_tree "$STAGING" "$PATCHED_TELE_SHA" || fail 'Prepared camera files failed verification'
        verify_file "$STAGING/$TUNING" "$TUNING_SHA" || fail 'Copied tuning file failed verification'
        { [ ! -e "$OUTPUT_DIR" ] && [ ! -L "$OUTPUT_DIR" ]; } || fail 'Output appeared during preparation; refusing to overwrite it'
        mv "$STAGING" "$OUTPUT_DIR" || fail 'Could not publish prepared camera directory'
        trap - EXIT HUP INT TERM
        info "Camera binaries prepared and verified at: $OUTPUT_DIR"
        info 'Original /odm files were not modified.'
        ;;
    *)
        usage
        exit 2
        ;;
esac
