#!/usr/bin/env bash

set -euo pipefail

SCRIPT_VERSION="0.1.0"
MODEL_ROOT="/srv/models"
LXD_STORAGE_DIR="/var/lib/lxd"

log() {
    echo "[bootstrap] $*"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        fail "Run this script as root or with sudo"
    fi
}

detect_target_user() {
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        printf '%s\n' "${SUDO_USER}"
        return 0
    fi

    if [[ -n "${PKEXEC_UID:-}" ]]; then
        getent passwd "${PKEXEC_UID}" | cut -d: -f1
        return 0
    fi

    printf '%s\n' ""
}

ensure_arch_family() {
    [[ -f /etc/os-release ]] || fail "/etc/os-release not found"
    . /etc/os-release

    case "${ID:-}" in
        arch|cachyos)
            ;;
        *)
            case " ${ID_LIKE:-} " in
                *" arch "*)
                    ;;
                *)
                    fail "This bootstrap currently supports Arch-family hosts only"
                    ;;
            esac
            ;;
    esac
}

install_packages() {
    local packages=(
        lxd
        lxcfs
        dnsmasq
        squashfs-tools
        qemu-base
        git
        curl
        rsync
    )

    log "Installing host packages"
    pacman -Sy --needed --noconfirm "${packages[@]}"
}

enable_services() {
    log "Enabling LXD and support services"
    systemctl enable --now lxd.service
    systemctl enable --now lxcfs.service
}

ensure_lxd_group_access() {
    local target_user="$1"

    if [[ -z "$target_user" ]]; then
        log "No non-root invoking user detected; skipping lxd group membership"
        return 0
    fi

    if id -nG "$target_user" | tr ' ' '\n' | grep -Fxq lxd; then
        log "User already in lxd group: $target_user"
        return 0
    fi

    log "Adding user to lxd group: $target_user"
    usermod -aG lxd "$target_user"
}

ensure_shared_layout() {
    log "Preparing shared model storage"
    install -d -m 0755 /srv
    install -d -m 2775 "$MODEL_ROOT"
    install -d -m 2775 "$MODEL_ROOT/cache"
    install -d -m 2775 "$MODEL_ROOT/gguf"
}

ensure_lxd_initialized() {
    log "Checking LXD initialization state"

    if lxc storage list >/dev/null 2>&1; then
        log "LXD already initialized"
        return 0
    fi

    log "Running non-interactive lxd init"
    lxd init --auto
}

print_next_steps() {
    local target_user="$1"

    echo
    log "Bootstrap complete"
    log "LXD storage root: $LXD_STORAGE_DIR"
    log "Shared model root: $MODEL_ROOT"

    if [[ -n "$target_user" ]]; then
        log "User $target_user must log out and back in for lxd group membership to apply"
    fi

    log "Next step: ./apply.bash --plan inventory/alienware-m17r2.yaml"
}

main() {
    local target_user

    require_root
    ensure_arch_family
    target_user="$(detect_target_user)"

    log "Arch/CachyOS bootstrap v${SCRIPT_VERSION}"
    install_packages
    enable_services
    ensure_lxd_group_access "$target_user"
    ensure_shared_layout
    ensure_lxd_initialized
    print_next_steps "$target_user"
}

main "$@"