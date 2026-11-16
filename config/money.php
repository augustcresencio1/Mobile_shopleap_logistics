<?php

return [
    'timezone' => 'Asia/Manila',
    // Must match the main web backend's seller-payment routing setting.
    'logistics_seller_settlements' => env('LOGISTICS_SELLER_SETTLEMENTS', true),
];
