<?php

namespace Tests\Feature;

use App\Models\CourierProfile;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RiderTrackingTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'database.connections.sqlite.url' => null, 'rider_navigation.tracking_cache_store' => 'array', 'cache.default' => 'array']);
        DB::purge('sqlite');
        Cache::store('array')->flush();
        Carbon::setTestNow(Carbon::parse('2026-11-08T04:00:00Z'));
        Schema::create('users', function (Blueprint $t) {
            $t->id();
            foreach (['name', 'email', 'password', 'role', 'account_status'] as $field) {
                $t->string($field);
            }
            $t->timestamps();
        });
        Schema::create('courier_profiles', function (Blueprint $t) {
            $t->id();
            $t->integer('user_id');
            $t->integer('logistics_profile_id');
            $t->string('status');
            $t->boolean('is_active');
            $t->timestamps();
        });
        Schema::create('logistics_profiles', function (Blueprint $t) {
            $t->id();
            $t->integer('user_id');
            $t->string('status');
        });
        Schema::create('orders', function (Blueprint $t) {
            $t->id();
            $t->string('status');
            $t->string('pickup_status');
            $t->integer('pickup_rider_id');
            $t->integer('delivery_rider_id');
        });
        foreach ([1 => 'courier', 2 => 'logistics', 3 => 'logistics', 4 => 'courier', 5 => 'buyer'] as $id => $role) {
            User::forceCreate(['id' => $id, 'name' => 'Person '.$id, 'email' => $id.'@test.example',
                'password' => 'password', 'role' => $role, 'account_status' => 'active']);
        }
        DB::table('logistics_profiles')->insert([
            ['id' => 10, 'user_id' => 2, 'status' => 'approved'], ['id' => 20, 'user_id' => 3, 'status' => 'approved']]);
        CourierProfile::create(['id' => 100, 'user_id' => 1, 'logistics_profile_id' => 10, 'status' => 'approved', 'is_active' => true]);
        CourierProfile::create(['id' => 200, 'user_id' => 4, 'logistics_profile_id' => 20, 'status' => 'approved', 'is_active' => true]);
        DB::table('orders')->insert(['id' => 1000, 'status' => 'OUT_FOR_DELIVERY', 'pickup_status' => 'accepted',
            'pickup_rider_id' => 100, 'delivery_rider_id' => 100]);
        Sanctum::actingAs(User::findOrFail(1));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function fix(array $changes = []): array
    {
        return array_replace(['latitude' => 14.6, 'longitude' => 120.98, 'accuracy' => 8,
            'recorded_at' => now('UTC')->toIso8601String(), 'speed' => 5, 'heading' => 90], $changes);
    }

    private function start(string $role = 'delivery'): string
    {
        return $this->postJson('/api/courier/tracking/start', $this->fix() + ['order_id' => 1000, 'role' => $role])
            ->assertOk()->assertJsonPath('data.tracking', true)->json('data.session_id');
    }

    public function test_hub_sees_fresh_updates_only_for_its_own_riders(): void
    {
        $session = $this->start();
        $this->putJson('/api/courier/tracking/location', $this->fix(['latitude' => 14.61]) + ['session_id' => $session])->assertOk();
        Sanctum::actingAs(User::findOrFail(2));
        $this->getJson('/api/logistics/rider-locations')->assertOk()->assertHeader('Cache-Control', 'no-store, private')
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.status', 'live')
            ->assertJsonPath('data.0.location.latitude', 14.61)->assertJsonMissingPath('data.0.session_id');
        Sanctum::actingAs(User::findOrFail(3));
        $this->getJson('/api/logistics/rider-locations')->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.courier_id', 200)->assertJsonPath('data.0.location', null);
    }

    public function test_stop_prevents_delayed_updates_and_old_sessions_cannot_stop_new_trips(): void
    {
        $old = $this->start();
        $this->postJson('/api/courier/tracking/stop', ['session_id' => $old])->assertOk();
        $this->putJson('/api/courier/tracking/location', $this->fix() + ['session_id' => $old])->assertStatus(409);
        $new = $this->start();
        $this->postJson('/api/courier/tracking/stop', ['session_id' => $old])->assertOk();
        $this->putJson('/api/courier/tracking/location', $this->fix() + ['session_id' => $new])->assertOk();
    }

    public function test_late_gps_fix_cannot_replace_a_newer_location(): void
    {
        $session = $this->start();
        $this->putJson('/api/courier/tracking/location', $this->fix(['latitude' => 15, 'recorded_at' => now()->subSeconds(10)->toIso8601String()])
            + ['session_id' => $session])->assertOk()->assertJsonPath('data.location.latitude', 14.6);
    }

    public function test_lost_connection_becomes_stale_and_expires_instead_of_showing_live_forever(): void
    {
        $this->start();
        Sanctum::actingAs(User::findOrFail(2));
        Carbon::setTestNow(now()->addSeconds(31));
        $this->getJson('/api/logistics/rider-locations')->assertOk()->assertJsonPath('data.0.status', 'stale');
        Carbon::setTestNow(now()->addMinutes(5));
        $this->getJson('/api/logistics/rider-locations')->assertOk()->assertJsonPath('data.0.status', 'unavailable');
    }

    public function test_completed_or_reassigned_order_stops_live_status_and_rejects_more_updates(): void
    {
        $session = $this->start();
        DB::table('orders')->where('id', 1000)->update(['status' => 'DELIVERED']);
        $this->putJson('/api/courier/tracking/location', $this->fix() + ['session_id' => $session])->assertForbidden();
        Sanctum::actingAs(User::findOrFail(2));
        $this->getJson('/api/logistics/rider-locations')->assertOk()->assertJsonPath('data.0.status', 'stopped');
        Sanctum::actingAs(User::findOrFail(1));
        DB::table('orders')->where('id', 1000)->update(['status' => 'OUT_FOR_DELIVERY', 'delivery_rider_id' => 200]);
        $this->putJson('/api/courier/tracking/location', $this->fix() + ['session_id' => $session])->assertForbidden();
    }

    public function test_pickup_continues_to_hub_after_scanning_and_stops_after_hub_handover(): void
    {
        DB::table('orders')->where('id', 1000)->update(['status' => 'READY_FOR_PICKUP']);
        $session = $this->start('pickup');
        DB::table('orders')->where('id', 1000)->update(['status' => 'PICKED_UP']);
        $this->putJson('/api/courier/tracking/location', $this->fix() + ['session_id' => $session])->assertOk();
        DB::table('orders')->where('id', 1000)->update(['status' => 'AT_HUB']);
        $this->putJson('/api/courier/tracking/location', $this->fix() + ['session_id' => $session])->assertForbidden();
    }

    public function test_bad_or_old_gps_and_other_riders_orders_are_rejected(): void
    {
        $this->postJson('/api/courier/tracking/start', $this->fix(['latitude' => 91]) + ['order_id' => 1000, 'role' => 'delivery'])->assertUnprocessable();
        $this->postJson('/api/courier/tracking/start', $this->fix(['recorded_at' => now()->subMinutes(3)->toIso8601String()]) + ['order_id' => 1000, 'role' => 'delivery'])->assertUnprocessable();
        $this->postJson('/api/courier/tracking/start', $this->fix(['recorded_at' => now()->addMinutes(2)->toIso8601String()]) + ['order_id' => 1000, 'role' => 'delivery'])->assertUnprocessable();
        Sanctum::actingAs(User::findOrFail(4));
        $this->postJson('/api/courier/tracking/start', $this->fix() + ['order_id' => 1000, 'role' => 'delivery'])->assertForbidden();
    }

    public function test_moving_to_another_hub_hides_the_old_hubs_location(): void
    {
        $this->start();
        DB::table('courier_profiles')->where('id', 100)->update(['logistics_profile_id' => 20]);
        Sanctum::actingAs(User::findOrFail(3));
        $this->getJson('/api/logistics/rider-locations')->assertOk()->assertJsonPath('data.0.courier_id', 100)
            ->assertJsonPath('data.0.location', null);
    }

    public function test_only_approved_active_hub_owners_can_read_locations(): void
    {
        $this->getJson('/api/logistics/rider-locations')->assertForbidden();
        Sanctum::actingAs(User::findOrFail(5));
        $this->getJson('/api/logistics/rider-locations')->assertForbidden();
        Sanctum::actingAs(User::findOrFail(2));
        DB::table('logistics_profiles')->where('id', 10)->update(['status' => 'pending']);
        $this->getJson('/api/logistics/rider-locations')->assertForbidden();
        $this->app['auth']->forgetGuards();
        $this->getJson('/api/logistics/rider-locations')->assertUnauthorized();
    }
}
