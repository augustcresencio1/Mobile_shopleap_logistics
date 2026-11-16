<?php

namespace App\Services;

use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class CourierDeliveryProofService
{
    public function validate(Request $request): array
    {
        abort_if((int) $request->server('CONTENT_LENGTH', 0) > 6 * 1024 * 1024,
            413, 'The delivery upload is too large. Use a photo of at most 5 MB.');

        return $request->validate([
            'amount' => 'required|numeric|decimal:0,2|min:0|max:9999999999.99',
            'proof_image' => [
                'bail', 'required', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120',
                'dimensions:min_width=640,min_height=640',
                function ($attribute, $file, $fail) {
                    $size = @getimagesize($file->getRealPath());
                    if (! $size || $size[0] * $size[1] > 40000000) {
                        $fail('The proof photo must be at most 40 megapixels.');
                    }
                },
            ],
            'captured_at' => ['nullable', 'date', 'regex:/(Z|[+-]\d{2}:?\d{2})$/'],
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'notes' => 'nullable|string|max:255',
        ]);
    }

    public function store(UploadedFile $file): array
    {
        $stored = [
            'disk' => config('delivery_proofs.disk'),
            'path' => 'delivery_proofs/'.Str::uuid().'.'.$file->guessExtension(),
            'mime_type' => $file->getMimeType(),
            'size_bytes' => $file->getSize(),
        ];
        $stream = fopen($file->getRealPath(), 'rb');
        try {
            $written = Storage::disk($stored['disk'])->put($stored['path'], $stream, ['visibility' => 'private']);
            if (! $written) {
                throw new \RuntimeException('Proof storage did not complete.');
            }
        } catch (\Throwable $exception) {
            $this->delete($stored);
            if ($exception instanceof \TypeError) {
                throw $exception;
            }
            // Storage errors can contain private paths or request details.
            Log::warning('Delivery proof storage failed.', ['exception_type' => $exception::class]);
            abort(503, 'Unable to save the delivery photo. Your submission is saved in the app; please retry.');
        } finally {
            if (is_resource($stream)) {
                fclose($stream);
            }
        }

        return $stored;
    }

    public function delete(array $stored): void
    {
        try {
            if (! Storage::disk($stored['disk'])->delete($stored['path'])) {
                Log::warning('Delivery proof cleanup did not complete.');
            }
        } catch (\Throwable $exception) {
            Log::warning('Delivery proof cleanup failed.', ['exception_type' => $exception::class]);
        }
    }

    public static function metadata(bool $uploaded, ?string $capturedAt): array
    {
        return [
            'uploaded' => $uploaded,
            'captured_at' => $capturedAt === null ? null : Carbon::parse($capturedAt, 'UTC')->utc()->toIso8601String(),
        ];
    }
}
