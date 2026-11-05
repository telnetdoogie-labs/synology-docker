#!/bin/bash
# DSM 6/7 runtime requirements and unsupported versions. Run alone with: bash tests/run.sh dsm_runtime_probe
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: expose the expected runtime commands and fake DSM service tools.
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

# Act/expect: DSM 7 passes with the package tool and core utilities.
probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 27)
expect_contains "$probe_output" 'DSM major version: 7' 'recognizes DSM 7'
expect_contains "$probe_output" 'OK      DSM 7 synopkg found' 'DSM 7 package tool found'
expect_contains "$probe_output" 'OK      timeout --foreground works' 'GNU timeout works'
expect_contains "$probe_output" 'OK      readlink -f works' 'readlink -f works'
expect_contains "$probe_output" 'OK      realpath works' 'realpath works'

# Act/expect: DSM 6 accepts its service controller.
printf 'majorversion="6"\nproductversion="6.2"\n' > /etc.defaults/VERSION
probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 27)
expect_contains "$probe_output" 'OK      DSM 6 synoservicectl found' 'DSM 6 service tool found'

# Act/expect: unsupported DSM 8 is rejected.
printf 'majorversion="8"\nproductversion="8.0"\n' > /etc.defaults/VERSION
if probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 27 2>&1); then
  printf 'Unsupported DSM version passed the runtime probe\n' >&2
  exit 1
fi
expect_contains "$probe_output" 'UNSUPPORTED DSM major version: 8' 'DSM 8 reports unsupported'
if probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" invalid 2>&1); then
  printf 'Non-numeric Docker major version passed the runtime probe\n' >&2
  exit 1
fi
expect_contains "$probe_output" 'Target Docker major version must be numeric' 'invalid Docker major explains error'
printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION

# Act/expect: Docker 28+ needs the DSM key-value utility, if absent.
if [[ ! -x /bin/get_key_value ]]; then
  if probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 28 2>&1); then
    printf 'Docker 28 runtime probe passed without /bin/get_key_value\n' >&2
    exit 1
  fi
  expect_contains "$probe_output" 'MISSING /bin/get_key_value' 'Docker 28 requires DSM key-value utility'
fi
printf 'DSM runtime probe tests passed\n'
