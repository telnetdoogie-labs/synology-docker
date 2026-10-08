#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--force] [--fresh-anonymous-volumes] [--status-file PATH] [--volume-root PATH] EXPORT_OR_INSPECT.json [OUTPUT_DIR]" >&2
  echo "Existing output is compared; differing candidates are saved as .generated unless --force is used." >&2
  exit 1
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

yaml_string() {
  jq -n --arg value "$1" '$value'
}

force='false'
fresh_anonymous_volumes='false'
status_file=''
volume_root='/volume1'
positional=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -f|--force)
      force='true'
      shift
      ;;
    --fresh-anonymous-volumes)
      fresh_anonymous_volumes='true'
      shift
      ;;
    --status-file)
      shift
      [[ "${1:-}" != '' ]] || fail "--status-file requires a path"
      status_file=$1
      shift
      ;;
    --volume-root)
      shift
      [[ "${1:-}" != '' ]] || fail "--volume-root requires a path"
      volume_root=$1
      shift
      ;;
    -*)
      usage
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [[ "${#positional[@]}" -lt 1 ]] || [[ "${#positional[@]}" -gt 2 ]]; then
  usage
fi
input=${positional[0]}
output_dir=${positional[1]:-$(dirname "$input")}

[[ -f "$input" ]] || fail "Export file not found: $input"
mkdir -p "$output_dir" || fail "Could not create output directory: $output_dir"
command -v jq >/dev/null 2>&1 || fail "jq is required"

record=$(jq '
  def docker_inspect_to_export:
    {
      name: (.Name | ltrimstr("/")),
      image: .Config.Image,
      cmd: .Config.Cmd,
      entrypoint: .Config.Entrypoint,
      enable_restart_policy: ((.HostConfig.RestartPolicy.Name // "no") != "no"),
      restart_policy: (.HostConfig.RestartPolicy.Name // "no"),
      restart_maximum_retry_count: (.HostConfig.RestartPolicy.MaximumRetryCount // 0),
      network_mode: (if .HostConfig.NetworkMode == "default" and ((.NetworkSettings.Networks // {}) | keys) == ["bridge"] then "bridge" else .HostConfig.NetworkMode end),
      use_host_network: (.HostConfig.NetworkMode == "host"),
      network: ((.NetworkSettings.Networks // {}) | keys | map({name: .})),
      env_variables: ((.Config.Env // []) | map(if contains("=") then {key: split("=")[0], value: sub("^[^=]*="; "")} else {key: ., value: ""} end)),
      port_bindings: (((.HostConfig.PortBindings // {}) | to_entries | map(. as $entry | (.value // [{}]) | map({
          container_port: ($entry.key | split("/")[0] | tonumber),
          type: ($entry.key | split("/")[1] // "tcp"),
          host_port: (.HostPort // ""),
          host_ip: (.HostIp // "")
        }))) | add // []),
      volume_bindings: ((.Mounts // []) | map(select(.Type != "tmpfs") | {
          host_volume_file: (if .Type == "volume" then .Name else .Source end),
          named_volume: (.Type == "volume"),
          anonymous_volume: (.Type == "volume" and (.Name | test("^[0-9a-f]{64}$"))),
          absolute_host_path: (.Type == "bind"),
          mount_point: .Destination,
          type: (if .RW == false then "ro" else "rw" end)
        })),
      tmpfs: ((.Mounts // []) | map(select(.Type == "tmpfs") | .Destination + (if .RW == false then ":ro" else "" end))),
      labels: (.Config.Labels // {}),
      CapAdd: (.HostConfig.CapAdd // []),
      CapDrop: (.HostConfig.CapDrop // []),
      devices: ((.HostConfig.Devices // []) | map({path_on_host: .PathOnHost, path_in_container: .PathInContainer, cgroup_permissions: .CgroupPermissions})),
      privileged: (.HostConfig.Privileged // false),
      tty: (.Config.Tty // false),
      stdin_open: (.Config.OpenStdin // false),
      hostname: (.Config.Hostname // ""),
      domainname: (.Config.Domainname // ""),
      user: (.Config.User // ""),
      working_dir: (.Config.WorkingDir // ""),
      memory_limit: (.HostConfig.Memory // 0),
      shm_size: (.HostConfig.ShmSize // null),
      read_only: (.HostConfig.ReadonlyRootfs // false),
      oom_kill_disable: (.HostConfig.OomKillDisable // null),
      runtime: (.HostConfig.Runtime // null),
      uts: (.HostConfig.UtsMode // null),
      ipc: (.HostConfig.IpcMode // null),
      pid: (.HostConfig.PidMode // null),
      cgroupns: (.HostConfig.CgroupnsMode // null),
      userns: (.HostConfig.UsernsMode // null),
      stop_signal: (.Config.StopSignal // null),
      stop_timeout: (.Config.StopTimeout // null),
      healthcheck: (.Config.Healthcheck // null),
      security_opt: (.HostConfig.SecurityOpt // []),
      dns: (.HostConfig.Dns // []),
      dns_search: (.HostConfig.DnsSearch // []),
      extra_hosts: (.HostConfig.ExtraHosts // []),
      group_add: (.HostConfig.GroupAdd // []),
      links: (.HostConfig.Links // []),
      sysctls: (.HostConfig.Sysctls // {}),
      storage_opt: (.HostConfig.StorageOpt // {}),
      ulimits: ((.HostConfig.Ulimits // []) | map({name: .Name, soft: .Soft, hard: .Hard})),
      inspect_source: true
    };
  (if type == "array" then .[0] else . end)
  | if has("Config") and has("HostConfig") then docker_inspect_to_export else . end
' "$input") || fail "Invalid JSON export"
name=$(printf '%s\n' "$record" | jq -r '.name // .Name // empty')
image=$(printf '%s\n' "$record" | jq -r '.image // .Image // empty')
[[ -n "$name" ]] || fail "Export does not contain a container name"
[[ -n "$image" ]] || fail "Export does not contain an image"
[[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail "Unsupported container name: $name"

compose_file="${output_dir}/${name}.docker-compose.yml"
env_file="${output_dir}/${name}.env"
compose_temp=$(mktemp "${compose_file}.XXXXXX")
env_temp=$(mktemp "${env_file}.XXXXXX")
cleanup() {
  rm -f "$compose_temp" "$env_temp"
}
trap cleanup EXIT
volume_names=''
outputs_exist='false'
if [[ -e "$compose_file" ]] || [[ -e "$env_file" ]]; then
  outputs_exist='true'
fi

{
  printf 'name: %s\n' "$(yaml_string "$name")"
  printf 'services:\n'
  printf '  %s:\n' "$(yaml_string "$name")"
  printf '    image: %s\n' "$(yaml_string "$image")"
  printf '    container_name: %s\n' "$(yaml_string "$name")"

  if [[ "$(printf '%s\n' "$record" | jq -r '.env_variables | length')" -gt 0 ]]; then
    printf '    env_file:\n      - %s\n' "$(yaml_string "./${name}.env")"
  fi

  restart_policy=$(printf '%s\n' "$record" | jq -r '.restart_policy // empty')
  restart_count=$(printf '%s\n' "$record" | jq -r '.restart_maximum_retry_count // 0')
  case "$restart_policy" in
    always|unless-stopped)
      printf '    restart: %s\n' "$restart_policy"
      ;;
    on-failure)
      if [[ "$restart_count" -gt 0 ]]; then
        printf '    restart: %s\n' "$(yaml_string "on-failure:$restart_count")"
      else
        printf '    restart: on-failure\n'
      fi
      ;;
    *)
      if [[ "$(printf '%s\n' "$record" | jq -r '.enable_restart_policy // false')" = 'true' ]]; then
        printf '    restart: unless-stopped\n'
      fi
      ;;
  esac
  if [[ "$(printf '%s\n' "$record" | jq -r '.privileged // false')" = 'true' ]]; then
    printf '    privileged: true\n'
  fi
  if [[ "$(printf '%s\n' "$record" | jq -r '.tty // false')" = 'true' ]]; then
    printf '    tty: true\n'
  fi
  if [[ "$(printf '%s\n' "$record" | jq -r '.stdin_open // false')" = 'true' ]]; then
    printf '    stdin_open: true\n'
  fi

  for field in hostname domainname user working_dir runtime uts ipc pid cgroupns userns stop_signal shm_size; do
    value=$(printf '%s\n' "$record" | jq -r --arg field "$field" '.[$field] // empty')
    if [[ -n "$value" ]]; then
      compose_field=$field
      case "$field" in
        cgroupns) compose_field='cgroup' ;;
        userns) compose_field='userns_mode' ;;
      esac
      printf '    %s: %s\n' "$compose_field" "$(yaml_string "$value")"
    fi
  done
  if [[ "$(printf '%s\n' "$record" | jq -r '.read_only // false')" = 'true' ]]; then
    printf '    read_only: true\n'
  fi
  if [[ "$(printf '%s\n' "$record" | jq -r '.oom_kill_disable // empty')" = 'true' ]]; then
    printf '    oom_kill_disable: true\n'
  fi
  stop_timeout=$(printf '%s\n' "$record" | jq -r '.stop_timeout // empty')
  if [[ -n "$stop_timeout" ]]; then
    printf '    stop_grace_period: %ss\n' "$stop_timeout"
  fi

  entrypoint_json=$(printf '%s\n' "$record" | jq -c '.entrypoint // null')
  entrypoint_type=$(printf '%s\n' "$entrypoint_json" | jq -r 'type')
  if [[ "$entrypoint_type" = 'array' ]]; then
    printf '    entrypoint:\n'
    while IFS= read -r entrypoint_arg; do
      printf '      - %s\n' "$(yaml_string "$entrypoint_arg")"
    done < <(printf '%s\n' "$entrypoint_json" | jq -r '.[] | tostring')
  elif [[ "$entrypoint_type" != 'null' ]] && [[ "$entrypoint_json" != '""' ]]; then
    printf '    entrypoint: %s\n' "$entrypoint_json"
  fi

  for list_field in dns dns_search extra_hosts security_opt group_add tmpfs links; do
    if [[ "$(printf '%s\n' "$record" | jq -r --arg field "$list_field" '.[$field] | length')" -gt 0 ]]; then
      printf '    %s:\n' "$list_field"
      while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        printf '      - %s\n' "$(yaml_string "$item")"
      done < <(printf '%s\n' "$record" | jq -r --arg field "$list_field" '.[$field][]? | tostring')
    fi
  done

  network_mode=$(printf '%s\n' "$record" | jq -r '.network_mode // empty')
  network_names=''
  host_network='false'
  if [[ "$(printf '%s\n' "$record" | jq -r '.use_host_network // false')" = 'true' ]] || [[ "$network_mode" = 'host' ]]; then
    host_network='true'
    printf '    network_mode: host\n'
  elif [[ "$network_mode" = 'bridge' ]] || [[ "$network_mode" = 'none' ]] || [[ "$network_mode" == service:* ]] || [[ "$network_mode" == container:* ]]; then
    printf '    network_mode: %s\n' "$(yaml_string "$network_mode")"
  else
    network_names=$(printf '%s\n' "$record" | jq -r '.network[]? | .name // .Name // empty')
    if [[ -z "$network_names" ]] && [[ -n "$network_mode" ]]; then
      network_names=$network_mode
    fi
    if [[ -n "$network_names" ]]; then
      printf '    networks:\n'
      while IFS= read -r network_name; do
        [[ -n "$network_name" ]] || continue
        printf '      - %s\n' "$(yaml_string "$network_name")"
      done <<< "$network_names"
    fi
  fi

  if [[ "$host_network" != 'true' ]] && [[ "$(printf '%s\n' "$record" | jq -r '.port_bindings | length')" -gt 0 ]]; then
    printf '    ports:\n'
    while IFS= read -r binding; do
      container_port=$(printf '%s\n' "$binding" | jq -r '.container_port // empty')
      host_port=$(printf '%s\n' "$binding" | jq -r '.host_port // empty')
      host_ip=$(printf '%s\n' "$binding" | jq -r '.host_ip // empty')
      protocol=$(printf '%s\n' "$binding" | jq -r '.type // "tcp"')
      [[ -n "$container_port" ]] || fail "Port binding is missing container_port"
      if [[ -n "$host_ip" ]]; then
        if [[ "$host_ip" == *:* && "$host_ip" != \[*\] ]]; then
          host_ip="[$host_ip]"
        fi
        port_mapping="${host_ip}:${host_port}:${container_port}/${protocol}"
      elif [[ -n "$host_port" ]]; then
        port_mapping="${host_port}:${container_port}/${protocol}"
      else
        port_mapping="${container_port}/${protocol}"
      fi
      printf '      - %s\n' "$(yaml_string "$port_mapping")"
    done < <(printf '%s\n' "$record" | jq -c '.port_bindings[]?')
  fi

  if [[ "$(printf '%s\n' "$record" | jq -r '.volume_bindings | length')" -gt 0 ]]; then
    printf '    volumes:\n'
    while IFS= read -r binding; do
      host_path=$(printf '%s\n' "$binding" | jq -r '.host_volume_file // empty')
      container_path=$(printf '%s\n' "$binding" | jq -r '.mount_point // empty')
      access=$(printf '%s\n' "$binding" | jq -r '.type // "rw"')
      named_volume=$(printf '%s\n' "$binding" | jq -r '.named_volume // false')
      anonymous_volume=$(printf '%s\n' "$binding" | jq -r '(.anonymous_volume // (.named_volume == true and (.host_volume_file // "" | test("^[0-9a-f]{64}$"))))')
      absolute_host_path=$(printf '%s\n' "$binding" | jq -r '.absolute_host_path // false')
      if [[ -z "$host_path" ]] || [[ -z "$container_path" ]]; then
        fail "Volume binding is missing a host path or mount point"
      fi
      if [[ "$named_volume" = 'true' ]] && { [[ "$fresh_anonymous_volumes" != 'true' ]] || [[ "$anonymous_volume" != 'true' ]]; }; then
        volume_names="${volume_names}${host_path}"$'\n'
      elif [[ "$named_volume" != 'true' ]] && [[ "$absolute_host_path" != 'true' ]]; then
        case "$host_path" in
          /volume*|/dev/*|/run/*)
            ;;
          /*)
            host_path="${volume_root%/}/${host_path#/}"
            ;;
          *)
            fail "Unsupported relative volume path: $host_path"
            ;;
        esac
      fi
      if [[ "$named_volume" = 'true' ]] && [[ "$fresh_anonymous_volumes" = 'true' ]] && [[ "$anonymous_volume" = 'true' ]]; then
        volume_mapping="${container_path}:${access}"
      else
        volume_mapping="${host_path}:${container_path}:${access}"
      fi
      printf '      - %s\n' "$(yaml_string "$volume_mapping")"
    done < <(printf '%s\n' "$record" | jq -c '.volume_bindings[]?')
  fi

  for cap_field in CapAdd CapDrop; do
    case "$cap_field" in
      CapAdd) compose_field='cap_add' ;;
      CapDrop) compose_field='cap_drop' ;;
    esac
    if [[ "$(printf '%s\n' "$record" | jq -r --arg field "$cap_field" '.[$field] | length')" -gt 0 ]]; then
      printf '    %s:\n' "$compose_field"
      while IFS= read -r capability; do
        [[ -n "$capability" ]] || continue
        printf '      - %s\n' "$(yaml_string "$capability")"
      done < <(printf '%s\n' "$record" | jq -r --arg field "$cap_field" '.[$field][]?')
    fi
  done

  if [[ "$(printf '%s\n' "$record" | jq -r '.labels | length')" -gt 0 ]]; then
    printf '    labels:\n'
    while IFS= read -r label; do
      key=$(printf '%s\n' "$label" | jq -r '.key')
      value=$(printf '%s\n' "$label" | jq -r '.value | tostring')
      printf '      %s: %s\n' "$(yaml_string "$key")" "$(yaml_string "$value")"
    done < <(printf '%s\n' "$record" | jq -c '.labels | to_entries[]?')
  fi

  if [[ "$(printf '%s\n' "$record" | jq -r '.devices | length')" -gt 0 ]]; then
    printf '    devices:\n'
    while IFS= read -r device; do
      device_mapping=$(printf '%s\n' "$device" | jq -r 'if type == "string" then . else ((.path_on_host // .host_path // .host_volume_file // .source // empty) + ":" + (.path_in_container // .container_path // .mount_point // .destination // empty) + (if (.cgroup_permissions // .permissions // "") == "" then "" else ":" + (.cgroup_permissions // .permissions) end)) end')
      [[ "$device_mapping" == *:* ]] || fail "Unsupported device mapping in export"
      printf '      - %s\n' "$(yaml_string "$device_mapping")"
    done < <(printf '%s\n' "$record" | jq -c '.devices[]?')
  fi

  for map_field in sysctls storage_opt; do
    if [[ "$(printf '%s\n' "$record" | jq -r --arg field "$map_field" '.[$field] | length')" -gt 0 ]]; then
      printf '    %s:\n' "$map_field"
      while IFS= read -r item; do
        key=$(printf '%s\n' "$item" | jq -r '.key')
        value=$(printf '%s\n' "$item" | jq -r '.value | tostring')
        printf '      %s: %s\n' "$(yaml_string "$key")" "$(yaml_string "$value")"
      done < <(printf '%s\n' "$record" | jq -c --arg field "$map_field" '.[$field] | to_entries[]?')
    fi
  done

  if [[ "$(printf '%s\n' "$record" | jq -r '.ulimits | length')" -gt 0 ]]; then
    printf '    ulimits:\n'
    while IFS= read -r ulimit_entry; do
      limit_name=$(printf '%s\n' "$ulimit_entry" | jq -r '.name')
      soft_limit=$(printf '%s\n' "$ulimit_entry" | jq -r '.soft // empty')
      hard_limit=$(printf '%s\n' "$ulimit_entry" | jq -r '.hard // empty')
      printf '      %s:\n' "$(yaml_string "$limit_name")"
      [[ -n "$soft_limit" ]] && printf '        soft: %s\n' "$soft_limit"
      [[ -n "$hard_limit" ]] && printf '        hard: %s\n' "$hard_limit"
    done < <(printf '%s\n' "$record" | jq -c '.ulimits[]?')
  fi

  healthcheck=$(printf '%s\n' "$record" | jq -c '.healthcheck // null')
  if [[ "$healthcheck" != 'null' ]] && [[ "$(printf '%s\n' "$healthcheck" | jq -r 'length')" -gt 0 ]]; then
    printf '    healthcheck:\n'
    test_type=$(printf '%s\n' "$healthcheck" | jq -r '.Test[0] // empty')
    case "$test_type" in
      CMD-SHELL)
        health_test=$(printf '%s\n' "$healthcheck" | jq -r '.Test[1] // empty')
        printf '      test: %s\n' "$(yaml_string "$health_test")"
        ;;
      CMD)
        printf '      test:\n'
        while IFS= read -r test_arg; do
          printf '        - %s\n' "$(yaml_string "$test_arg")"
        done < <(printf '%s\n' "$healthcheck" | jq -r '.Test[1:][]? | tostring')
        ;;
      NONE)
        printf '      test: ["NONE"]\n'
        ;;
    esac
    for health_field in Interval Timeout StartPeriod StartInterval; do
      compose_health_field=$(printf '%s' "$health_field" | tr '[:upper:]' '[:lower:]')
      case "$compose_health_field" in
        startperiod) compose_health_field='start_period' ;;
        startinterval) compose_health_field='start_interval' ;;
      esac
      health_value=$(printf '%s\n' "$healthcheck" | jq -r --arg field "$health_field" '.[$field] // 0')
      if [[ "$health_value" != '0' ]]; then
        printf '      %s: %s\n' "$compose_health_field" "$(yaml_string "${health_value}ns")"
      fi
    done
    retries=$(printf '%s\n' "$healthcheck" | jq -r '.Retries // 0')
    [[ "$retries" != '0' ]] && printf '      retries: %s\n' "$retries"
  fi

  command_json=$(printf '%s\n' "$record" | jq -c '.cmd_v2 // .cmd // null')
  command_type=$(printf '%s\n' "$command_json" | jq -r 'type')
  if [[ "$command_type" = 'array' ]]; then
    printf '    command:\n'
    while IFS= read -r command_arg; do
      printf '      - %s\n' "$(yaml_string "$command_arg")"
    done < <(printf '%s\n' "$command_json" | jq -r '.[] | tostring')
  elif [[ "$command_type" != 'null' ]] && [[ "$command_json" != '""' ]]; then
    printf '    command: %s\n' "$command_json"
  fi

  printf '    logging:\n      driver: local\n'

  cpu_priority=$(printf '%s\n' "$record" | jq -r '.cpu_priority // empty')
  memory_limit=$(printf '%s\n' "$record" | jq -r '.memory_limit // 0')
  if [[ "$(printf '%s\n' "$record" | jq -r '.inspect_source // false')" = 'true' ]] && [[ -n "$memory_limit" ]] && [[ "$memory_limit" != '0' ]]; then
    printf '    mem_limit: %s\n' "$memory_limit"
  elif [[ -n "$cpu_priority" ]] || { [[ -n "$memory_limit" ]] && [[ "$memory_limit" != '0' ]]; }; then
    printf '    # Review Synology-only resource settings manually:'
    [[ -n "$cpu_priority" ]] && printf ' cpu_priority=%s' "$cpu_priority"
    [[ -n "$memory_limit" ]] && [[ "$memory_limit" != '0' ]] && printf ' memory_limit=%s' "$memory_limit"
    printf '\n'
  fi

  if [[ -n "$network_names" ]] && [[ "$host_network" != 'true' ]] &&
    [[ "$network_mode" != 'bridge' ]] && [[ "$network_mode" != 'none' ]] &&
    [[ "$network_mode" != service:* ]] && [[ "$network_mode" != container:* ]]; then
    printf 'networks:\n'
    while IFS= read -r network_name; do
      [[ -n "$network_name" ]] || continue
      printf '  %s:\n    external: true\n' "$(yaml_string "$network_name")"
    done <<< "$network_names"
  fi

  if [[ -n "$volume_names" ]]; then
    printf 'volumes:\n'
    while IFS= read -r volume_name; do
      [[ -n "$volume_name" ]] || continue
      printf '  %s:\n    external: true\n' "$(yaml_string "$volume_name")"
    done <<< "$volume_names"
  fi
} > "$compose_temp"

if [[ "$(printf '%s\n' "$record" | jq -r '.env_variables | length')" -gt 0 ]]; then
  while IFS= read -r env_entry; do
    env_key=$(printf '%s\n' "$env_entry" | jq -r '.key // .name // empty')
    env_value=$(printf '%s\n' "$env_entry" | jq -r '(.value // "") | tostring')
    [[ "$env_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail "Unsupported environment variable name: $env_key"
    if [[ "$env_value" == *$'\n'* ]] || [[ "$env_value" == *$'\r'* ]]; then
      fail "Environment variable $env_key contains a newline and needs manual review"
    fi
    printf '%s=%s\n' "$env_key" "$env_value" >> "$env_temp"
  done < <(printf '%s\n' "$record" | jq -c '.env_variables[]?')
fi

if [[ "$outputs_exist" = 'true' ]]; then
  command -v diff >/dev/null 2>&1 || fail "diff is required to compare existing Compose output"
  compose_same='false'
  env_same='false'
  if [[ -f "$compose_file" ]] && diff -q "$compose_file" "$compose_temp" >/dev/null; then
    compose_same='true'
  fi
  if [[ -f "$env_file" ]] && [[ -s "$env_temp" ]] && diff -q "$env_file" "$env_temp" >/dev/null; then
    env_same='true'
  elif [[ ! -f "$env_file" ]] && [[ ! -s "$env_temp" ]]; then
    env_same='true'
  fi

  if [[ "$compose_same" = 'true' ]] && [[ "$env_same" = 'true' ]] && [[ "$force" != 'true' ]]; then
    rm -f "$compose_temp" "$env_temp" "${compose_file}.generated" "${env_file}.generated"
    trap - EXIT
    [[ -z "$status_file" ]] || printf 'already-converted\n' > "$status_file"
    printf 'Already converted: %s\n' "$compose_file"
    exit 0
  fi

  if [[ "$force" != 'true' ]]; then
    generated_compose="${compose_file}.generated"
    generated_env="${env_file}.generated"
    mv -f "$compose_temp" "$generated_compose"
    if [[ -s "$env_temp" ]]; then
      mv -f "$env_temp" "$generated_env"
      chmod 600 "$generated_env"
    else
      rm -f "$env_temp" "$generated_env"
    fi
    chmod 600 "$generated_compose"
    trap - EXIT
    [[ -z "$status_file" ]] || printf 'candidate-generated\n' > "$status_file"

    if [[ "$compose_same" != 'true' ]]; then
      printf 'Existing Compose file differs: %s\n' "$compose_file"
      printf 'Generated candidate: %s\n' "$generated_compose"
      if [[ -f "$compose_file" ]]; then
        diff -u "$compose_file" "$generated_compose" || true
      fi
    fi
    if [[ "$env_same" != 'true' ]]; then
      if [[ -f "$generated_env" ]]; then
        printf 'Environment file differs; generated private candidate: %s\n' "$generated_env"
      else
        printf 'Environment file differs; generated candidate has no environment file\n'
      fi
    fi
    exit 0
  fi

  if [[ "$compose_same" != 'true' ]] && [[ -f "$compose_file" ]]; then
    printf 'Existing Compose file differs and will be replaced by --force:\n'
    diff -u "$compose_file" "$compose_temp" || true
  fi
  if [[ "$env_same" != 'true' ]]; then
    printf 'Existing environment file differs and will be replaced by --force.\n'
  fi
fi

mv "$compose_temp" "$compose_file"
if [[ -s "$env_temp" ]]; then
  mv "$env_temp" "$env_file"
  chmod 600 "$env_file"
else
  rm -f "$env_temp" "$env_file"
fi
chmod 600 "$compose_file"
rm -f "${compose_file}.generated" "${env_file}.generated"
trap - EXIT
[[ -z "$status_file" ]] || printf 'written\n' > "$status_file"

printf 'Wrote %s\n' "$compose_file"
if [[ -f "$env_file" ]]; then
  printf 'Wrote private environment file %s\n' "$env_file"
fi
printf 'Review the files, remove or rename the old stopped container, then run:\n'
printf '  docker-compose -f %q up -d --force-recreate\n' "$compose_file"
