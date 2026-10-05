#!/usr/bin/env bash
# Run as root in the baked image and again on the deployed management VM.
set -euo pipefail
fail=0
check() {
  local label="$1"
  shift
  if "$@"; then echo "PASS: $label"; else echo "FAIL: $label"; fail=$((fail + 1)); fi
}
sshd_settings=$(sshd -T)
for setting in 'permitrootlogin no' 'passwordauthentication no' 'x11forwarding no' 'maxauthtries 4'; do
  check "sshd $setting" grep -Fxq "$setting" <<<"$sshd_settings"
done
check 'auditd active' systemctl is-active --quiet auditd
rules=$(auditctl -l)
check 'identity audit rule loaded' grep -q -- '-k identity\|key=identity' <<<"$rules"
check 'sudo audit rule loaded' grep -q -- '-k scope\|key=scope' <<<"$rules"
check 'audit rules immutable' bash -c "auditctl -s | grep -Eq '^enabled[[:space:]]+2$'"
. /etc/os-release
if [[ "$ID" == ubuntu || "$ID" == debian ]]; then
  check 'fail2ban active' systemctl is-active --quiet fail2ban
  check 'fail2ban sshd jail' fail2ban-client status sshd
else
  echo 'SKIP: fail2ban is not packaged for the AL2023 baseline'
fi
for spec in net.ipv4.conf.all.rp_filter=1 kernel.randomize_va_space=2 fs.suid_dumpable=0 kernel.kptr_restrict=2; do
  check "sysctl $spec" test "$(sysctl -n "${spec%=*}")" = "${spec#*=}"
done
for module in cramfs freevxfs jffs2 hfs hfsplus udf; do
  check "blacklist $module" grep -Eq "^blacklist[[:space:]]+$module$" /etc/modprobe.d/60-blacklist-filesystems.conf
  check "disable $module" grep -Eq "^install[[:space:]]+$module[[:space:]]+/bin/(true|false)$" /etc/modprobe.d/60-blacklist-filesystems.conf
done
check 'password minimum length' grep -Eq '^minlen[[:space:]]*=[[:space:]]*14$' /etc/security/pwquality.conf
check 'password maximum age' grep -Eq '^PASS_MAX_DAYS[[:space:]]+90$' /etc/login.defs
if [[ "$fail" -ne 0 ]]; then echo "HARDENING_FAILED: $fail"; exit 1; fi
echo HARDENING_OK
