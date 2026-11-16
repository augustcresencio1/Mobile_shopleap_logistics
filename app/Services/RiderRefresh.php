<?php

namespace App\Services;

use App\Models\CourierProfile;
use Illuminate\Support\Facades\DB;

/** Resolve recipients before commit; only broadcast once their data is committed. */
class RiderRefresh
{
    public static function riders(array $ids): void
    {
        $ids = array_values(array_unique(array_filter($ids)));
        if ($ids) {
            DB::afterCommit(fn () => RiderRealtime::notifyMany($ids));
        }
    }

    public static function orders(array $orderIds): void
    {
        $ids = DB::table('orders')->whereIn('id', array_filter($orderIds))->get()
            ->flatMap(fn ($order) => [
                $order->pickup_rider_id ?? null,
                $order->delivery_rider_id ?? null,
                $order->earning_courier_id ?? null,
            ])->all();

        self::riders($ids);
    }

    public static function users(array $userIds): void
    {
        self::riders(CourierProfile::whereIn('user_id', array_filter($userIds))->pluck('id')->all());
    }

    public static function conversations(array $conversationIds): void
    {
        // sender_id and participant.user_id are User ids, never channel ids.
        self::users(DB::table('conversation_participants')
            ->whereIn('conversation_id', array_filter($conversationIds))->pluck('user_id')->all());
    }
}
