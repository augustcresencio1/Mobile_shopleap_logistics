<?php

namespace Tests\Feature;

use App\Models\CourierProfile;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Contracts\Filesystem\Filesystem;
use Illuminate\Database\Events\TransactionCommitted;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CourierEarningsTest extends TestCase
{
    private User $rider;

    private CourierProfile $courier;

    protected function setUp(): void
    {
        parent::setUp();
        // These tests never connect to the application's shared PostgreSQL database.
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'database.connections.sqlite.url' => null]);
        DB::purge('sqlite');
        Carbon::setTestNow(Carbon::parse('2026-11-08T12:00:00+08:00'));
        $this->createSchema();
        (require database_path('migrations/2026_11_15_040000_create_order_delivery_proofs_table.php'))->up();
        config(['delivery_proofs.disk' => 'r2_private']);
        Storage::fake('r2_private');
        $this->rider = User::forceCreate(['id' => 1, 'name' => 'Rider', 'email' => 'rider@example.test',
            'password' => 'password', 'role' => 'courier', 'account_status' => 'active']);
        User::forceCreate(['id' => 2, 'name' => 'Hub', 'email' => 'hub@example.test',
            'password' => 'password', 'role' => 'logistics', 'account_status' => 'active']);
        DB::table('logistics_profiles')->insert(['id' => 1, 'user_id' => 2, 'status' => 'approved']);
        $this->courier = CourierProfile::create(['id' => 1, 'user_id' => 1, 'logistics_profile_id' => 1,
            'status' => 'approved', 'is_active' => true]);
        Sanctum::actingAs($this->rider);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function createSchema(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            foreach (['name', 'email', 'password', 'role', 'account_status'] as $column) {
                $table->string($column);
            }
            $table->timestamps();
        });
        Schema::create('courier_profiles', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('user_id');
            $table->unsignedBigInteger('logistics_profile_id')->nullable();
            $table->string('status');
            $table->boolean('is_active');
            $table->timestamps();
        });
        Schema::create('logistics_profiles', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('user_id');
            $table->string('status');
        });
        Schema::create('rider_rates', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('logistics_profile_id');
            $table->decimal('amount', 12, 2);
            $table->timestamp('effective_from');
            $table->unsignedBigInteger('created_by');
            $table->timestamps();
        });
        Schema::create('orders', function (Blueprint $table) {
            $table->id();
            $table->string('order_number')->nullable();
            $table->string('waybill_code')->nullable();
            $table->json('shipping_address')->nullable();
            foreach (['seller_id', 'pickup_rider_id', 'delivery_rider_id', 'logistics_profile_id',
                'earning_hub_id', 'earning_courier_id'] as $column) {
                $table->unsignedBigInteger($column)->nullable();
            }
            $table->string('status');
            foreach (['buyer_name', 'pickup_status', 'pickup_date', 'pickup_time_slot', 'pickup_decline_reason',
                'delivery_area', 'ship_province', 'ship_municipality', 'ship_barangay', 'ship_street', 'ship_contact_no'] as $column) {
                $table->string($column)->nullable();
            }
            $table->integer('delivery_attempts')->default(0);
            foreach (['total_amount', 'shipping_fee', 'rider_fee', 'rider_pay', 'cod_collected_amount', 'delivered_shipping_fee'] as $column) {
                $table->decimal($column, 12, 2)->nullable();
            }
            foreach (['delivered_at', 'cod_collected_at', 'earnings_recorded_at'] as $column) {
                $table->timestamp($column)->nullable();
            }
            $table->timestamps();
        });
        Schema::create('order_events', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('order_id');
            $table->unsignedBigInteger('actor_id')->nullable();
            $table->string('status')->nullable();
            $table->string('title');
            $table->text('note')->nullable();
            $table->timestamps();
        });
        Schema::create('parcel_events', function (Blueprint $table) {
            $table->id();
            foreach (['order_id', 'hub_id', 'rider_id', 'actor_user_id'] as $field) {
                $table->unsignedBigInteger($field)->nullable();
            }
            foreach (['event_type', 'from_status', 'to_status', 'note'] as $field) {
                $table->string($field)->nullable();
            }
            $table->timestamps();
        });
        Schema::create('order_items', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('order_id');
            $table->string('product_name');
            $table->json('selected_options')->nullable();
            $table->decimal('weight_kg', 10, 3)->nullable();
            $table->integer('quantity');
        });
        Schema::create('seller_profiles', function (Blueprint $table) {
            $table->id();
            $table->string('business_name')->nullable();
            $table->unsignedBigInteger('user_id');
            foreach (['street_address', 'barangay', 'municipality', 'province', 'contact_no'] as $column) {
                $table->string($column)->nullable();
            }
        });
    }

    private function order(array $overrides = []): int
    {
        return DB::table('orders')->insertGetId(array_merge([
            'order_number' => 'SL-TEST-'.(DB::table('orders')->max('id') + 1),
            'seller_id' => 2, 'delivery_rider_id' => 1, 'logistics_profile_id' => 1,
            'status' => 'DELIVERED', 'rider_fee' => '99.99', 'total_amount' => '120.00', 'shipping_fee' => '20.00',
            'delivered_at' => '2026-11-08 04:00:00', 'created_at' => '2026-11-08 04:00:00',
            'updated_at' => '2026-11-08 04:00:00',
        ], $overrides));
    }

    public function test_atomic_pickup_delivery_and_cod_writes_broadcast_after_the_commit(): void
    {
        config(['services.supabase.url' => 'https://realtime.example.test',
            'services.supabase.service_key' => 'test-service-key']);
        Http::fake(['*' => Http::response([], 202)]);
        $pickup = $this->order(['pickup_rider_id' => 1, 'delivery_rider_id' => 10,
            'status' => 'READY_FOR_PICKUP', 'pickup_status' => 'assigned']);
        $this->postJson('/api/courier/orders/'.$pickup.'/pickup/accept')->assertOk();
        Http::assertSent(fn ($request) => $request['messages'][0]['topic'] === 'rider:10');

        $delivery = $this->order(['status' => 'ASSIGNED_TO_RIDER', 'delivered_at' => null]);
        DB::beginTransaction();
        $before = Http::recorded()->count();
        $this->postJson('/api/courier/orders/'.$delivery.'/start-delivery')->assertOk();
        $this->assertCount($before, Http::recorded());
        DB::commit();
        $this->assertCount($before + 1, Http::recorded());
        $this->submitDelivery($this->deliveryPath($delivery))->assertOk();
        $this->assertCount($before + 2, Http::recorded());
    }

    private function rate(string $amount = '20.25', string $effective = '2026-11-08 01:00:00', int $hub = 1): void
    {
        DB::table('rider_rates')->insert(['logistics_profile_id' => $hub, 'amount' => $amount,
            'effective_from' => $effective, 'created_by' => 2]);
    }

    private function proof(int $width = 640, int $height = 800): UploadedFile
    {
        // Generate a valid RGB PNG without depending on the optional GD extension.
        $chunk = fn ($type, $bytes) => pack('N', strlen($bytes)).$type.$bytes.pack('N', crc32($type.$bytes));
        $bytes = "\x89PNG\r\n\x1a\n"
            .$chunk('IHDR', pack('NNCCCCC', $width, $height, 8, 2, 0, 0, 0))
            .$chunk('IDAT', gzcompress(str_repeat("\0".str_repeat("\0", $width * 3), $height)))
            .$chunk('IEND', '');

        return UploadedFile::fake()->createWithContent('proof.png', $bytes);
    }

    private function deliveryPath(int $id): string
    {
        return '/api/courier/deliveries/'.DB::table('orders')->where('id', $id)->value('order_number').'/delivered';
    }

    private function submitDelivery(string $path, array $fields = [])
    {
        return $this->post($path, array_merge(['amount' => '140.00', 'proof_image' => $this->proof()], $fields),
            ['Accept' => 'application/json']);
    }

    private function publicCodeOrder(array $overrides = []): int
    {
        DB::table('seller_profiles')->insert(['user_id' => 2, 'business_name' => 'Test shop']);

        return $this->order($overrides + [
            'order_number' => 'SL23456789ABCDEF', 'waybill_code' => 'WB23456789ABCDEF',
            'status' => 'READY_FOR_PICKUP', 'pickup_status' => 'accepted',
            'pickup_rider_id' => 1, 'delivery_rider_id' => null,
            'total_amount' => '90.00', 'shipping_fee' => '40.00',
        ]);
    }

    public function test_public_and_legacy_labels_resolve_the_same_assigned_parcel_without_mutating_it(): void
    {
        $id = $this->publicCodeOrder();
        foreach (['WB23456789ABCDEF', 'wb23456789abcdef', 'SL23456789ABCDEF',
            'SHOPLEAP:ORDER:WB23456789ABCDEF', 'SHOPLEAP:ORDER:SL23456789ABCDEF',
            (string) $id, str_pad((string) $id, 10, '0', STR_PAD_LEFT),
            'SHOPLEAP:ORDER:'.$id, 'SL-ORDER-'.$id, 'https://example.test/orders/'.$id.'?print=1'] as $code) {
            $this->getJson('/api/courier/orders/scan/'.rawurlencode($code))->assertOk()
                ->assertJsonPath('data.id', $id)->assertJsonPath('data.order_number', 'SL23456789ABCDEF')
                ->assertJsonPath('data.waybill_code', 'WB23456789ABCDEF')->assertJsonPath('role', 'pickup');
        }
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'READY_FOR_PICKUP',
            'total_amount' => '90.00', 'shipping_fee' => '40.00']);
        $this->assertSame(0, DB::table('order_events')->count());
    }

    public function test_scan_resolves_hyphenated_waybills_and_legacy_codes_with_the_expected_response(): void
    {
        $this->assertCurrentScanCodesResolve();
    }

    public function test_scan_resolves_hyphenated_waybills_and_legacy_codes_with_cached_routes(): void
    {
        $router = $this->app['router'];
        $router->setCompiledRoutes($router->getRoutes()->compile());

        $this->assertCurrentScanCodesResolve();
    }

    private function assertCurrentScanCodesResolve(): void
    {
        $id = $this->publicCodeOrder(['waybill_code' => 'WB-CMSJY2NW5X', 'order_number' => 'SL-PZ7NKDPW']);
        $codes = ['WB-CMSJY2NW5X', 'wb-cmsjy2nw5x', 'WBCMSJY2NW5X', 'SL-PZ7NKDPW',
            (string) $id, str_pad((string) $id, 10, '0', STR_PAD_LEFT),
            'SHOPLEAP:ORDER:'.$id, 'SHOPLEAP:ORDER:WB-CMSJY2NW5X',
            'https://shopleap.shop/track/WB-CMSJY2NW5X?print=1'];

        foreach (['READY_FOR_PICKUP' => 'pickup', 'ASSIGNED_TO_RIDER' => 'delivery'] as $status => $role) {
            DB::table('orders')->where('id', $id)->update(['status' => $status,
                'pickup_rider_id' => $role === 'pickup' ? 1 : null,
                'delivery_rider_id' => $role === 'delivery' ? 1 : null]);

            foreach ($codes as $code) {
                $response = $this->getJson('/api/courier/orders/scan/'.rawurlencode($code))->assertOk()
                    ->assertJsonPath('data.id', $id)->assertJsonPath('data.waybill_code', 'WB-CMSJY2NW5X')
                    ->assertJsonPath('data.order_number', 'SL-PZ7NKDPW')->assertJsonPath('data.status', $status)
                    ->assertJsonPath('role', $role)
                    ->assertJsonStructure(['data' => ['items', 'seller_shop', 'seller_contact', 'parcel_weight_kg'], 'role']);
                $this->assertSame(['data', 'role'], array_keys($response->json()));
            }
        }

        DB::table('orders')->where('id', $id)->update(['pickup_rider_id' => 99, 'delivery_rider_id' => 99]);
        foreach (['WB-CMSJY2NW5X', 'SL-PZ7NKDPW', (string) $id] as $code) {
            $this->getJson('/api/courier/orders/scan/'.$code)->assertNotFound()
                ->assertExactJson(['message' => 'No such order, or it is not assigned to you.']);
        }
    }

    public function test_public_scan_never_exposes_another_riders_parcel_or_falls_back_to_its_numeric_suffix(): void
    {
        $id = $this->publicCodeOrder(['pickup_rider_id' => 99]);
        foreach (['WB23456789ABCDEF', 'SL23456789ABCDEF', 'SHOPLEAP:ORDER:WB23456789ABCDEF', (string) $id] as $code) {
            $this->getJson('/api/courier/orders/scan/'.rawurlencode($code))->assertNotFound();
        }
        $this->getJson('/api/courier/orders/scan/WB23456789ABCDE2')->assertNotFound();
        foreach (['WB-missing-1', 'SHOPLEAP:BAG:1', '0', '999999999999999999999999999999999', "x' OR 1=1", str_repeat('A', 257)] as $code) {
            $this->getJson('/api/courier/orders/scan/'.rawurlencode($code))->assertUnprocessable();
        }
    }

    public function test_pickup_confirmation_validates_the_supplied_public_qr_using_the_public_order_number(): void
    {
        $id = $this->publicCodeOrder();
        $path = '/api/courier/pickups/SL23456789ABCDEF/confirm';
        $this->postJson($path, ['scan' => 'WB23456789ABCDE2'])->assertUnprocessable();
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'READY_FOR_PICKUP']);
        $this->postJson($path, ['scan' => 'SHOPLEAP:ORDER:WB23456789ABCDEF'])->assertOk();
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'PICKED_UP', 'pickup_rider_id' => 1,
            'order_number' => 'SL23456789ABCDEF', 'waybill_code' => 'WB23456789ABCDEF']);
        $this->postJson($path, ['scan' => 'WB23456789ABCDEF'])->assertConflict();
        $this->assertSame(1, DB::table('order_events')->where('order_id', $id)->where('status', 'PICKED_UP')->count());
        $this->assertSame(1, DB::table('parcel_events')->where('order_id', $id)->where('to_status', 'PICKED_UP')->count());
        $this->assertDatabaseHas('parcel_events', ['order_id' => $id, 'event_type' => 'picked_up',
            'from_status' => 'READY_FOR_PICKUP', 'to_status' => 'PICKED_UP', 'hub_id' => 1, 'rider_id' => 1, 'actor_user_id' => 1]);
    }

    public function test_delivered_history_and_earnings_preserve_the_saved_public_reference_and_money(): void
    {
        $id = $this->publicCodeOrder(['status' => 'ASSIGNED_TO_RIDER', 'delivery_rider_id' => 1, 'delivered_at' => null]);
        $this->rate('20.25');
        $this->getJson('/api/courier/orders/scan/WB23456789ABCDEF')->assertOk()->assertJsonPath('role', 'delivery');
        $this->postJson('/api/courier/orders/'.$id.'/start-delivery')->assertOk();
        $this->submitDelivery($this->deliveryPath($id), ['amount' => '130.00'])->assertOk();
        $this->submitDelivery($this->deliveryPath($id), ['amount' => '130.00'])->assertOk();
        $this->assertSame(['OUT_FOR_DELIVERY', 'DELIVERED'], DB::table('parcel_events')->where('order_id', $id)->orderBy('id')->pluck('to_status')->all());
        $this->getJson('/api/courier/history')->assertOk()
            ->assertJsonPath('data.0.id', $id)->assertJsonPath('data.0.order_number', 'SL23456789ABCDEF')
            ->assertJsonPath('data.0.waybill_code', 'WB23456789ABCDEF')->assertJsonPath('data.0.cod_collected', '130.00');
        $this->getJson('/api/courier/earnings/history')->assertOk()
            ->assertJsonPath('data.0.order_id', $id)->assertJsonPath('data.0.order_number', 'SL23456789ABCDEF')
            ->assertJsonPath('data.0.waybill_code', 'WB23456789ABCDEF')->assertJsonPath('data.0.amount', '20.25');
    }

    public function test_assignment_acceptance_is_internal_and_does_not_invent_a_public_status_transition(): void
    {
        $id = $this->publicCodeOrder(['pickup_status' => 'assigned']);
        $this->postJson('/api/courier/pickups/SL23456789ABCDEF/accept')->assertOk();
        $this->assertDatabaseHas('order_events', ['order_id' => $id, 'status' => null, 'title' => 'Rider accepted the pickup']);
        $this->assertSame(0, DB::table('parcel_events')->where('order_id', $id)->count());
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'READY_FOR_PICKUP', 'pickup_status' => 'accepted']);
    }

    public function test_legacy_database_without_parcel_events_retains_numeric_pickup_and_public_lookup(): void
    {
        Schema::drop('parcel_events');
        $id = $this->publicCodeOrder();
        $this->getJson('/api/courier/orders/scan/WB23456789ABCDEF')->assertOk();
        $this->postJson('/api/courier/orders/'.$id.'/pickup')->assertOk();
        $this->assertDatabaseHas('order_events', ['order_id' => $id, 'status' => 'PICKED_UP']);
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'PICKED_UP']);
    }

    public function test_failed_tracking_insert_rolls_back_the_status_and_legacy_event_together(): void
    {
        $id = $this->publicCodeOrder();
        Schema::table('parcel_events', fn (Blueprint $table) => $table->dropColumn('actor_user_id'));
        $this->postJson('/api/courier/pickups/SL23456789ABCDEF/confirm', ['scan' => 'WB23456789ABCDEF'])->assertStatus(500);
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'READY_FOR_PICKUP']);
        $this->assertSame(0, DB::table('order_events')->where('order_id', $id)->count());
    }

    public function test_all_new_routes_require_authentication(): void
    {
        auth()->forgetGuards();
        foreach (['pickups', 'deliveries', 'history', 'dashboard', 'earnings', 'earnings/rate', 'earnings/overview', 'earnings/summary', 'earnings/history'] as $path) {
            $this->getJson('/api/courier/'.$path)->assertUnauthorized();
        }
        $this->postJson('/api/courier/deliveries/1/delivered', ['amount' => '140.00'])->assertUnauthorized();
        $this->getJson('/api/courier/orders/scan/WB23456789ABCDEF')->assertUnauthorized();
        foreach (['pickups/SL-PZ7NKDPW/accept', 'pickups/SL-PZ7NKDPW/decline', 'pickups/SL-PZ7NKDPW/confirm',
            'deliveries/SL-PZ7NKDPW/out', 'deliveries/SL-PZ7NKDPW/failed'] as $path) {
            $this->postJson('/api/courier/'.$path)->assertUnauthorized();
        }
    }

    public function test_public_pickup_and_delivery_routes_resolve_only_the_assigned_public_number(): void
    {
        $id = $this->publicCodeOrder(['order_number' => 'SL-PZ7NKDPW', 'waybill_code' => 'WB-CMSJY2NW5X',
            'pickup_status' => 'assigned', 'buyer_name' => 'Waybill recipient']);
        $this->getJson('/api/courier/pickups?filter=awaiting_accept')->assertOk()
            ->assertJsonPath('data.0.order_number', 'SL-PZ7NKDPW')->assertJsonPath('data.0.buyer_name', 'Waybill recipient');
        $this->getJson('/api/courier/pickups')->assertOk()->assertJsonCount(0, 'data');
        $this->postJson('/api/courier/pickups/'.$id.'/accept')->assertNotFound();
        $this->postJson('/api/courier/pickups/SL-PZ7NKDPW/decline')->assertUnprocessable()->assertJsonValidationErrors('reason');
        $this->postJson('/api/courier/pickups/SL-PZ7NKDPW/accept')->assertOk();
        $this->getJson('/api/courier/pickups')->assertOk()->assertJsonPath('data.0.buyer_name', 'Waybill recipient');
        $this->postJson('/api/courier/pickups/SL-PZ7NKDPW/confirm', ['scan' => 'WB-CMSJY2NW5X'])
            ->assertOk()->assertJsonPath('status', 'PICKED_UP');

        $declined = $this->publicCodeOrder(['order_number' => 'SL-DECLINED', 'pickup_status' => 'assigned']);
        $this->postJson('/api/courier/pickups/SL-DECLINED/decline', ['reason' => 'Cannot reach seller'])->assertOk();
        $this->assertDatabaseHas('orders', ['id' => $declined, 'pickup_status' => 'declined', 'pickup_decline_reason' => 'Cannot reach seller']);

        DB::table('orders')->where('id', $id)->update(['delivery_rider_id' => 1, 'status' => 'ASSIGNED_TO_RIDER']);
        $this->postJson('/api/courier/deliveries/'.$id.'/out')->assertNotFound();
        $this->postJson('/api/courier/deliveries/SL-PZ7NKDPW/out')->assertOk()->assertJsonPath('status', 'OUT_FOR_DELIVERY');
        $this->postJson('/api/courier/deliveries/SL-PZ7NKDPW/delivered', ['amount' => '130.00'])
            ->assertUnprocessable()->assertJsonValidationErrors('proof_image');
        $this->postJson('/api/courier/deliveries/SL-PZ7NKDPW/failed')->assertUnprocessable()->assertJsonValidationErrors('reason');
        $this->postJson('/api/courier/deliveries/SL-PZ7NKDPW/failed', ['reason' => 'Recipient unavailable'])
            ->assertOk()->assertJsonPath('status', 'DELIVERY_FAILED');
        $this->assertDatabaseHas('orders', ['id' => $id, 'delivery_attempts' => 1]);

        DB::table('orders')->where('id', $id)->update(['pickup_rider_id' => 99, 'delivery_rider_id' => 99]);
        foreach (['pickups/SL-PZ7NKDPW/accept', 'pickups/SL-PZ7NKDPW/decline', 'pickups/SL-PZ7NKDPW/confirm',
            'deliveries/SL-PZ7NKDPW/out', 'deliveries/SL-PZ7NKDPW/failed'] as $path) {
            $this->postJson('/api/courier/'.$path, ['scan' => 'WB-CMSJY2NW5X', 'reason' => 'test'])->assertNotFound();
        }
    }

    public function test_awaiting_pickup_filter_includes_null_pending_and_assigned_only(): void
    {
        foreach ([null, 'pending', 'assigned', 'accepted', 'declined'] as $status) {
            $this->order(['pickup_rider_id' => 1, 'status' => 'READY_FOR_PICKUP', 'pickup_status' => $status]);
        }
        $this->getJson('/api/courier/pickups?filter=awaiting_accept')->assertOk()->assertJsonCount(3, 'data');
        $this->getJson('/api/courier/pickups')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.pickup_status', 'accepted');
    }

    public function test_all_listed_routes_require_an_approved_active_courier_and_available_hub(): void
    {
        $getPaths = ['pickups', 'deliveries', 'dashboard', 'history', 'earnings', 'earnings/summary', 'earnings/rate', 'earnings/history'];
        $postPaths = ['pickups/SL-PZ7NKDPW/accept', 'pickups/SL-PZ7NKDPW/decline', 'pickups/SL-PZ7NKDPW/confirm',
            'deliveries/SL-PZ7NKDPW/out', 'deliveries/SL-PZ7NKDPW/delivered', 'deliveries/SL-PZ7NKDPW/failed'];
        foreach (['pending_courier', 'inactive_courier', 'unapproved_hub', 'inactive_hub_owner'] as $state) {
            $this->courier->update(['status' => $state === 'pending_courier' ? 'pending' : 'approved',
                'is_active' => $state !== 'inactive_courier']);
            DB::table('logistics_profiles')->where('id', 1)->update(['status' => $state === 'unapproved_hub' ? 'pending' : 'approved']);
            DB::table('users')->where('id', 2)->update(['account_status' => $state === 'inactive_hub_owner' ? 'inactive' : 'active']);
            foreach ($getPaths as $path) {
                $this->getJson('/api/courier/'.$path)->assertForbidden();
            }
            foreach ($postPaths as $path) {
                $this->postJson('/api/courier/'.$path)->assertForbidden();
            }
        }
    }

    public function test_bell_retains_accepted_parcels_without_changing_dashboard_or_tab_lists(): void
    {
        $request = $this->order(['status' => 'READY_FOR_PICKUP', 'pickup_status' => 'assigned', 'pickup_rider_id' => 1, 'delivery_rider_id' => null]);
        $accepted = $this->order(['status' => 'READY_FOR_PICKUP', 'pickup_status' => 'accepted', 'pickup_rider_id' => 1, 'delivery_rider_id' => null]);
        $pickedUp = $this->order(['status' => 'PICKED_UP', 'pickup_status' => 'accepted', 'pickup_rider_id' => 1, 'delivery_rider_id' => null]);
        $atHub = $this->order(['status' => 'AT_HUB', 'pickup_status' => 'accepted', 'pickup_rider_id' => 1, 'delivery_rider_id' => null]);
        $delivery = $this->order(['status' => 'OUT_FOR_DELIVERY', 'pickup_status' => 'accepted', 'pickup_rider_id' => 1]);
        $this->order(['status' => 'PICKED_UP', 'pickup_status' => 'accepted', 'pickup_rider_id' => 2, 'delivery_rider_id' => 2]);
        foreach (['DELIVERED', 'COMPLETED', 'DELIVERY_FAILED', 'RETURNED', 'CANCELLED'] as $status) {
            $this->order(['status' => $status, 'pickup_status' => 'accepted', 'pickup_rider_id' => 1]);
        }
        $home = $this->getJson('/api/courier/home')->assertOk();
        $this->assertSame([$request], array_column($home->json('requests'), 'id'));
        $this->assertSame([$accepted], array_column($home->json('pickups'), 'id'));
        $this->assertSame([$delivery], array_column($home->json('deliveries'), 'id'));
        $this->assertEqualsCanonicalizing([$accepted, $pickedUp, $atHub, $delivery], array_column($home->json('in_progress'), 'id'));
        $this->assertSame('delivery', collect($home->json('in_progress'))->firstWhere('id', $delivery)['notification_role']);
        $this->assertSame('pickup', collect($home->json('in_progress'))->firstWhere('id', $pickedUp)['notification_role']);
        $this->getJson('/api/courier/pickups')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $accepted);
        $this->getJson('/api/courier/deliveries')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $delivery);
    }

    public function test_summary_and_dashboard_use_saved_pay_including_zero_without_a_fallback(): void
    {
        $this->rate('50.00');
        $this->order(['rider_pay' => '20.25', 'earning_courier_id' => 1, 'cod_collected_amount' => '140.00']);
        $this->order(['rider_pay' => '0.00', 'earning_courier_id' => 1, 'cod_collected_amount' => '140.00']);
        $this->order(['rider_pay' => null, 'cod_collected_amount' => '140.00']);
        $this->order(['status' => 'DELIVERY_FAILED', 'rider_pay' => '99.00']);
        $this->order(['delivery_rider_id' => 2, 'earning_courier_id' => 2, 'rider_pay' => '999.00']);
        $summary = $this->getJson('/api/courier/earnings/summary?preset=today&rider_id=2')->assertOk()
            ->assertJsonPath('total_earned', '20.25')->assertJsonPath('deliveries', 3)
            ->assertJsonPath('recorded_earnings', 2)->assertJsonPath('fee_per_delivery', '50.00')
            ->assertJsonPath('cod_collected', '420.00')->assertJsonPath('daily.0.date', '2026-11-08')
            ->assertJsonPath('daily.0.currency', 'PHP');
        $this->getJson('/api/courier/earnings?preset=today&rider_id=2')->assertOk()->assertExactJson($summary->json());
        $this->getJson('/api/courier/dashboard')->assertOk()
            ->assertJsonPath('earned_today', '20.25')->assertJsonPath('delivered_today', 3)
            ->assertJsonPath('currency', 'PHP');
        $this->getJson('/api/courier/home')->assertOk()
            ->assertJsonPath('earned_week', '20.25')
            ->assertJsonPath('earned_today', '20.25')
            ->assertJsonPath('currency', 'PHP');
    }

    public function test_missing_rates_and_empty_periods_keep_money_nullable_or_zero_as_appropriate(): void
    {
        $this->getJson('/api/courier/earnings/rate')->assertOk()
            ->assertExactJson(['amount' => null, 'currency' => 'PHP', 'effective_from' => null]);
        $this->getJson('/api/courier/earnings/summary')->assertOk()->assertJsonPath('period', 'month')
            ->assertJsonPath('total_earned', '0.00')->assertJsonPath('fee_per_delivery', null)
            ->assertJsonPath('recorded_earnings', 0)->assertJsonPath('daily', []);
    }

    public function test_overview_combines_matching_earnings_data_without_repeating_profile_or_rate_queries(): void
    {
        $this->rate('30.00');
        $this->order(['rider_pay' => '20.25', 'earning_courier_id' => 1, 'cod_collected_amount' => '140.00']);
        DB::enableQueryLog();
        $this->getJson('/api/courier/earnings/overview?preset=today')->assertOk()
            ->assertJsonPath('summary.total_earned', '20.25')
            ->assertJsonPath('summary.deliveries', 1)
            ->assertJsonPath('rate.amount', '30.00')
            ->assertJsonPath('history.meta.total', 1)
            ->assertJsonPath('history.data.0.amount', '20.25');
        $queries = collect(DB::getQueryLog());
        $this->assertCount(1, $queries->filter(fn ($query) => str_contains($query['query'], 'courier_profiles')));
        $this->assertCount(1, $queries->filter(fn ($query) => str_contains($query['query'], 'rider_rates')));
        // One request-scoped schema check handles an older backend without money tables.
        $this->assertLessThanOrEqual(6, $queries->count());
        DB::disableQueryLog();
    }

    public function test_current_rate_uses_the_latest_effective_hub_rate_and_preserves_zero(): void
    {
        $this->rate('10.00', '2026-11-07 00:00:00');
        $this->rate('0.00');
        $this->rate('90.00', '2026-11-09 00:00:00');
        $this->rate('999.00', '2026-11-08 02:00:00', 2);
        $this->getJson('/api/courier/earnings/rate')->assertOk()->assertJsonPath('amount', '0.00')
            ->assertJsonPath('effective_from', '2026-11-08T09:00:00+08:00');
    }

    public function test_summary_and_history_use_the_same_inclusive_manila_dates(): void
    {
        foreach (['2026-11-07 15:59:59', '2026-11-07 16:00:00', '2026-11-08 15:59:59', '2026-11-08 16:00:00'] as $date) {
            $this->order(['delivered_at' => $date, 'rider_pay' => '1.25']);
        }
        $query = '?preset=custom&from=2026-11-08&to=2026-11-08';
        $this->getJson('/api/courier/earnings/summary'.$query)->assertOk()
            ->assertJsonPath('deliveries', 2)->assertJsonPath('total_earned', '2.50');
        $this->getJson('/api/courier/earnings/history'.$query)->assertOk()
            ->assertJsonPath('meta.total', 2)->assertJsonPath('data.0.delivered_at', '2026-11-08T23:59:59+08:00');
    }

    public function test_presets_take_precedence_and_invalid_filters_return_422(): void
    {
        $this->getJson('/api/courier/earnings/summary?period=invalid&preset=today')->assertOk()
            ->assertJsonPath('period', 'today');
        $this->getJson('/api/courier/earnings/summary?preset=custom&from=2026-01-01&to=2027-01-01')->assertOk();
        foreach (['preset=custom', 'preset=custom&from=2026-01-01&to=2027-01-02',
            'preset=custom&from=2026-11-08&to=2026-11-01', 'period=invalid', 'preset=all'] as $query) {
            $this->getJson('/api/courier/earnings/summary?'.$query)->assertUnprocessable();
            $this->getJson('/api/courier/earnings/history?'.$query)->assertUnprocessable();
        }
        $this->getJson('/api/courier/earnings/history?page=0')->assertUnprocessable();
    }

    public function test_history_paginates_and_does_not_invent_pay_for_legacy_deliveries(): void
    {
        for ($index = 0; $index < 21; $index++) {
            $this->order(['rider_pay' => $index === 0 ? '0.00' : null]);
        }
        $this->getJson('/api/courier/earnings/history?preset=today')->assertOk()
            ->assertJsonCount(20, 'data')->assertJsonPath('meta.total', 21)
            ->assertJsonPath('meta.last_page', 2)->assertJsonPath('data.0.amount', null)
            ->assertJsonPath('data.0.recorded_at', null);
        $this->getJson('/api/courier/earnings/history?preset=today&page=2')->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.amount', '0.00');
    }

    public function test_delivery_saves_cod_and_a_fixed_snapshot_and_retries_do_not_duplicate_it(): void
    {
        $this->rate();
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $path = $this->deliveryPath($id);
        $first = $this->submitDelivery($path)->assertOk()
            ->assertJsonPath('earning.amount', '20.25')->assertJsonPath('earning.currency', 'PHP')->json();
        $this->assertDatabaseHas('orders', ['id' => $id, 'rider_pay' => '20.25',
            'cod_collected_amount' => '140.00', 'earning_hub_id' => 1, 'earning_courier_id' => 1]);
        $this->rate('60.00', '2026-11-08 03:00:00');
        $this->submitDelivery($path, ['amount' => '999.99'])->assertOk()->assertExactJson($first);
        $this->assertDatabaseCount('order_events', 1);
        $this->assertDatabaseHas('orders', ['id' => $id, 'rider_pay' => '20.25', 'cod_collected_amount' => '140.00']);
        $this->getJson('/api/courier/earnings/summary?preset=today')->assertOk()
            ->assertJsonPath('deliveries', 1)->assertJsonPath('total_earned', '20.25');
    }

    public function test_a_delivery_without_a_rate_is_not_backfilled_on_retry(): void
    {
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $path = $this->deliveryPath($id);
        $this->submitDelivery($path)->assertOk()->assertJsonPath('earning', null);
        $this->rate();
        $this->submitDelivery($path)->assertOk()->assertJsonPath('earning', null);
        $this->getJson('/api/courier/earnings/summary?preset=today')->assertOk()
            ->assertJsonPath('deliveries', 1)->assertJsonPath('recorded_earnings', 0)->assertJsonPath('total_earned', '0.00');
    }

    public function test_a_zero_rate_creates_a_valid_recorded_earning(): void
    {
        $this->rate('0.00');
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $this->submitDelivery($this->deliveryPath($id), ['amount' => '0.00'])
            ->assertOk()->assertJsonPath('earning.amount', '0.00');
        $this->getJson('/api/courier/earnings/summary?preset=today')->assertOk()
            ->assertJsonPath('recorded_earnings', 1)->assertJsonPath('total_earned', '0.00');
    }

    public function test_delivery_requires_valid_cash_the_correct_rider_and_the_delivery_stage(): void
    {
        $id = $this->order(['status' => 'ASSIGNED_TO_RIDER', 'delivered_at' => null]);
        $path = $this->deliveryPath($id);
        foreach ([[], ['amount' => '-1'], ['amount' => '1.234']] as $body) {
            $this->postJson($path, $body)->assertUnprocessable();
        }
        $this->submitDelivery($path)->assertConflict();
        DB::table('orders')->where('id', $id)->update(['delivery_rider_id' => 2]);
        $this->submitDelivery($path)->assertForbidden();
        $this->assertDatabaseCount('order_events', 0);
    }

    public function test_public_delivery_code_saves_private_proof_and_exposes_only_metadata_in_both_histories(): void
    {
        $this->rate();
        $id = $this->order(['order_number' => 'SL-POD-VERIFY-NEW', 'status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $photo = $this->proof();
        $bytes = file_get_contents($photo->getRealPath());
        $first = $this->submitDelivery($this->deliveryPath($id), [
            'amount' => '800.50', 'proof_image' => $photo,
            'captured_at' => '2026-11-08T11:59:00+08:00',
            'latitude' => '14.5995', 'longitude' => '120.9842', 'notes' => 'Handed to buyer.',
        ])->assertOk()->assertJsonPath('earning.amount', '20.25')
            ->assertJsonPath('proof', ['uploaded' => true, 'captured_at' => '2026-11-08T03:59:00+00:00'])->json();

        $saved = DB::table('order_delivery_proofs')->where('order_id', $id)->first();
        $this->assertSame($bytes, Storage::disk('r2_private')->get($saved->path));
        $this->assertDatabaseHas('order_delivery_proofs', ['order_id' => $id, 'courier_id' => 1,
            'captured_at' => '2026-11-08 03:59:00', 'notes' => 'Handed to buyer.',
            'latitude' => '14.5995', 'longitude' => '120.9842']);

        // A retry cannot replace the accepted image, fields, COD or earning.
        $this->rate('60.00', '2026-11-08 03:00:00');
        $this->submitDelivery($this->deliveryPath($id), ['amount' => '999.99',
            'proof_image' => $this->proof(800, 640), 'notes' => 'Changed on retry.',
            'captured_at' => '2026-11-08T04:00:00Z'])->assertOk()->assertExactJson($first);
        $this->assertEquals($saved, DB::table('order_delivery_proofs')->where('order_id', $id)->first());
        $this->assertSame([$saved->path], Storage::disk('r2_private')->allFiles());
        $this->assertDatabaseHas('orders', ['id' => $id, 'cod_collected_amount' => '800.50',
            'rider_pay' => '20.25', 'delivery_attempts' => 0]);
        $this->assertSame(1, DB::table('parcel_events')->where('to_status', 'DELIVERED')->count());
        foreach (['history', 'earnings/history'] as $path) {
            $response = $this->getJson('/api/courier/'.$path)->assertOk()
                ->assertJsonPath('data.0.proof', $first['proof']);
            foreach ([$saved->path, 'Handed to buyer.', '14.5995', '120.9842'] as $privateValue) {
                $this->assertStringNotContainsString($privateValue, $response->getContent());
            }
        }
    }

    public function test_public_delivery_route_never_interprets_a_code_as_an_internal_id(): void
    {
        $id = $this->order(['order_number' => 'SL-POD-REJECT-ID', 'status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        foreach ([(string) $id, 'SL-MISSING-'.$id, 'WB-POD-REJECT-ID'] as $code) {
            $this->submitDelivery('/api/courier/deliveries/'.$code.'/delivered')->assertForbidden();
        }
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'OUT_FOR_DELIVERY']);
        $this->assertDatabaseCount('order_delivery_proofs', 0);
        DB::table('orders')->where('id', $id)->update(['delivery_rider_id' => 99]);
        $this->submitDelivery($this->deliveryPath($id))->assertForbidden();
        $this->assertSame([], Storage::disk('r2_private')->allFiles());
    }

    public function test_proof_and_optional_fields_are_validated_without_recording_delivery(): void
    {
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $path = $this->deliveryPath($id);
        $basePhoto = $this->proof();
        $overPixels = file_get_contents($basePhoto->getRealPath());
        $overPixels = substr_replace($overPixels, pack('NN', 8000, 5001), 16, 8);
        foreach ([
            ['proof_image' => null],
            ['proof_image' => UploadedFile::fake()->createWithContent('proof.jpg', 'not an image')],
            ['proof_image' => $this->proof(639, 800)],
            ['proof_image' => $this->proof()->size(5121)],
            ['proof_image' => UploadedFile::fake()->createWithContent('proof.png', $overPixels)],
            ['captured_at' => 'invalid'], ['captured_at' => '2026-11-08T11:59:00'],
            ['latitude' => '91'], ['longitude' => '-181'], ['notes' => str_repeat('a', 256)],
            ['amount' => '10000000000.00'],
        ] as $fields) {
            $this->submitDelivery($path, $fields)->assertUnprocessable()->assertJsonStructure(['errors']);
        }
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'OUT_FOR_DELIVERY']);
        $this->assertDatabaseCount('order_delivery_proofs', 0);
        $this->assertSame([], Storage::disk('r2_private')->allFiles());
        $this->submitDelivery($path)->assertOk()
            ->assertJsonPath('proof', ['uploaded' => true, 'captured_at' => null]);
    }

    public function test_legacy_deliver_alias_also_requires_and_saves_a_photo(): void
    {
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $path = '/api/courier/orders/'.$id.'/deliver';
        $this->postJson($path, ['amount' => '140.00'])->assertUnprocessable()->assertJsonValidationErrors('proof_image');
        $this->submitDelivery($path)->assertOk()->assertJsonPath('proof.uploaded', true);
        $this->assertDatabaseCount('order_delivery_proofs', 1);
    }

    public function test_camera_jpeg_and_webp_proofs_are_accepted_with_their_detected_mime_type(): void
    {
        foreach (['jpg' => 'image/jpeg', 'webp' => 'image/webp'] as $extension => $mime) {
            $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
            $photo = new UploadedFile(base_path('tests/Fixtures/delivery-proof.'.$extension),
                'camera.'.$extension, $mime, null, true);
            $this->submitDelivery($this->deliveryPath($id), ['proof_image' => $photo])->assertOk()
                ->assertJsonPath('proof.uploaded', true);
            $this->assertDatabaseHas('order_delivery_proofs', ['order_id' => $id, 'mime_type' => $mime]);
        }
    }

    public function test_older_deliveries_keep_missing_proof_and_are_not_backfilled_on_retry(): void
    {
        $id = $this->order(['status' => 'COMPLETED', 'rider_pay' => '0.00']);
        $this->submitDelivery($this->deliveryPath($id))->assertOk()
            ->assertJsonPath('earning.amount', '0.00')
            ->assertJsonPath('proof', ['uploaded' => false, 'captured_at' => null]);
        foreach (['history', 'earnings/history'] as $path) {
            $this->getJson('/api/courier/'.$path)->assertOk()
                ->assertJsonPath('data.0.proof', ['uploaded' => false, 'captured_at' => null]);
        }
        $this->assertDatabaseCount('order_delivery_proofs', 0);
        $this->assertSame([], Storage::disk('r2_private')->allFiles());
    }

    public function test_failed_storage_preserves_the_delivery_for_retry(): void
    {
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $disk = \Mockery::mock(Filesystem::class);
        $disk->shouldReceive('put')->once()->withArgs(fn ($path, $stream, $options) => is_resource($stream) && $options['visibility'] === 'private')->andReturn(false);
        $disk->shouldReceive('delete')->once()->andReturn(true);
        Storage::shouldReceive('disk')->with('unavailable')->andReturn($disk);
        config(['delivery_proofs.disk' => 'unavailable']);
        $this->submitDelivery($this->deliveryPath($id))->assertStatus(503);
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'OUT_FOR_DELIVERY',
            'rider_pay' => null, 'cod_collected_amount' => null]);
        $this->assertDatabaseCount('order_delivery_proofs', 0);
        $this->assertDatabaseCount('order_events', 0);
    }

    public function test_failed_event_rolls_back_proof_cod_and_earning_and_removes_the_uploaded_file(): void
    {
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $this->rate();
        Schema::table('parcel_events', fn (Blueprint $table) => $table->dropColumn('actor_user_id'));
        $this->submitDelivery($this->deliveryPath($id), ['notes' => 'Sensitive delivery note.'])->assertStatus(503);
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'OUT_FOR_DELIVERY',
            'rider_pay' => null, 'cod_collected_amount' => null]);
        $this->assertDatabaseCount('order_delivery_proofs', 0);
        $this->assertDatabaseCount('order_events', 0);
        $this->assertSame([], Storage::disk('r2_private')->allFiles());
    }

    public function test_delivery_type_errors_are_not_converted_to_storage_or_transaction_success(): void
    {
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $disk = \Mockery::mock(Filesystem::class);
        $disk->shouldReceive('put')->once()->andThrow(new \TypeError('Synthetic proof storage type mismatch.'));
        $disk->shouldReceive('delete')->once()->andReturn(true);
        Storage::shouldReceive('disk')->with('type-error')->andReturn($disk);
        config(['delivery_proofs.disk' => 'type-error']);
        $this->withoutExceptionHandling();

        try {
            $this->submitDelivery($this->deliveryPath($id));
            $this->fail('The original TypeError must reach the exception handler.');
        } catch (\TypeError $exception) {
            $this->assertSame('Synthetic proof storage type mismatch.', $exception->getMessage());
        }
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'OUT_FOR_DELIVERY',
            'rider_pay' => null, 'cod_collected_amount' => null]);
        $this->assertDatabaseCount('order_delivery_proofs', 0);
    }

    public function test_retry_recovers_a_committed_delivery_after_its_acknowledgement_fails(): void
    {
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $this->rate();
        Event::listen(TransactionCommitted::class, function () {
            throw new \RuntimeException('Connection lost after commit.');
        });
        $path = $this->deliveryPath($id);
        $this->submitDelivery($path)->assertStatus(503);
        Event::forget(TransactionCommitted::class);
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'DELIVERED']);
        $saved = DB::table('order_delivery_proofs')->where('order_id', $id)->first();
        Storage::disk('r2_private')->assertExists($saved->path);
        $this->submitDelivery($path)->assertOk()->assertJsonPath('earning.amount', '20.25')
            ->assertJsonPath('proof.uploaded', true);
        $this->assertDatabaseCount('order_delivery_proofs', 1);
        $this->assertDatabaseCount('order_events', 1);
        $this->assertSame([$saved->path], Storage::disk('r2_private')->allFiles());
    }

    public function test_total_upload_limit_and_missing_migration_return_recoverable_errors(): void
    {
        $id = $this->order(['status' => 'OUT_FOR_DELIVERY', 'delivered_at' => null]);
        $this->withServerVariables(['CONTENT_LENGTH' => 6 * 1024 * 1024 + 1]);
        $this->submitDelivery($this->deliveryPath($id))->assertStatus(413);
        $this->withServerVariables(['CONTENT_LENGTH' => 0]);
        Schema::drop('order_delivery_proofs');
        $this->submitDelivery($this->deliveryPath($id))->assertStatus(503);
        $this->assertDatabaseHas('orders', ['id' => $id, 'status' => 'OUT_FOR_DELIVERY']);
    }

    public function test_unavailable_hubs_and_inactive_couriers_cannot_access_earnings(): void
    {
        $this->courier->update(['is_active' => false]);
        $this->getJson('/api/courier/earnings/summary')->assertForbidden();
        $this->courier->update(['is_active' => true]);
        DB::table('users')->where('id', 2)->update(['account_status' => 'inactive']);
        $this->getJson('/api/courier/dashboard')->assertForbidden()
            ->assertJsonPath('courier_status', 'hub_unavailable');
    }

    public function test_existing_history_returns_scalar_nullable_money_and_zero_for_returns(): void
    {
        $legacy = $this->order();
        $zero = $this->order(['rider_pay' => '0.00', 'cod_collected_amount' => '140.00']);
        $returned = $this->order(['status' => 'RETURNED', 'rider_pay' => '20.25']);
        $items = collect($this->getJson('/api/courier/history')->assertOk()->json('data'))->keyBy('order_id');
        $this->assertNull($items[$legacy]['earning']);
        $this->assertNull($items[$legacy]['cod_collected']);
        $this->assertSame('0.00', $items[$zero]['earning']);
        $this->assertSame('140.00', $items[$zero]['cod_collected']);
        $this->assertSame('0.00', $items[$returned]['earning']);
        $this->assertSame('PHP', $items[$zero]['currency']);
    }
}
