#!/usr/bin/env bash
# Temporary mitigation: disables session.upload_progress for every installed
# PHP version through a conf.d drop-in, then reloads PHP-FPM. Run as root.
# Remove later with: rm /etc/php/*/{fpm,cli}/conf.d/99-disable-upload-progress.ini
set -u
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
for d in /etc/php/*/; do
  v=$(basename "$d")
  for sapi in fpm cli; do
    [ -d "$d$sapi/conf.d" ] || continue
    printf '; php2shell mitigation\nsession.upload_progress.enabled = Off\n' > "$d$sapi/conf.d/99-disable-upload-progress.ini"
  done
  if systemctl is-active --quiet "php$v-fpm"; then
    systemctl reload "php$v-fpm" && st=reloaded || st=RELOAD-FAILED
  else
    st=no-fpm
  fi
  eff=$(php-fpm$v -i 2>/dev/null | grep -m1 'session.upload_progress.enabled' | awk '{print $NF}')
  echo "$(hostname -s) php$v: $st, effective=${eff:-?}"
done
