<?php

namespace Tests\Feature;

use App\Models\CourierProfile;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CourierMoneyTest extends TestCase
{
    private User $rider;

    private CourierProfile $courier;

    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'database.connections.sqlite.url' => null, 'cache.default' => 'array']);
        DB::purge('sqlite');
        Carbon::setTestNow(Carbon::parse('2026-11-16T10:00:00Z'));
        $this->schema();
        foreach ([10 => 'courier', 11 => 'courier', 20 => 'logistics'] as $id => $role) {
            User::forceCreate(['id' => $id, 'name' => 'Person '.$id, 'email' => $id.'@example.test',
                'role' => $role, 'account_status' => 'active', 'password' => 'password']);
        }
        foreach ([1, 2] as $id) {
            DB::table('logistics_profiles')->insert(['id' => $id, 'user_id' => 20, 'business_name' => 'Hub '.$id, 'status' => 'approved']);
        }
        $this->rider = User::findOrFail(10);
        $this->courier = CourierProfile::create(['id' => 100, 'user_id' => 10, 'logistics_profile_id' => 2,
            'first_name' => 'Ada', 'last_name' => 'Rider', 'status' => 'approved', 'is_active' => true]);
        CourierProfile::create(['id' => 101, 'user_id' => 11, 'logistics_profile_id' => 2,
            'first_name' => 'Other', 'last_name' => 'Rider', 'status' => 'approved', 'is_active' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function schema(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            foreach (['name', 'email', 'password', 'role', 'account_status'] as $field) {
                $table->string($field);
            }
            $table->timestamps();
        });
        Schema::create('logistics_profiles', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('user_id');
            $table->string('business_name');
            $table->string('status');
        });
        Schema::create('courier_profiles', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('user_id');
            $table->unsignedBigInteger('logistics_profile_id');
            $table->string('first_name');
            $table->string('last_name');
            $table->string('status');
            $table->boolean('is_active');
            $table->timestamps();
        });
        Schema::create('orders', function (Blueprint $table) {
            $table->id();
            $table->string('order_number')->unique();
            $table->string('waybill_code')->nullable();
            $table->string('status')->default('DELIVERED');
            foreach (['earning_courier_id', 'earning_hub_id', 'delivery_rider_id'] as $field) {
                $table->unsignedBigInteger($field)->nullable();
            }
            $table->decimal('rider_pay', 12, 2)->nullable();
            $table->decimal('cod_collected_amount', 12, 2)->nullable();
            $table->timestamp('delivered_at')->nullable();
            $table->timestamp('earnings_recorded_at')->nullable();
            $table->timestamps();
        });
        Schema::create('order_events', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('order_id');
            $table->string('status');
            $table->timestamps();
        });
        Schema::create('order_delivery_proofs', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('order_id');
            $table->timestamp('captured_at')->nullable();
        });
        Schema::create('rider_rates', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('logistics_profile_id');
            $table->decimal('amount', 12, 2);
            $table->timestamp('effective_from');
        });
        Schema::create('ledger_transactions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('order_id')->nullable();
            $table->string('type');
            $table->unsignedBigInteger('reversal_of')->nullable();
        });
        Schema::create('rider_cash_handovers', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('hub_id');
            $table->unsignedBigInteger('rider_id');
            $table->string('reference_no')->unique();
            foreach (['amount_expected', 'amount_received', 'short_amount', 'settled_amount'] as $field) {
                $table->decimal($field, 12, 2)->default(0);
            }
            $table->string('status');
            $table->timestamp('confirmed_at');
            $table->timestamp('settled_at')->nullable();
            $table->text('notes')->nullable();
            $table->text('settlement_note')->nullable();
        });
        Schema::create('rider_cash_handover_items', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('handover_id');
            $table->unsignedBigInteger('order_id');
            $table->decimal('amount', 12, 2);
        });
        Schema::create('rider_payouts', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('hub_id');
            $table->unsignedBigInteger('rider_id');
            $table->string('reference_no')->unique();
            $table->decimal('amount', 12, 2);
            $table->string('status');
            $table->timestamp('paid_at');
            $table->text('notes')->nullable();
        });
        Schema::create('rider_payout_items', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('rider_payout_id');
            $table->unsignedBigInteger('order_id')->unique();
            $table->decimal('amount', 12, 2);
        });
        Schema::create('notifications', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('type');
            $table->morphs('notifiable');
            $table->text('data');
            $table->timestamp('read_at')->nullable();
            $table->timestamps();
        });
    }

    private function order(array $overrides = [], bool $ledger = true): int
    {
        $id = DB::table('orders')->insertGetId(array_merge([
            'order_number' => 'SL-MONEY-'.(DB::table('orders')->max('id') + 1),
            'earning_hub_id' => 1, 'earning_courier_id' => 100, 'delivery_rider_id' => 101,
            'rider_pay' => '15.25', 'cod_collected_amount' => '100.10',
            'delivered_at' => '2026-11-16 01:00:00', 'earnings_recorded_at' => '2026-11-16 01:00:00',
            'created_at' => '2026-11-16 01:00:00', 'updated_at' => '2026-11-16 01:00:00',
        ], $overrides));
        if ($ledger) {
            DB::table('ledger_transactions')->insert(['order_id' => $id, 'type' => 'delivery']);
        }

        return $id;
    }

    private function handover(array $overrides = []): int
    {
        return DB::table('rider_cash_handovers')->insertGetId(array_merge([
            'hub_id' => 1, 'rider_id' => 100, 'reference_no' => 'HO-'.Str::upper(Str::random(10)),
            'amount_expected' => '100.10', 'amount_received' => '100.10', 'short_amount' => '0.00',
            'settled_amount' => '0.00', 'status' => 'confirmed', 'confirmed_at' => '2026-11-16 02:00:00',
        ], $overrides));
    }

    private function payout(int $orderId, array $overrides = []): int
    {
        $id = DB::table('rider_payouts')->insertGetId(array_merge([
            'hub_id' => 1, 'rider_id' => 100, 'reference_no' => 'RP-'.Str::upper(Str::random(10)),
            'amount' => '15.25', 'status' => 'paid', 'paid_at' => '2026-12-01 02:00:00',
        ], $overrides));
        DB::table('rider_payout_items')->insert(['rider_payout_id' => $id, 'order_id' => $orderId, 'amount' => '15.25']);

        return $id;
    }

    private function paths(): array
    {
        return ['cash/summary', 'cash/history', 'receipts/cash-handovers/HO-EXAMPLE', 'receipts/rider-payouts/RP-EXAMPLE', 'notifications'];
    }

    public function test_money_endpoints_require_an_approved_rider(): void
    {
        foreach ($this->paths() as $path) {
            $this->getJson('/api/courier/'.$path)->assertUnauthorized();
        }
        Sanctum::actingAs($this->rider);
        $this->courier->update(['status' => 'pending']);
        foreach ($this->paths() as $path) {
            $this->getJson('/api/courier/'.$path)->assertForbidden();
        }
    }

    public function test_cash_uses_unreversed_frozen_ledger_orders_and_actual_allocations_across_hubs(): void
    {
        Sanctum::actingAs($this->rider);
        $first = $this->order(['cod_collected_amount' => '900.10']);
        $this->order();
        $this->order(['earning_courier_id' => 101, 'cod_collected_amount' => '999.00']);
        $this->order(['cod_collected_amount' => '888.00'], ledger: false);
        $this->order(['earnings_recorded_at' => null, 'cod_collected_amount' => '777.00']);
        $reversed = $this->order(['cod_collected_amount' => '666.00']);
        DB::table('ledger_transactions')->insert(['type' => 'reversal',
            'reversal_of' => DB::table('ledger_transactions')->where('order_id', $reversed)->value('id')]);
        $handover = $this->handover(['amount_received' => '700.05', 'amount_expected' => '710.10',
            'short_amount' => '10.05', 'status' => 'short']);
        DB::table('rider_cash_handover_items')->insert(['handover_id' => $handover, 'order_id' => $first, 'amount' => '700.05']);
        $this->handover(['rider_id' => 101, 'short_amount' => '999.00', 'status' => 'short']);

        $response = $this->getJson('/api/courier/cash/summary?rider_id=101&hub_id=2')->assertOk()
            ->assertJsonPath('cash_on_hand', '300.15')->assertJsonPath('shortage_amount', '10.05')
            ->assertJsonPath('currency', 'PHP')->assertJsonCount(2, 'orders')
            ->assertJsonPath('orders.0.amount', '200.05')->assertJsonPath('orders.1.amount', '100.10');
        $this->assertStringNotContainsString('888.00', $response->getContent());
    }

    public function test_cash_returns_real_zero_for_empty_ledger_and_unavailable_for_missing_schema(): void
    {
        Sanctum::actingAs($this->rider);
        $this->getJson('/api/courier/cash/summary')->assertOk()->assertExactJson([
            'cash_on_hand' => '0.00', 'shortage_amount' => '0.00', 'currency' => 'PHP', 'orders' => [],
        ]);
        Schema::drop('rider_cash_handover_items');
        $this->getJson('/api/courier/cash/summary')->assertStatus(503)->assertJsonMissingPath('cash_on_hand');
    }

    public function test_handover_history_keeps_statuses_settled_cash_and_paginated_ownership(): void
    {
        Sanctum::actingAs($this->rider);
        for ($i = 0; $i < 22; $i++) {
            $this->handover(['reference_no' => 'HO-PAGE-'.$i]);
        }
        $this->handover(['status' => 'settled', 'amount_received' => '80.05', 'settled_amount' => '20.05']);
        $this->handover(['rider_id' => 101, 'reference_no' => 'HO-OTHER']);
        $first = $this->getJson('/api/courier/cash/history')->assertOk()->assertJsonCount(20, 'data')
            ->assertJsonPath('meta.total', 23)->assertJsonPath('meta.last_page', 2)
            ->assertJsonPath('data.0.status', 'settled')->assertJsonPath('data.0.amount', '100.10');
        $second = $this->getJson('/api/courier/cash/history?page=2')->assertOk()->assertJsonCount(3, 'data');
        $this->assertStringNotContainsString('HO-OTHER', $first->getContent().$second->getContent());
        $this->getJson('/api/courier/cash/history?page=0')->assertUnprocessable();
    }

    public function test_paid_and_unpaid_follow_delivery_dates_and_frozen_rider_ownership(): void
    {
        Sanctum::actingAs($this->rider);
        $paid = $this->order(['delivered_at' => '2026-11-15 16:00:00']);
        $this->payout($paid);
        $this->order(['rider_pay' => '20.10']);
        $this->order(['rider_pay' => '0.00']);
        $this->order(['rider_pay' => null]);
        $this->order(['delivered_at' => '2026-11-15 15:59:59', 'rider_pay' => '999.00']);
        $this->order(['earning_courier_id' => 101, 'rider_pay' => '888.00']);
        $this->order(['rider_pay' => '5.00'], ledger: false);
        $this->getJson('/api/courier/earnings/summary?period=today')->assertOk()
            ->assertJsonPath('paid', '15.25')->assertJsonPath('accrued_unpaid', '20.10')
            ->assertJsonPath('total_earned', '40.35');
        $rows = collect($this->getJson('/api/courier/earnings/history?period=today')->assertOk()->json('data'))->keyBy('order_id');
        $this->assertSame('paid', $rows[$paid]['payout_status']);
        $this->assertSame('accrued', $rows[$paid + 1]['payout_status']);
        $this->assertNull($rows[$paid + 3]['amount']);
    }

    public function test_missing_payout_schema_preserves_saved_earnings_without_claiming_zero_paid(): void
    {
        Sanctum::actingAs($this->rider);
        $this->order();
        Schema::drop('rider_payout_items');
        $this->getJson('/api/courier/earnings/summary?period=all')->assertOk()
            ->assertJsonPath('total_earned', '15.25')->assertJsonPath('paid', null)->assertJsonPath('accrued_unpaid', null);
        $this->getJson('/api/courier/earnings/history?period=all')->assertOk()->assertJsonPath('data.0.payout_status', null);
    }

    public function test_native_receipts_use_exact_references_and_escape_notes_without_assets_or_scripts(): void
    {
        Sanctum::actingAs($this->rider);
        $order = $this->order();
        $handover = $this->handover(['reference_no' => 'HO-OWN', 'notes' => '<script>alert(1)</script>']);
        DB::table('rider_cash_handover_items')->insert(['handover_id' => $handover, 'order_id' => $order, 'amount' => '100.10']);
        $this->payout($order, ['reference_no' => 'RP-OWN']);
        $cash = $this->get('/api/courier/receipts/cash-handovers/HO-OWN', ['Accept' => 'application/json, text/html'])
            ->assertOk()->assertHeader('Content-Type', 'text/html; charset=utf-8')->assertSee('HO-OWN')
            ->assertSee('₱100.10')->assertSee('SL-MONEY-1')->assertSee('&lt;script&gt;', escape: false);
        $this->assertStringContainsString('no-store', $cash->headers->get('Cache-Control'));
        $this->assertStringNotContainsString('<script>', $cash->getContent());
        $this->assertStringNotContainsString('/build/', $cash->getContent());
        $this->get('/api/courier/receipts/rider-payouts/RP-OWN')->assertOk()->assertSee('₱15.25');
        $this->handover(['rider_id' => 101, 'reference_no' => 'HO-OTHER']);
        $this->getJson('/api/courier/receipts/cash-handovers/HO-OTHER')->assertForbidden();
        $this->getJson('/api/courier/receipts/cash-handovers/'.$handover)->assertNotFound();
        $this->getJson('/api/courier/receipts/seller-payouts/RP-OWN')->assertNotFound();
    }

    private function notification(int $userId, string $kind, array $meta = []): string
    {
        $id = (string) Str::uuid();
        DB::table('notifications')->insert([
            'id' => $id, 'type' => 'App\\Notifications\\ActivityNotification', 'notifiable_type' => User::class,
            'notifiable_id' => $userId, 'data' => json_encode(['kind' => $kind, 'title' => 'Update',
                'body' => 'Recorded update', 'meta' => $meta]), 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    public function test_stored_notifications_use_user_ownership_and_keep_money_receipt_metadata(): void
    {
        Sanctum::actingAs($this->rider);
        $mine = $this->notification(10, 'cash.handover.short', ['reference_no' => 'HO-OWN', 'screen' => 'cash']);
        $other = $this->notification(11, 'rider.payout.paid', ['reference_no' => 'RP-PRIVATE']);
        $this->getJson('/api/courier/notifications')->assertOk()->assertJsonPath('unread', 1)
            ->assertJsonPath('data.0.id', $mine)->assertJsonPath('data.0.meta.reference_no', 'HO-OWN')
            ->assertJsonPath('data.0.read', false);
        $this->postJson('/api/courier/notifications/'.$other.'/read')->assertNotFound();
        $this->postJson('/api/courier/notifications/'.$mine.'/read')->assertOk()->assertJsonPath('unread', 0);
        $this->notification(10, 'rider.payout.paid');
        $this->postJson('/api/courier/notifications/read-all')->assertOk()->assertJsonPath('unread', 0);
        $this->assertNull(DB::table('notifications')->where('id', $other)->value('read_at'));
    }

    public function test_financial_reads_do_not_create_or_reconstruct_any_money_records(): void
    {
        Sanctum::actingAs($this->rider);
        $order = $this->order(ledger: false);
        $this->handover(['reference_no' => 'HO-OWN']);
        $mutations = [];
        DB::listen(function ($event) use (&$mutations) {
            if (preg_match('/^\s*(insert|update|delete|create|alter|drop|replace)\b/i', $event->sql)) {
                $mutations[] = $event->sql;
            }
        });
        foreach (['cash/summary', 'cash/history', 'earnings/summary?period=all', 'earnings/history?period=all', 'receipts/cash-handovers/HO-OWN'] as $path) {
            $this->getJson('/api/courier/'.$path)->assertOk();
        }
        $this->assertSame([], $mutations);
        $this->assertDatabaseCount('ledger_transactions', 0);
        $this->assertSame($order, DB::table('orders')->value('id'));
    }
}
