<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CourierProfile;
use App\Services\RiderTrackingService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class RiderTrackingController extends Controller
{
    private function courier(Request $request): CourierProfile
    {
        return $request->attributes->get('courier_profile')
            ?? CourierProfile::where('user_id', $request->user()->id)->firstOrFail();
    }

    private function rules(): array
    {
        return ['latitude' => 'required|numeric|between:-90,90', 'longitude' => 'required|numeric|between:-180,180',
            'accuracy' => 'required|numeric|between:0,100000', 'recorded_at' => 'required|date',
            'speed' => 'nullable|numeric|between:0,150', 'heading' => 'nullable|numeric|between:0,360'];
    }

    public function start(Request $request, RiderTrackingService $tracking)
    {
        $data = $request->validate($this->rules() + ['order_id' => 'required|integer|min:1', 'role' => 'required|in:pickup,delivery']);

        return response()->json(['data' => $tracking->start($this->courier($request), $data)])
            ->header('Cache-Control', 'no-store, private');
    }

    public function update(Request $request, RiderTrackingService $tracking)
    {
        $data = $request->validate($this->rules() + ['session_id' => 'required|uuid']);

        return response()->json(['data' => $tracking->update($this->courier($request), $data)])
            ->header('Cache-Control', 'no-store, private');
    }

    public function stop(Request $request, RiderTrackingService $tracking)
    {
        $data = $request->validate(['session_id' => 'required|uuid']);
        $tracking->stop($this->courier($request), $data['session_id']);

        return response()->json(['message' => 'Live location stopped.'])->header('Cache-Control', 'no-store, private');
    }

    public function index(Request $request, RiderTrackingService $tracking)
    {
        $request->validate(['page' => 'sometimes|integer|min:1', 'per_page' => 'sometimes|integer|between:1,100']);
        $hub = DB::table('logistics_profiles')->where('user_id', $request->user()->id)->where('status', 'approved')->first();
        abort_unless($hub, 403, 'An approved assigned hub is required.');
        $riders = DB::table('courier_profiles as c')->join('users as u', 'u.id', '=', 'c.user_id')
            ->where('c.logistics_profile_id', $hub->id)->where('c.status', 'approved')->where('c.is_active', true)
            ->where('u.account_status', 'active')->where('u.role', 'courier')
            ->orderBy('c.id')->paginate($request->integer('per_page', 50), ['c.id', 'u.name']);
        $states = collect($riders->items())->mapWithKeys(fn ($rider) => [$rider->id => $tracking->latest($rider->id)]);
        $orders = DB::table('orders')->whereIn('id', $states->filter()->pluck('order_id'))
            ->get(['id', 'status', 'pickup_status', 'pickup_rider_id', 'delivery_rider_id'])->keyBy('id');
        $data = collect($riders->items())->map(function ($rider) use ($states, $orders, $tracking, $hub) {
            $state = $states[$rider->id];
            if ($state && (int) $state['hub_id'] !== (int) $hub->id) {
                $state = null;
            }
            $order = $state ? $orders->get($state['order_id']) : null;
            $pickup = ($state['role'] ?? null) === 'pickup';
            $active = $order && (int) ($pickup ? $order->pickup_rider_id : $order->delivery_rider_id) === (int) $rider->id
                && ($pickup ? $order->pickup_status === 'accepted' && in_array($order->status, RiderTrackingService::PICKUP_STATUSES, true)
                    : in_array($order->status, ['ASSIGNED_TO_RIDER', 'OUT_FOR_DELIVERY'], true));

            return ['courier_id' => $rider->id, 'name' => $rider->name] + $tracking->display($state, (bool) $active);
        });

        return response()->json(['data' => $data, 'meta' => ['current_page' => $riders->currentPage(),
            'last_page' => $riders->lastPage(), 'total' => $riders->total(), 'poll_after_seconds' => 5],
            'server_time' => now('UTC')->toIso8601String()])->header('Cache-Control', 'no-store, private');
    }
}
