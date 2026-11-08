#!/bin/bash
# The module download path needs the platform. DSM 7 records it as 'platform_name';
# DSM 6 has no such key, only 'unique' (e.g. synology_apollolake_918+).
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/kernel_modules_fixture.sh
source "$(dirname "$0")/../lib/kernel_modules_fixture.sh"
prepare_kernel_modules_fixture

# Arrange: a stand-in for DSM's get_key_value, removed again afterwards so other
# cases still see a machine without it.
trap 'rm -f /bin/get_key_value; rm -rf "$test_tmp_dir"' EXIT
cat > /bin/get_key_value <<'EOF'
#!/bin/sh
sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$1"
EOF
chmod +x /bin/get_key_value
dsm7_synoinfo="$test_tmp_dir/dsm7-synoinfo.conf"
dsm6_synoinfo="$test_tmp_dir/dsm6-synoinfo.conf"
bare_synoinfo="$test_tmp_dir/bare-synoinfo.conf"
printf 'platform_name="geminilake"\nunique="synology_geminilake_920+"\n' > "$dsm7_synoinfo"
printf 'unique="synology_apollolake_918+"\n' > "$dsm6_synoinfo"
printf 'maxdisks="4"\n' > "$bare_synoinfo"

# Act/expect: DSM 7 uses platform_name.
expect_eq geminilake "$(detect_platform "$dsm7_synoinfo")" 'DSM 7 platform comes from platform_name'

# Act/expect: DSM 6 falls back to the platform inside 'unique'.
expect_eq apollolake "$(detect_platform "$dsm6_synoinfo")" 'DSM 6 platform comes from unique'

# Act/expect: with neither key, no platform is invented.
expect_eq '' "$(detect_platform "$bare_synoinfo")" 'missing keys give no platform'
