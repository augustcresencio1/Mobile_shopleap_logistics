<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CourierProfile;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AuthController extends Controller
{
    // POST /api/login
    public function login(Request $request)
    {
        $data = $request->validate([
            'email' => 'required|email',
            'password' => 'required|string',
        ]);

        $user = User::whereRaw('lower(email) = ?', [strtolower(trim($data['email']))])
            ->where('role', 'courier')
            ->first();

        if (!$user || !Hash::check($data['password'], $user->password)) {
            return response()->json(['message' => 'Incorrect email or password.'], 401);
        }

        if ($user->account_status !== 'active') {
            return response()->json(['message' => 'Your account has been deactivated.'], 403);
        }

        $profile = CourierProfile::where('user_id', $user->id)->first();

        if (!$profile) {
            return response()->json(['message' => 'This account has no courier profile.'], 403);
        }

        if ($profile->status === 'rejected') {
            return response()->json([
                'message' => 'Your registration was rejected.',
                'courier_status' => 'rejected',
                'reason' => $profile->rejection_reason,
            ], 403);
        }

        if (!$profile->is_active) {
            return response()->json(['message' => 'Your account has been deactivated.'], 403);
        }

        return response()->json([
            'role' => 'courier',
            'token' => $user->createToken('rider-app')->plainTextToken,
            'courier_status' => $profile->status,
            'user' => $user->only(['id', 'name', 'email']),
            'message' => $profile->status === 'pending'
                ? 'Your account is waiting for approval.'
                : null,
        ]);
    }
}