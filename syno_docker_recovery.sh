#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")
readonly SCRIPT_DIR
DEFAULT_COMPOSE_ROOT=${COMPOSE_ROOT:-/volume1/docker/recover}

usage() {
  cat >&2 <<'EOF'
Usage: syno_docker_recovery.sh [ACTION]

Actions:
  preflight [DOCKER_MAJOR]       Check DSM runtime prerequisites
  status                         Show package/container status and recreate hints
  list                           List containers, Compose location, and logger
  next [ROOT] [--fresh-anonymous-volumes]
                                 Export one remaining db-logger container
  export-all [ROOT] [--fresh-anonymous-volumes]
                                 Export all non-Compose containers
  validate ROOT CONTAINER        Validate generated Compose output
  recreate ROOT CONTAINER        Remove a stopped container and recreate it
  compose-recreate COMPOSE_FILE  Run Compose force-recreate for a project
  manifest [ROOT]                Show recovery manifest status
  backup                         Create an updater backup
  update                         Run the Docker updater after typed confirmation
  downgrade DOCKER COMPOSE       Force a specified downgrade after typed confirmation
  restore BACKUP.tgz             Restore an updater backup after typed confirmation
  menu                           Show the interactive menu

With no action, the interactive menu is shown.
EOF
  exit 1
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

prompt_default() {
  local prompt=$1
  local default=$2
  local value
  printf '%s [%s]: ' "$prompt" "$default" >&2
  read -r value || value=''
  printf '%s' "${value:-$default}"
}

prompt_required() {
  local prompt=$1
  local value
  printf '%s: ' "$prompt" >&2
  read -r value || fail "No value supplied"
  [[ -n "$value" ]] || fail "No value supplied"
  printf '%s' "$value"
}

ask_yes_no() {
  local prompt=$1
  local value
  printf '%s [y/N]: ' "$prompt" >&2
  read -r value || value=''
  [[ "$value" =~ ^[Yy][Ee]?[Ss]?$ ]]
}

confirm_word() {
  local word=$1
  local value
  printf 'Type %s to continue: ' "$word" >&2
  read -r value || fail "Operation not confirmed"
  [[ "$value" = "$word" ]] || fail "Operation not confirmed"
}

preflight() {
  local target=${1:-}
  [[ -n "$target" ]] || target=$(prompt_default 'Target Docker Engine major version' '29')
  sh "${SCRIPT_DIR}/tests/check-dsm-runtime.sh" "$target"
}

status() {
  "${SCRIPT_DIR}/syno_docker_list_containers.sh"
  echo
  docker ps -a
}

recover_next() {
  local root=${1:-}
  shift || true
  local fresh='false'
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --fresh-anonymous-volumes) fresh='true' ;;
      *) usage ;;
    esac
    shift
  done
  [[ -n "$root" ]] || root=$(prompt_default 'Recovery output root' "$DEFAULT_COMPOSE_ROOT")
  if [[ "$fresh" != 'true' ]] && [[ -t 0 ]]; then
    ask_yes_no 'Replace anonymous volumes with fresh Docker-managed volumes' && fresh='true'
  fi

  local args=(--compose-dir "$root" --container-dirs --next)
  [[ "$fresh" = 'true' ]] && args+=(--fresh-anonymous-volumes)
  "${SCRIPT_DIR}/syno_docker_list_containers.sh" "${args[@]}"
  printf '\nNext: use the validate action for the generated container output.\n'
}

export_all() {
  local root=${1:-}
  shift || true
  local fresh='false'
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --fresh-anonymous-volumes) fresh='true' ;;
      *) usage ;;
    esac
    shift
  done
  [[ -n "$root" ]] || root=$(prompt_default 'Recovery output root' "$DEFAULT_COMPOSE_ROOT")
  if [[ "$fresh" != 'true' ]] && [[ -t 0 ]]; then
    ask_yes_no 'Replace anonymous volumes with fresh Docker-managed volumes' && fresh='true'
  fi

  local args=(--compose-dir "$root" --container-dirs)
  [[ "$fresh" = 'true' ]] && args+=(--fresh-anonymous-volumes)
  "${SCRIPT_DIR}/syno_docker_list_containers.sh" "${args[@]}"
}

compose_file_for() {
  local root=$1
  local name=$2
  local compose_file="${root}/${name}/${name}.docker-compose.yml"
  if [[ ! -f "$compose_file" ]] && [[ -f "${compose_file}.generated" ]]; then
    compose_file="${compose_file}.generated"
  fi
  printf '%s' "$compose_file"
}

validate_export() {
  local root=${1:-}
  local name=${2:-}
  [[ -n "$root" ]] || root=$(prompt_default 'Recovery output root' "$DEFAULT_COMPOSE_ROOT")
  [[ -n "$name" ]] || name=$(prompt_required 'Container name')
  local compose_file
  compose_file=$(compose_file_for "$root" "$name")
  [[ -f "$compose_file" ]] || fail "Generated Compose file not found: $compose_file"
  compose -f "$compose_file" config >/dev/null
  printf 'Compose configuration is valid: %s\n' "$compose_file"
}

recreate_export() {
  local root=${1:-}
  local name=${2:-}
  [[ -n "$root" ]] || root=$(prompt_default 'Recovery output root' "$DEFAULT_COMPOSE_ROOT")
  [[ -n "$name" ]] || name=$(prompt_required 'Container name')
  local compose_file logger
  compose_file=$(compose_file_for "$root" "$name")
  [[ -f "$compose_file" ]] || fail "Generated Compose file not found: $compose_file"
  compose -f "$compose_file" config >/dev/null || fail "Generated Compose configuration is invalid"
  logger=$(docker inspect "$name" --format '{{.HostConfig.LogConfig.Type}}') || fail "Container not found: $name"
  printf 'Container %s currently uses logger: %s\n' "$name" "$logger"
  printf 'This removes the existing container record, not bind-mounted folders or named volumes.\n'
  confirm_word 'RECREATE'
  docker rm "$name"
  compose -f "$compose_file" up -d --force-recreate
}

compose_recreate() {
  local compose_file=${1:-}
  [[ -n "$compose_file" ]] || compose_file=$(prompt_required 'Compose file path')
  [[ -f "$compose_file" ]] || fail "Compose file not found: $compose_file"
  compose -f "$compose_file" config >/dev/null || fail "Compose configuration is invalid"
  confirm_word 'RECREATE'
  (cd "$(dirname "$compose_file")" && compose -f "$(basename "$compose_file")" up -d --force-recreate)
}

show_manifest() {
  local root=${1:-}
  [[ -n "$root" ]] || root=$(prompt_default 'Recovery output root' "$DEFAULT_COMPOSE_ROOT")
  local manifest_file="${root}/compose-export-manifest.json"
  [[ -f "$manifest_file" ]] || fail "Manifest not found: $manifest_file"
  jq -r '.containers | to_entries[] | "\(.key)\tlogger=\(.value.logger)\trecreate=\(.value.requires_recreate)\t\(.value.conversion)"' "$manifest_file"
}

backup() {
  sudo "${SCRIPT_DIR}/syno_docker_update.sh" backup
}

update() {
  printf 'This will stop and replace the Synology Docker package binaries and configuration.\n'
  confirm_word 'UPDATE'
  sudo "${SCRIPT_DIR}/syno_docker_update.sh" update
}

downgrade() {
  local docker_version=${1:-}
  local compose_version=${2:-}
  [[ -n "$docker_version" ]] || docker_version=$(prompt_required 'Target Docker Engine version')
  [[ -n "$compose_version" ]] || compose_version=$(prompt_required 'Target Docker Compose version')
  printf 'Downgrading can invalidate kernel-module and AppArmor preparation. Create a backup first.\n'
  confirm_word 'DOWNGRADE'
  sudo "${SCRIPT_DIR}/syno_docker_update.sh" \
    --docker "$docker_version" \
    --compose "$compose_version" \
    --force update
}

restore() {
  local backup_file=${1:-}
  [[ -n "$backup_file" ]] || backup_file=$(prompt_required 'Backup archive path')
  [[ -f "$backup_file" ]] || fail "Backup archive not found: $backup_file"
  printf 'This will stop Docker and restore binaries/configuration from %s.\n' "$backup_file"
  confirm_word 'RESTORE'
  sudo "${SCRIPT_DIR}/syno_docker_update.sh" --backup "$backup_file" restore
}

menu_upgrade() {
  while true; do
    cat <<'MENU'

Upgrade Docker/Compose
Recommended order: runtime check -> inventory -> backup -> update -> verification
 1) Check DSM runtime prerequisites
 2) Show container inventory and status
 3) Create updater backup
 4) Update Docker/Compose
 5) Verify post-update status
 0) Back
MENU
    printf 'Select an action: ' >&2
    read -r choice || return 0
    case "$choice" in
      1) preflight ;;
      2) status ;;
      3) backup ;;
      4) update ;;
      5) status ;;
      0) return 0 ;;
      *) printf 'Unknown action: %s\n' "$choice" >&2 ;;
    esac
  done
}

menu_downgrade() {
  while true; do
    cat <<'MENU'

Downgrade or restore Docker/Compose
Recommended order: runtime check -> backup -> restore/downgrade -> verification
 1) Check DSM runtime prerequisites
 2) Create updater backup
 3) Restore updater backup
 4) Downgrade to specified versions
 5) Verify post-restore status
 0) Back
MENU
    printf 'Select an action: ' >&2
    read -r choice || return 0
    case "$choice" in
      1) preflight ;;
      2) backup ;;
      3) restore '' ;;
      4) downgrade '' '' ;;
      5) status ;;
      0) return 0 ;;
      *) printf 'Unknown action: %s\n' "$choice" >&2 ;;
    esac
  done
}

menu_convert() {
  while true; do
    cat <<'MENU'

Convert containers away from the removed db logger
Recommended order: inventory -> export -> validate -> recreate -> manifest/status
 1) Show container inventory and status
 2) Export next db-logger container
 3) Validate generated Compose output
 4) Recreate generated container
 5) Recreate existing Compose project
 6) Export all non-Compose containers
 7) Show recovery manifest
 0) Back
MENU
    printf 'Select an action: ' >&2
    read -r choice || return 0
    case "$choice" in
      1) status ;;
      2) recover_next '' ;;
      3) validate_export '' '' ;;
      4) recreate_export '' '' ;;
      5) compose_recreate '' ;;
      6) export_all '' ;;
      7) show_manifest '' ;;
      0) return 0 ;;
      *) printf 'Unknown action: %s\n' "$choice" >&2 ;;
    esac
  done
}

menu() {
  while true; do
    cat <<'MENU'

What do you want to do?
 1) Upgrade Docker/Compose
    runtime check -> inventory -> backup -> update -> verification
 2) Downgrade or restore Docker/Compose
    runtime check -> backup -> restore/downgrade -> verification
 3) Convert containers
    inventory -> export -> validate -> recreate -> verification
 0) Exit
MENU
    printf 'Select a workflow: ' >&2
    read -r choice || return 0
    case "$choice" in
      1) menu_upgrade ;;
      2) menu_downgrade ;;
      3) menu_convert ;;
      0) return 0 ;;
      *) printf 'Unknown workflow: %s\n' "$choice" >&2 ;;
    esac
  done
}

if [[ "$#" -eq 0 ]]; then
  menu
  exit 0
fi

action=$1
shift
case "$action" in
  preflight) preflight "$@" ;;
  status) [[ "$#" -eq 0 ]] || usage; status ;;
  list) [[ "$#" -eq 0 ]] || usage; "${SCRIPT_DIR}/syno_docker_list_containers.sh" ;;
  next) recover_next "$@" ;;
  export-all) export_all "$@" ;;
  validate) validate_export "$@" ;;
  recreate) recreate_export "$@" ;;
  compose-recreate) compose_recreate "$@" ;;
  manifest) show_manifest "$@" ;;
  backup) [[ "$#" -eq 0 ]] || usage; backup ;;
  update) [[ "$#" -eq 0 ]] || usage; update ;;
  downgrade) downgrade "$@" ;;
  restore) restore "$@" ;;
  menu) [[ "$#" -eq 0 ]] || usage; menu ;;
  -h|--help|help) usage ;;
  *) usage ;;
esac
