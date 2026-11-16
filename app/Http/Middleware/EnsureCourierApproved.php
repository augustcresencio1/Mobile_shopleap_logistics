<?php

namespace App\Http\Middleware;

use App\Models\CourierProfile;
use Closure;
use Illuminate\Http\Request;

class EnsureCourierApproved
{
    public function handle(Request $request, Closure $next)
    {
        $profile = CourierProfile::query()
            ->leftJoin('logistics_profiles as hub', 'hub.id', '=', 'courier_profiles.logistics_profile_id')
            ->leftJoin('users as owner', 'owner.id', '=', 'hub.user_id')
            ->where('courier_profiles.user_id', $request->user()->id)
            ->select('courier_profiles.*', 'hub.status as hub_status', 'owner.account_status as hub_account_status')
            ->first();

        if (! $profile || $profile->status !== 'approved' || ! $profile->is_active) {
            return response()->json([
                'message' => 'Hindi pa approved o naka-deactivate ang account mo.',
                'courier_status' => $profile?->status,
            ], 403);
        }

        $hubAvailable = $profile->hub_status === 'approved' && $profile->hub_account_status === 'active';

        if (! $hubAvailable) {
            return response()->json([
                'message' => 'Your hub is unavailable. Please contact support.',
                'courier_status' => 'hub_unavailable',
            ], 403);
        }

        unset($profile->hub_status, $profile->hub_account_status);
        $request->attributes->set('courier_profile', $profile);

        return $next($request);
    }
}
