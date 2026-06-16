#!/usr/bin/env bash
# Confirms the live jump host actually booted hardened, using az vm run-command
# so it works whether or not the host has a public IP.
set -euo pipefail

RG="${1:-rg-vmhardening}"
VM="${2:-vm-vmhardening-jumphost}"

read -r -d '' CHECK <<'EOF' || true
echo "== sshd =="
sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication|x11forwarding)\b'
echo "== auditd =="
systemctl is-active auditd || true
auditctl -l 2>/dev/null | head -n 5
echo "== fail2ban =="
systemctl is-active fail2ban || true
echo "== sysctl =="
sysctl net.ipv4.conf.all.rp_filter kernel.randomize_va_space fs.suid_dumpable
echo "== blacklisted modules =="
grep -h blacklist /etc/modprobe.d/60-blacklist-filesystems.conf
EOF

echo "Running hardening checks on ${VM}..."
az vm run-command invoke \
  --resource-group "${RG}" \
  --name "${VM}" \
  --command-id RunShellScript \
  --scripts "${CHECK}" \
  --query 'value[0].message' -o tsv
