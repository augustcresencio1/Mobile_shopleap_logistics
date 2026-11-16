<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use LogicException;
use RuntimeException;

/** Delivery posting and seller routing from the main web OrderLedger/SellerSettlements flow. */
class CourierDeliveryLedgerService
{
    public function __construct(private LedgerService $ledger) {}

    /** Called only inside the transaction that moves an order to DELIVERED. */
    public function recordNewDelivery(object $order): int
    {
        if (DB::transactionLevel() === 0) {
            throw new LogicException('Delivery and ledger posting must share a transaction.');
        }
        foreach (['wallet_accounts', 'ledger_transactions', 'ledger_entries'] as $table) {
            if (! Schema::hasTable($table)) {
                throw new RuntimeException('The shared financial schema is not ready.');
            }
        }
        if ($order->status !== 'DELIVERED' || ! $order->delivered_at || ! $order->earnings_recorded_at
            || ! $order->earning_hub_id || ! $order->earning_courier_id || ! $order->seller_id) {
            throw new RuntimeException('A complete frozen delivery snapshot is required.');
        }
        foreach (['total_amount', 'commission_amount', 'delivered_shipping_fee', 'cod_collected_amount'] as $field) {
            if (! isset($order->$field)) {
                throw new RuntimeException('A recorded order amount is missing.');
            }
        }
        $items = LedgerService::cents((string) $order->total_amount);
        $commission = LedgerService::cents((string) $order->commission_amount);
        $shipping = LedgerService::cents((string) $order->delivered_shipping_fee);
        $cash = LedgerService::cents((string) $order->cod_collected_amount);
        if ($items < 0 || $commission < 0 || $commission > $items || $shipping < 0 || $cash < 0) {
            throw new RuntimeException('The recorded order amounts are inconsistent.');
        }
        $lines = [
            $this->line('rider', $order->earning_courier_id, 'cash_on_hand', 'debit', $cash),
            $this->line('rider', $order->earning_courier_id, 'cash_due_hub', 'credit', $cash),
            $this->line('hub', $order->earning_hub_id, 'cash_receivable', 'debit', $cash),
            $this->line('hub', $order->earning_hub_id, 'cod_to_remit', 'credit', $items),
            $this->line('hub', $order->earning_hub_id, 'shipping_earned', 'credit', $shipping),
            $this->line('platform', 0, 'cod_receivable', 'debit', $items),
            $this->line('seller', $order->seller_id, 'pending', 'credit', $items - $commission),
            $this->line('platform', 0, 'commission_pending', 'credit', $commission),
        ];
        $variance = $items + $shipping - $cash;
        if ($variance !== 0) {
            $lines[] = $this->line('hub', $order->earning_hub_id, 'collection_variance', $variance > 0 ? 'debit' : 'credit', abs($variance));
        }
        if ($order->rider_pay !== null) {
            $pay = LedgerService::cents((string) $order->rider_pay);
            $lines[] = $this->line('hub', $order->earning_hub_id, 'rider_expense', 'debit', $pay);
            $lines[] = $this->line('hub', $order->earning_hub_id, 'rider_pay_owed', 'credit', $pay);
            $lines[] = $this->line('rider', $order->earning_courier_id, 'earnings_accrued', 'debit', $pay);
            $lines[] = $this->line('rider', $order->earning_courier_id, 'earnings_income', 'credit', $pay);
        }

        return DB::transaction(function () use ($order, $lines, $items, $commission): int {
            $existing = DB::table('ledger_transactions')->where('idempotency_key', 'order:'.$order->id.':delivered')->exists();
            $id = $this->ledger->post('order:'.$order->id.':delivered', 'delivery', $order->id,
                'COD collected - Order '.$order->order_number, $lines);
            if (! $existing && config('money.logistics_seller_settlements', true)) {
                $this->routeSellerFunds($order, $items - $commission);
            }

            return $id;
        });
    }

    private function routeSellerFunds(object $order, int $net): void
    {
        if ($net <= 0 || DB::table('ledger_transactions')->where('idempotency_key', 'order:'.$order->id.':logistics-routing')->exists()) {
            return;
        }
        if (! Schema::hasTable('seller_settlement_orders')) {
            throw new RuntimeException('The shared seller-payment routing schema is not ready.');
        }
        DB::table('seller_settlement_orders')->insert([
            'order_id' => $order->id, 'hub_id' => $order->earning_hub_id, 'seller_id' => $order->seller_id,
            'seller_amount' => LedgerService::decimal($net), 'commission_amount' => $order->commission_amount,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $this->ledger->post('order:'.$order->id.':logistics-routing', 'logistics_routing', $order->id,
            'Seller funds held by logistics - '.$order->order_number, [
                $this->line('platform', 0, 'cod_receivable', 'credit', $net),
                $this->line('seller', $order->seller_id, 'hub_receivable', 'debit', $net),
                $this->line('hub', $order->earning_hub_id, 'cod_to_remit', 'debit', $net),
                $this->line('hub', $order->earning_hub_id, 'seller_payable', 'credit', $net),
            ]);
    }

    private function line(string $ownerType, int $ownerId, string $accountType, string $direction, int $cents): array
    {
        return ['owner_type' => $ownerType, 'owner_id' => $ownerId, 'account_type' => $accountType,
            'direction' => $direction, 'cents' => $cents];
    }
}
