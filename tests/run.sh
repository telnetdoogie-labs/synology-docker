#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
test_tmp_dir=$(mktemp -d)
trap 'rm -rf "$test_tmp_dir"' EXIT

docker() {
  case "$1" in
    inspect)
      if [[ "${3:-}" = '--format' ]] && [[ "${MOCK_LIST_MODE:-}" = 'true' ]]; then
        printf '/web %s local\n' "$COMPOSE_PATH"
      elif [[ "${3:-}" = '--format' ]] && [[ "${MOCK_LIST_MODE:-}" = 'unmanaged' ]]; then
        printf '/review-test !---not_managed_by_compose---! local\n'
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

for script in "$repo_dir"/*.sh; do
  bash -n "$script"
done
printf 'Shell syntax tests passed\n'
