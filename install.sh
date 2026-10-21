#!/usr/bin/env bash
# Installs php2shell-watch on this server. Run as root from the repo directory:
#   sudo ./install.sh
# Schedules through cron when a cron daemon is present, otherwise through a
# systemd timer (Amazon Linux 2023 and other hosts that ship without cron).
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

missing=""
for t in find ss ps md5sum diff cmp awk logger; do command -v "$t" >/dev/null || missing="$missing $t"; done
if [ -n "$missing" ]; then
  echo "missing tools:$missing" >&2
  echo "Debian/Ubuntu: apt install findutils iproute2 procps coreutils diffutils bsdutils" >&2
  echo "RHEL/Amazon Linux: dnf install findutils iproute procps-ng coreutils diffutils util-linux" >&2
  exit 1
fi

install -m 750 "$dir/php2shell-watch.sh" /usr/local/sbin/php2shell-watch.sh
bash -n /usr/local/sbin/php2shell-watch.sh

if [ ! -f /etc/php2shell-watch.conf ]; then
  install -m 600 "$dir/php2shell-watch.conf.example" /etc/php2shell-watch.conf
fi

have_cron=0
if [ -d /etc/cron.d ] && { systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null || pgrep -x cron >/dev/null || pgrep -x crond >/dev/null; }; then
  have_cron=1
fi

if [ $have_cron -eq 1 ]; then
  printf '*/5 * * * * root /usr/local/sbin/php2shell-watch.sh >/dev/null 2>&1\n' > /etc/cron.d/php2shell-watch
  chmod 644 /etc/cron.d/php2shell-watch
  echo "scheduled via /etc/cron.d/php2shell-watch"
elif command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then
  cat > /etc/systemd/system/php2shell-watch.service <<'EOF'
[Unit]
Description=php2shell-watch run

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/php2shell-watch.sh
EOF
  cat > /etc/systemd/system/php2shell-watch.timer <<'EOF'
[Unit]
Description=php2shell-watch every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now php2shell-watch.timer
  echo "scheduled via systemd timer php2shell-watch.timer (no cron daemon found)"
else
  echo "no cron daemon and no systemd found; schedule /usr/local/sbin/php2shell-watch.sh every 5 minutes yourself" >&2
fi

echo "fpm logs watched: $(ls /var/log/php*-fpm.log /var/log/php-fpm/*.log /var/opt/remi/php*/log/php-fpm/*.log 2>/dev/null | tr '\n' ' ')"
/usr/local/sbin/php2shell-watch.sh --init
/usr/local/sbin/php2shell-watch.sh -v
echo "installed; edit /etc/php2shell-watch.conf to add a Slack webhook or mail address"
