<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CourierProfile;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class CourierAuthController extends Controller
{
    private const OTP_MINUTES = 10;

    private function key(string $email): string
    {
        return 'courier_reg:'.strtolower(trim($email));
    }

    private function sendOtp(string $email, string $otp): void
    {
        Mail::send(
            'emails.rider-otp',
            ['otp' => $otp, 'minutes' => self::OTP_MINUTES],
            fn ($m) => $m->to($email)->subject('Shopleap Rider verification code')
        );
    }

    // GET /api/courier/hubs -> list for registration dropdown
    public function hubs()
    {
        return response()->json(
            DB::table('logistics_profiles')
                ->select('id', 'business_name as hub_name')
                ->where('status', 'approved')
                ->orderBy('business_name')
                ->get()
        );
    }

    // POST /api/courier/register -> stash + send OTP
    public function register(Request $request)
    {
        // Tanggapin ang v4 field names (hub_id, or_cr_upload, license_upload)
        if ($request->has('hub_id') && ! $request->has('logistics_profile_id')) {
            $request->merge(['logistics_profile_id' => $request->input('hub_id')]);
        }
        $data = $request->validate([
            'last_name' => 'required|string|max:100',
            'first_name' => 'required|string|max:100',
            'middle_initial' => 'nullable|string|max:1',
            'sex' => 'required|in:male,female',
            'email' => 'required|email|unique:users,email',
            'contact_no' => ['required', 'regex:/^09\d{9}$/'],
            'birthday' => 'required|date|before_or_equal:-18 years',
            'province' => 'required|string|max:100',
            'municipality' => 'required|string|max:100',
            'barangay' => 'required|string|max:100',
            'street_address' => 'nullable|string|max:255',
            'vehicle_type' => 'required|in:Trike,Motor,Van',
            'plate_number' => 'required|string|max:20',
            'logistics_profile_id' => 'required|integer|exists:logistics_profiles,id',
            'password' => 'required|string|min:8|confirmed',
            'or_cr_upload' => 'required|image|max:5120',
            'license_upload' => 'required|image|max:5120',
        ]);

        // A failed upload/cache/email must not leave a half-submitted registration.
        $dir = 'pending_couriers/'.Str::uuid();
        $stage = 'documents';
        try {
            $orCrPath = $request->file('or_cr_upload')->store($dir, 'local');
            $licensePath = $request->file('license_upload')->store($dir, 'local');
            if (! $orCrPath || ! $licensePath) {
                throw new \RuntimeException('Registration document storage failed.');
            }

            $payload = collect($data)->except(['password', 'password_confirmation', 'or_cr_upload', 'license_upload'])->all();
            $payload['password'] = Hash::make($data['password']);
            $payload['or_cr_path'] = $orCrPath;
            $payload['license_path'] = $licensePath;
            $payload['dir'] = $dir;
            $otp = (string) random_int(100000, 999999);

            $stage = 'cache';
            if (! Cache::put($this->key($data['email']), [
                'otp_hash' => Hash::make($otp),
                'attempts' => 0,
                'data' => $payload,
            ], now()->addMinutes(self::OTP_MINUTES))) {
                throw new \RuntimeException('Registration cache write failed.');
            }

            $stage = 'email';
            $this->sendOtp($data['email'], $otp);
        } catch (\Throwable $exception) {
            // Never log an email, password, document, OTP, or SMTP credentials.
            Log::error('Courier registration unavailable.', [
                'stage' => $stage,
                'exception_type' => get_class($exception),
            ]);
            try {
                Cache::forget($this->key($data['email']));
                Storage::disk('local')->deleteDirectory($dir);
            } catch (\Throwable $cleanupException) {
                Log::warning('Courier registration cleanup failed.', [
                    'exception_type' => get_class($cleanupException),
                ]);
            }

            return response()->json([
                'code' => $stage === 'email' ? 'REGISTRATION_EMAIL_UNAVAILABLE' : 'REGISTRATION_UNAVAILABLE',
                'message' => $stage === 'email'
                    ? 'Verification email could not be sent. Please try again later.'
                    : 'Registration is temporarily unavailable. Please try again later.',
            ], 503);
        }

        return response()->json(['message' => 'Verification code sent to your email.'], 201);
    }

    // POST /api/courier/otp/verify -> create user + profile, issue token
    public function verifyOtp(Request $request)
    {
        $request->validate(['email' => 'required|email', 'otp' => 'required|digits:6']);

        $key = $this->key($request->email);
        $pending = Cache::get($key);

        if (! $pending) {
            return response()->json(['message' => 'Code expired. Please register again.'], 422);
        }
        if ($pending['attempts'] >= 5) {
            Cache::forget($key);

            return response()->json(['message' => 'Too many attempts. Please register again.'], 429);
        }
        if (! Hash::check($request->otp, $pending['otp_hash'])) {
            $pending['attempts']++;
            Cache::put($key, $pending, now()->addMinutes(self::OTP_MINUTES));

            return response()->json(['message' => 'Invalid verification code.'], 422);
        }

        $d = $pending['data'];
        $local = Storage::disk('local');

        // Siguraduhing nandoon pa ang temp files bago gumawa ng user
        if (! $local->exists($d['or_cr_path']) || ! $local->exists($d['license_path'])) {
            Cache::forget($key);

            return response()->json(['message' => 'Uploaded files not found. Please register again.'], 422);
        }

        $user = DB::transaction(function () use ($d, $local) {
            $user = new User;
            $user->forceFill([
                'name' => trim($d['first_name'].' '.$d['last_name']),
                'email' => $d['email'],
                'password' => $d['password'],
                'role' => 'courier',
                'account_status' => 'active',
            ])->save();

            $final = "couriers/{$user->id}";
            $orCr = $final.'/'.basename($d['or_cr_path']);
            $license = $final.'/'.basename($d['license_path']);

            $r2 = Storage::disk('r2_private');
            $r2->put($orCr, $local->readStream($d['or_cr_path']));
            $r2->put($license, $local->readStream($d['license_path']));

            CourierProfile::create([
                'user_id' => $user->id,
                'logistics_profile_id' => $d['logistics_profile_id'],
                'last_name' => $d['last_name'],
                'first_name' => $d['first_name'],
                'middle_initial' => $d['middle_initial'] ?? null,
                'sex' => $d['sex'],
                'contact_no' => $d['contact_no'],
                'birthday' => $d['birthday'],
                'age' => Carbon::parse($d['birthday'])->age,
                'province' => $d['province'],
                'municipality' => $d['municipality'],
                'barangay' => $d['barangay'],
                'street_address' => $d['street_address'] ?? null,
                'vehicle_type' => $d['vehicle_type'],
                'plate_number' => $d['plate_number'],
                'or_cr_upload_path' => $orCr,
                'license_upload_path' => $license,
                'status' => 'pending',
                'is_active' => true,
            ]);

            return $user;
        });

        $local->deleteDirectory($d['dir']);
        Cache::forget($key);

        return response()->json([
            'token' => $user->createToken('rider-app')->plainTextToken,
            'courier_status' => 'pending',
            'message' => 'Registration submitted. Please wait for approval.',
        ], 201);
    }

    // POST /api/courier/otp/resend
    public function resendOtp(Request $request)
    {
        $request->validate(['email' => 'required|email']);

        $key = $this->key($request->email);
        $pending = Cache::get($key);

        if (! $pending) {
            return response()->json(['message' => 'No pending registration. Please register again.'], 422);
        }

        $otp = (string) random_int(100000, 999999);
        $pending['otp_hash'] = Hash::make($otp);
        $pending['attempts'] = 0;
        Cache::put($key, $pending, now()->addMinutes(self::OTP_MINUTES));

        $this->sendOtp($request->email, $otp);

        return response()->json(['message' => 'A new code was sent.']);
    }

    // POST /api/courier/login
    public function login(Request $request)
    {
        $data = $request->validate([
            'email' => 'required|email',
            'password' => 'required|string',
        ]);

        $user = User::whereRaw('lower(email) = ?', [strtolower(trim($data['email']))])
            ->where('role', 'courier')
            ->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            return response()->json(['message' => 'Incorrect email or password.'], 401);
        }

        if ($user->account_status !== 'active') {
            return response()->json(['message' => 'Your account has been deactivated.'], 403);
        }

        $profile = CourierProfile::where('user_id', $user->id)->first();

        if (! $profile) {
            return response()->json(['message' => 'This account has no courier profile.'], 403);
        }

        if ($profile->status === 'rejected') {
            return response()->json([
                'message' => 'Your registration was rejected.',
                'courier_status' => 'rejected',
                'reason' => $profile->rejection_reason,
            ], 403);
        }

        if (! $profile->is_active) {
            return response()->json(['message' => 'Your account has been deactivated.'], 403);
        }

        return response()->json([
            'token' => $user->createToken('rider-app')->plainTextToken,
            'courier_status' => $profile->status, // pending | approved
            'message' => $profile->status === 'pending'
                ? 'Waiting for approval.'
                : null,
        ]);
    }

    private function pwKey(string $email): string
    {
        return 'courier_pw:'.strtolower(trim($email));
    }

    // POST /api/courier/password/forgot -> send 6-digit code (same reply for any email)
    public function forgotPassword(Request $request)
    {
        $request->validate(['email' => 'required|email']);
        $email = strtolower(trim($request->email));

        $user = User::whereRaw('lower(email) = ?', [$email])->where('role', 'courier')->first();

        if ($user) {
            $otp = (string) random_int(100000, 999999);
            Cache::put($this->pwKey($email), [
                'otp_hash' => Hash::make($otp),
                'attempts' => 0,
                'token_hash' => null,
            ], now()->addMinutes(self::OTP_MINUTES));

            Mail::send(
                'emails.rider-reset',
                ['otp' => $otp, 'minutes' => self::OTP_MINUTES],
                fn ($m) => $m->to($email)->subject('Shopleap Rider password reset code')
            );
        }

        return response()->json(['message' => 'If the email is registered, a code has been sent.']);
    }

    // POST /api/courier/password/verify -> returns a one-time reset token
    public function verifyResetCode(Request $request)
    {
        $request->validate(['email' => 'required|email', 'otp' => 'required|digits:6']);
        $key = $this->pwKey($request->email);
        $pending = Cache::get($key);

        if (! $pending || $pending['attempts'] >= 5) {
            Cache::forget($key);

            return response()->json(['message' => 'Invalid or expired code.'], 422);
        }
        if (! Hash::check($request->otp, $pending['otp_hash'])) {
            $pending['attempts']++;
            Cache::put($key, $pending, now()->addMinutes(self::OTP_MINUTES));

            return response()->json(['message' => 'Invalid or expired code.'], 422);
        }

        $token = Str::random(40);
        $pending['otp_hash'] = Hash::make(Str::random(20));
        $pending['token_hash'] = Hash::make($token);
        Cache::put($key, $pending, now()->addMinutes(self::OTP_MINUTES));

        return response()->json(['reset_token' => $token]);
    }

    // POST /api/courier/reset-password (v4 style: email + otp + password sa isang hakbang)
    public function resetPasswordV4(Request $request)
    {
        $data = $request->validate([
            'email' => 'required|email',
            'otp' => 'required|digits:6',
            'password' => 'required|string|min:8|confirmed',
        ]);

        $email = strtolower(trim($data['email']));
        $key = $this->pwKey($email);
        $pending = Cache::get($key);

        if (! $pending || $pending['attempts'] >= 5) {
            Cache::forget($key);

            return response()->json(['message' => 'Invalid or expired code.'], 422);
        }
        if (! Hash::check($data['otp'], $pending['otp_hash'])) {
            $pending['attempts']++;
            Cache::put($key, $pending, now()->addMinutes(self::OTP_MINUTES));

            return response()->json(['message' => 'Invalid or expired code.'], 422);
        }

        $user = User::whereRaw('lower(email) = ?', [$email])->where('role', 'courier')->first();
        if (! $user) {
            Cache::forget($key);

            return response()->json(['message' => 'Invalid or expired code.'], 422);
        }

        $user->forceFill(['password' => Hash::make($data['password'])])->save();
        $user->tokens()->delete();
        Cache::forget($key);

        return response()->json(['message' => 'Password changed. Please sign in.']);
    }

    // POST /api/courier/password/reset
    public function resetPassword(Request $request)
    {
        $data = $request->validate([
            'email' => 'required|email',
            'reset_token' => 'required|string',
            'password' => 'required|string|min:8|confirmed',
        ]);

        $key = $this->pwKey($data['email']);
        $pending = Cache::get($key);

        if (! $pending || empty($pending['token_hash']) || ! Hash::check($data['reset_token'], $pending['token_hash'])) {
            return response()->json(['message' => 'Invalid or expired request. Please start again.'], 422);
        }

        $user = User::whereRaw('lower(email) = ?', [strtolower(trim($data['email']))])->where('role', 'courier')->first();
        if (! $user) {
            Cache::forget($key);

            return response()->json(['message' => 'Invalid or expired request. Please start again.'], 422);
        }

        $user->forceFill(['password' => Hash::make($data['password'])])->save();
        $user->tokens()->delete();
        Cache::forget($key);

        return response()->json(['message' => 'Password updated. You can now log in.']);
    }

    // GET /api/courier/me
    public function me(Request $request)
    {
        $user = $request->user();
        $profile = CourierProfile::where('user_id', $user->id)->firstOrFail();

        return response()->json([
            'user' => $user->only(['id', 'name', 'email']),
            'courier' => $profile->only([
                'first_name', 'last_name', 'contact_no', 'vehicle_type',
                'plate_number', 'status', 'is_active', 'rejection_reason',
            ]),
        ]);
    }

    // POST /api/courier/logout
    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Logged out.']);
    }
}
