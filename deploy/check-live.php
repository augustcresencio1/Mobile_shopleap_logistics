<?php

// Public checks only: no credentials, uploads, records, email, or order actions.
$origin = rtrim($argv[1] ?? '', '/');
if (parse_url($origin, PHP_URL_SCHEME) !== 'https' || parse_url($origin, PHP_URL_PATH)
    || parse_url($origin, PHP_URL_USER) || parse_url($origin, PHP_URL_QUERY)) {
    fwrite(STDERR, 'Usage: php deploy/check-live.php https://your-service.onrender.com'.PHP_EOL); exit(1);
}
$checks = [];
try {
    foreach ([['GET','/up',200],['GET','/api/hubs',200],['POST','/api/courier/login',422],['GET','/api/courier/me',401]] as [$method,$path,$expected]) {
        $curl = curl_init($origin.$path);
        curl_setopt_array($curl, [CURLOPT_CUSTOMREQUEST=>$method, CURLOPT_RETURNTRANSFER=>true,
            CURLOPT_CONNECTTIMEOUT=>10, CURLOPT_TIMEOUT=>90, CURLOPT_FOLLOWLOCATION=>false,
            CURLOPT_SSL_VERIFYPEER=>true, CURLOPT_SSL_VERIFYHOST=>2,
            CURLOPT_HTTPHEADER=>['Accept: application/json','Content-Type: application/json']]);
        if ($method === 'POST') curl_setopt($curl, CURLOPT_POSTFIELDS, '{}');
        $body = curl_exec($curl);
        $result = ['method'=>$method,'path'=>$path,'http'=>curl_getinfo($curl, CURLINFO_RESPONSE_CODE),
            'seconds'=>round(curl_getinfo($curl, CURLINFO_TOTAL_TIME), 3)];
        unset($curl); $checks[] = $result;
        if ($body === false || $result['http'] !== $expected || ($path !== '/up' && !is_array(json_decode($body,true)))) {
            throw new RuntimeException('LIVE_CHECK_FAILED');
        }
    }
    echo json_encode(['origin'=>$origin,'checks'=>$checks,'authenticatedPhoneTestPending'=>true,
        'mailDeliveryTested'=>false], JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES), PHP_EOL;
} catch (Throwable) {
    echo json_encode(['checks'=>$checks,'error'=>'Live check failed; response contents hidden.'], JSON_PRETTY_PRINT), PHP_EOL;
    exit(1);
}
