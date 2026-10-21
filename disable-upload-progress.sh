#!/usr/bin/env bash
# Temporary mitigation: disables session.upload_progress for every installed
# PHP through a conf.d drop-in, then reloads PHP-FPM. Run as root.
# Covers Debian/Ubuntu (/etc/php/<ver>), RHEL/Amazon Linux (/etc/php.d) and Remi SCL.
# Remove later by deleting the 99-disable-upload-progress.ini files and reloading FPM.
set -u
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
ini='; php2shell mitigation
session.upload_progress.enabled = Off
'
drop() {  # drop <conf.d dir> <fpm service> <fpm binary>
  local dir=$1 svc=$2 bin=$3 st eff
  [ -d "$dir" ] || return
  printf '%s' "$ini" > "$dir/99-disable-upload-progress.ini"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    systemctl reload "$svc" && st=reloaded || st=RELOAD-FAILED
  else
    st=no-fpm
  fi
  eff=$("$bin" -i 2>/dev/null | grep -m1 'session.upload_progress.enabled' | awk '{print $NF}')
  echo "$(hostname -s 2>/dev/null || uname -n) $dir: $st, effective=${eff:-?}"
}
# Debian/Ubuntu: one dir per version
for d in /etc/php/*/; do
  [ -d "$d" ] || continue
  v=$(basename "$d")
  drop "$d/fpm/conf.d" "php$v-fpm" "php-fpm$v"
  [ -d "$d/cli/conf.d" ] && printf '%s' "$ini" > "$d/cli/conf.d/99-disable-upload-progress.ini"
done
# RHEL/Amazon Linux: single /etc/php.d, service php-fpm
drop /etc/php.d php-fpm /usr/sbin/php-fpm
# Remi SCL: /etc/opt/remi/php83/php.d, service php83-php-fpm
for d in /etc/opt/remi/php*/; do
  [ -d "$d" ] || continue
  v=$(basename "$d")
  drop "$d/php.d" "$v-php-fpm" "/opt/remi/$v/root/usr/sbin/php-fpm"
done
