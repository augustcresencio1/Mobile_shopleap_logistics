<?php

namespace Tests\Fixtures;

use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/** The shared financial tables needed by the rider, only in isolated SQLite tests. */
class CourierLedgerSchema
{
    public static function create(): void
    {
        Schema::create('wallet_accounts', function (Blueprint $table) {
            $table->id();
            $table->string('owner_type');
            $table->unsignedBigInteger('owner_id');
            $table->string('account_type');
            $table->string('currency')->default('PHP');
            $table->unique(['owner_type', 'owner_id', 'account_type']);
        });
        Schema::create('ledger_transactions', function (Blueprint $table) {
            $table->id();
            $table->string('reference_no')->unique();
            $table->string('type');
            $table->unsignedBigInteger('order_id')->nullable();
            $table->string('description');
            $table->string('status')->default('posted');
            $table->string('idempotency_key')->unique();
            $table->char('payload_hash', 64);
            $table->timestamp('posted_at');
            $table->unsignedBigInteger('reversal_of')->nullable()->unique();
        });
        Schema::create('ledger_entries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('transaction_id')->constrained('ledger_transactions');
            $table->foreignId('account_id')->constrained('wallet_accounts');
            $table->string('direction');
            $table->decimal('amount', 12, 2);
        });
        foreach (['ledger_entries', 'ledger_transactions'] as $table) {
            foreach (['UPDATE', 'DELETE'] as $operation) {
                DB::unprepared("CREATE TRIGGER {$table}_".strtolower($operation)."_immutable BEFORE {$operation} ON {$table} BEGIN SELECT RAISE(ABORT, 'Ledger records are immutable; post a reversal'); END");
            }
        }
        Schema::create('seller_settlement_orders', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('order_id')->unique();
            $table->unsignedBigInteger('hub_id');
            $table->unsignedBigInteger('seller_id');
            $table->decimal('seller_amount', 12, 2);
            $table->decimal('commission_amount', 12, 2);
            $table->timestamps();
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
            $table->string('status')->default('paid');
            $table->timestamp('paid_at');
        });
        Schema::create('rider_payout_items', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('rider_payout_id');
            $table->unsignedBigInteger('order_id')->unique();
            $table->decimal('amount', 12, 2);
        });
    }
}
