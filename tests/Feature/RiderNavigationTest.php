<?php

namespace Tests\Feature;

use App\Models\CourierProfile;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RiderNavigationTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'database.connections.sqlite.url' => null, 'rider_navigation.enforce_arrival_radius' => false]);
        DB::purge('sqlite');
        Carbon::setTestNow(Carbon::parse('2026-11-08T04:00:00Z'));
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            foreach (['name', 'email', 'password', 'role', 'account_status'] as $field) {
                $table->string($field);
            }
            $table->timestamps();
        });
        Schema::create('courier_profiles', function (Blueprint $table) {
            $table->id();
            $table->integer('user_id');
            $table->integer('logistics_profile_id');
            $table->string('status');
            $table->boolean('is_active');
            $table->timestamps();
        });
        foreach (['seller_profiles', 'logistics_profiles'] as $name) {
            Schema::create($name, function (Blueprint $table) {
                $table->id();
                $table->integer('user_id');
                foreach (['business_name', 'status', 'contact_no', 'street_address', 'barangay', 'municipality', 'province'] as $field) {
                    $table->string($field)->nullable();
                }
                $table->decimal('latitude', 10, 7)->nullable();
                $table->decimal('longitude', 10, 7)->nullable();
            });
        }
        Schema::create('orders', function (Blueprint $table) {
            $table->id();
            $table->integer('seller_id');
            $table->integer('pickup_rider_id')->nullable();
            $table->integer('delivery_rider_id')->nullable();
            $table->string('status');
            foreach (['pickup_status', 'pickup_date', 'buyer_name', 'ship_street', 'ship_barangay', 'ship_municipality', 'ship_province', 'ship_contact_no'] as $field) {
                $table->string($field)->nullable();
            }
            $table->json('shipping_address')->nullable();
        });
        Schema::create('order_events', function (Blueprint $table) {
            $table->id();
            $table->integer('order_id');
            $table->integer('actor_id');
            $table->string('status')->nullable();
            $table->string('title');
            $table->text('note')->nullable();
            $table->timestamps();
        });
        foreach ([1 => 'courier', 2 => 'logistics', 3 => 'seller'] as $id => $role) {
            User::forceCreate(['id' => $id, 'name' => 'Person '.$id, 'email' => $id.'@example.test',
                'password' => 'password', 'role' => $role, 'account_status' => 'active']);
        }
        CourierProfile::create(['id' => 10, 'user_id' => 1, 'logistics_profile_id' => 5, 'status' => 'approved', 'is_active' => true]);
        DB::table('logistics_profiles')->insert(['id' => 5, 'user_id' => 2, 'status' => 'approved',
            'business_name' => 'Assigned hub', 'street_address' => '100 Hub Road', 'municipality' => 'Manila']);
        DB::table('seller_profiles')->insert(['id' => 1, 'user_id' => 3, 'business_name' => 'Seller shop',
            'contact_no' => '09171234567', 'street_address' => '25 Seller Road', 'municipality' => 'Manila']);
        DB::table('orders')->insert(['id' => 100, 'seller_id' => 3, 'pickup_rider_id' => 10, 'delivery_rider_id' => 10,
            'status' => 'OUT_FOR_DELIVERY', 'pickup_status' => 'accepted', 'buyer_name' => 'Customer Name',
            'ship_street' => '15 Customer Road', 'ship_municipality' => 'Manila', 'ship_contact_no' => '09179876543',
            'shipping_address' => json_encode(['latitude' => 14.6, 'longitude' => 120.98])]);
        Sanctum::actingAs(User::findOrFail(1));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function location(array $overrides = []): array
    {
        return array_merge(['role' => 'delivery', 'latitude' => 14.6, 'longitude' => 120.98,
            'accuracy' => 10, 'recorded_at' => now('UTC')->toIso8601String()], $overrides);
    }

    public function test_route_uses_token_assignment_and_ends_at_the_assigned_hub(): void
    {
        DB::table('orders')->insert(['id' => 101, 'seller_id' => 3, 'delivery_rider_id' => 99, 'status' => 'OUT_FOR_DELIVERY']);
        $this->getJson('/api/courier/navigation/route?role=delivery&rider_id=99')->assertOk()
            ->assertJsonCount(1, 'stops')->assertJsonPath('stops.0.order_id', 100)
            ->assertJsonPath('stops.0.address', '15 Customer Road, Manila')
            ->assertJsonPath('stops.0.latitude', 14.6)->assertJsonPath('stops.0.phone', '09179876543')
            ->assertJsonPath('station.id', 5)->assertJsonPath('station.address', '100 Hub Road, Manila');
    }

    public function test_pickup_route_uses_seller_address_and_contact_without_customer_names(): void
    {
        DB::table('orders')->where('id', 100)->update(['status' => 'READY_FOR_PICKUP']);
        $this->getJson('/api/courier/navigation/route?role=pickup')->assertOk()
            ->assertJsonPath('stops.0.address', '25 Seller Road, Manila')
            ->assertJsonPath('stops.0.phone', '09171234567')->assertJsonPath('stops.0.latitude', null);
    }

    public function test_arrival_records_fresh_gps_without_changing_delivery_status(): void
    {
        $this->postJson('/api/courier/orders/100/arrived', $this->location())->assertOk()
            ->assertJsonPath('within_radius', true)->assertJsonPath('warning', null);
        $this->assertDatabaseHas('orders', ['id' => 100, 'status' => 'OUT_FOR_DELIVERY']);
        $event = DB::table('order_events')->first();
        $this->assertSame(1, $event->actor_id);
        $this->assertSame(14.6, json_decode($event->note, true)['latitude']);
    }

    public function test_radius_is_a_warning_by_default_but_strict_mode_rejects_it(): void
    {
        $far = $this->location(['latitude' => 14.61]);
        $this->postJson('/api/courier/orders/100/arrived', $far)->assertOk()
            ->assertJsonPath('within_radius', false)->assertJsonPath('warning', 'You appear to be outside the 150 m arrival radius.');
        config(['rider_navigation.enforce_arrival_radius' => true]);
        $this->postJson('/api/courier/orders/100/arrived', $far)->assertUnprocessable();
        $this->assertDatabaseCount('order_events', 1);
    }

    public function test_missing_pin_stays_unknown_and_cannot_pass_strict_verification(): void
    {
        DB::table('orders')->where('id', 100)->update(['shipping_address' => null]);
        $this->postJson('/api/courier/orders/100/arrived', $this->location())->assertOk()
            ->assertJsonPath('within_radius', null)->assertJsonPath('distance_meters', null);
        config(['rider_navigation.enforce_arrival_radius' => true]);
        $this->postJson('/api/courier/orders/100/arrived', $this->location())->assertUnprocessable();
    }

    public function test_stale_invalid_or_inaccurate_gps_does_not_pass_strict_arrival(): void
    {
        config(['rider_navigation.enforce_arrival_radius' => true]);
        foreach ([['recorded_at' => now('UTC')->subMinutes(3)->toIso8601String()], ['latitude' => 91],
            ['recorded_at' => now('UTC')->addMinutes(3)->toIso8601String()], ['accuracy' => 300]] as $invalid) {
            $this->postJson('/api/courier/orders/100/arrived', $this->location($invalid))->assertUnprocessable();
        }
        $this->assertDatabaseCount('order_events', 0);
    }

    public function test_arrival_rejects_another_rider_and_an_incorrect_delivery_stage(): void
    {
        DB::table('orders')->where('id', 100)->update(['status' => 'ASSIGNED_TO_RIDER']);
        $this->postJson('/api/courier/orders/100/arrived', $this->location())->assertUnprocessable();
        DB::table('orders')->where('id', 100)->update(['delivery_rider_id' => 99]);
        $this->postJson('/api/courier/orders/100/arrived', $this->location())->assertForbidden();
        $this->assertDatabaseCount('order_events', 0);
    }

    public function test_new_endpoints_require_authentication(): void
    {
        auth()->forgetGuards();
        $this->getJson('/api/courier/navigation/route?role=delivery')->assertUnauthorized();
        $this->postJson('/api/courier/orders/100/arrived', $this->location())->assertUnauthorized();
    }
}
