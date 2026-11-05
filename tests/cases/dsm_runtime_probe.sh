#!/bin/bash
# DSM 6/7 runtime requirements and unsupported versions. Run alone with: bash tests/run.sh dsm_runtime_probe
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

probe_bin="$test_tmp_dir/runtime-probe-bin"
mkdir -p "$probe_bin"
for tool in bash jq realpath readlink timeout mktemp awk; do
  tool_path=$(type -P "$tool" || true)
  [[ -n "$tool_path" ]] || { printf 'Required test utility missing: %s\n' "$tool" >&2; exit 1; }
  ln -s "$tool_path" "$probe_bin/$tool"
done
for tool in comm sort sed tar find diff date curl docker insmod lsmod iptables sha256sum; do
  tool_path=$(type -P "$tool" || true)
  if [[ -n "$tool_path" ]]; then
    ln -s "$tool_path" "$probe_bin/$tool"
  else
    printf '#!/bin/sh\nexit 0\n' > "$probe_bin/$tool"
    chmod +x "$probe_bin/$tool"
  fi
done
cat > /usr/syno/bin/synopkg <<'EOF'
#!/bin/sh
exit 0
EOF
cat > /usr/syno/sbin/synoservicectl <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x /usr/syno/bin/synopkg /usr/syno/sbin/synoservicectl
mkdir -p /etc.defaults
printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION
probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 27)
[[ "$probe_output" == *'DSM major version: 7'* ]]
[[ "$probe_output" == *'OK      DSM 7 synopkg found'* ]]
[[ "$probe_output" == *'OK      timeout --foreground works'* ]]
[[ "$probe_output" == *'OK      readlink -f works'* ]]
[[ "$probe_output" == *'OK      realpath works'* ]]
printf 'majorversion="6"\nproductversion="6.2"\n' > /etc.defaults/VERSION
probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 27)
[[ "$probe_output" == *'OK      DSM 6 synoservicectl found'* ]]
printf 'majorversion="8"\nproductversion="8.0"\n' > /etc.defaults/VERSION
if probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 27 2>&1); then
  printf 'Unsupported DSM version passed the runtime probe\n' >&2
  exit 1
fi
[[ "$probe_output" == *'UNSUPPORTED DSM major version: 8'* ]]
if probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" invalid 2>&1); then
  printf 'Non-numeric Docker major version passed the runtime probe\n' >&2
  exit 1
fi
[[ "$probe_output" == *'Target Docker major version must be numeric'* ]]
printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION
if [[ ! -x /bin/get_key_value ]]; then
  if probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 28 2>&1); then
    printf 'Docker 28 runtime probe passed without /bin/get_key_value\n' >&2
    exit 1
  fi
  [[ "$probe_output" == *'MISSING /bin/get_key_value'* ]]
fi
printf 'DSM runtime probe tests passed\n'
