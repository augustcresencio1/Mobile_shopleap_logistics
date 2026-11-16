<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CourierProfile;
use App\Models\OrderEvent;
use App\Services\RiderNavigationService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class RiderNavigationController extends Controller
{
    private function courier(Request $request): CourierProfile
    {
        return $request->attributes->get('courier_profile')
            ?? CourierProfile::where('user_id', $request->user()->id)->firstOrFail();
    }

    public function route(Request $request, RiderNavigationService $navigation)
    {
        $data = $request->validate(['role' => 'required|in:pickup,delivery']);

        return response()->json($navigation->route($this->courier($request), $data['role']));
    }

    public function arrived(Request $request, int $id, RiderNavigationService $navigation)
    {
        $data = $request->validate([
            'role' => 'required|in:pickup,delivery',
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
            'accuracy' => 'required|numeric|between:0,100000',
            'recorded_at' => 'required|date',
        ]);
        $recordedAt = Carbon::parse($data['recorded_at'])->utc();
        abort_if($recordedAt->lt(now('UTC')->subMinutes(2)) || $recordedAt->gt(now('UTC')->addMinute()),
            422, 'Get a fresh GPS location before confirming arrival.');
        $courier = $this->courier($request);
        $role = $data['role'];
        $order = DB::table('orders')->where('id', $id)
            ->where($role === 'pickup' ? 'pickup_rider_id' : 'delivery_rider_id', $courier->id)->first();
        abort_unless($order, 403, 'This order is not assigned to you.');
        $validStage = $role === 'pickup'
            ? $order->pickup_status === 'accepted' && $order->status === 'READY_FOR_PICKUP'
            : $order->status === 'OUT_FOR_DELIVERY';
        abort_unless($validStage, 422, 'This parcel is not at the arrival stage.');
        $stop = $navigation->stop($order, $role);
        $pin = $navigation->pin($stop);
        $radius = (float) config('rider_navigation.arrival_radius_meters', 150);
        $distance = $pin ? $navigation->distance($data, $pin) : null;
        $within = $distance !== null ? $distance <= $radius : null;
        $warning = $pin === null ? 'No destination pin is saved, so arrival distance could not be verified.'
            : (! $within ? 'You appear to be outside the 150 m arrival radius.' : null);
        if ((float) $data['accuracy'] > $radius) {
            $warning = 'GPS accuracy is low. Move to an open area and check your location.';
        }
        if (config('rider_navigation.enforce_arrival_radius') && ($within !== true || (float) $data['accuracy'] > $radius)) {
            return response()->json(['message' => $warning, 'within_radius' => $within,
                'distance_meters' => $distance === null ? null : round($distance, 1)], 422);
        }
        OrderEvent::create([
            'order_id' => $id, 'actor_id' => $request->user()->id, 'status' => null,
            'title' => $role === 'pickup' ? 'Rider arrived at seller' : 'Rider arrived at customer',
            'note' => json_encode(['role' => $role, 'latitude' => (float) $data['latitude'],
                'longitude' => (float) $data['longitude'], 'accuracy' => (float) $data['accuracy'],
                'recorded_at' => $recordedAt->toIso8601String(), 'within_radius' => $within,
                'distance_meters' => $distance === null ? null : round($distance, 1)]),
            'created_at' => now('UTC'), 'updated_at' => now('UTC'),
        ]);

        return response()->json(['message' => 'Arrival recorded.', 'warning' => $warning,
            'within_radius' => $within, 'distance_meters' => $distance === null ? null : round($distance, 1)]);
    }
}
