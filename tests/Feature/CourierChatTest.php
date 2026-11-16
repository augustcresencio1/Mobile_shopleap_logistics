<?php

namespace Tests\Feature;

use App\Models\CourierProfile;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CourierChatTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'database.connections.sqlite.url' => null]);
        DB::purge('sqlite');
        Carbon::setTestNow(Carbon::parse('2026-11-15T01:50:00Z'));
        $this->createSchema();
        foreach ([1 => 'courier', 2 => 'seller', 3 => 'buyer', 4 => 'logistics'] as $id => $role) {
            User::forceCreate(['id' => $id, 'name' => 'Person '.$id, 'email' => $id.'@example.test',
                'password' => 'password', 'role' => $role, 'account_status' => 'active']);
        }
        DB::table('logistics_profiles')->insert(['id' => 20, 'user_id' => 4, 'status' => 'approved']);
        CourierProfile::create(['id' => 10, 'user_id' => 1, 'logistics_profile_id' => 20,
            'status' => 'approved', 'is_active' => true]);
        DB::table('orders')->insert(['id' => 100, 'seller_id' => 2, 'buyer_id' => 3,
            'buyer_name' => 'Customer', 'pickup_rider_id' => 10, 'logistics_profile_id' => 20,
            'status' => 'READY_FOR_PICKUP']);
        $this->conversation(1, 100, 2);
        $this->conversation(2, 100, 3);
        $this->conversation(3, null, 4);
        Sanctum::actingAs(User::findOrFail(1));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_chat_writes_refresh_the_profile_channel_only_after_commit(): void
    {
        config(['services.supabase.url' => 'https://realtime.example.test',
            'services.supabase.service_key' => 'test-service-key']);
        Http::fake(['*' => Http::response([], 202)]);
        $this->message(1, 2, '2026-11-15 01:00:00');
        DB::beginTransaction();
        $this->postJson('/api/courier/orders/100/messages', ['with' => 'seller', 'body' => 'On my way'])->assertCreated();
        Http::assertNothingSent();
        DB::commit();
        Http::assertSentCount(2); // Read marker and newly sent message.
        $this->assertTrue(Http::recorded()->every(fn ($pair) => $pair[0]['messages'][0]['topic'] === 'rider:10'));
    }

    private function createSchema(): void
    {
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
            foreach (['seller_id', 'buyer_id', 'pickup_rider_id', 'delivery_rider_id', 'logistics_profile_id'] as $field) {
                $t->integer($field)->nullable();
            }
            $t->string('buyer_name')->nullable();
            $t->string('status');
        });
        Schema::create('conversations', function (Blueprint $t) {
            $t->id();
            $t->integer('order_id')->nullable();
            $t->integer('created_by');
            $t->string('subject')->nullable();
            $t->string('status');
            $t->timestamp('last_message_at')->nullable();
            $t->timestamps();
        });
        Schema::create('conversation_participants', function (Blueprint $t) {
            $t->integer('conversation_id');
            $t->integer('user_id');
            $t->timestamp('last_read_at')->nullable();
            $t->timestamps();
        });
        Schema::create('messages', function (Blueprint $t) {
            $t->id();
            $t->integer('conversation_id');
            $t->integer('sender_id');
            $t->text('body');
            $t->timestamps();
        });
    }

    private function conversation(int $id, ?int $orderId, int $otherId): void
    {
        DB::table('conversations')->insert(['id' => $id, 'order_id' => $orderId,
            'created_by' => 1, 'status' => 'open']);
        foreach ([1, $otherId] as $userId) {
            DB::table('conversation_participants')->insert(['conversation_id' => $id, 'user_id' => $userId]);
        }
    }

    private function message(int $conversation, int $sender, string $at): int
    {
        return DB::table('messages')->insertGetId(['conversation_id' => $conversation,
            'sender_id' => $sender, 'body' => 'Hello', 'created_at' => $at, 'updated_at' => $at]);
    }

    private function thread(string $party): array
    {
        return collect($this->getJson('/api/courier/chats')->assertOk()->json('data'))->firstWhere('with', $party);
    }

    public function test_seen_messages_clear_even_when_the_other_app_clock_is_ahead_and_new_replies_are_unread(): void
    {
        $this->message(1, 2, '2026-11-15 09:40:00');
        $latest = $this->message(1, 2, '2026-11-15 09:41:00');
        $this->assertSame(2, $this->thread('seller')['unread']);
        $this->getJson('/api/courier/orders/100/messages?with=seller')->assertOk()->assertJsonCount(2, 'data');
        $this->assertDatabaseHas('conversation_participants', ['conversation_id' => 1,
            'user_id' => 1, 'last_read_at' => '2026-11-15 09:41:00']);
        $this->assertSame(0, $this->thread('seller')['unread']);
        $this->assertSame($latest, $this->thread('seller')['last_message_id']);

        $this->message(1, 2, '2026-11-15 09:42:00');
        $this->assertSame(1, $this->thread('seller')['unread']);
        $this->assertFalse($this->thread('seller')['last_is_mine']);
        $this->getJson('/api/courier/orders/100/messages?with=seller')->assertOk();
        $this->assertSame(0, $this->thread('seller')['unread']);
    }

    public function test_successful_reply_marks_existing_messages_read_and_returns_a_confirmed_sent_message(): void
    {
        $this->message(1, 2, '2026-11-15 09:40:00');
        $this->message(1, 2, '2026-11-15 09:41:00');
        $sent = $this->postJson('/api/courier/orders/100/messages', ['with' => 'seller', 'body' => 'Reply'])
            ->assertCreated()->assertJsonPath('data.body', 'Reply')->assertJsonPath('data.mine', true)
            ->assertJsonPath('data.conversation_id', 1)->json('id');
        $thread = $this->thread('seller');
        $this->assertSame(0, $thread['unread']);
        $this->assertTrue($thread['last_is_mine']);
        $this->assertSame($sent, $thread['last_message_id']);
        $this->assertDatabaseHas('conversation_participants', ['conversation_id' => 1,
            'user_id' => 2, 'last_read_at' => null]);
    }

    public function test_reading_one_chat_preserves_other_chats_and_read_markers_never_move_backwards(): void
    {
        $this->message(1, 2, '2026-11-15 01:40:00');
        $this->message(2, 3, '2026-11-15 01:41:00');
        DB::table('conversation_participants')->where('conversation_id', 1)->where('user_id', 1)
            ->update(['last_read_at' => '2026-11-15 01:45:00']);
        $this->getJson('/api/courier/orders/100/messages?with=seller')->assertOk();
        $this->assertSame(0, $this->thread('seller')['unread']);
        $this->assertSame(1, $this->thread('buyer')['unread']);
        $this->assertDatabaseHas('conversation_participants', ['conversation_id' => 1,
            'user_id' => 1, 'last_read_at' => '2026-11-15 01:45:00']);
    }

    public function test_failed_send_and_unauthorized_reads_never_acknowledge_messages(): void
    {
        $this->message(1, 2, '2026-11-15 01:40:00');
        $this->postJson('/api/courier/orders/100/messages', ['with' => 'seller', 'body' => ''])
            ->assertUnprocessable();
        DB::table('orders')->where('id', 100)->update(['pickup_rider_id' => 99]);
        $this->getJson('/api/courier/orders/100/messages?with=seller')->assertNotFound();
        $this->postJson('/api/courier/orders/100/messages', ['with' => 'seller', 'body' => 'Reply'])
            ->assertNotFound();
        $this->assertDatabaseHas('conversation_participants', ['conversation_id' => 1,
            'user_id' => 1, 'last_read_at' => null]);
        $this->assertSame(1, DB::table('messages')->count());
    }

    public function test_hub_unread_is_counted_once_and_clears_for_all_orders_sharing_the_chat(): void
    {
        DB::table('orders')->insert(['id' => 101, 'seller_id' => 2, 'buyer_id' => 3,
            'pickup_rider_id' => 10, 'logistics_profile_id' => 20, 'status' => 'READY_FOR_PICKUP']);
        $this->message(3, 4, '2026-11-15 01:40:00');
        $threads = $this->getJson('/api/courier/chats')->assertOk()->json('data');
        $this->assertCount(1, collect($threads)->where('with', 'logistics'));
        $this->assertSame(1, $this->thread('logistics')['unread']);
        $this->getJson('/api/courier/orders/100/messages?with=logistics')->assertOk();
        $this->assertSame(0, $this->thread('logistics')['unread']);
    }
}
