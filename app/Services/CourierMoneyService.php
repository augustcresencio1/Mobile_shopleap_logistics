<?php

namespace App\Services;

use App\Models\CourierProfile;
use App\Support\LedgerMoney;
use Carbon\CarbonImmutable;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/** Rider-only adapter of the main web app's MoneyMovementQueries/PayoutQueries. */
class CourierMoneyService
{
    private function hasTables(array $tables): bool
    {
        $request = request();
        $available = $request->attributes->get('courier_money_tables', []);
        foreach ($tables as $table) {
            if (! array_key_exists($table, $available)) {
                $available[$table] = Schema::hasTable($table);
            }
            $request->attributes->set('courier_money_tables', $available);
            if (! $available[$table]) {
                return false;
            }
        }

        return true;
    }

    public function payoutsAvailable(): bool
    {
        return $this->hasTables(['ledger_transactions', 'rider_payouts', 'rider_payout_items']);
    }

    private function assertCashAvailable(): void
    {
        abort_unless($this->hasTables(['ledger_transactions', 'rider_cash_handovers', 'rider_cash_handover_items']),
            503, 'Cash records are not available on this server yet. Please contact your hub.');
    }

    /** Frozen ownership and an unreversed delivery posting determine eligibility. */
    private function deliveries(int $riderId): Builder
    {
        return DB::table('orders as o')->whereNotNull('o.earnings_recorded_at')->whereNotNull('o.delivered_at')
            ->where('o.earning_courier_id', $riderId)
            ->whereExists(fn (Builder $query) => $query->selectRaw('1')->from('ledger_transactions as t')
                ->whereColumn('t.order_id', 'o.id')->where('t.type', 'delivery')
                ->whereNotExists(fn (Builder $reversal) => $reversal->selectRaw('1')->from('ledger_transactions as reversal')
                    ->whereColumn('reversal.reversal_of', 't.id')));
    }

    public function cashSummary(int $riderId): array
    {
        $this->assertCashAvailable();
        $allocated = DB::table('rider_cash_handover_items')->select('order_id')->selectRaw('SUM(amount) as amount')->groupBy('order_id');
        $orders = $this->deliveries($riderId)->leftJoinSub($allocated, 'allocated', 'allocated.order_id', '=', 'o.id')
            ->select('o.order_number', 'o.delivered_at')
            ->selectRaw('ROUND(o.cod_collected_amount - COALESCE(allocated.amount, 0), 2) as amount')
            ->whereRaw('ROUND(o.cod_collected_amount - COALESCE(allocated.amount, 0), 2) > 0')
            ->orderBy('o.delivered_at')->orderBy('o.id')->get();
        $shortage = DB::table('rider_cash_handovers')->where('rider_id', $riderId)->where('status', 'short')
            ->selectRaw('ROUND(COALESCE(SUM(short_amount - settled_amount), 0), 2) as amount')->value('amount');

        return [
            'cash_on_hand' => LedgerMoney::decimal($orders->sum(fn (object $order): int => LedgerMoney::cents((string) $order->amount))),
            'shortage_amount' => LedgerMoney::decimal(LedgerMoney::cents((string) $shortage)),
            'currency' => 'PHP',
            'orders' => $orders->map(fn (object $order): array => [
                'order_number' => $order->order_number,
                'amount' => LedgerMoney::decimal(LedgerMoney::cents((string) $order->amount)),
                'delivered_at' => $this->timestamp($order->delivered_at),
            ]),
        ];
    }

    public function cashHistory(int $riderId): array
    {
        $this->assertCashAvailable();
        $page = DB::table('rider_cash_handovers')->where('rider_id', $riderId)
            ->orderByDesc('confirmed_at')->orderByDesc('id')->paginate(20);

        return [
            'currency' => 'PHP',
            'data' => $page->getCollection()->map(fn (object $handover): array => [
                'reference_no' => $handover->reference_no,
                'amount' => LedgerMoney::decimal(LedgerMoney::cents((string) $handover->amount_received) + LedgerMoney::cents((string) $handover->settled_amount)),
                'currency' => 'PHP', 'status' => $handover->status,
                'confirmed_at' => $this->timestamp($handover->confirmed_at),
            ]),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
        ];
    }

    private function paidOrders(int $riderId): Builder
    {
        return $this->deliveries($riderId)->join('rider_payout_items as i', 'i.order_id', '=', 'o.id')
            ->join('rider_payouts as p', 'p.id', '=', 'i.rider_payout_id')
            ->where('p.rider_id', $riderId)->where('p.status', 'paid');
    }

    /** Delivery-date filters apply to both balances, irrespective of payout date. */
    public function earningsTotals(int $riderId, array $range): array
    {
        if (! $this->payoutsAvailable()) {
            return ['accrued_unpaid' => null, 'paid' => null];
        }
        $unpaid = $this->deliveries($riderId)->whereNotNull('o.rider_pay')->where('o.rider_pay', '>', 0)
            ->whereNotExists(fn (Builder $query) => $query->selectRaw('1')->from('rider_payout_items as i')->whereColumn('i.order_id', 'o.id'));
        $totals = [];
        foreach (['accrued_unpaid' => $unpaid, 'paid' => $this->paidOrders($riderId)] as $key => $query) {
            $column = $key === 'paid' ? 'i.amount' : 'o.rider_pay';
            $amount = $query->when($range['start'], fn (Builder $query, $start) => $query->where('o.delivered_at', '>=', $start))
                ->where('o.delivered_at', '<', $range['end'])->selectRaw('ROUND(COALESCE(SUM('.$column.'), 0), 2) as total')->value('total');
            $totals[$key] = LedgerMoney::decimal(LedgerMoney::cents((string) $amount));
        }

        return $totals;
    }

    public function paidOrderIds(int $riderId, array $orderIds): ?Collection
    {
        return $this->payoutsAvailable()
            ? $this->paidOrders($riderId)->whereIn('o.id', $orderIds)->pluck('o.id')->flip()
            : null;
    }

    public function receipt(CourierProfile $courier, string $type, string $reference): array
    {
        [$table, $itemsTable, $foreignKey, $title, $dateColumn] = match ($type) {
            'cash-handovers' => ['rider_cash_handovers', 'rider_cash_handover_items', 'handover_id', 'Rider Cash Handover Receipt', 'confirmed_at'],
            'rider-payouts' => ['rider_payouts', 'rider_payout_items', 'rider_payout_id', 'Rider Payout Receipt', 'paid_at'],
            default => abort(404),
        };
        abort_unless($this->hasTables([$table, $itemsTable]), 503, 'Receipt records are not available on this server yet.');
        $record = DB::table($table)->where('reference_no', $reference)->firstOrFail();
        abort_unless((int) $record->rider_id === (int) $courier->id, 403, 'This receipt belongs to another rider.');
        $hubName = DB::table('logistics_profiles')->where('id', $record->hub_id)->value('business_name');
        $riderName = trim($courier->first_name.' '.$courier->last_name);
        $isCash = $type === 'cash-handovers';
        $amount = $isCash
            ? LedgerMoney::decimal(LedgerMoney::cents((string) $record->amount_received) + LedgerMoney::cents((string) $record->settled_amount))
            : LedgerMoney::decimal(LedgerMoney::cents((string) $record->amount));
        $details = $isCash ? [
            'Expected cash' => LedgerMoney::peso((string) $record->amount_expected),
            'Received at confirmation' => LedgerMoney::peso((string) $record->amount_received),
            'Additional cash received' => LedgerMoney::peso((string) $record->settled_amount),
            'Outstanding shortage' => LedgerMoney::peso(LedgerMoney::decimal(LedgerMoney::cents((string) $record->short_amount) - LedgerMoney::cents((string) $record->settled_amount))),
        ] : [];
        foreach (['notes' => 'Notes', 'settlement_note' => 'Settlement note', 'transfer_reference' => 'External transfer reference'] as $field => $label) {
            if (! empty($record->$field)) {
                $details[$label] = $record->$field;
            }
        }
        $items = DB::table($itemsTable.' as i')->join('orders as o', 'o.id', '=', 'i.order_id')
            ->where('i.'.$foreignKey, $record->id)->orderBy('o.order_number')->select('o.order_number', 'i.amount')->get();
        $timeline = [];
        foreach (['confirmed_at' => 'Confirmed', 'settled_at' => 'Settled', 'paid_at' => 'Paid'] as $field => $label) {
            if (! empty($record->$field)) {
                $timeline[$label] = $this->timestamp($record->$field);
            }
        }

        return ['title' => $title, 'reference' => $record->reference_no, 'status' => $record->status,
            'from' => $isCash ? $riderName : $hubName, 'to' => $isCash ? $hubName : $riderName,
            'amount' => $amount, 'date' => $this->timestamp($record->$dateColumn),
            'details' => $details, 'items' => $items, 'timeline' => $timeline];
    }

    private function timestamp(string $value): string
    {
        return CarbonImmutable::parse($value, 'UTC')->setTimezone('Asia/Manila')->toIso8601String();
    }
}
