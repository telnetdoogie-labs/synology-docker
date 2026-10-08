#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
test_tmp_dir=$(mktemp -d)
trap 'rm -rf "$test_tmp_dir"' EXIT

docker() {
  case "$1" in
    inspect)
      if [[ "${3:-}" = '--format' ]] && [[ "${4:-}" = '{{.Config.Image}}' ]]; then
        printf 'example/test:1\n'
      elif [[ "${3:-}" = '--format' ]] && [[ "${MOCK_LIST_MODE:-}" = 'true' ]]; then
        printf '/web %s local\n' "$COMPOSE_PATH"
      elif [[ "${3:-}" = '--format' ]] && [[ "${MOCK_LIST_MODE:-}" = 'unmanaged' ]]; then
        printf '/review-test !---not_managed_by_compose---! local\n'
      elif [[ "${3:-}" = '--format' ]] && [[ "${MOCK_LIST_MODE:-}" = 'unmanaged-db' ]]; then
        printf '/review-test !---not_managed_by_compose---! db\n'
      else
        printf '%s\n' "$DOCKER_FIXTURE"
      fi
      ;;
    ps)
      [[ "${2:-}" = '-aq' ]] || return 2
      printf '%s\n' "${MOCK_DOCKER_IDS:-}"
      ;;
    run)
      shift
      printf 'MOCK_DOCKER_RUN\n'
      printf '<%s>\n' "$@"
      ;;
    *)
      return 2
      ;;
  esac
}
export -f docker

marker="$test_tmp_dir/command-injected"
anon_volume='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
DOCKER_FIXTURE=$(jq -cn --arg marker "$marker" --arg anon_volume "$anon_volume" '[{Name:"/review-test",Config:{Image:"example/test:1",Env:["RECREATE_TEST_APP=one","RECREATE_TEST_APP_EXTRA=two",("RECREATE_TEST_DANGEROUS=$(touch "+$marker+")")],Entrypoint:["/entry","--entry-flag"],Cmd:["argument with spaces","second-argument","line1\nline2"],Tty:true,OpenStdin:false},HostConfig:{PortBindings:{"80/tcp":[{HostIp:"127.0.0.1",HostPort:"8080"}]},RestartPolicy:{Name:"unless-stopped"},NetworkMode:"custom-net",LogConfig:{Type:"db"},CgroupnsMode:"host",UsernsMode:"host",UtsMode:"host"},Mounts:[{Type:"bind",Source:"/tmp/source path",Destination:"/data path",RW:false,Mode:""},{Type:"volume",Name:"config_volume",Source:"/var/lib/docker/volumes/config_volume/_data",Destination:"/config",RW:true,Mode:""},{Type:"volume",Name:$anon_volume,Source:"/var/lib/docker/volumes/anonymous/_data",Destination:"/storage",RW:true,Mode:""},{Type:"tmpfs",Destination:"/cache",RW:true}]}]')
export DOCKER_FIXTURE
unset RECREATE_TEST_APP RECREATE_TEST_APP_EXTRA RECREATE_TEST_DANGEROUS
suggestion=$("$repo_dir/container_recreate.sh" review-test)
run_result=$(eval "$suggestion")
[[ ! -e "$marker" ]]
[[ "$suggestion" != *"$marker"* ]]
[[ "$suggestion" != *'RECREATE_TEST_APP=one'* ]]
[[ "$run_result" == *'</REVIEW_AND_CREATE_ENV_FILE_BEFORE_RUNNING>'* ]]
[[ "$run_result" == *'<argument with spaces>'* ]]
[[ "$run_result" == *'<second-argument>'* ]]
[[ "$run_result" == *$'line1\nline2'* ]]
[[ "$run_result" == *'<127.0.0.1:8080:80/tcp>'* ]]
[[ "$run_result" == *'</tmp/source path:/data path:ro>'* ]]
[[ "$run_result" == *'<config_volume:/config>'* ]]
[[ "$run_result" == *'</cache>'* ]]
[[ "$run_result" == *'<-t>'* && "$run_result" != *'<-i>'* ]]
[[ "$run_result" == *'<--log-driver>'*'<local>'* ]]
[[ "$run_result" == *'<--restart>'*'<unless-stopped>'* ]]
[[ "$run_result" == *'<--network>'*'<custom-net>'* ]]
[[ "$run_result" == *'<--entrypoint>'*'</entry>'*'--entry-flag'* ]]
printf 'Container recreation rendering tests passed\n'

compose_path="$test_tmp_dir/compose  file.yml"
: > "$compose_path"
MOCK_LIST_MODE=true
MOCK_DOCKER_IDS=review-list-test
export MOCK_LIST_MODE MOCK_DOCKER_IDS COMPOSE_PATH="$compose_path"
listing=$("$repo_dir/syno_docker_list_containers.sh")
[[ "$listing" == *"$compose_path"* ]]
MOCK_LIST_MODE=unmanaged
export MOCK_LIST_MODE
listing=$("$repo_dir/syno_docker_list_containers.sh")
[[ "$listing" != *"$marker"* ]]
[[ "$listing" != *'RECREATE_TEST_APP=one'* ]]
[[ "$listing" == *'/REVIEW_AND_CREATE_ENV_FILE_BEFORE_RUNNING'* ]]
printf 'Container listing path and secret-redaction tests passed\n'

export_dir=$(mktemp -d)
jq -n '{
  name:"exported-app", image:"example/exported:1", cmd:"/init",
  enable_restart_policy:true, network_mode:"custom-net", use_host_network:false,
  network:[{driver:"bridge",name:"custom-net"}],
  env_variables:[{key:"TEST_SECRET",value:"do-not-print"},{key:"EMPTY_VALUE",value:""}],
  port_bindings:[{container_port:8443,host_port:9443,type:"tcp"}],
  volume_bindings:[{host_volume_file:"/docker/exported-app",is_directory:true,mount_point:"/config",type:"rw"}],
  labels:{owner:"test"}, cpu_priority:50
}' > "$export_dir/exported.json"
converter_output=$("$repo_dir/syno_container_export_to_compose.sh" "$export_dir/exported.json" "$export_dir")
[[ "$converter_output" != *'do-not-print'* ]]
[[ -f "$export_dir/exported-app.docker-compose.yml" ]]
grep -Fq 'container_name: "exported-app"' "$export_dir/exported-app.docker-compose.yml"
grep -Fq 'restart: unless-stopped' "$export_dir/exported-app.docker-compose.yml"
grep -Fq 'driver: local' "$export_dir/exported-app.docker-compose.yml"
grep -Fq '"9443:8443/tcp"' "$export_dir/exported-app.docker-compose.yml"
grep -Fq '"/volume1/docker/exported-app:/config:rw"' "$export_dir/exported-app.docker-compose.yml"
grep -Fq 'custom-net' "$export_dir/exported-app.docker-compose.yml"
grep -Fq 'external: true' "$export_dir/exported-app.docker-compose.yml"
grep -Fxq 'TEST_SECRET=do-not-print' "$export_dir/exported-app.env"
grep -Fxq 'EMPTY_VALUE=' "$export_dir/exported-app.env"
[[ "$(stat -c '%a' "$export_dir/exported-app.env")" == '600' ]]
second_conversion=$("$repo_dir/syno_container_export_to_compose.sh" "$export_dir/exported.json" "$export_dir")
[[ "$second_conversion" == *'Already converted'* ]]
[[ ! -e "$export_dir/exported-app.docker-compose.yml.generated" ]]
printf '# locally reviewed change\n' >> "$export_dir/exported-app.docker-compose.yml"
changed_conversion=$("$repo_dir/syno_container_export_to_compose.sh" "$export_dir/exported.json" "$export_dir")
[[ "$changed_conversion" == *'Existing Compose file differs'* ]]
[[ "$changed_conversion" == *'Generated candidate'* ]]
[[ "$changed_conversion" == *'locally reviewed change'* ]]
[[ -f "$export_dir/exported-app.docker-compose.yml.generated" ]]
"$repo_dir/syno_container_export_to_compose.sh" --force "$export_dir/exported.json" "$export_dir" >/dev/null
[[ ! -e "$export_dir/exported-app.docker-compose.yml.generated" ]]
printf 'Synology export conversion and reconciliation tests passed\n'

inspect_dir=$(mktemp -d)
printf '%s\n' "$DOCKER_FIXTURE" > "$inspect_dir/inspect.json"
converter_output=$("$repo_dir/syno_container_export_to_compose.sh" "$inspect_dir/inspect.json" "$inspect_dir")
[[ "$converter_output" != *"$marker"* ]]
[[ -f "$inspect_dir/review-test.docker-compose.yml" ]]
grep -Fq 'restart: unless-stopped' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq 'driver: local' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq '"127.0.0.1:8080:80/tcp"' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq '"/tmp/source path:/data path:ro"' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq 'config_volume:/config:rw' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq 'external: true' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq 'cgroup: "host"' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq 'userns_mode: "host"' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq 'uts: "host"' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq '/entry' "$inspect_dir/review-test.docker-compose.yml"
grep -Fq '/cache' "$inspect_dir/review-test.docker-compose.yml"
grep -Fxq 'RECREATE_TEST_APP=one' "$inspect_dir/review-test.env"
grep -Fxq 'RECREATE_TEST_APP_EXTRA=two' "$inspect_dir/review-test.env"
grep -Fq "$anon_volume:/storage:rw" "$inspect_dir/review-test.docker-compose.yml"

fresh_dir=$(mktemp -d)
"$repo_dir/syno_container_export_to_compose.sh" --fresh-anonymous-volumes "$inspect_dir/inspect.json" "$fresh_dir" >/dev/null
grep -Fq '"/storage:rw"' "$fresh_dir/review-test.docker-compose.yml"
if grep -Fq "$anon_volume" "$fresh_dir/review-test.docker-compose.yml"; then
  printf 'Fresh anonymous volume conversion retained the old volume name\n' >&2
  exit 1
fi
printf 'Docker inspect conversion tests passed\n'

selected_dir=$(mktemp -d)
MOCK_LIST_MODE=unmanaged
export MOCK_LIST_MODE
selected_output=$("$repo_dir/syno_docker_list_containers.sh" --compose-dir "$selected_dir" review-test)
[[ "$selected_output" != *"$marker"* ]]
[[ "$selected_output" != *'RECREATE_TEST_APP=one'* ]]
[[ -f "$selected_dir/review-test.docker-compose.yml" ]]
[[ -f "$selected_dir/review-test.env" ]]
grep -Fq 'restart: unless-stopped' "$selected_dir/review-test.docker-compose.yml"
manifest_file="$selected_dir/compose-export-manifest.json"
[[ -f "$manifest_file" ]]
[[ "$(stat -c '%a' "$manifest_file")" == '600' ]]
jq -e '.containers["review-test"].conversion == "written" and .containers["review-test"].requires_recreate == false' "$manifest_file" >/dev/null

next_dir=$(mktemp -d)
MOCK_LIST_MODE=unmanaged-db
export MOCK_LIST_MODE
next_output=$("$repo_dir/syno_docker_list_containers.sh" --compose-dir "$next_dir" --container-dirs --next)
[[ "$next_output" == *'Manifest updated'* ]]
[[ -f "$next_dir/review-test/review-test.docker-compose.yml" ]]
jq -e '.containers["review-test"].conversion == "written" and .containers["review-test"].requires_recreate == true' "$next_dir/compose-export-manifest.json" >/dev/null
MOCK_LIST_MODE=unmanaged
export MOCK_LIST_MODE
next_output=$("$repo_dir/syno_docker_list_containers.sh" --compose-dir "$next_dir" --container-dirs --next)
[[ "$next_output" == *"No containers still use the removed 'db' logger"* ]]
jq -e '.containers["review-test"].conversion == "updated" and .containers["review-test"].requires_recreate == false' "$next_dir/compose-export-manifest.json" >/dev/null

recovery_dir=$(mktemp -d)
MOCK_LIST_MODE=unmanaged-db
export MOCK_LIST_MODE
recovery_output=$("$repo_dir/syno_docker_recovery.sh" next "$recovery_dir" --fresh-anonymous-volumes)
[[ "$recovery_output" == *'Next: use the validate action'* ]]
[[ -f "$recovery_dir/review-test/review-test.docker-compose.yml" ]]
grep -Fq '"/storage:rw"' "$recovery_dir/review-test/review-test.docker-compose.yml"
manifest_output=$("$repo_dir/syno_docker_recovery.sh" manifest "$recovery_dir")
[[ "$manifest_output" == *'review-test'* && "$manifest_output" == *'logger=db'* && "$manifest_output" == *'written'* ]]
menu_output=$(printf '3\n0\n0\n' | "$repo_dir/syno_docker_recovery.sh")
[[ "$menu_output" == *'What do you want to do?'* ]]
[[ "$menu_output" == *'Convert containers away from the removed db logger'* ]]
[[ "$menu_output" == *'inventory -> export -> validate -> recreate'* ]]
printf 'Single-container, manifest, recovery-menu, and next-container Compose export tests passed\n'

for script in "$repo_dir"/*.sh; do
  bash -n "$script"
done
printf 'Shell syntax tests passed\n'
