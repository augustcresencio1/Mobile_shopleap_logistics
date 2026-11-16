<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CourierProfile;
use App\Models\Message;
use App\Services\CourierDeliveryProofService;
use App\Services\CourierEarningsService;
use App\Services\RiderRefresh;
use App\Support\CourierScanCode;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

class CourierDeliveryController extends Controller
{
    // ===== I-EDIT KUNG IBA ANG VALUES SA WEB APP MO =====
    private const PICKUP_PENDING = 'pending';

    private const PICKUP_ASSIGNED = 'assigned'; // isinusulat ng web admin kapag nag-assign

    private const PICKUP_ACCEPTED = 'accepted';

    private const PICKUP_DECLINED = 'declined';

    // Mga pickup_status na "naghihintay pa ng accept/decline ng rider" (bukod sa NULL)
    private const PICKUP_WAITING = [self::PICKUP_PENDING, self::PICKUP_ASSIGNED];

    // Mga status kung kailan pwedeng may pickup request / pickup list
    private const PICKUP_LIST_STATUSES = ['CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP'];

    // =====================================================

    // ---------- helpers ----------

    private function me(Request $r): CourierProfile
    {
        return $r->attributes->get('courier_profile')
            ?? CourierProfile::where('user_id', $r->user()->id)->firstOrFail();
    }

    private function orderSelect()
    {
        return DB::table('orders as o')
            ->join('users as s', 's.id', '=', 'o.seller_id')
            ->leftJoin('seller_profiles as sp', 'sp.user_id', '=', 'o.seller_id')
            ->select(
                'o.id', 'o.order_number', 'o.waybill_code', 'o.status', 'o.buyer_name', 'o.total_amount', 'o.shipping_fee', 'o.rider_fee',
                'o.delivered_at', 'o.cod_collected_amount', 'o.rider_pay',
                'o.earnings_recorded_at', 'o.earning_courier_id',
                'o.pickup_status', 'o.pickup_date', 'o.pickup_time_slot', 'o.pickup_decline_reason',
                'o.delivery_attempts', 'o.delivery_area',
                'o.ship_province', 'o.ship_municipality', 'o.ship_barangay', 'o.ship_street',
                'o.ship_contact_no', 'o.created_at', 'o.updated_at',
                'o.shipping_address', 'sp.contact_no as seller_contact',
                's.name as seller_name',
                'sp.street_address as seller_street',
                'sp.barangay as seller_barangay',
                'sp.municipality as seller_municipality',
                'sp.province as seller_province'
            );
    }

    private function withItems($orders)
    {
        $orders = collect($orders);
        $items = DB::table('order_items')
            ->whereIn('order_id', $orders->pluck('id'))
            ->get(['order_id', 'product_name', 'quantity'])
            ->groupBy('order_id');

        return $orders->map(function ($o) use ($items) {
            $o->items = $items->get($o->id, collect())->values();

            return $o;
        })->values();
    }

    private function logEvent(int $orderId, int $actorId, ?string $status, string $title, ?string $note = null, ?string $fromStatus = null): void
    {
        DB::table('order_events')->insert([
            'order_id' => $orderId,
            'actor_id' => $actorId,
            'status' => $status,
            'title' => $title,
            'note' => $note,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // The web tracker reads parcel_events once a checkout has parcel history.
        // Mirror real courier transitions inside the caller's transaction while
        // retaining legacy order_events for older consumers/databases.
        $from = ['PICKED_UP' => 'READY_FOR_PICKUP', 'OUT_FOR_DELIVERY' => 'ASSIGNED_TO_RIDER',
            'DELIVERED' => 'OUT_FOR_DELIVERY', 'DELIVERY_FAILED' => 'OUT_FOR_DELIVERY'];
        if ($fromStatus !== null && ($from[$status] ?? null) === $fromStatus && Schema::hasTable('parcel_events')) {
            $order = DB::table('orders')->where('id', $orderId)
                ->first(['logistics_profile_id', 'pickup_rider_id', 'delivery_rider_id']);
            DB::table('parcel_events')->insert([
                'order_id' => $orderId, 'hub_id' => $order->logistics_profile_id,
                'rider_id' => $status === 'PICKED_UP' ? $order->pickup_rider_id : $order->delivery_rider_id,
                'event_type' => ['PICKED_UP' => 'picked_up', 'OUT_FOR_DELIVERY' => 'out_for_delivery',
                    'DELIVERED' => 'delivered', 'DELIVERY_FAILED' => 'delivery_attempt'][$status],
                'from_status' => $from[$status], 'to_status' => $status,
                'actor_user_id' => $actorId, 'note' => $note,
                'created_at' => now(), 'updated_at' => now(),
            ]);
        }

        // All query-builder order transitions and their notification events use
        // this helper. Observers do not run for those atomic SQL updates.
        RiderRefresh::orders([$orderId]);
    }

    /**
     * Atomic na pagpapalit ng status. Mananalo lang kung:
     *  - sa iyo naka-assign ang order (sa $riderCol)
     *  - nasa isa sa $from na status pa ito
     */
    private function transition(
        Request $r,
        int $orderId,
        string $riderCol,
        array $from,
        string $to,
        string $title,
        array $extra = [],
        ?string $note = null,
        ?callable $scope = null
    ) {
        $me = $this->me($r);

        $affected = DB::transaction(function () use ($r, $me, $orderId, $riderCol, $from, $to, $title, $extra, $note, $scope) {
            $q = DB::table('orders')
                ->where('id', $orderId)
                ->where($riderCol, $me->id)
                ->whereIn('status', $from);

            if ($scope) {
                $scope($q);
            }

            $n = $q->update(array_merge(['status' => $to, 'updated_at' => now()], $extra));

            if ($n) {
                $this->logEvent($orderId, $r->user()->id, $to, $title, $note, $from[0]);
            }

            return $n;
        });

        if (! $affected) {
            return response()->json(['message' => 'This order cannot be updated.'], 409);
        }

        return response()->json(['message' => 'OK', 'status' => $to]);
    }

    // ---------- DASHBOARDS ----------

    // GET /courier/home  -> lahat ng kailangan ng Home tab at ng bell sa iisang request
    public function home(Request $r, CourierEarningsService $earnings)
    {
        $me = $this->me($r);

        // Pickups: isang query lang, hinahati sa PHP
        $pickupRows = $this->orderSelect()
            ->where('o.pickup_rider_id', $me->id)
            ->where(fn ($q) => $q->whereIn('o.status', self::PICKUP_LIST_STATUSES)
                ->orWhere(fn ($q) => $q->where('o.pickup_status', self::PICKUP_ACCEPTED)
                    ->whereNotIn('o.status', ['DELIVERED', 'COMPLETED', 'DELIVERY_FAILED', 'RETURNED', 'CANCELLED', 'CANCELED'])))
            ->orderBy('o.pickup_date')->orderBy('o.id')
            ->get();

        $requests = $pickupRows->filter(
            fn ($o) => $o->pickup_status === null || in_array($o->pickup_status, self::PICKUP_WAITING, true)
        )->values();

        $pickups = $pickupRows->filter(
            fn ($o) => $o->pickup_status === self::PICKUP_ACCEPTED && in_array($o->status, self::PICKUP_LIST_STATUSES, true)
        )->values();

        $deliveries = $this->orderSelect()
            ->where('o.delivery_rider_id', $me->id)
            ->whereIn('o.status', ['ASSIGNED_TO_RIDER', 'OUT_FOR_DELIVERY'])
            ->orderBy('o.id')
            ->get();

        // Ang orders lang ng rider na ito ang tinitingnan sa order_events
        $mine = DB::table('orders')->where('delivery_rider_id', $me->id)->select('id');

        $done = DB::table('order_events')
            ->select('order_id', DB::raw('max(created_at) as finished_at'))
            ->whereIn('status', ['DELIVERED', 'DELIVERY_FAILED', 'RETURNED'])
            ->whereIn('order_id', $mine)
            ->groupBy('order_id');

        $recent = $this->orderSelect()
            ->leftJoinSub($done, 'd', 'd.order_id', '=', 'o.id')
            ->addSelect(DB::raw('coalesce(d.finished_at, o.updated_at) as finished_at'))
            ->where('o.delivery_rider_id', $me->id)
            ->whereIn('o.status', ['DELIVERED', 'COMPLETED', 'DELIVERY_FAILED', 'RETURNED'])
            ->orderByRaw('coalesce(d.finished_at, o.updated_at) desc')
            ->limit(3)
            ->get();

        $earned = $earnings->summary($me, $earnings->range(['period' => 'week']), ['amount' => null], includePayouts: false);
        $today = collect($earned['daily'])->firstWhere('date', Carbon::now(CourierEarningsService::TIMEZONE)->toDateString());

        // Items ng lahat ng order: isang query lang
        $ids = $pickupRows->pluck('id')
            ->merge($deliveries->pluck('id'))
            ->merge($recent->pluck('id'))
            ->unique()->values();

        $items = DB::table('order_items')
            ->whereIn('order_id', $ids)
            ->get(['order_id', 'product_name', 'quantity'])
            ->groupBy('order_id');

        $attach = fn ($rows) => $rows->map(function ($o) use ($items) {
            $o->items = $items->get($o->id, collect())->values();

            return $o;
        })->values();

        // The bell keeps accepted parcels after pickup; dashboard/tab lists keep their existing stages.
        $deliveryIds = $deliveries->pluck('id')->all();
        $inProgress = $attach($pickupRows->where('pickup_status', self::PICKUP_ACCEPTED)
            ->merge($deliveries)->unique('id')->values())->map(fn ($o) => array_merge((array) $o, [
                'notification_role' => in_array($o->id, $deliveryIds, true) ? 'delivery' : 'pickup',
            ]));

        return response()->json([
            'requests' => $attach($requests),
            'pickups' => $attach($pickups),
            'deliveries' => $attach($deliveries),
            'in_progress' => $inProgress,
            'recent' => $attach($recent),
            'earned_week' => $earned['total_earned'],
            'earned_today' => $today['earned'] ?? '0.00',
            'currency' => 'PHP',
        ]);
    }

    // GET /courier/pickup-requests  -> naghihintay ng accept/decline mo
    public function pickupRequests(Request $r)
    {
        $me = $this->me($r);

        $rows = $this->orderSelect()
            ->where('o.pickup_rider_id', $me->id)
            ->whereIn('o.status', self::PICKUP_LIST_STATUSES)
            ->where(fn ($q) => $q->whereNull('o.pickup_status')->orWhereIn('o.pickup_status', self::PICKUP_WAITING))
            ->orderBy('o.pickup_date')->orderBy('o.id')
            ->get();

        return response()->json(['data' => $this->withItems($rows)]);
    }

    // GET /courier/pickups  -> items for pickup (tinanggap mo na)
    public function pickups(Request $r)
    {
        $me = $this->me($r);

        $rows = $this->orderSelect()
            ->where('o.pickup_rider_id', $me->id)
            ->whereIn('o.status', self::PICKUP_LIST_STATUSES)
            ->when(
                $r->query('filter') === 'awaiting_accept',
                fn ($q) => $q->where(fn ($q) => $q->whereNull('o.pickup_status')->orWhereIn('o.pickup_status', self::PICKUP_WAITING)),
                fn ($q) => $q->where('o.pickup_status', self::PICKUP_ACCEPTED)
            )
            ->orderBy('o.pickup_date')->orderBy('o.id')
            ->get();

        return response()->json(['data' => $this->withItems($rows)]);
    }

    // GET /courier/deliveries  -> items for delivery
    public function deliveries(Request $r)
    {
        $me = $this->me($r);

        $rows = $this->orderSelect()
            ->where('o.delivery_rider_id', $me->id)
            ->whereIn('o.status', ['ASSIGNED_TO_RIDER', 'OUT_FOR_DELIVERY'])
            ->orderBy('o.id')
            ->get();

        return response()->json(['data' => $this->withItems($rows)]);
    }

    // GET /courier/notifications  -> galing sa order_events ng mga order mo
    public function notifications(Request $r)
    {
        $me = $this->me($r);

        $rows = DB::table('order_events as e')
            ->join('orders as o', 'o.id', '=', 'e.order_id')
            ->where(fn ($q) => $q->where('o.pickup_rider_id', $me->id)->orWhere('o.delivery_rider_id', $me->id))
            ->orderByDesc('e.id')
            ->limit(50)
            ->get(['e.id', 'e.order_id', 'e.status', 'e.title', 'e.note', 'e.created_at']);

        return response()->json(['data' => $rows]);
    }

    // ---------- PICKUP FLOW ----------

    private function assignedOrderId(Request $r, string $orderNumber, string $riderColumn): int
    {
        $id = DB::table('orders')->where('order_number', $orderNumber)
            ->where($riderColumn, $this->me($r)->id)->value('id');
        abort_unless($id, 404, 'No such order, or it is not assigned to you.');

        return (int) $id;
    }

    public function acceptPickupOrder(Request $r, string $orderNumber)
    {
        return $this->acceptPickup($r, $this->assignedOrderId($r, $orderNumber, 'pickup_rider_id'));
    }

    public function declinePickupOrder(Request $r, string $orderNumber)
    {
        return $this->declinePickup($r, $this->assignedOrderId($r, $orderNumber, 'pickup_rider_id'));
    }

    public function confirmPickupOrder(Request $r, string $orderNumber)
    {
        return $this->pickup($r, $this->assignedOrderId($r, $orderNumber, 'pickup_rider_id'));
    }

    // POST /courier/orders/{id}/pickup/accept
    public function acceptPickup(Request $r, int $id)
    {
        $me = $this->me($r);

        $n = DB::table('orders')
            ->where('id', $id)
            ->where('pickup_rider_id', $me->id)
            ->where(fn ($q) => $q->whereNull('pickup_status')->orWhereIn('pickup_status', self::PICKUP_WAITING))
            ->update(['pickup_status' => self::PICKUP_ACCEPTED, 'updated_at' => now()]);

        if (! $n) {
            return response()->json(['message' => 'This pickup cannot be accepted.'], 409);
        }

        // Accepting an assignment is internal, as in the web pickup flow.
        $this->logEvent($id, $r->user()->id, null, 'Rider accepted the pickup');

        return response()->json(['message' => 'OK']);
    }

    // POST /courier/orders/{id}/pickup/decline   body: reason
    public function declinePickup(Request $r, int $id)
    {
        $data = $r->validate(['reason' => 'required|string|max:500']);
        $me = $this->me($r);

        $n = DB::table('orders')
            ->where('id', $id)
            ->where('pickup_rider_id', $me->id)
            ->where(fn ($q) => $q->whereNull('pickup_status')->orWhereIn('pickup_status', self::PICKUP_WAITING))
            ->update([
                'pickup_status' => self::PICKUP_DECLINED,
                'pickup_decline_reason' => $data['reason'],
                'updated_at' => now(),
            ]);

        if (! $n) {
            return response()->json(['message' => 'This pickup cannot be declined.'], 409);
        }

        $this->logEvent($id, $r->user()->id, null, 'Rider declined the pickup', $data['reason']);

        return response()->json(['message' => 'OK']);
    }

    // POST /courier/orders/{id}/pickup  -> nakuha na sa seller
    public function pickup(Request $r, int $id)
    {
        $data = $r->validate(['scan' => 'sometimes|required|string|max:256']);
        if (isset($data['scan'])) {
            $selector = CourierScanCode::parse($data['scan']);
            $matches = $selector && DB::table('orders')->where('id', $id)
                ->where('pickup_rider_id', $this->me($r)->id)
                ->where($selector['column'], $selector['value'])->exists();
            abort_unless($matches, 422, 'Scanned code does not match this pickup.');
        }

        return $this->transition(
            $r, $id, 'pickup_rider_id',
            ['READY_FOR_PICKUP'], 'PICKED_UP', 'Picked up by rider',
            [], null,
            fn ($q) => $q->where('pickup_status', self::PICKUP_ACCEPTED)
        );
    }

    // ---------- DELIVERY FLOW ----------

    public function outForDelivery(Request $r, string $orderNumber)
    {
        return $this->startDelivery($r, $this->assignedOrderId($r, $orderNumber, 'delivery_rider_id'));
    }

    public function failDeliveryOrder(Request $r, string $orderNumber)
    {
        return $this->failDelivery($r, $this->assignedOrderId($r, $orderNumber, 'delivery_rider_id'));
    }

    // POST /courier/orders/{id}/start-delivery
    public function startDelivery(Request $r, int $id)
    {
        return $this->transition(
            $r, $id, 'delivery_rider_id',
            ['ASSIGNED_TO_RIDER'], 'OUT_FOR_DELIVERY', 'Out for delivery'
        );
    }

    // POST /courier/orders/{id}/deliver
    public function deliver(Request $r, int $id, CourierEarningsService $earnings, CourierDeliveryProofService $proofs)
    {
        return $this->recordDelivery($r, 'id', $id, $earnings, $proofs);
    }

    // The app sends the public order number, never an internal numeric ID.
    public function delivered(Request $r, string $orderNumber, CourierEarningsService $earnings, CourierDeliveryProofService $proofs)
    {
        return $this->recordDelivery($r, 'order_number', $orderNumber, $earnings, $proofs);
    }

    private function recordDelivery(Request $r, string $column, int|string $value, CourierEarningsService $earnings, CourierDeliveryProofService $proofs)
    {
        $data = $proofs->validate($r);
        $me = $this->me($r);
        abort_unless(Schema::hasTable('order_delivery_proofs'), 503,
            'Delivery photo storage is not ready. Please contact your hub and retry later.');
        $stored = null;
        $readyToCommit = false;

        try {
            $result = DB::transaction(function () use ($r, $column, $value, $data, $me, $earnings, $proofs, &$stored, &$readyToCommit) {
                $order = DB::table('orders')->where($column, $value)
                    ->where('delivery_rider_id', $me->id)->lockForUpdate()->first();
                abort_unless($order, 403, 'This delivery is not assigned to you.');
                abort_if($order->earning_courier_id !== null && (int) $order->earning_courier_id !== (int) $me->id,
                    403, 'This delivery earning belongs to another courier.');

                // A retry returns the original snapshot, even if the rate has changed.
                if (in_array($order->status, ['DELIVERED', 'COMPLETED'], true)) {
                    $proof = DB::table('order_delivery_proofs')->where('order_id', $order->id)->first();

                    return ['earning' => $earnings->snapshot($order),
                        'proof' => $proofs::metadata($proof !== null, $proof?->captured_at)];
                }

                abort_unless($order->status === 'OUT_FOR_DELIVERY', 409,
                    'Start the delivery before marking this parcel delivered.');
                // Hold the order lock through storage and commit so concurrent retries
                // cannot replace the original proof, COD, earning or tracking event.
                $stored = $proofs->store($r->file('proof_image'));
                $now = Carbon::now('UTC');
                $proof = array_merge($stored, [
                    'order_id' => $order->id,
                    'courier_id' => $me->id,
                    'captured_at' => isset($data['captured_at']) ? Carbon::parse($data['captured_at'])->utc()->format('Y-m-d H:i:s') : null,
                    'latitude' => $data['latitude'] ?? null,
                    'longitude' => $data['longitude'] ?? null,
                    'notes' => $data['notes'] ?? null,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
                DB::table('order_delivery_proofs')->insert($proof);
                $rate = $earnings->currentRate($me->logistics_profile_id, $now);
                $update = [
                    'status' => 'DELIVERED',
                    'delivered_at' => $now,
                    'cod_collected_amount' => $earnings->money($data['amount']),
                    'cod_collected_at' => $now,
                    'earning_hub_id' => $me->logistics_profile_id,
                    'earning_courier_id' => $me->id,
                    'rider_pay' => $rate ? $earnings->money($rate->amount) : null,
                    'delivered_shipping_fee' => $order->shipping_fee,
                    'earnings_recorded_at' => $rate ? $now : null,
                    'updated_at' => $now,
                ];
                DB::table('orders')->where('id', $order->id)->update($update);
                $this->logEvent($order->id, $r->user()->id, 'DELIVERED', 'Delivered to buyer', fromStatus: 'OUT_FOR_DELIVERY');

                $result = ['earning' => $earnings->snapshot(DB::table('orders')->where('id', $order->id)->first()),
                    'proof' => $proofs::metadata(true, $proof['captured_at'])];
                $readyToCommit = true;

                return $result;
            });
        } catch (\Throwable $exception) {
            // A failed commit acknowledgement may still mean the DB committed.
            // Preserve that image so Retry can return the original delivery.
            if ($stored !== null && ! $readyToCommit) {
                $proofs->delete($stored);
            }
            if ($exception instanceof HttpExceptionInterface || $exception instanceof \TypeError) {
                throw $exception;
            }
            // SQL exceptions may contain notes and coordinates: log only the type.
            Log::error('Delivery transaction failed.', ['exception_type' => $exception::class]);
            abort(503, 'Delivery could not be confirmed. Your submission is saved in the app; please retry.');
        }

        return response()->json(array_merge(['message' => 'Delivery recorded. Thank you.'], $result));
    }

    // POST /courier/orders/{id}/fail   body: reason
    public function failDelivery(Request $r, int $id)
    {
        $data = $r->validate(['reason' => 'required|string|max:500']);

        return $this->transition(
            $r, $id, 'delivery_rider_id',
            ['OUT_FOR_DELIVERY'], 'DELIVERY_FAILED', 'Delivery attempt failed',
            ['delivery_attempts' => DB::raw('delivery_attempts + 1')],
            $data['reason']
        );
    }

    // data para sa scan: may seller shop/contact, variant at weight ng bawat item
    private function scanData($o)
    {
        $data = $this->withItems([$o])->first();

        $sellerId = DB::table('orders')->where('id', $o->id)->value('seller_id');
        $sp = DB::table('seller_profiles')->where('user_id', $sellerId)->first(['business_name', 'contact_no']);

        $items = DB::table('order_items')
            ->where('order_id', $o->id)
            ->get(['product_name', 'quantity', 'selected_options', 'weight_kg'])
            ->map(function ($i) {
                $opts = is_string($i->selected_options) ? json_decode($i->selected_options, true) : null;
                $variant = is_array($opts)
                    ? collect($opts)->map(fn ($v, $k) => $k.': '.(is_array($v) ? implode(', ', $v) : $v))->implode(', ')
                    : '';

                return [
                    'product_name' => $i->product_name,
                    'quantity' => (int) $i->quantity,
                    'variant' => $variant,
                    'weight_kg' => (float) $i->weight_kg,
                ];
            })->values();

        $data->items = $items;
        $data->seller_shop = $sp->business_name ?? null;
        $data->seller_contact = $sp->contact_no ?? null;
        $data->parcel_weight_kg = round((float) $items->sum('weight_kg'), 3);

        return $data;
    }

    // Public WB/SL and QR references; legacy numeric labels remain supported.
    public function scan(Request $r, string $code)
    {
        $me = $this->me($r);

        $selector = CourierScanCode::parse($code);
        if (! $selector) {
            return response()->json(['message' => 'Invalid waybill or order code.'], 422);
        }

        $o = $this->orderSelect()
            ->where('o.'.$selector['column'], $selector['value'])
            ->where(function ($q) use ($me) {
                $q->where('o.pickup_rider_id', $me->id)
                    ->orWhere('o.delivery_rider_id', $me->id);
            })
            ->first();

        if (! $o) {
            return response()->json(['message' => 'No such order, or it is not assigned to you.'], 404);
        }

        return response()->json([
            'data' => $this->scanData($o),
            'role' => $o->status === 'READY_FOR_PICKUP' ? 'pickup' : 'delivery',
        ]);
    }

    // ---------- HISTORY + EARNINGS ----------

    // GET /courier/history?status=delivered|returned&from=YYYY-MM-DD&to=YYYY-MM-DD
    public function history(Request $r, CourierEarningsService $earnings)
    {
        $me = $this->me($r);
        $tz = 'Asia/Manila';

        $statuses = match ($r->query('status')) {
            'delivered' => ['DELIVERED', 'COMPLETED'],
            'returned' => ['DELIVERY_FAILED', 'RETURNED'],
            default => ['DELIVERED', 'COMPLETED', 'DELIVERY_FAILED', 'RETURNED'],
        };

        // kailan natapos ang delivery (galing sa order_events, UTC)
        $done = DB::table('order_events')
            ->select('order_id', DB::raw('max(created_at) as finished_at'))
            ->whereIn('status', ['DELIVERED', 'DELIVERY_FAILED', 'RETURNED'])
            ->groupBy('order_id');

        $finished = 'coalesce(d.finished_at, o.updated_at)';

        $q = $this->orderSelect()
            ->leftJoinSub($done, 'd', 'd.order_id', '=', 'o.id')
            ->leftJoin('order_delivery_proofs as proof', 'proof.order_id', '=', 'o.id')
            ->addSelect('proof.id as delivery_proof_id', 'proof.captured_at as proof_captured_at')
            ->addSelect(DB::raw("$finished as finished_at"))
            ->where('o.delivery_rider_id', $me->id)
            ->whereIn('o.status', $statuses);

        $hasPay = Schema::hasColumn('orders', 'payment_method');
        if ($hasPay) {
            $q->addSelect('o.payment_method');
        }

        if ($r->filled('from')) {
            $from = Carbon::parse($r->query('from'), $tz)->startOfDay()->utc()->format('Y-m-d H:i:s');
            $q->whereRaw("$finished >= ?", [$from]);
        }
        if ($r->filled('to')) {
            $to = Carbon::parse($r->query('to'), $tz)->endOfDay()->utc()->format('Y-m-d H:i:s');
            $q->whereRaw("$finished <= ?", [$to]);
        }

        $page = $q->orderByRaw("$finished desc")->paginate(20);

        $page->setCollection(
            $this->withItems($page->getCollection())->map(function ($o) use ($tz, $hasPay, $earnings) {
                $returned = in_array($o->status, ['DELIVERY_FAILED', 'RETURNED'], true);
                $when = Carbon::parse($o->finished_at, 'UTC')->setTimezone($tz);
                $isCod = ! $hasPay || in_array(strtolower((string) ($o->payment_method ?? '')), ['cod', 'cash', 'cash_on_delivery'], true);

                $o->order_number = trim((string) $o->order_number) !== '' ? $o->order_number : (string) $o->id;
                $o->items_count = (int) $o->items->sum('quantity');
                $o->customer_name = $o->buyer_name;
                $o->address = implode(', ', array_filter([$o->ship_barangay, $o->ship_municipality]));
                $o->finished_at = $when->toIso8601String();
                $o->finished_label = $when->format('M j, Y · h:i A');
                $o->is_returned = $returned;
                $o->status_label = $returned ? 'Returned' : 'Delivered';
                $o->cash_collected = ($returned || ! $isCod) ? '0.00'
                    : $earnings->money($o->cod_collected_amount);

                // mga pangalan na inaasahan ng app (guide v4)
                $o->cod_collected = $o->cash_collected;
                $o->order_id = $o->id;
                $o->outcome = $returned ? 'returned' : 'delivered';
                $o->barangay = $o->ship_barangay;
                $o->municipality = $o->ship_municipality;
                $o->earning = $returned ? '0.00' : $earnings->money($o->rider_pay);
                $o->currency = 'PHP';
                $o->proof = CourierDeliveryProofService::metadata($o->delivery_proof_id !== null, $o->proof_captured_at);
                unset($o->delivery_proof_id, $o->proof_captured_at);

                return $o;
            })
        );

        $payload = $page->toArray();
        $payload['meta'] = [
            'current_page' => $page->currentPage(),
            'last_page' => $page->lastPage(),
            'total' => $page->total(),
        ];

        return response()->json($payload);
    }

    // Legacy controller entry point uses the same saved-earnings summary.
    public function earnings(Request $r, CourierEarningsService $earnings)
    {
        return response()->json($earnings->summary($this->me($r), $earnings->range($r->query())));
    }

    // ---------- CHAT ----------
    // with = seller | buyer | logistics  (default: seller)

    private function chatContext(Request $r, int $orderId): array
    {
        $me = $this->me($r);

        $order = DB::table('orders')
            ->where('id', $orderId)
            ->where(fn ($q) => $q->where('pickup_rider_id', $me->id)->orWhere('delivery_rider_id', $me->id))
            ->first();

        abort_if(! $order, 404, 'Order not found.');

        $with = $r->input('with', $r->query('with', 'seller'));
        abort_unless(in_array($with, ['seller', 'buyer', 'logistics'], true), 422, 'with must be seller, buyer or logistics.');

        if ($with === 'logistics') {
            $hubId = $order->logistics_profile_id ?: $me->logistics_profile_id;
            $otherId = $hubId
                ? DB::table('logistics_profiles')->where('id', $hubId)->value('user_id')
                : null;
        } else {
            $otherId = $with === 'seller' ? $order->seller_id : $order->buyer_id;
        }
        abort_if(! $otherId, 422, 'No '.$with.' for this order.');

        $order->chat_order_id = $with === 'logistics' ? null : $order->id;

        return [$order, $r->user()->id, (int) $otherId];
    }

    private function findConversation(?int $orderId, int $a, int $b)
    {
        $has = fn ($uid) => function ($q) use ($uid) {
            $q->select(DB::raw(1))->from('conversation_participants as p')
                ->whereColumn('p.conversation_id', 'c.id')->where('p.user_id', $uid);
        };

        return DB::table('conversations as c')
            ->when($orderId === null, fn ($q) => $q->whereNull('c.order_id'), fn ($q) => $q->where('c.order_id', $orderId))
            ->whereExists($has($a))
            ->whereExists($has($b))
            ->first();
    }

    private function markChatRead(int $conversationId, int $userId, ?string $through): void
    {
        if ($through === null) {
            return;
        }

        // Use the messages actually fetched, even if another app's clock differs.
        // An older concurrent request must never move the read marker backwards.
        $changed = DB::table('conversation_participants')
            ->where('conversation_id', $conversationId)->where('user_id', $userId)
            ->where(fn ($q) => $q->whereNull('last_read_at')->orWhere('last_read_at', '<', $through))
            ->update(['last_read_at' => $through]);

        if ($changed) {
            RiderRefresh::users([$userId]);
        }
    }

    // GET /courier/chats -> listahan ng threads (seller / buyer / logistics) ng mga order mo
    public function chats(Request $r)
    {
        $me = $this->me($r);
        $uid = (int) $r->user()->id;

        $orders = DB::table('orders')
            ->where(fn ($q) => $q->where('pickup_rider_id', $me->id)->orWhere('delivery_rider_id', $me->id))
            ->orderByDesc('id')->limit(100)
            ->get(['id', 'status', 'seller_id', 'buyer_id', 'buyer_name', 'logistics_profile_id']);

        $hubIds = $orders->pluck('logistics_profile_id')->push($me->logistics_profile_id)->filter()->unique()->values();
        $hubUsers = DB::table('logistics_profiles')->whereIn('id', $hubIds)->pluck('user_id', 'id');

        $userIds = $orders->pluck('seller_id')->merge($orders->pluck('buyer_id'))->merge($hubUsers->values())->filter()->unique()->values();
        $names = DB::table('users')->whereIn('id', $userIds)->pluck('name', 'id');

        // mga conversation ko
        $mine = DB::table('conversation_participants as p')
            ->join('conversations as c', 'c.id', '=', 'p.conversation_id')
            ->where('p.user_id', $uid)
            ->get(['c.id', 'c.order_id']);
        $ids = $mine->pluck('id');

        $others = DB::table('conversation_participants')
            ->whereIn('conversation_id', $ids)->where('user_id', '!=', $uid)
            ->get(['conversation_id', 'user_id'])
            ->groupBy('conversation_id');

        $convByKey = [];
        foreach ($mine as $c) {
            foreach ($others->get($c->id, collect()) as $o) {
                $convByKey[($c->order_id ?? 0).'|'.$o->user_id] = $c->id;
            }
        }

        $last = DB::table('messages')
            ->whereIn('id', DB::table('messages')->selectRaw('max(id)')->whereIn('conversation_id', $ids)->groupBy('conversation_id'))
            ->get(['id', 'conversation_id', 'sender_id', 'body', 'created_at'])
            ->keyBy('conversation_id');

        $unread = DB::table('messages as m')
            ->join('conversation_participants as p', fn ($j) => $j->on('p.conversation_id', '=', 'm.conversation_id')->where('p.user_id', $uid))
            ->whereIn('m.conversation_id', $ids)
            ->where('m.sender_id', '!=', $uid)
            ->where(fn ($q) => $q->whereNull('p.last_read_at')->orWhereColumn('m.created_at', '>', 'p.last_read_at'))
            ->groupBy('m.conversation_id')
            ->selectRaw('m.conversation_id as cid, count(*) as n')
            ->pluck('n', 'cid');

        $finished = ['DELIVERED', 'COMPLETED', 'DELIVERY_FAILED', 'RETURNED'];
        $threads = [];
        $seenHub = [];

        foreach ($orders as $o) {
            foreach (['seller', 'buyer', 'logistics'] as $with) {
                if ($with === 'seller') {
                    $otherId = $o->seller_id;
                    $name = $names[$otherId] ?? 'Seller';
                    $sub = 'Seller · Order #'.$o->id;
                } elseif ($with === 'buyer') {
                    $otherId = $o->buyer_id;
                    $name = $o->buyer_name ?: ($names[$otherId] ?? 'Customer');
                    $sub = 'Customer · Order #'.$o->id;
                } else {
                    $hubId = $o->logistics_profile_id ?: $me->logistics_profile_id;
                    $otherId = $hubId ? ($hubUsers[$hubId] ?? null) : null;
                    $name = 'Logistics (hub)';
                    $sub = 'Hub';
                    if ($otherId && isset($seenHub[$otherId])) {
                        continue;
                    }
                }
                if (! $otherId) {
                    continue;
                }

                $convId = $convByKey[($with === 'logistics' ? 0 : $o->id).'|'.$otherId] ?? null;

                // walang usapan at tapos na ang order -> huwag nang ilista
                if (! $convId && in_array($o->status, $finished, true)) {
                    continue;
                }
                if ($with === 'logistics') {
                    $seenHub[$otherId] = true;
                }

                $l = $convId ? $last->get($convId) : null;
                $threads[] = [
                    'key' => $with.'-'.($with === 'logistics' ? $otherId : $o->id),
                    'with' => $with,
                    'order_id' => $o->id,
                    'conversation_id' => $convId,
                    'name' => $name,
                    'subtitle' => $sub,
                    'last_message' => $l->body ?? null,
                    'last_message_id' => $l->id ?? null,
                    'last_is_mine' => $l ? (int) $l->sender_id === $uid : false,
                    'last_message_at' => $l ? Carbon::parse($l->created_at, 'UTC')->toIso8601String() : null,
                    'unread' => (int) ($unread[$convId] ?? 0),
                ];
            }
        }

        usort($threads, function ($a, $b) {
            if ($a['last_message_at'] === $b['last_message_at']) {
                return $b['order_id'] <=> $a['order_id'];
            }
            if ($a['last_message_at'] === null) {
                return 1;
            }
            if ($b['last_message_at'] === null) {
                return -1;
            }

            return strcmp($b['last_message_at'], $a['last_message_at']);
        });

        return response()->json(['data' => $threads]);
    }

    // GET /courier/orders/{id}/messages?with=seller
    public function messages(Request $r, int $id)
    {
        [$order, $uid, $otherId] = $this->chatContext($r, $id);
        $conv = $this->findConversation($order->chat_order_id, $uid, $otherId);

        if (! $conv) {
            return response()->json(['conversation_id' => null, 'data' => []]);
        }

        $rows = DB::table('messages as m')
            ->join('users as u', 'u.id', '=', 'm.sender_id')
            ->where('m.conversation_id', $conv->id)
            ->orderBy('m.id')
            ->get(['m.id', 'm.sender_id', 'u.name as sender_name', 'm.body', 'm.created_at']);

        $this->markChatRead((int) $conv->id, (int) $uid, $rows->max('created_at'));

        $rows = $rows->map(function ($m) use ($uid) {
            $m->mine = (int) $m->sender_id === (int) $uid;
            $m->created_at = Carbon::parse($m->created_at, 'UTC')->toIso8601String();

            return $m;
        });

        return response()->json(['conversation_id' => $conv->id, 'data' => $rows]);
    }

    // POST /courier/orders/{id}/messages   body: body, with
    public function sendMessage(Request $r, int $id)
    {
        $r->validate(['body' => 'required|string|max:2000']);
        [$order, $uid, $otherId] = $this->chatContext($r, $id);

        $sent = DB::transaction(function () use ($r, $order, $uid, $otherId) {
            $conv = $this->findConversation($order->chat_order_id, $uid, $otherId);

            if (! $conv) {
                $convId = DB::table('conversations')->insertGetId([
                    'subject' => $order->chat_order_id ? 'Order #'.$order->id : null,
                    'order_id' => $order->chat_order_id,
                    'created_by' => $uid,
                    'status' => 'open',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                foreach ([$uid, $otherId] as $pid) {
                    DB::table('conversation_participants')->insert([
                        'conversation_id' => $convId,
                        'user_id' => $pid,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }
            } else {
                $convId = $conv->id;
            }

            // Replying acknowledges the existing messages, only for the sender.
            $through = DB::table('messages')->where('conversation_id', $convId)->max('created_at');
            $this->markChatRead((int) $convId, (int) $uid, $through);

            $sentAt = now();

            $message = Message::create([
                'conversation_id' => $convId,
                'sender_id' => $uid,
                'body' => $r->input('body'),
                'created_at' => $sentAt,
                'updated_at' => $sentAt,
            ]);

            DB::table('conversations')->where('id', $convId)
                ->update(['last_message_at' => now(), 'updated_at' => now()]);

            return [
                'id' => $message->id,
                'conversation_id' => (int) $convId,
                'body' => $r->input('body'),
                'mine' => true,
                'sender_name' => $r->user()->name,
                'created_at' => $sentAt->toIso8601String(),
            ];
        });

        return response()->json(['message' => 'Sent.', 'id' => $sent['id'], 'data' => $sent], 201);
    }

    // ---------- ACCOUNT ----------

    // GET /courier/account
    public function account(Request $r)
    {
        $profile = $this->me($r);

        return response()->json([
            'email' => $r->user()->email,
            'courier' => $profile,
        ]);
    }

    // PUT /courier/account
    public function updateAccount(Request $r)
    {
        $data = $r->validate([
            'contact_no' => ['sometimes', 'regex:/^09\d{9}$/'],
            'vehicle_type' => 'sometimes|in:Trike,Motor,Van',
            'plate_number' => 'sometimes|string|max:20',
            'barangay' => 'sometimes|string|max:100',
            'street_address' => 'sometimes|nullable|string|max:255',
        ]);

        $profile = $this->me($r);
        $profile->update($data);

        return response()->json(['message' => 'Updated.', 'courier' => $profile->fresh()]);
    }

    // POST /courier/account/password
    public function changePassword(Request $r)
    {
        $data = $r->validate([
            'current_password' => 'required|string',
            'password' => 'required|string|min:8|confirmed',
        ]);

        $user = $r->user();

        if (! Hash::check($data['current_password'], $user->password)) {
            return response()->json(['message' => 'Current password is incorrect.'], 422);
        }

        $user->forceFill(['password' => Hash::make($data['password'])])->save();

        // i-logout ang ibang devices
        $user->tokens()->where('id', '!=', $user->currentAccessToken()->id)->delete();

        return response()->json(['message' => 'Password updated.']);
    }
}
