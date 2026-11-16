<?php

namespace Tests\Feature;

use App\Models\Message;
use App\Models\Order;
use App\Models\OrderEvent;
use App\Services\RiderRealtime;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Exceptions;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class RiderRealtimeTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['services.supabase.url' => 'https://realtime.example.test',
            'services.supabase.service_key' => 'test-service-key']);
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'database.connections.sqlite.url' => null]);
        DB::purge('sqlite');
        Schema::create('orders', function (Blueprint $table) {
            $table->id();
            foreach (['pickup_rider_id', 'delivery_rider_id', 'earning_courier_id'] as $column) {
                $table->integer($column)->nullable();
            }
            $table->decimal('rider_pay', 12, 2)->nullable();
            $table->string('status')->nullable();
            $table->timestamps();
        });
        Schema::create('order_events', function (Blueprint $table) {
            $table->id();
            $table->integer('order_id');
            $table->string('title');
            $table->timestamps();
        });
        Schema::create('messages', function (Blueprint $table) {
            $table->id();
            $table->integer('conversation_id');
            $table->integer('sender_id');
            $table->text('body');
            $table->timestamps();
        });
        Schema::create('conversation_participants', function (Blueprint $table) {
            $table->integer('conversation_id');
            $table->integer('user_id');
        });
        Schema::create('courier_profiles', function (Blueprint $table) {
            $table->id();
            $table->integer('user_id');
        });
    }

    private function topics(): array
    {
        return Http::recorded()->map(fn ($pair) => $pair[0]['messages'][0]['topic'])->all();
    }

    public function test_transport_sends_only_a_refresh_and_deduplicates_profile_ids(): void
    {
        Http::fake(['*' => Http::response([], 202)]);
        RiderRealtime::notifyMany([10, null, 10, 0, 20]);
        $this->assertSame(['rider:10', 'rider:20'], $this->topics());
        Http::assertSent(fn ($request) => $request->url() === 'https://realtime.example.test/realtime/v1/api/broadcast'
            && $request->hasHeader('apikey', 'test-service-key')
            && $request['messages'][0]['event'] === 'refresh'
            && $request['messages'][0]['private'] === false
            && array_keys($request['messages'][0]['payload']) === ['at']);
    }

    public function test_reassignment_captures_both_original_and_current_riders_before_commit(): void
    {
        Http::fake(['*' => Http::response([], 202)]);
        $id = DB::table('orders')->insertGetId(['pickup_rider_id' => 10, 'delivery_rider_id' => 20,
            'earning_courier_id' => 30]);
        DB::beginTransaction();
        $order = Order::findOrFail($id);
        $order->update(['pickup_rider_id' => 40, 'delivery_rider_id' => 50, 'earning_courier_id' => 60]);
        // save() has already synced originals here; the callback must retain the old ids.
        Http::assertNothingSent();
        DB::commit();
        $this->assertEqualsCanonicalizing(['rider:10', 'rider:20', 'rider:30',
            'rider:40', 'rider:50', 'rider:60'], $this->topics());
    }

    public function test_rollback_discards_refreshes_including_nested_transactions(): void
    {
        Http::fake(['*' => Http::response([], 202)]);
        DB::beginTransaction();
        DB::transaction(fn () => Order::create(['pickup_rider_id' => 10]));
        Http::assertNothingSent();
        DB::rollBack();
        Http::assertNothingSent();
    }

    public function test_order_creation_money_changes_and_deletion_refresh_the_owning_rider(): void
    {
        Http::fake(['*' => Http::response([], 202)]);
        $order = Order::create(['earning_courier_id' => 30]);
        $order->update(['rider_pay' => '25.00']);
        $order->delete();
        $this->assertSame(['rider:30', 'rider:30', 'rider:30'], $this->topics());
    }

    public function test_messages_map_participant_user_ids_and_notify_old_and_new_conversations(): void
    {
        Http::fake(['*' => Http::response([], 202)]);
        DB::table('courier_profiles')->insert([['id' => 10, 'user_id' => 100], ['id' => 20, 'user_id' => 200]]);
        DB::table('conversation_participants')->insert([
            ['conversation_id' => 1, 'user_id' => 100], ['conversation_id' => 1, 'user_id' => 999],
            ['conversation_id' => 2, 'user_id' => 200],
        ]);
        DB::beginTransaction();
        $message = Message::create(['conversation_id' => 1, 'sender_id' => 999, 'body' => 'Hello']);
        $message->update(['conversation_id' => 2]);
        $message->delete();
        Http::assertNothingSent();
        DB::commit();
        $this->assertSame(['rider:10', 'rider:10', 'rider:20', 'rider:20'], $this->topics());
    }

    public function test_notification_events_resolve_both_old_and_new_order_owners(): void
    {
        Http::fake(['*' => Http::response([], 202)]);
        DB::table('orders')->insert([['id' => 1, 'pickup_rider_id' => 10], ['id' => 2, 'pickup_rider_id' => 20]]);
        $id = DB::table('order_events')->insertGetId(['order_id' => 1, 'title' => 'Assigned']);
        DB::beginTransaction();
        OrderEvent::findOrFail($id)->update(['order_id' => 2]);
        Http::assertNothingSent();
        DB::commit();
        $this->assertSame(['rider:10', 'rider:20'], $this->topics());
    }

    public function test_missing_config_logs_a_warning_without_a_request(): void
    {
        config(['services.supabase.service_key' => null]);
        Log::spy();
        RiderRealtime::notify(10);
        Log::shouldHaveReceived('warning')->once()->with('RiderRealtime: Supabase URL or service key is missing.');
        Http::assertNothingSent();
    }

    public function test_http_errors_and_network_failures_are_reported_without_breaking_model_saves(): void
    {
        Exceptions::fake();
        $responses = Http::sequence()->push([], 401)->push([], 403)->push([], 500);
        Http::fake(fn () => $responses->isEmpty()
            ? throw new ConnectionException('Synthetic offline failure')
            : $responses());
        foreach ([401, 403, 500] as $status) {
            Order::create(['pickup_rider_id' => 10]);
        }
        Order::create(['pickup_rider_id' => 10]);
        $this->assertDatabaseCount('orders', 4);
        Exceptions::assertReportedCount(4);
    }

    public function test_diagnostic_command_reports_status_without_credentials_or_response_bodies(): void
    {
        $sequence = Http::sequence();
        foreach ([200, 202, 401, 403, 500] as $status) {
            $sequence->push(['private' => 'test-service-key'], $status);
        }
        Http::fake(['*' => $sequence]);
        foreach ([200, 202, 401, 403, 500] as $status) {
            $command = $this->artisan('rider:realtime-test', ['courierProfileId' => 10]);
            $command->doesntExpectOutputToContain('test-service-key');
            $command->expectsOutputToContain('HTTP '.$status);
            $command->assertExitCode($status < 400 ? 0 : 1);
        }
    }

    public function test_diagnostic_command_rejects_invalid_ids_and_missing_config(): void
    {
        $this->artisan('rider:realtime-test', ['courierProfileId' => 0])->assertFailed();
        config(['services.supabase.url' => null]);
        $this->artisan('rider:realtime-test', ['courierProfileId' => 10])
            ->expectsOutputToContain('Missing SUPABASE_URL')->assertFailed();
        Http::assertNothingSent();
    }
}
