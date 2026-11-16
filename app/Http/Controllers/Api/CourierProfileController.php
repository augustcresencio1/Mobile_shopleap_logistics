<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CourierProfile;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class CourierProfileController extends Controller
{
    private function profile(Request $r): CourierProfile
    {
        return $r->attributes->get('courier_profile')
            ?? CourierProfile::where('user_id', $r->user()->id)->firstOrFail();
    }

    private function photoUrl(CourierProfile $p): ?string
    {
        $path = $p->profile_photo_path ?? null;
        if (! $path) {
            return null;
        }

        try {
            return Storage::disk('r2_private')->temporaryUrl($path, now()->addHours(6));
        } catch (\Throwable $e) {
            report($e);

            return null;
        }
    }

    private function payload(Request $r, CourierProfile $p): array
    {
        $user = $r->user();

        $courier = $p->makeHidden(['profile_photo_path'])->toArray();
        $courier['name'] = $user->name;
        $courier['photo_url'] = $this->photoUrl($p);

        return [
            'user' => $user->only(['id', 'name', 'email']),
            'email' => $user->email,
            'name' => $user->name,
            'courier_status' => $p->status,
            'courier' => $courier,
        ];
    }

    // GET /api/courier/me
    public function show(Request $r)
    {
        return response()->json($this->payload($r, $this->profile($r)));
    }

    // POST /api/courier/account/profile
    public function update(Request $r)
    {
        $user = $r->user();
        $p = $this->profile($r);

        if ($r->has('email')) {
            $r->merge(['email' => Str::lower(trim((string) $r->input('email')))]);
        }

        $data = $r->validate([
            'first_name' => 'sometimes|string|min:2|max:60',
            'last_name' => 'sometimes|string|min:2|max:60',
            'email' => ['sometimes', 'email:rfc', 'max:255', Rule::unique('users', 'email')->ignore($user->id)],
            'contact_no' => ['sometimes', 'regex:/^09\d{9}$/'],
            'vehicle_type' => 'sometimes|in:Trike,Motor,Van',
            'plate_number' => 'sometimes|string|max:20',
            'province' => 'sometimes|string|max:100',
            'municipality' => 'sometimes|string|max:100',
            'barangay' => 'sometimes|string|max:100',
            'street_address' => 'sometimes|nullable|string|max:255',
        ]);

        DB::transaction(function () use ($data, $user, $p) {
            $profileData = Arr::only($data, [
                'first_name', 'last_name', 'contact_no', 'vehicle_type',
                'plate_number', 'barangay', 'street_address',
                'province', 'municipality',
            ]);
            if ($profileData) {
                $p->update($profileData);
            }
            $p->refresh();

            $userData = [];
            if (isset($data['email'])) {
                $userData['email'] = $data['email'];
            }
            if (isset($data['first_name']) || isset($data['last_name'])) {
                $userData['name'] = trim($p->first_name.' '.$p->last_name);
            }
            if ($userData) {
                $user->forceFill($userData)->save();
            }
        });

        return response()->json(array_merge(
            ['message' => 'Updated.'],
            $this->payload($r, $p->fresh())
        ));
    }

    // POST /api/courier/account/photo  (multipart, field: photo)
    public function uploadPhoto(Request $r)
    {
        if (! Schema::hasColumn('courier_profiles', 'profile_photo_path')) {
            return response()->json(['message' => 'Profile photo is not available yet.'], 503);
        }

        $field = ! $r->hasFile('photo') && $r->hasFile('avatar') ? 'avatar' : 'photo';
        $r->validate([
            $field => 'required|image|mimes:jpg,jpeg,png,webp|max:5120',
        ]);

        $p = $this->profile($r);
        $file = $r->file($field);
        $ext = strtolower($file->guessExtension() ?: 'jpg');
        $path = 'courier_photos/'.$p->id.'/'.Str::uuid().'.'.$ext;

        $disk = Storage::disk('r2_private');
        $stream = fopen($file->getRealPath(), 'r');
        abort_unless(is_resource($stream), 503, 'Unable to read the profile photo. Please try again.');
        try {
            $stored = $disk->put($path, $stream, ['visibility' => 'private']);
        } finally {
            fclose($stream);
        }
        abort_unless($stored, 503, 'Unable to save the profile photo. Please try again.');

        $old = $p->profile_photo_path;
        $p->forceFill(['profile_photo_path' => $path])->save();

        if ($old && $old !== $path) {
            try {
                $disk->delete($old);
            } catch (\Throwable $e) {
                report($e);
            }
        }

        return response()->json(array_merge(
            ['message' => 'Photo updated.'],
            $this->payload($r, $p->fresh())
        ));
    }

    public function removePhoto(Request $r)
    {
        if (! Schema::hasColumn('courier_profiles', 'profile_photo_path')) {
            return response()->json(['message' => 'Profile photo is not available yet.'], 503);
        }
        $profile = $this->profile($r);
        $old = $profile->profile_photo_path;
        $profile->forceFill(['profile_photo_path' => null])->save();
        if ($old) {
            try {
                Storage::disk('r2_private')->delete($old);
            } catch (\Throwable $exception) {
                report($exception);
            }
        }

        return response()->json(array_merge(
            ['message' => 'Photo removed.'], $this->payload($r, $profile->fresh())
        ));
    }
}
