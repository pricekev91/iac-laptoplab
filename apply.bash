#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="apply"

usage() {
    cat <<'EOF'
Usage:
  ./apply.bash inventory/<host>.yaml
  ./apply.bash --plan inventory/<host>.yaml

Modes:
  --plan   Validate inventory and print the reconciliation plan without executing LXD changes.
EOF
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

log() {
    echo "[apply] $*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

run_cmd() {
    if [[ "$MODE" == "plan" ]]; then
        printf '[plan]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

container_exists() {
    local project="$1"
    local name="$2"

    lxc list --project "$project" --format csv -c n | grep -Fxq "$name"
}

project_exists() {
    local project="$1"

    lxc project list --format csv -c n | grep -Fxq "$project"
}

profile_exists() {
    local profile="$1"

    lxc profile list --format csv -c n | grep -Fxq "$profile"
}

container_running() {
    local project="$1"
    local name="$2"

local result
    result="$(lxc list --project "$project" --format csv -c ns | awk -F, -v target="$name" '$1 == target { print $2 }')"
    [[ "$result" == "RUNNING" ]]
}

render_profile_yaml() {
    local profile_file="$1"

    python3 - "$profile_file" <<'PY'
import pathlib
import sys

profile_path = pathlib.Path(sys.argv[1])
content = profile_path.read_text().splitlines()
indent_stack = [(-1, {})]

def parse_scalar(value):
    if value == "{}":
        return {}
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    return value.strip('"')

root = {}
stack = [(-1, root)]

for raw_line in content:
    if not raw_line.strip() or raw_line.lstrip().startswith("#"):
        continue
    indent = len(raw_line) - len(raw_line.lstrip(" "))
    line = raw_line.strip()
    while stack and indent <= stack[-1][0]:
        stack.pop()
    current = stack[-1][1]
    key, _, value = line.partition(":")
    key = key.strip()
    value = value.strip()
    if not value:
        current[key] = {}
        stack.append((indent, current[key]))
    else:
        current[key] = parse_scalar(value)

print("config:")
config = root.get("config", {})
if config:
    for key, value in config.items():
        print(f"  {key}: {str(value).lower() if isinstance(value, bool) else value}")
print(f"description: {root.get('description', '')}")
print("devices:")
for device_name, device in root.get("devices", {}).items():
    print(f"  {device_name}:")
    for key, value in device.items():
        print(f"    {key}: {value}")
print(f"name: {root.get('name', '')}")
PY
}

parse_state() {
    local inventory_path="$1"

    python3 - "$inventory_path" "$SCRIPT_DIR" <<'PY'
import json
import pathlib
import re
import sys

inventory_path = pathlib.Path(sys.argv[1]).resolve()
repo_root = pathlib.Path(sys.argv[2]).resolve()

def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)

def parse_scalar(value):
    lowered = value.lower()
    if lowered == 'true':
        return True
    if lowered == 'false':
        return False
    if re.fullmatch(r'-?\d+', value):
        return int(value)
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value

def parse_yaml_lines(lines):
    root = {}
    stack = [(-1, root)]

    index = 0
    while index < len(lines):
        raw_line = lines[index]
        line = raw_line.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            index += 1
            continue

        indent = len(line) - len(line.lstrip(' '))
        stripped = line.strip()

        while len(stack) > 1 and indent <= stack[-1][0]:
            stack.pop()

        parent = stack[-1][1]

        if stripped.startswith('- '):
            value = stripped[2:].strip()
            if not isinstance(parent, list):
                fail(f'Invalid list item: {stripped}')

            if ': ' in value:
                key, raw_val = value.split(':', 1)
                item = {key.strip(): parse_scalar(raw_val.strip())}
                parent.append(item)
                stack.append((indent, item))
            else:
                parent.append(parse_scalar(value))
            index += 1
            continue

        if ':' not in stripped:
            fail(f'Invalid line: {stripped}')

        key, raw_val = stripped.split(':', 1)
        key = key.strip()
        raw_val = raw_val.strip()

        if raw_val == '':
            next_container = {}
            next_meaningful = None
            for candidate in lines[index + 1:]:
                if not candidate.strip() or candidate.lstrip().startswith('#'):
                    continue
                next_meaningful = candidate
                break

            if next_meaningful is not None:
                next_indent = len(next_meaningful) - len(next_meaningful.lstrip(' '))
                next_stripped = next_meaningful.strip()
                if next_indent > indent and next_stripped.startswith('- '):
                    next_container = []

            if isinstance(parent, list):
                fail(f'Unexpected mapping key in list context: {key}')

            parent[key] = next_container
            stack.append((indent, next_container))
            index += 1
            continue

        if raw_val == '>':
            folded = []
            continue_indent = None
            look_ahead = index + 1
            while look_ahead < len(lines):
                candidate = lines[look_ahead]
                if not candidate.strip():
                    look_ahead += 1
                    continue
                candidate_indent = len(candidate) - len(candidate.lstrip(' '))
                if candidate_indent <= indent:
                    break
                if continue_indent is None:
                    continue_indent = candidate_indent
                folded.append(candidate[continue_indent:].rstrip())
                look_ahead += 1

            if isinstance(parent, list):
                fail(f'Unexpected folded scalar in list context: {key}')
            parent[key] = ' '.join(part for part in folded if part)
            index = look_ahead
            continue

        if isinstance(parent, list):
            fail(f'Unexpected mapping key in list context: {key}')

        parent[key] = parse_scalar(raw_val)
        index += 1

    return root

def parse_yaml_file(path):
    lines = path.read_text().splitlines()
    return parse_yaml_lines(lines)

inventory = parse_yaml_file(inventory_path)

host = inventory.get('host', {})
projects = inventory.get('projects', [])
platform_names = inventory.get('platforms', [])
network = inventory.get('network', {})

required_host_keys = ['id', 'os', 'gpu', 'model_dir']
for key in required_host_keys:
    if key not in host:
        fail(f'Missing inventory host key: {key}')

if not projects:
    fail('Inventory must define at least one project')

if not platform_names:
    fail('Inventory must define at least one platform')

gpu_profile_map = {
    'nvidia': 'gpu-nvidia',
    'amd': 'gpu-amd',
    'intel': 'gpu-intel',
}

gpu_vendor = str(host['gpu']).lower()
gpu_profile = gpu_profile_map.get(gpu_vendor)
if gpu_profile is None:
    fail(f'Unsupported GPU vendor in inventory: {host["gpu"]}')

profile_file = repo_root / 'profiles' / f'{gpu_profile}.yaml'
if not profile_file.exists():
    fail(f'GPU profile file not found: {profile_file}')

platforms = []
for platform_name in platform_names:
    platform_file = repo_root / 'platforms' / f'{platform_name}.yaml'
    if not platform_file.exists():
        fail(f'Platform file not found: {platform_file}')

    platform = parse_yaml_file(platform_file)
    container = platform.get('container', {})
    mounts = container.get('mounts', [])
    env = container.get('env', {})
    profiles = container.get('profiles', [])
    ports = platform.get('ports', [])

    host_model_dir = str(host['model_dir'])
    resolved_mounts = []
    for mount in mounts:
        mount_host = str(mount.get('host', '')).replace('{{ host.model_dir }}', host_model_dir)
        resolved_mounts.append({
            'host': mount_host,
            'container': mount['container'],
            'readonly': bool(mount.get('readonly', False)),
        })

    resolved_profiles = []
    for profile in profiles:
        resolved_profiles.append(gpu_profile if profile == 'gpu' else profile)

    resolved_ports = []
    expose_ui = bool(network.get('expose_ui', False))
    for port in ports:
        bind_local_only = bool(port.get('bind_local_only', False))
        listen = '127.0.0.1' if bind_local_only and not expose_ui else '0.0.0.0'
        resolved_ports.append({
            'host': int(port['host']),
            'container': int(port['container']),
            'listen': listen,
        })

    platforms.append({
        'name': platform['name'],
        'project': platform['project'],
        'container_name': container['name'],
        'image': container['image'],
        'profiles': resolved_profiles,
        'mounts': resolved_mounts,
        'env': env,
        'command': container['command'],
        'ports': resolved_ports,
    })

state = {
    'inventory': str(inventory_path),
    'host': host,
    'projects': projects,
    'gpu_profile': gpu_profile,
    'gpu_profile_file': str(profile_file),
    'platforms': platforms,
}

print(json.dumps(state))
PY
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 1
fi

if [[ $# -eq 2 ]]; then
    [[ "$1" == "--plan" ]] || fail "Unknown option: $1"
    MODE="plan"
    inventory_file="$2"
else
    inventory_file="$1"
fi

[[ -f "$inventory_file" ]] || fail "Inventory file not found: $inventory_file"
require_command python3

state_json="$(parse_state "$inventory_file")"

eval "$(python3 - <<'PY' "$state_json"
import json
import shlex
import sys

state = json.loads(sys.argv[1])

def emit(name, value):
    print(f'{name}={shlex.quote(str(value))}')

emit('HOST_ID', state['host']['id'])
emit('GPU_PROFILE', state['gpu_profile'])
emit('GPU_PROFILE_FILE', state['gpu_profile_file'])
emit('PROJECT_COUNT', len(state['projects']))
emit('PLATFORM_COUNT', len(state['platforms']))

for index, project in enumerate(state['projects']):
    emit(f'PROJECT_{index}', project)

for index, platform in enumerate(state['platforms']):
    emit(f'PLATFORM_{index}_NAME', platform['name'])
    emit(f'PLATFORM_{index}_PROJECT', platform['project'])
    emit(f'PLATFORM_{index}_CONTAINER_NAME', platform['container_name'])
    emit(f'PLATFORM_{index}_IMAGE', platform['image'])
    emit(f'PLATFORM_{index}_COMMAND', platform['command'])
    emit(f'PLATFORM_{index}_PROFILE_COUNT', len(platform['profiles']))
    emit(f'PLATFORM_{index}_MOUNT_COUNT', len(platform['mounts']))
    emit(f'PLATFORM_{index}_ENV_COUNT', len(platform['env']))
    emit(f'PLATFORM_{index}_PORT_COUNT', len(platform['ports']))

    for p_index, profile in enumerate(platform['profiles']):
        emit(f'PLATFORM_{index}_PROFILE_{p_index}', profile)

    for m_index, mount in enumerate(platform['mounts']):
        emit(f'PLATFORM_{index}_MOUNT_{m_index}_HOST', mount['host'])
        emit(f'PLATFORM_{index}_MOUNT_{m_index}_CONTAINER', mount['container'])
        emit(f'PLATFORM_{index}_MOUNT_{m_index}_READONLY', str(mount['readonly']).lower())

    for e_index, (key, value) in enumerate(platform['env'].items()):
        emit(f'PLATFORM_{index}_ENV_{e_index}_KEY', key)
        emit(f'PLATFORM_{index}_ENV_{e_index}_VALUE', value)

    for port_index, port in enumerate(platform['ports']):
        emit(f'PLATFORM_{index}_PORT_{port_index}_HOST', port['host'])
        emit(f'PLATFORM_{index}_PORT_{port_index}_CONTAINER', port['container'])
        emit(f'PLATFORM_{index}_PORT_{port_index}_LISTEN', port['listen'])
PY
)"

log "Host: $HOST_ID"
log "Mode: $MODE"
log "Resolved GPU profile: $GPU_PROFILE"

for ((i = 0; i < PROJECT_COUNT; i++)); do
    project_var="PROJECT_${i}"
    project_name="${!project_var}"
    log "Ensure project: $project_name"

    if [[ "$MODE" == "apply" ]]; then
        require_command lxc
        if ! project_exists "$project_name"; then
            run_cmd lxc project create "$project_name"
        else
            log "Project already present: $project_name"
        fi
    else
        run_cmd lxc project create "$project_name"
    fi
done

log "Ensure GPU profile from $GPU_PROFILE_FILE"
if [[ "$MODE" == "apply" ]]; then
    require_command lxc
    if profile_exists "$GPU_PROFILE"; then
        log "Profile already present: $GPU_PROFILE"
    else
        run_cmd lxc profile create "$GPU_PROFILE"
    fi

    render_profile_yaml "$GPU_PROFILE_FILE" | lxc profile edit "$GPU_PROFILE"
else
    run_cmd lxc profile create "$GPU_PROFILE"
    printf '[plan] lxc profile edit %q < %q\n' "$GPU_PROFILE" "$GPU_PROFILE_FILE"
fi

for ((i = 0; i < PLATFORM_COUNT; i++)); do
    name_var="PLATFORM_${i}_NAME"
    project_var="PLATFORM_${i}_PROJECT"
    container_var="PLATFORM_${i}_CONTAINER_NAME"
    image_var="PLATFORM_${i}_IMAGE"
    command_var="PLATFORM_${i}_COMMAND"
    profile_count_var="PLATFORM_${i}_PROFILE_COUNT"
    mount_count_var="PLATFORM_${i}_MOUNT_COUNT"
    env_count_var="PLATFORM_${i}_ENV_COUNT"
    port_count_var="PLATFORM_${i}_PORT_COUNT"

    platform_name="${!name_var}"
    project_name="${!project_var}"
    container_name="${!container_var}"
    image_name="${!image_var}"
    command_value="${!command_var}"
    profile_count="${!profile_count_var}"
    mount_count="${!mount_count_var}"
    env_count="${!env_count_var}"
    port_count="${!port_count_var}"

    log "Reconciling platform: $platform_name"

    profile_args=()
    for ((p = 0; p < profile_count; p++)); do
        profile_var="PLATFORM_${i}_PROFILE_${p}"
        profile_args+=("${!profile_var}")
    done

    if [[ "$MODE" == "apply" ]]; then
        require_command lxc
        if ! container_exists "$project_name" "$container_name"; then
            init_args=(lxc init "$image_name" "$container_name" --project "$project_name")
            run_cmd "${init_args[@]}"
        else
            log "Container already present: $project_name/$container_name"
        fi
    else
        init_args=(lxc init "$image_name" "$container_name" --project "$project_name")
        run_cmd "${init_args[@]}"
    fi

    if (( profile_count > 0 )); then
        profile_assign_args=(lxc profile assign "$container_name" --project "$project_name")
        for profile_name in "${profile_args[@]}"; do
            profile_assign_args+=("$profile_name")
        done
        run_cmd "${profile_assign_args[@]}"
    fi

    for ((m = 0; m < mount_count; m++)); do
        mount_host_var="PLATFORM_${i}_MOUNT_${m}_HOST"
        mount_container_var="PLATFORM_${i}_MOUNT_${m}_CONTAINER"
        mount_ro_var="PLATFORM_${i}_MOUNT_${m}_READONLY"
        device_name="disk-${platform_name}-${m}"
        readonly_flag="${!mount_ro_var}"

        run_cmd lxc config device remove "$container_name" "$device_name" --project "$project_name" || true
        device_args=(lxc config device add "$container_name" "$device_name" disk --project "$project_name" source "${!mount_host_var}" path "${!mount_container_var}")
        if [[ "$readonly_flag" == "true" ]]; then
            device_args+=(readonly=true)
        fi
        run_cmd "${device_args[@]}"
    done

    for ((e = 0; e < env_count; e++)); do
        env_key_var="PLATFORM_${i}_ENV_${e}_KEY"
        env_value_var="PLATFORM_${i}_ENV_${e}_VALUE"
        run_cmd lxc config set "$container_name" "environment.${!env_key_var}" "${!env_value_var}" --project "$project_name"
    done

    run_cmd lxc config set "$container_name" user.command "$command_value" --project "$project_name"

    for ((p = 0; p < port_count; p++)); do
        host_port_var="PLATFORM_${i}_PORT_${p}_HOST"
        container_port_var="PLATFORM_${i}_PORT_${p}_CONTAINER"
        listen_var="PLATFORM_${i}_PORT_${p}_LISTEN"
        proxy_name="proxy-${platform_name}-${p}"
        connect_target="tcp:127.0.0.1:${!container_port_var}"
        listen_target="tcp:${!listen_var}:${!host_port_var}"
        run_cmd lxc config device remove "$container_name" "$proxy_name" --project "$project_name" || true
        run_cmd lxc config device add "$container_name" "$proxy_name" proxy --project "$project_name" listen="$listen_target" connect="$connect_target"
    done

    if [[ "$MODE" == "apply" ]]; then
        if container_running "$project_name" "$container_name"; then
            run_cmd lxc restart "$container_name" --project "$project_name"
        else
            run_cmd lxc start "$container_name" --project "$project_name"
        fi
    else
        run_cmd lxc start "$container_name" --project "$project_name"
    fi
done

log "Reconciliation complete"