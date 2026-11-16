<?php

namespace App\Services;

use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Nagpapadala ng "refresh" signal sa mobile app ng rider (Supabase Realtime Broadcast).
 * $courierProfileId = CourierProfile id (yung nasa orders.pickup_rider_id / delivery_rider_id).
 */
class RiderRealtime
{
    public static function notify(?int $courierProfileId, string $event = 'refresh'): void
    {
        if (! $courierProfileId) {
            return;
        }

        try {
            self::broadcast($courierProfileId, $event);
        } catch (\Throwable $e) {
            report($e); // huwag hayaang pumalya ang web action
        }
    }

    /** Shared transport for notifications and the diagnostic command. */
    public static function broadcast(int $courierProfileId, string $event = 'refresh'): ?Response
    {
        $url = config('services.supabase.url');
        $key = config('services.supabase.service_key');
        if (! $url || ! $key) {
            Log::warning('RiderRealtime: Supabase URL or service key is missing.');

            return null;
        }

        $response = Http::timeout(3)
            ->withHeaders([
                'apikey' => $key,
                'Authorization' => 'Bearer '.$key,
            ])
            ->post(rtrim($url, '/').'/realtime/v1/api/broadcast', [
                'messages' => [[
                    'topic' => "rider:{$courierProfileId}",
                    'event' => $event,
                    'payload' => ['at' => now()->toIso8601String()],
                    'private' => false,
                ]],
            ])->throw();

        Log::debug('RiderRealtime: broadcast accepted.', [
            'courier_profile_id' => $courierProfileId,
            'status' => $response->status(),
        ]);

        return $response;
    }

    /** Para sa assign/reassign: i-notify ang luma at bagong rider. */
    public static function notifyMany(array $courierProfileIds): void
    {
        foreach (array_unique(array_filter($courierProfileIds)) as $id) {
            self::notify((int) $id);
        }
    }
}
