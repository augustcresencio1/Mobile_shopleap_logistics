#!/bin/sh
set -eu
cd /var/www/html
export PORT="${PORT:-8080}"
case "$PORT" in ''|*[!0-9]*) echo 'PORT must be numeric.' >&2; exit 1 ;; esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then echo 'PORT is out of range.' >&2; exit 1; fi
php deploy/check-runtime.php
mkdir -p bootstrap/cache storage/app/private storage/app/public \
    storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs
chown -R www-data:www-data storage bootstrap/cache

# These commands never apply migrations, seed records, or reset shared data.
php artisan package:discover --no-interaction --quiet
php artisan config:cache --no-interaction --quiet
php artisan route:cache --no-interaction --quiet
php artisan view:cache --no-interaction --quiet
chown -R www-data:www-data storage bootstrap/cache
chmod 640 bootstrap/cache/*.php
apache2ctl -t
exec docker-php-entrypoint "$@"
