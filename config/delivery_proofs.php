<?php

return [
    // Use private storage; proof images must never be served by a public disk.
    'disk' => env('DELIVERY_PROOFS_DISK', 'r2_private'),
];
