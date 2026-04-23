#!/usr/bin/env bash

set -euo pipefail

SCRIPT_VERSION="0.1.0"
MODEL_ROOT="/srv/models"
LXD_STORAGE_DIR="/var/lib/lxd"
LXD_STORAGE_POOL="ai-default"
LXD_STORAGE_POOL_DIR="${LXD_STORAGE_DIR}/storage-pools/${LXD_STORAGE_POOL}"
LXD_NETWORK="ai-lxdbr0"
LXD_NETWORK_IPV4="10.126.64.1/24"
LXD_SUBID_HOST_START="1000000"
LXD_SUBID_RANGE="1000000000"
ACTIVE_LXD_STORAGE_POOL="$LXD_STORAGE_POOL"
ACTIVE_LXD_NETWORK="$LXD_NETWORK"

log() {
    echo "[bootstrap] $*"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

default_uplink_interface() {
    ip route show default | awk '/^default/ { print $5; exit }'
}

ensure_subid_range() {
    local mapping_file="$1"
    local account="$2"
    local desired_entry="${account}:${LXD_SUBID_HOST_START}:${LXD_SUBID_RANGE}"
    local temp_file

    if awk -F: -v account="$account" -v start="$LXD_SUBID_HOST_START" -v range="$LXD_SUBID_RANGE" '
        $1 == account && $2 == start && $3 == range { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$mapping_file"; then
        log "Subordinate ID range already present in $mapping_file for $account"
        return 0
    fi

    temp_file="$(mktemp)"
    awk -F: -v account="$account" '$1 != account { print $0 }' "$mapping_file" > "$temp_file"
    printf '%s\n' "$desired_entry" >> "$temp_file"
    install -m 0644 "$temp_file" "$mapping_file"
    rm -f "$temp_file"

    log "Configured subordinate ID range in $mapping_file for $account"
}

path_is_empty_dir() {
    local dir_path="$1"

    [[ -d "$dir_path" ]] || return 1
    find "$dir_path" -mindepth 1 -maxdepth 1 | read -r _ && return 1
    return 0
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
        kmod
        lxd
        lxcfs
        dnsmasq
        iptables-nft
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

wait_for_lxd() {
    local attempt

    for attempt in $(seq 1 20); do
        if lxc info >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    fail "LXD daemon did not become ready in time"
}

require_kernel_module_tree() {
    local running_kernel
    local modules_dir

    running_kernel="$(uname -r)"
    modules_dir="/usr/lib/modules/${running_kernel}"

    if [[ -d "$modules_dir" ]]; then
        return 0
    fi

    fail "No kernel module tree exists for the running kernel ${running_kernel}. Reboot into an installed kernel or reinstall the matching CachyOS kernel package set before rerunning bootstrap."
}

ensure_bridge_support() {
    require_command modprobe
    require_kernel_module_tree

    if modprobe bridge >/dev/null 2>&1; then
        log "Linux bridge kernel support ready"
        return 0
    fi

    fail "Unable to load the Linux bridge kernel module for $(uname -r). Reboot into the installed kernel or reinstall the matching CachyOS kernel packages before rerunning bootstrap."
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

ensure_lxd_subid_ranges() {
    ensure_subid_range /etc/subuid root
    ensure_subid_range /etc/subgid root

    if getent passwd lxd >/dev/null 2>&1; then
        ensure_subid_range /etc/subuid lxd
        ensure_subid_range /etc/subgid lxd
    fi
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

    if lxc profile show default >/dev/null 2>&1; then
        log "LXD already initialized"
        return 0
    fi

    log "Running non-interactive lxd init"
    lxd init --auto
    wait_for_lxd
}

storage_pool_exists() {
    local pool="$1"

    lxc storage show "$pool" >/dev/null 2>&1
}

default_root_pool() {
    lxc profile show default | awk '
        /^devices:/ { in_devices=1; next }
        in_devices && /^  root:$/ { in_root=1; next }
        in_root && /^    pool:/ { print $2; exit }
        in_root && /^  [^ ]/ { in_root=0 }
    '
}

storage_pool_status() {
    local pool="$1"

    lxc storage show "$pool" | awk '
        /^status:/ { print $2; found=1; exit }
        END { exit(found ? 0 : 1) }
    '
}

network_status() {
    local network="$1"

    lxc network show "$network" | awk '
        /^status:/ { print $2; found=1; exit }
        END { exit(found ? 0 : 1) }
    '
}

default_profile_network() {
    lxc profile show default | awk '
        /^devices:/ { in_devices=1; next }
        in_devices && /^  eth0:$/ { in_eth0=1; next }
        in_eth0 && /^    network:/ { print $2; exit }
        in_eth0 && /^  [^ ]/ { in_eth0=0 }
    '
}

network_exists() {
    local network="$1"

    lxc network show "$network" >/dev/null 2>&1
}

network_ready() {
    local network="$1"

    lxc network info "$network" >/dev/null 2>&1
}

ensure_lxd_firewall_access() {
    local network_name="$1"
    local uplink_interface

    if ! command_exists ufw; then
        return 0
    fi

    if ! ufw status | grep -iq '^status: active'; then
        return 0
    fi

    log "Allowing trusted container traffic on $network_name through ufw"
    ufw allow in on "$network_name"

    uplink_interface="$(default_uplink_interface || true)"
    if [[ -n "$uplink_interface" ]]; then
        log "Allowing routed container traffic from $network_name out through $uplink_interface"
        ufw route allow in on "$network_name" out on "$uplink_interface"
    fi
}

adopt_active_default_resources() {
    local default_pool
    local default_network

    default_pool="$(default_root_pool || true)"
    if [[ -n "$default_pool" ]] && storage_pool_exists "$default_pool"; then
        ACTIVE_LXD_STORAGE_POOL="$default_pool"
        log "Reusing active default-profile storage pool: $ACTIVE_LXD_STORAGE_POOL"
    fi

    default_network="$(default_profile_network || true)"
    if [[ -n "$default_network" ]] && network_exists "$default_network"; then
        ACTIVE_LXD_NETWORK="$default_network"
        log "Reusing active default-profile network: $ACTIVE_LXD_NETWORK"
    fi
}

ensure_lxd_storage_pool() {
    local pool_name="$ACTIVE_LXD_STORAGE_POOL"
    local pool_dir="${LXD_STORAGE_DIR}/storage-pools/${pool_name}"
    local pool_status=""

    if storage_pool_exists "$pool_name"; then
        pool_status="$(storage_pool_status "$pool_name" || true)"
        case "${pool_status,,}" in
            available|created)
                log "LXD storage pool already present: $pool_name ($pool_status)"
                return 0
                ;;
            unavailable)
                log "Resetting unavailable LXD storage pool: $pool_name"
                lxc storage delete "$pool_name"
                ;;
            *)
                fail "Unexpected LXD storage pool status for $pool_name: ${pool_status:-unknown}"
                ;;
        esac
    fi

    if [[ -e "$pool_dir" ]]; then
        if path_is_empty_dir "$pool_dir"; then
            log "Removing stale empty storage pool directory: $pool_dir"
            rmdir "$pool_dir"
        else
            fail "Storage pool path already exists and is not empty: $pool_dir"
        fi
    fi

    log "Creating LXD storage pool: $pool_name"
    install -d -m 0711 "$LXD_STORAGE_DIR/storage-pools"
    lxc storage create "$pool_name" dir source="$pool_dir"
}

ensure_lxd_network() {
    local network_name="$ACTIVE_LXD_NETWORK"
    local bridge_status=""

    ensure_bridge_support

    if network_exists "$network_name"; then
        bridge_status="$(network_status "$network_name" || true)"
        case "${bridge_status,,}" in
            available|created)
                log "LXD network already present: $network_name ($bridge_status)"
                return 0
                ;;
            unavailable)
                log "Resetting unavailable LXD network: $network_name"
                lxc network delete "$network_name"
                ;;
            *)
                fail "Unexpected LXD network status for $network_name: ${bridge_status:-unknown}"
                ;;
        esac
    fi

    log "Creating LXD bridge network: $network_name"
    lxc network create "$network_name" ipv4.address="$LXD_NETWORK_IPV4" ipv4.nat=true ipv6.address=none
}

ensure_default_profile() {
    log "Configuring global default LXD profile"
    if ! lxc profile show default >/dev/null 2>&1; then
        lxc profile create default
    fi
    lxc profile device remove default root >/dev/null 2>&1 || true
    lxc profile device remove default eth0 >/dev/null 2>&1 || true
    lxc profile device add default root disk path=/ pool="$ACTIVE_LXD_STORAGE_POOL"
    lxc profile device add default eth0 nic name=eth0 network="$ACTIVE_LXD_NETWORK"
}

validate_lxd_prerequisites() {
    local storage_status
    local bridge_status

    storage_status="$(storage_pool_status "$ACTIVE_LXD_STORAGE_POOL")" || fail "Unable to determine status for LXD storage pool: $ACTIVE_LXD_STORAGE_POOL"
    case "${storage_status,,}" in
        available|created)
            log "LXD storage pool ready: $ACTIVE_LXD_STORAGE_POOL ($storage_status)"
            ;;
        *)
            fail "LXD storage pool '$ACTIVE_LXD_STORAGE_POOL' is not ready (status: $storage_status)"
            ;;
    esac

    bridge_status="$(network_status "$ACTIVE_LXD_NETWORK")" || fail "Unable to determine status for LXD network: $ACTIVE_LXD_NETWORK"
    case "${bridge_status,,}" in
        available|created)
            ;;
        *)
            fail "LXD network '$ACTIVE_LXD_NETWORK' is not ready (status: $bridge_status)"
            ;;
    esac

    if network_ready "$ACTIVE_LXD_NETWORK"; then
        log "LXD network ready: $ACTIVE_LXD_NETWORK"
    else
        fail "LXD network '$ACTIVE_LXD_NETWORK' exists but is not operational"
    fi
}

print_next_steps() {
    local target_user="$1"

    echo
    log "Bootstrap complete"
    log "LXD storage root: $LXD_STORAGE_DIR"
    log "Active LXD storage pool: $ACTIVE_LXD_STORAGE_POOL"
    log "Active LXD network: $ACTIVE_LXD_NETWORK"
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
    wait_for_lxd
    ensure_bridge_support
    ensure_lxd_group_access "$target_user"
    ensure_lxd_subid_ranges
    ensure_shared_layout
    ensure_lxd_initialized
    adopt_active_default_resources
    ensure_lxd_storage_pool
    ensure_lxd_network
    ensure_lxd_firewall_access "$ACTIVE_LXD_NETWORK"
    ensure_default_profile
    validate_lxd_prerequisites
    print_next_steps "$target_user"
}

main "$@"