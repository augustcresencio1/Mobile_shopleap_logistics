<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CourierProfile;
use App\Services\CourierEarningsService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CourierEarningsController extends Controller
{
    private function courier(Request $request): CourierProfile
    {
        return $request->attributes->get('courier_profile')
            ?? CourierProfile::where('user_id', $request->user()->id)->firstOrFail();
    }

    public function show(Request $request, CourierEarningsService $earnings)
    {
        return response()->json($earnings->summary(
            $this->courier($request), $earnings->range($request->query())
        ));
    }

    public function rate(Request $request, CourierEarningsService $earnings)
    {
        return response()->json($earnings->ratePayload($this->courier($request)));
    }

    public function overview(Request $request, CourierEarningsService $earnings)
    {
        $courier = $this->courier($request);
        $range = $earnings->range($request->query());
        $rate = $earnings->ratePayload($courier);

        return response()->json([
            'summary' => $earnings->summary($courier, $range, $rate),
            'rate' => $rate,
            'history' => $earnings->history($courier, $range),
        ]);
    }

    public function history(Request $request, CourierEarningsService $earnings)
    {
        $request->validate(['page' => 'sometimes|integer|min:1']);

        return response()->json($earnings->history(
            $this->courier($request), $earnings->range($request->query())
        ));
    }

    public function dashboard(Request $request, CourierEarningsService $earnings)
    {
        $courier = $this->courier($request);
        $pickups = DB::table('orders')->where('pickup_rider_id', $courier->id)
            ->whereIn('status', ['CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP'])
            ->selectRaw('pickup_status, count(*) as total')->groupBy('pickup_status')
            ->pluck('total', 'pickup_status');
        $deliveries = DB::table('orders')->where('delivery_rider_id', $courier->id)
            ->selectRaw('status, count(*) as total')->groupBy('status')->pluck('total', 'status');
        $today = $earnings->summary($courier, $earnings->range(['period' => 'today']), includePayouts: false);

        return response()->json([
            'pickups' => [
                'awaiting_accept' => (int) ($pickups[''] ?? 0) + (int) ($pickups['pending'] ?? 0) + (int) ($pickups['assigned'] ?? 0),
                'accepted' => (int) ($pickups['accepted'] ?? 0),
                'total' => (int) $pickups->sum(),
            ],
            'deliveries' => [
                'to_deliver' => (int) ($deliveries['ASSIGNED_TO_RIDER'] ?? 0),
                'out_for_delivery' => (int) ($deliveries['OUT_FOR_DELIVERY'] ?? 0),
                'waiting_hub_decision' => (int) ($deliveries['DELIVERY_FAILED'] ?? 0),
            ],
            'delivered_today' => $today['deliveries'],
            'earned_today' => $today['total_earned'],
            'currency' => 'PHP',
        ]);
    }
}
