FROM php:8.4-apache-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip libpq-dev libonig-dev libzip-dev \
        libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" pdo_pgsql pgsql mbstring zip bcmath gd opcache \
    && update-ca-certificates \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
WORKDIR /var/www/html

# Copy only backend source. Secrets and Flutter builds are not image inputs.
COPY artisan composer.json composer.lock ./
COPY app/ app/
COPY bootstrap/app.php bootstrap/providers.php bootstrap/
COPY config/ config/
COPY routes/ routes/
COPY resources/ resources/
COPY public/index.php public/.htaccess public/favicon.ico public/robots.txt public/
COPY deploy/ deploy/
COPY deploy/apache.conf /etc/apache2/sites-available/000-default.conf
COPY deploy/php.ini /usr/local/etc/php/conf.d/zz-shopleap-rider.ini

RUN printf 'Listen ${PORT}\n' > /etc/apache2/ports.conf \
    && mkdir -p bootstrap/cache database/factories database/seeders \
        storage/app/private storage/app/public storage/framework/cache/data \
        storage/framework/sessions storage/framework/views storage/logs \
    && composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts --optimize-autoloader \
    && composer check-platform-reqs --no-dev \
    && sed -i 's/\r$//' deploy/start.sh \
    && chmod +x deploy/start.sh \
    && chown -R www-data:www-data storage bootstrap/cache

ENV PORT=8080 APP_ENV=production APP_DEBUG=false LOG_CHANNEL=stderr \
    LOG_LEVEL=error CACHE_STORE=file SESSION_DRIVER=file SESSION_SECURE_COOKIE=true \
    QUEUE_CONNECTION=sync QUEUE_FAILED_DRIVER=null DB_CONNECTION=pgsql DB_SSLMODE=require DB_EMULATE_PREPARES=true \
    FILESYSTEM_DISK=r2_private DELIVERY_PROOFS_DISK=r2_private \
    R2_REGION=auto MAIL_MAILER=resend_http MAIL_TIMEOUT=15 TRUSTED_PROXIES=*
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl --fail --silent --output /dev/null "http://127.0.0.1:${PORT}/up" || exit 1

ENTRYPOINT ["/var/www/html/deploy/start.sh"]
CMD ["apache2-foreground"]
