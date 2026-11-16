<?php

// Standalone validation: no database, storage, or email operations.
$requiredExtensions = ['pdo_pgsql','pgsql','mbstring','openssl','curl','fileinfo','xml','dom','zip','bcmath','gd','Zend OPcache'];
$missing = array_values(array_filter($requiredExtensions, fn($name) => !extension_loaded($name)));
if ($missing) { fwrite(STDERR, 'Missing PHP extension names: '.implode(', ', $missing).PHP_EOL); exit(1); }
$required = ['APP_KEY','APP_URL','DB_HOST','DB_PORT','DB_DATABASE','DB_USERNAME','DB_PASSWORD',
    'R2_ACCESS_KEY_ID','R2_SECRET_ACCESS_KEY','R2_ENDPOINT','R2_PRIVATE_BUCKET','R2_PUBLIC_BUCKET','R2_PUBLIC_URL'];
$missing = array_values(array_filter($required, fn($name) => getenv($name) === false || trim(getenv($name)) === ''));
if ($missing) { fwrite(STDERR, 'Missing environment variable names: '.implode(', ', $missing).PHP_EOL); exit(1); }
$checks = [
    'APP_ENV must be production' => getenv('APP_ENV') === 'production',
    'APP_DEBUG must be false' => in_array(strtolower((string)getenv('APP_DEBUG')), ['false','0'], true),
    'APP_KEY must be a valid existing base64 key' => str_starts_with(getenv('APP_KEY'), 'base64:') && strlen((string)base64_decode(substr(getenv('APP_KEY'), 7), true)) === 32,
    'APP_URL must use HTTPS' => parse_url(getenv('APP_URL'), PHP_URL_SCHEME) === 'https',
    'DB_CONNECTION must be pgsql' => getenv('DB_CONNECTION') === 'pgsql',
    'DB_SSLMODE must require TLS' => in_array(getenv('DB_SSLMODE'), ['require','verify-ca','verify-full'], true),
    'R2_ENDPOINT must use HTTPS' => parse_url(getenv('R2_ENDPOINT'), PHP_URL_SCHEME) === 'https',
    'R2_PUBLIC_URL must use HTTPS' => parse_url(getenv('R2_PUBLIC_URL'), PHP_URL_SCHEME) === 'https',
    'Private uploads must use R2' => getenv('FILESYSTEM_DISK') === 'r2_private' && getenv('DELIVERY_PROOFS_DISK') === 'r2_private',
    'Cache and sessions must use files' => getenv('CACHE_STORE') === 'file' && getenv('SESSION_DRIVER') === 'file',
    'Queue must be synchronous' => getenv('QUEUE_CONNECTION') === 'sync',
    'CA bundle must be readable' => is_readable((string)ini_get('curl.cainfo')) && is_readable((string)ini_get('openssl.cafile')),
];
foreach ($checks as $message => $passed) if (!$passed) { fwrite(STDERR, $message.PHP_EOL); exit(1); }
if (getenv('RENDER') && getenv('MAIL_MAILER') === 'smtp') {
    fwrite(STDERR, 'OTP email is not ready on Render Free: configure an HTTPS email relay before using registration or password reset.'.PHP_EOL);
}
echo 'Runtime configuration checked. No database records or uploads were changed.'.PHP_EOL;
