#!/bin/sh

set -eu

SUPPORTED_SFOS_VERSION=5.1.0.11
GLOBAL_FILE=/usr/libexec/droid-hybris/system/etc/init/disabled_services.rc
DEVICE_FILE=/usr/libexec/droid-hybris/system/etc/init/disabled_services_device.rc
MEDIA_DEFINITION=/system/etc/init/mediaextractor.rc
CAMERA_DEFINITION=/vendor/etc/init/android.hardware.camera.provider@2.5-service_64.rc
BACKUP_ROOT=/root/sailfish-xperia-10v-tweaks/backups

MEDIA_SERVICE='service mediaextractor /system/bin/mediaextractor_HYBRIS_DISABLED'
CAMERA_SERVICE='service vendor.camera-provider-2-5 /vendor/bin/hw/android.hardware.camera.provider@2.5-service_64_HYBRIS_DISABLED'
MARKER='# sailfish-xperia-10v-tweaks: '

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

sfos_version() {
    sed -n 's/^VERSION_ID=//p' /etc/os-release 2>/dev/null | tr -d '"'
}

override_state() {
    file=$1
    service=$2
    plain_count=$(grep -Fxc "$service" "$file" || true)
    marked_count=$(grep -Fxc "$MARKER$service" "$file" || true)

    case "$plain_count:$marked_count" in
        1:0) printf 'disabled' ;;
        0:1) printf 'enabled' ;;
        *)   printf 'unknown' ;;
    esac
}

runtime_state() {
    value=$(getprop "init.svc.$1" 2>/dev/null || true)
    [ -n "$value" ] && printf '%s' "$value" || printf 'unknown'
}

show_status() {
    version=$(sfos_version)
    [ -n "$version" ] || version=unknown
    printf 'Sailfish OS version:              %s\n' "$version"
    printf 'mediaextractor override:          %s\n' \
        "$(override_state "$GLOBAL_FILE" "$MEDIA_SERVICE")"
    printf 'camera provider override:         %s\n' \
        "$(override_state "$DEVICE_FILE" "$CAMERA_SERVICE")"
    printf 'mediaextractor runtime:           %s\n' \
        "$(runtime_state mediaextractor)"
    printf 'camera provider runtime:          %s\n' \
        "$(runtime_state vendor.camera-provider-2-5)"
}

check_known_state() {
    [ -r "$GLOBAL_FILE" ] || die "Cannot read $GLOBAL_FILE"
    [ -r "$DEVICE_FILE" ] || die "Cannot read $DEVICE_FILE"
    [ "$(override_state "$GLOBAL_FILE" "$MEDIA_SERVICE")" != unknown ] ||
        die "Unknown mediaextractor override state; no files were changed."
    [ "$(override_state "$DEVICE_FILE" "$CAMERA_SERVICE")" != unknown ] ||
        die "Unknown camera provider override state; no files were changed."
}

check_target() {
    version=$(sfos_version)
    [ -n "$version" ] || version=unknown
    [ "$version" = "$SUPPORTED_SFOS_VERSION" ] ||
        die "Only Sailfish OS $SUPPORTED_SFOS_VERSION is supported (found $version)."

    grep -Fqx 'service mediaextractor /system/bin/mediaextractor' \
        "$MEDIA_DEFINITION" ||
        die "Expected mediaextractor definition not found in $MEDIA_DEFINITION"
    grep -Fqx 'service vendor.camera-provider-2-5 /vendor/bin/hw/android.hardware.camera.provider@2.5-service_64' \
        "$CAMERA_DEFINITION" ||
        die "Expected camera provider definition not found in $CAMERA_DEFINITION"
}

backup_files() {
    backup_dir=$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)
    mkdir -p "$backup_dir"
    cp -a "$GLOBAL_FILE" "$backup_dir/disabled_services.rc"
    cp -a "$DEVICE_FILE" "$backup_dir/disabled_services_device.rc"
    printf 'Backup: %s\n' "$backup_dir"
}

rewrite_service() {
    action=$1
    file=$2
    service=$3
    with_override=$4
    tmp=$file.sxt.$$

    trap 'rm -f "$tmp"' EXIT HUP INT TERM
    cp -a "$file" "$tmp"

    if ! awk \
        -v action="$action" \
        -v service="$service" \
        -v marker="$MARKER" \
        -v with_override="$with_override" '
        action == "enable" && $0 == service {
            print marker $0
            if (with_override) {
                if ((getline following) <= 0 || following != "    override")
                    exit 2
                print marker following
            }
            changed++
            next
        }
        action == "disable" && $0 == marker service {
            print service
            if (with_override) {
                if ((getline following) <= 0 || following != marker "    override")
                    exit 2
                print "    override"
            }
            changed++
            next
        }
        { print }
        END {
            if (changed != 1)
                exit 3
        }
    ' "$file" > "$tmp"; then
        rm -f "$tmp"
        trap - EXIT HUP INT TERM
        die "Unexpected service block in $file; no changes were applied."
    fi

    mv -f "$tmp" "$file"
    trap - EXIT HUP INT TERM
}

if [ "$#" -eq 0 ]; then
    action=status
else
    action=$1
fi

case "$action" in
    status)
        check_known_state
        show_status
        ;;
    apply|revert)
        [ "$(id -u)" -eq 0 ] || die "Run this action as root."
        check_known_state
        check_target
        backup_files

        media_state=$(override_state "$GLOBAL_FILE" "$MEDIA_SERVICE")
        camera_state=$(override_state "$DEVICE_FILE" "$CAMERA_SERVICE")

        if [ "$action" = apply ]; then
            [ "$media_state" = enabled ] ||
                rewrite_service enable "$GLOBAL_FILE" "$MEDIA_SERVICE" 1
            [ "$camera_state" = enabled ] ||
                rewrite_service enable "$DEVICE_FILE" "$CAMERA_SERVICE" 0
            printf 'Camera subsystem enabled. Reboot, then run status again.\n'
        else
            [ "$media_state" = disabled ] ||
                rewrite_service disable "$GLOBAL_FILE" "$MEDIA_SERVICE" 1
            [ "$camera_state" = disabled ] ||
                rewrite_service disable "$DEVICE_FILE" "$CAMERA_SERVICE" 0
            printf 'Camera subsystem overrides restored. Reboot, then run status again.\n'
        fi
        ;;
    *)
        printf 'Usage: %s [status|apply|revert]\n' "$0" >&2
        exit 2
        ;;
esac
