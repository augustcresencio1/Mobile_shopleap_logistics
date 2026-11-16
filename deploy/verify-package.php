<?php

// Run only in an isolated checkout without real environment or cached config.
$root = dirname(__DIR__);
if (is_file($root.'/.env') || is_file($root.'/bootstrap/cache/config.php')) {
    fwrite(STDERR, 'Use a clean isolated checkout without .env or cached configuration.'.PHP_EOL); exit(1);
}
foreach ([
    'APP_ENV' => 'production', 'APP_DEBUG' => 'false', 'APP_KEY' => 'base64:'.base64_encode(str_repeat('0', 32)),
    'APP_URL' => 'https://rider.example.test', 'DB_CONNECTION' => 'sqlite', 'DB_DATABASE' => ':memory:',
    'CACHE_STORE' => 'file', 'SESSION_DRIVER' => 'file', 'QUEUE_CONNECTION' => 'sync',
    'MAIL_MAILER' => 'array', 'TRUSTED_PROXIES' => '*',
] as $name => $value) { putenv($name.'='.$value); $_ENV[$name] = $_SERVER[$name] = $value; }
require $root.'/vendor/autoload.php';
$app = require $root.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();
$queries = 0;
Illuminate\Support\Facades\DB::connection()->beforeExecuting(function () use (&$queries): void {
    $queries++; throw new RuntimeException('Database queries are prohibited in this package verification.');
});
$checks = [];
try {
    foreach (['package:discover', 'config:cache', 'route:cache', 'view:cache'] as $command) {
        if ($kernel->call($command, ['--quiet' => true]) !== 0) throw new RuntimeException('CACHE_COMMAND_FAILED');
        $checks[] = $command;
    }
    $http = $app->make(Illuminate\Contracts\Http\Kernel::class);
    foreach ([['GET','/up',200], ['POST','/api/courier/login',422], ['GET','/api/courier/me',401]] as [$method,$path,$expected]) {
        $request = Illuminate\Http\Request::create($path, $method, [], [], [], ['HTTP_ACCEPT'=>'application/json']);
        $response = $http->handle($request);
        if ($response->getStatusCode() !== $expected) throw new RuntimeException('UNEXPECTED_HTTP_STATUS');
        $checks[] = $method.' '.$path.' '.$expected;
        $http->terminate($request, $response);
    }
    $request = Illuminate\Http\Request::create('/up', 'GET', [], [], [], [
        'HTTP_HOST'=>'rider.example.test', 'REMOTE_ADDR'=>'10.0.0.1', 'HTTP_X_FORWARDED_PROTO'=>'https', 'HTTP_ACCEPT'=>'application/json',
    ]);
    $response = $http->handle($request);
    if ($response->getStatusCode() !== 200 || !$request->isSecure()) throw new RuntimeException('PROXY_HTTPS_FAILED');
    $http->terminate($request, $response);
    $checks[] = 'Trusted proxy HTTPS';
    echo json_encode(['checks'=>$checks, 'databaseQueries'=>$queries, 'emailsSent'=>0, 'r2Writes'=>0], JSON_PRETTY_PRINT), PHP_EOL;
} catch (Throwable) {
    fwrite(STDERR, 'Package verification failed. Details hidden; no production environment was loaded.'.PHP_EOL); exit(1);
} finally {
    foreach (['route:clear','config:clear','view:clear'] as $command) $kernel->call($command, ['--quiet'=>true]);
}
