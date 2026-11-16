<?php

namespace App\Services;

use App\Models\CourierProfile;
use Carbon\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class RiderTrackingService
{
    public const PICKUP_STATUSES = ['CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'PICKED_UP'];

    private function cache()
    {
        return Cache::store(config('rider_navigation.tracking_cache_store', 'file'));
    }

    private function key(int $courierId): string
    {
        return 'rider-location:v1:'.$courierId;
    }

    public function activeOrder(int $id, int $courierId, string $role): bool
    {
        return DB::table('orders')->where('id', $id)
            ->where($role === 'pickup' ? 'pickup_rider_id' : 'delivery_rider_id', $courierId)
            ->when($role === 'pickup', fn ($q) => $q->where('pickup_status', 'accepted'))
            ->whereIn('status', $role === 'pickup'
                ? self::PICKUP_STATUSES
                : ['ASSIGNED_TO_RIDER', 'OUT_FOR_DELIVERY'])->exists();
    }

    public function fresh(array $data): void
    {
        $time = Carbon::parse($data['recorded_at'])->utc();
        abort_if($time->lt(now('UTC')->subMinutes(2)) || $time->gt(now('UTC')->addMinute()),
            422, 'Get a fresh GPS location before sharing your trip.');
    }

    private function coordinates(array $data): array
    {
        return ['latitude' => (float) $data['latitude'], 'longitude' => (float) $data['longitude'],
            'accuracy' => (float) $data['accuracy'], 'speed' => isset($data['speed']) ? (float) $data['speed'] : null,
            'heading' => isset($data['heading']) ? (float) $data['heading'] : null,
            'recorded_at' => Carbon::parse($data['recorded_at'])->utc()->toIso8601String()];
    }

    public function start(CourierProfile $courier, array $data): array
    {
        $this->fresh($data);
        abort_unless($this->activeOrder($data['order_id'], $courier->id, $data['role']),
            403, 'This active trip is not assigned to you.');

        return $this->cache()->lock($this->key($courier->id).':lock', 5)->block(2, function () use ($courier, $data) {
            $state = ['session_id' => (string) Str::uuid(), 'courier_id' => $courier->id,
                'hub_id' => $courier->logistics_profile_id, 'order_id' => (int) $data['order_id'],
                'role' => $data['role'], 'tracking' => true, 'location' => $this->coordinates($data),
                'received_at' => now('UTC')->toIso8601String()];
            $this->cache()->put($this->key($courier->id), $state, now()->addMinutes(5));

            return $state;
        });
    }

    public function update(CourierProfile $courier, array $data): array
    {
        $this->fresh($data);

        return $this->cache()->lock($this->key($courier->id).':lock', 5)->block(2, function () use ($courier, $data) {
            $state = $this->latest($courier->id);
            abort_unless($state && $state['tracking'] && hash_equals($state['session_id'], $data['session_id'])
                && (int) $state['hub_id'] === (int) $courier->logistics_profile_id, 409, 'Start live location again.');
            abort_unless($this->activeOrder($state['order_id'], $courier->id, $state['role']),
                403, 'This trip has ended or is no longer assigned to you.');
            // Delayed network requests must never move a rider back to an older fix.
            if (Carbon::parse($data['recorded_at'])->gte(Carbon::parse($state['location']['recorded_at']))) {
                $state['location'] = $this->coordinates($data);
                $state['received_at'] = now('UTC')->toIso8601String();
                $this->cache()->put($this->key($courier->id), $state, now()->addMinutes(5));
            }

            return $state;
        });
    }

    public function stop(CourierProfile $courier, string $sessionId): void
    {
        $this->cache()->lock($this->key($courier->id).':lock', 5)->block(2, function () use ($courier, $sessionId) {
            $state = $this->latest($courier->id);
            if ($state && hash_equals($state['session_id'], $sessionId)) {
                $state['tracking'] = false;
                $state['stopped_at'] = now('UTC')->toIso8601String();
                $this->cache()->put($this->key($courier->id), $state, now()->addMinutes(5));
            }
        });
    }

    public function latest(int $courierId): ?array
    {
        return $this->cache()->get($this->key($courierId));
    }

    public function display(?array $state, bool $activeTrip): array
    {
        if (! $state) {
            return ['status' => 'unavailable', 'tracking' => false, 'location' => null];
        }
        unset($state['session_id']);
        $state['tracking'] = $state['tracking'] && $activeTrip;
        $stale = Carbon::parse($state['received_at'])->lt(now('UTC')->subSeconds(30))
            || Carbon::parse($state['location']['recorded_at'])->lt(now('UTC')->subSeconds(30));
        $state['status'] = ! $state['tracking'] ? 'stopped' : ($stale ? 'stale' : 'live');

        return $state;
    }
}
