<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\Http;

abstract class TestCase extends BaseTestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        // Realtime observers must never use a developer's credentials/network in tests.
        config(['services.supabase.url' => null, 'services.supabase.service_key' => null]);
        Http::preventStrayRequests();
    }
}
