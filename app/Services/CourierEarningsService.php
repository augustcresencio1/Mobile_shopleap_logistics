<?php

namespace App\Services;

use App\Models\CourierProfile;
use Carbon\Carbon;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class CourierEarningsService
{
    public const TIMEZONE = 'Asia/Manila';

    public function money(mixed $amount): ?string
    {
        if ($amount === null) {
            return null;
        }

        $parts = explode('.', (string) $amount, 2);

        return $parts[0].'.'.str_pad(substr($parts[1] ?? '', 0, 2), 2, '0');
    }

    public function timestamp(?string $value): ?string
    {
        return $value === null ? null : Carbon::parse($value, 'UTC')
            ->setTimezone(self::TIMEZONE)->toIso8601String();
    }

    public function currentRate(int $hubId, ?Carbon $at = null): ?object
    {
        return DB::table('rider_rates')
            ->where('logistics_profile_id', $hubId)
            ->where('effective_from', '<=', ($at ?? Carbon::now('UTC'))->copy()->utc())
            ->orderByDesc('effective_from')->orderByDesc('id')->first();
    }

    public function ratePayload(CourierProfile $courier): array
    {
        $rate = $this->currentRate($courier->logistics_profile_id);

        return [
            'amount' => $this->money($rate?->amount),
            'currency' => 'PHP',
            'effective_from' => $this->timestamp($rate?->effective_from),
        ];
    }

    public function range(array $filters): array
    {
        $isPreset = array_key_exists('preset', $filters);
        $period = $isPreset ? $filters['preset'] : ($filters['period'] ?? 'month');
        $data = Validator::make([
            'period' => $period,
            'from' => $filters['from'] ?? null,
            'to' => $filters['to'] ?? null,
        ], [
            'period' => ['required', Rule::in($isPreset
                ? ['today', '7d', '30d', 'custom']
                : ['today', 'week', 'month', 'all', '7d', '30d', 'custom'])],
            'from' => ['required_if:period,custom', 'nullable', 'date_format:Y-m-d'],
            'to' => ['required_if:period,custom', 'nullable', 'date_format:Y-m-d'],
        ])->validate();

        $today = Carbon::now(self::TIMEZONE)->startOfDay();
        $start = match ($period) {
            'today' => $today->copy(),
            '7d' => $today->copy()->subDays(6),
            '30d' => $today->copy()->subDays(29),
            'week' => $today->copy()->startOfWeek(Carbon::MONDAY),
            'month' => $today->copy()->startOfMonth(),
            'custom' => Carbon::parse($data['from'], self::TIMEZONE)->startOfDay(),
            default => null,
        };
        $end = $period === 'custom'
            ? Carbon::parse($data['to'], self::TIMEZONE)->startOfDay() : $today;

        if ($period === 'custom' && ($end->lt($start) || $start->diffInDays($end) > 365)) {
            throw ValidationException::withMessages([
                'to' => 'Choose a range of 1 to 366 calendar days, ending on or after the start date.',
            ]);
        }

        return [
            'period' => $period,
            'from' => $start?->toDateString(),
            'to' => $end->toDateString(),
            'start' => $start?->copy()->utc(),
            'end' => $end->copy()->addDay()->utc(),
        ];
    }

    private function deliveredAt(): string
    {
        return 'coalesce(o.delivered_at, d.delivered_at, o.updated_at)';
    }

    private function deliveries(CourierProfile $courier, array $range): Builder
    {
        $events = DB::table('order_events')->selectRaw('order_id, max(created_at) as delivered_at')
            ->whereIn('status', ['DELIVERED', 'COMPLETED'])->groupBy('order_id');
        $finished = $this->deliveredAt();

        return DB::table('orders as o')->leftJoinSub($events, 'd', 'd.order_id', '=', 'o.id')
            ->whereIn('o.status', ['DELIVERED', 'COMPLETED'])
            ->where(function (Builder $query) use ($courier) {
                $query->where('o.earning_courier_id', $courier->id)
                    ->orWhere(fn (Builder $legacy) => $legacy->whereNull('o.earning_courier_id')
                        ->where('o.delivery_rider_id', $courier->id));
            })
            ->when($range['start'], fn (Builder $query, $start) => $query->whereRaw("$finished >= ?", [$start]))
            ->whereRaw("$finished < ?", [$range['end']]);
    }

    public function summary(CourierProfile $courier, array $range, ?array $rate = null, bool $includePayouts = true): array
    {
        $finished = $this->deliveredAt();
        $day = DB::getDriverName() === 'sqlite'
            ? "date($finished, '+8 hours')"
            : "(($finished AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Manila')::date";
        $rows = $this->deliveries($courier, $range)
            ->selectRaw("$day as day, count(*) as deliveries, count(o.rider_pay) as recorded_earnings, "
                .'coalesce(sum(o.rider_pay), 0) as earned, coalesce(sum(o.cod_collected_amount), 0) as cod')
            ->groupByRaw($day)->orderByRaw("$day desc")->get();

        $earnedCents = 0;
        $codCents = 0;
        $daily = [];
        foreach ($rows as $row) {
            $earned = $this->money($row->earned);
            $cod = $this->money($row->cod);
            $earnedCents += (int) str_replace('.', '', $earned);
            $codCents += (int) str_replace('.', '', $cod);
            $daily[] = [
                'date' => (string) $row->day,
                'deliveries' => (int) $row->deliveries,
                'earned' => $earned,
                'cod_collected' => $cod,
                'currency' => 'PHP',
            ];
        }

        return [
            'period' => $range['period'],
            'from' => $range['from'],
            'to' => $range['to'],
            'currency' => 'PHP',
            'fee_per_delivery' => ($rate ?? $this->ratePayload($courier))['amount'],
            'deliveries' => (int) $rows->sum('deliveries'),
            'total_earned' => $this->fromCents($earnedCents),
            'recorded_earnings' => (int) $rows->sum('recorded_earnings'),
            'cod_collected' => $this->fromCents($codCents),
            'daily' => $daily,
            ...($includePayouts ? app(CourierMoneyService::class)->earningsTotals($courier->id, $range) : []),
        ];
    }

    private function fromCents(int $cents): string
    {
        return intdiv($cents, 100).'.'.str_pad((string) ($cents % 100), 2, '0', STR_PAD_LEFT);
    }

    public function history(CourierProfile $courier, array $range): array
    {
        $finished = $this->deliveredAt();
        $page = $this->deliveries($courier, $range)
            ->leftJoin('order_delivery_proofs as proof', 'proof.order_id', '=', 'o.id')
            ->select('o.id', 'o.order_number', 'o.waybill_code', 'o.rider_pay', 'o.earnings_recorded_at')
            ->addSelect('proof.id as delivery_proof_id', 'proof.captured_at as proof_captured_at')
            ->selectRaw("$finished as finished_at")
            ->orderByRaw("$finished desc")->orderByDesc('o.id')->paginate(20);
        $paid = app(CourierMoneyService::class)->paidOrderIds($courier->id, $page->getCollection()->pluck('id')->all());

        return [
            'data' => $page->getCollection()->map(fn ($order) => [
                'order_id' => $order->id,
                'order_number' => trim((string) $order->order_number) !== '' ? $order->order_number : (string) $order->id,
                'waybill_code' => $order->waybill_code,
                'amount' => $this->money($order->rider_pay),
                'currency' => 'PHP',
                'recorded_at' => $this->timestamp($order->earnings_recorded_at),
                'delivered_at' => $this->timestamp($order->finished_at),
                'proof' => CourierDeliveryProofService::metadata($order->delivery_proof_id !== null, $order->proof_captured_at),
                'payout_status' => $paid === null ? null : ($paid->has($order->id) ? 'paid' : 'accrued'),
            ])->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
            ],
        ];
    }

    public function snapshot(object $order): ?array
    {
        return $order->rider_pay === null ? null : [
            'amount' => $this->money($order->rider_pay),
            'currency' => 'PHP',
            'recorded_at' => $this->timestamp($order->earnings_recorded_at),
        ];
    }
}
