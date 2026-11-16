<?php

namespace App\Services;

use App\Models\CourierProfile;
use Illuminate\Support\Facades\DB;

class RiderNavigationService
{
    public function pin(array $data): ?array
    {
        foreach ([$data, $data['location'] ?? [], $data['pin'] ?? []] as $candidate) {
            if (! is_array($candidate)) {
                continue;
            }
            $lat = $candidate['latitude'] ?? $candidate['lat'] ?? null;
            $lng = $candidate['longitude'] ?? $candidate['lng'] ?? $candidate['lon'] ?? null;
            if (is_numeric($lat) && is_numeric($lng) && is_finite((float) $lat) && is_finite((float) $lng)
                && abs((float) $lat) <= 90 && abs((float) $lng) <= 180) {
                return ['latitude' => (float) $lat, 'longitude' => (float) $lng];
            }
        }

        return null;
    }

    private function address(array $parts): string
    {
        return implode(', ', array_filter(array_map(fn ($value) => is_scalar($value) ? trim((string) $value) : '', $parts),
            fn ($value) => $value !== ''));
    }

    public function stop(object $order, string $role, ?object $seller = null): array
    {
        if ($role === 'pickup') {
            $seller ??= DB::table('seller_profiles')->where('user_id', $order->seller_id)->first();
            $name = $order->seller_name ?? $seller?->business_name ?? 'Seller';
            $address = $this->address([$seller?->street_address, $seller?->barangay, $seller?->municipality, $seller?->province]);
            $phone = $seller?->contact_no;
            $pin = $this->pin((array) $seller);
        } else {
            $snapshot = $order->shipping_address ?? null;
            $snapshot = is_string($snapshot) ? json_decode($snapshot, true) : $snapshot;
            $snapshot = is_array($snapshot) ? $snapshot : [];
            $name = $order->buyer_name ?? $snapshot['recipient_name'] ?? 'Customer';
            $address = $this->address([$order->ship_street ?? null, $order->ship_barangay ?? null,
                $order->ship_municipality ?? null, $order->ship_province ?? null]);
            if ($address === '') {
                $address = $this->address([$snapshot['street_address'] ?? $snapshot['address'] ?? null,
                    $snapshot['barangay'] ?? null, $snapshot['city_municipality'] ?? $snapshot['municipality'] ?? null,
                    $snapshot['province'] ?? null]);
            }
            $phone = $order->ship_contact_no ?? $snapshot['phone'] ?? null;
            $pin = $this->pin($snapshot);
        }

        return ['order_id' => $order->id, 'name' => $name, 'address' => $address, 'phone' => $phone,
            'latitude' => $pin['latitude'] ?? null, 'longitude' => $pin['longitude'] ?? null];
    }

    public function route(CourierProfile $courier, string $role): array
    {
        $query = DB::table('orders as o')->join('users as seller', 'seller.id', '=', 'o.seller_id')
            ->select('o.*', 'seller.name as seller_name');
        if ($role === 'pickup') {
            $query->where('o.pickup_rider_id', $courier->id)->where('o.pickup_status', 'accepted')
                ->whereIn('o.status', ['CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP'])
                ->orderBy('o.pickup_date');
        } else {
            $query->where('o.delivery_rider_id', $courier->id)
                ->whereIn('o.status', ['ASSIGNED_TO_RIDER', 'OUT_FOR_DELIVERY']);
        }
        $orders = $query->orderBy('o.id')->get();
        $sellers = $role === 'pickup' ? DB::table('seller_profiles')
            ->whereIn('user_id', $orders->pluck('seller_id'))->get()->keyBy('user_id') : collect();
        $hub = DB::table('logistics_profiles')->where('id', $courier->logistics_profile_id)->first();
        $hubPin = $this->pin((array) $hub);

        return [
            'role' => $role,
            'station' => $hub ? ['id' => $hub->id, 'name' => $hub->business_name ?? 'Assigned hub',
                'address' => $this->address([$hub->street_address ?? $hub->street ?? null,
                    $hub->barangay ?? null, $hub->municipality ?? null, $hub->province ?? null]),
                'phone' => $hub->contact_no ?? null,
                'latitude' => $hubPin['latitude'] ?? null, 'longitude' => $hubPin['longitude'] ?? null] : null,
            'stops' => $orders->map(fn ($order) => $this->stop($order, $role, $sellers->get($order->seller_id)))->values(),
        ];
    }

    public function distance(array $from, array $to): float
    {
        $dLat = deg2rad($to['latitude'] - $from['latitude']);
        $dLng = deg2rad($to['longitude'] - $from['longitude']);
        $a = sin($dLat / 2) ** 2 + cos(deg2rad($from['latitude'])) * cos(deg2rad($to['latitude'])) * sin($dLng / 2) ** 2;

        return 6371000 * 2 * asin(sqrt(min(1, max(0, $a))));
    }
}
