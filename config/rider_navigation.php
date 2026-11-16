<?php

return [
    'arrival_radius_meters' => 150,
    'enforce_arrival_radius' => env('PICKRUSH_ENFORCE_ARRIVAL_RADIUS', false),
    'tracking_cache_store' => env('RIDER_TRACKING_CACHE_STORE', 'file'),
];
