<?php

namespace Tests\Feature;

use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class CourierRegistrationTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'database.connections.sqlite.url' => null, 'cache.default' => 'array']);
        DB::purge('sqlite');
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('email');
        });
        Schema::create('logistics_profiles', function (Blueprint $table) {
            $table->id();
        });
        DB::table('logistics_profiles')->insert(['id' => 1]);
        Storage::fake('local');
    }

    private function payload(): array
    {
        return [
            'first_name' => 'Test', 'last_name' => 'Rider', 'sex' => 'male',
            'email' => 'rider@example.test', 'contact_no' => '09123456789', 'birthday' => '2000-01-01',
            'province' => 'Laguna', 'municipality' => 'Santa Cruz', 'barangay' => 'Bagumbayan',
            'vehicle_type' => 'Motor', 'plate_number' => 'TEST123', 'hub_id' => 1,
            'password' => 'test-password', 'password_confirmation' => 'test-password',
            'or_cr_upload' => UploadedFile::fake()->createWithContent('or-cr.webp', file_get_contents(base_path('tests/Fixtures/delivery-proof.webp'))),
            'license_upload' => UploadedFile::fake()->createWithContent('license.webp', file_get_contents(base_path('tests/Fixtures/delivery-proof.webp'))),
        ];
    }

    public function test_registration_keeps_valid_documents_and_hashed_values_after_email_is_sent(): void
    {
        $otp = null;
        Mail::shouldReceive('send')->once()->withArgs(function ($view, $data, $callback) use (&$otp) {
            $otp = $data['otp'];

            return $view === 'emails.rider-otp' && is_callable($callback);
        });

        $this->post('/api/courier/register', $this->payload(), ['Accept' => 'application/json'])->assertCreated();
        $pending = Cache::get('courier_reg:rider@example.test');
        $this->assertTrue(Hash::check($otp, $pending['otp_hash']));
        $this->assertTrue(Hash::check('test-password', $pending['data']['password']));
        Storage::disk('local')->assertExists($pending['data']['or_cr_path']);
        Storage::disk('local')->assertExists($pending['data']['license_path']);
        $this->assertDatabaseCount('users', 0);
    }

    public function test_email_failure_returns_a_safe_retryable_error_and_cleans_pending_files(): void
    {
        Mail::shouldReceive('send')->once()->andThrow(new \RuntimeException('sensitive transport details'));
        Log::spy();
        $response = $this->post('/api/courier/register', $this->payload(), ['Accept' => 'application/json']);
        $response->assertStatus(503)->assertJsonPath('code', 'REGISTRATION_EMAIL_UNAVAILABLE');
        $this->assertStringNotContainsString('sensitive', $response->getContent());
        $this->assertNull(Cache::get('courier_reg:rider@example.test'));
        $this->assertSame([], Storage::disk('local')->allFiles('pending_couriers'));
        $this->assertDatabaseCount('users', 0);
        Log::shouldHaveReceived('error')->with('Courier registration unavailable.', [
            'stage' => 'email', 'exception_type' => \RuntimeException::class,
        ])->once();
    }

    public function test_invalid_registration_stays_a_validation_error_without_email_or_storage(): void
    {
        Mail::shouldReceive('send')->never();
        $payload = $this->payload();
        $payload['password_confirmation'] = 'different-password';
        $this->post('/api/courier/register', $payload, ['Accept' => 'application/json'])
            ->assertStatus(422)->assertJsonValidationErrors('password');
        $this->assertSame([], Storage::disk('local')->allFiles());
    }
}
