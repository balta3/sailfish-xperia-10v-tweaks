#!/bin/sh
# Xperia 10 V (PDX235): fail-open bind mount for the verified camera blobs.
#
# Usage (as root):
#   sh mount-camera-binaries.sh status
#   sh mount-camera-binaries.sh apply
#   sh mount-camera-binaries.sh revert
#
# No Sailfish OS version check: the input and output SHA-256 hashes are
# checked instead. 'apply' NEVER fails the Android startup on bad input.
# It does NOT generate or modify any camera blobs.

set -u
umask 077

PROJECT_DIR=${CAMERA_PROJECT_DIR:-/root/sailfish-xperia-10v-tweaks}
SOURCE_DIR=${CAMERA_OUTPUT_DIR:-$PROJECT_DIR/binaries}
TARGET_DIR=${CAMERA_TARGET_DIR:-/odm/lib64/camera}
DISABLE_FILE=$PROJECT_DIR/disable-camera-mount
STATE_FILE=$PROJECT_DIR/last-camera-mount-status

log() { printf 'sailfish-camera-binaries: %s\n' "$*"; }

record() {
    [ -d "$PROJECT_DIR" ] || return 0
    # Diagnostic information is best-effort and must never affect boot.
    {
        printf '%s | %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown-time')" "$*"
    } > "$STATE_FILE.$$" 2>/dev/null &&
        mv -f "$STATE_FILE.$$" "$STATE_FILE" 2>/dev/null ||
        rm -f "$STATE_FILE.$$" 2>/dev/null || :
}

skip() {
    log "SKIPPED: $*"
    record "SKIPPED: $*"
    exit 0
}

fail() {
    log "ERROR: $*" >&2
    record "ERROR: $*"
    exit 1
}

# Verify one file in a subshell to avoid clobbering caller variables.
verify_file() (
    file=$1
    expected=$2
    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    line=$(sha256sum "$file" 2>/dev/null) || return 1
    [ "${line%% *}" = "$expected" ]
)

# Intentionally fixed hashes: validation works across Sailfish updates
# *as long as the underlying Sony camera blobs remain unchanged*.
verify_original() {
    d=$1
    verify_file "$d/com.qti.tuned.default.bin" a53b78f5d10ff97b97f640469ef3c330817ba143bf5655d4699755453ae95a72 &&
    verify_file "$d/com.sony.sensor.hi846.so" 18b7183980bf2380ee3568ca589e0b8f2a1b5f22ef9026bb0ed245992e545cb2 &&
    verify_file "$d/com.sony.sensor.hi847.so" 388401aae7b232605cdf44c0e16d8d8164e4e912dc9f640177dc7a7eb98d5b4a &&
    verify_file "$d/com.sony.sensor.imx582.so" 774784c3e3e30e2e2da8bebb42db7cab712b577563ab243d2bb36c91ee2b31cd &&
    verify_file "$d/com.sony.sensormodule.murray_front.bin" b6891c7e331af0349bc2c3dabcf01a12b27d8ec35b48e461010ad5c148a2de38 &&
    verify_file "$d/com.sony.sensormodule.murray_tele.bin" 762c311c4dc009db271231f45bdb127f849e16a2d784cc72789ef2103e202f87 &&
    verify_file "$d/com.sony.sensormodule.murray_uwide.bin" 1bc0bc891e70441d85ac0790ef0ccf116de3cbd30d0fb546c9885b3f6b8b141f &&
    verify_file "$d/com.sony.sensormodule.murray_wide.bin" 19177e4784d372b78416171a2e15e0022f217f78738e886c82e4721847f8160d &&
    verify_file "$d/com.sony.sensormodule.zambezi_wide.bin" d6bfb399446382ea1ea7a1f09b8be5abba6b1874ee8efd0dc43dbc597d5f7451
}

verify_patched() {
    d=$1
    verify_file "$d/com.qti.tuned.default.bin" a53b78f5d10ff97b97f640469ef3c330817ba143bf5655d4699755453ae95a72 &&
    verify_file "$d/com.sony.sensor.hi846.so" 18b7183980bf2380ee3568ca589e0b8f2a1b5f22ef9026bb0ed245992e545cb2 &&
    verify_file "$d/com.sony.sensor.hi847.so" 388401aae7b232605cdf44c0e16d8d8164e4e912dc9f640177dc7a7eb98d5b4a &&
    verify_file "$d/com.sony.sensor.imx582.so" 774784c3e3e30e2e2da8bebb42db7cab712b577563ab243d2bb36c91ee2b31cd &&
    verify_file "$d/com.sony.sensormodule.murray_front.bin" b6891c7e331af0349bc2c3dabcf01a12b27d8ec35b48e461010ad5c148a2de38 &&
    verify_file "$d/com.sony.sensormodule.murray_tele.bin" dd8249c928dd0bb799e71f183f979f69e96821cadb2ea83ab8a2ebe114eeb7fb &&
    verify_file "$d/com.sony.sensormodule.murray_uwide.bin" 1bc0bc891e70441d85ac0790ef0ccf116de3cbd30d0fb546c9885b3f6b8b141f &&
    verify_file "$d/com.sony.sensormodule.murray_wide.bin" 19177e4784d372b78416171a2e15e0022f217f78738e886c82e4721847f8160d &&
    verify_file "$d/com.sony.sensormodule.zambezi_wide.bin" d6bfb399446382ea1ea7a1f09b8be5abba6b1874ee8efd0dc43dbc597d5f7451 &&
    verify_file "$d/com.qti.tuned.blair_lce_hi847.bin" fae940dd8cb3bf567a854cab3dd8cd474ae97b7219b6c9e022cc9d9a7e10b141
}

mounted_here() {
    # '-M' checks exact mountpoints; '-T' would also match the root filesystem.
    findmnt -rn -M "$TARGET_DIR" -o TARGET >/dev/null 2>&1
}

same_directory() {
    [ -d "$SOURCE_DIR" ] && [ -d "$TARGET_DIR" ] || return 1
    a=$(stat -Lc '%d:%i' "$SOURCE_DIR" 2>/dev/null) || return 1
    b=$(stat -Lc '%d:%i' "$TARGET_DIR" 2>/dev/null) || return 1
    [ "$a" = "$b" ]
}

preflight() {
    for program in sha256sum findmnt stat mount umount date; do
        command -v "$program" >/dev/null 2>&1 || return 1
    done
    [ -d "$SOURCE_DIR" ] && [ ! -L "$SOURCE_DIR" ] &&
    [ -d "$TARGET_DIR" ] && [ ! -L "$TARGET_DIR" ]
}

case "${1:-}" in
    status)
        if [ -e "$DISABLE_FILE" ]; then
            log "Autostart disabled by: $DISABLE_FILE"
        fi
        if ! command -v findmnt >/dev/null 2>&1 ||
           ! command -v stat >/dev/null 2>&1; then
            fail 'findmnt/stat unavailable'
        fi
        if mounted_here; then
            if same_directory; then
                log 'ACTIVE: prepared camera directory is bind-mounted'
                if verify_patched "$SOURCE_DIR"; then
                    log 'SHA-256 verification: OK'
                    exit 0
                fi
                fail 'Mounted files do not match tested camera binaries'
            fi
            fail "A different mount occupies $TARGET_DIR"
        fi
        log 'INACTIVE: original camera directory is visible'
        if verify_patched "$SOURCE_DIR"; then
            log 'Prepared camera binaries: verified'
        else
            log 'Prepared camera binaries: missing or invalid'
        fi
        if [ -f "$STATE_FILE" ]; then
            log "Last boot attempt: $(cat "$STATE_FILE" 2>/dev/null || true)"
        fi
        exit 0
        ;;
    apply)
        [ "$(id -u)" -eq 0 ] || skip 'Root privileges unavailable'
        [ ! -e "$DISABLE_FILE" ] || skip "disabled by $DISABLE_FILE"
        preflight || skip 'Required commands/directories unavailable'

        # An existing mount must never be overwritten or stacked.
        if mounted_here; then
            if same_directory && verify_patched "$SOURCE_DIR"; then
                log 'Already active: no changes made'
                record 'ACTIVE: already mounted'
                exit 0
            fi
            skip 'Target is already mounted (unexpected mount or invalid source)'
        fi

        verify_patched "$SOURCE_DIR" || skip 'Prepared binaries missing or SHA-256 mismatch'
        verify_original "$TARGET_DIR" || skip 'Original ODM camera files changed or unavailable'

        if ! mount --bind "$SOURCE_DIR" "$TARGET_DIR"; then
            skip 'Bind mount failed; using original ODM files'
        fi
        if mounted_here && same_directory; then
            log "ACTIVE: $SOURCE_DIR -> $TARGET_DIR"
            record 'ACTIVE: bind mount successful'
            exit 0
        fi
        # Only reached after this process successfully invoked mount.
        # Avoid lazy/force unmount: a failed rollback is logged but must
        # not hold Android startup.
        if mounted_here; then
            umount "$TARGET_DIR" 2>/dev/null || log 'WARNING: rollback unmount failed'
        fi
        skip 'Post-mount verification failed'
        ;;
    revert)
        [ "$(id -u)" -eq 0 ] || fail 'Run as root'
        command -v findmnt >/dev/null 2>&1 &&
            command -v stat >/dev/null 2>&1 || fail 'findmnt/stat unavailable'
        if ! mounted_here; then
            log 'Already inactive'
            exit 0
        fi
        same_directory || fail 'Refusing to unmount an unknown source'
        umount "$TARGET_DIR" || fail 'Unmount failed (camera services may be using the files)'
        log 'INACTIVE: original ODM camera directory restored'
        record 'INACTIVE: manually unmounted'
        ;;
    *)
        printf 'Usage: %s {status|apply|revert}\n' "$0" >&2
        exit 2
        ;;
esac
