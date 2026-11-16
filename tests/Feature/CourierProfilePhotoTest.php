<?php

namespace Tests\Feature;

use App\Models\CourierProfile;
use App\Models\User;
use Illuminate\Contracts\Filesystem\Filesystem;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CourierProfilePhotoTest extends TestCase
{
    private CourierProfile $courier;

    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'database.connections.sqlite.url' => null]);
        DB::purge('sqlite');
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            foreach (['name', 'email', 'password', 'role', 'account_status'] as $column) {
                $table->string($column);
            }
            $table->timestamps();
        });
        Schema::create('courier_profiles', function (Blueprint $table) {
            $table->id();
            $table->integer('user_id');
            $table->integer('logistics_profile_id');
            $table->string('status');
            $table->boolean('is_active');
            $table->string('profile_photo_path')->nullable();
            $table->timestamps();
        });
        Schema::create('logistics_profiles', function (Blueprint $table) {
            $table->id();
            $table->integer('user_id');
            $table->string('status');
        });
        foreach ([1 => 'courier', 2 => 'logistics'] as $id => $role) {
            User::forceCreate(['id' => $id, 'name' => 'Person '.$id, 'email' => $id.'@example.test',
                'password' => 'password', 'role' => $role, 'account_status' => 'active']);
        }
        DB::table('logistics_profiles')->insert(['id' => 20, 'user_id' => 2, 'status' => 'approved']);
        $this->courier = CourierProfile::create(['id' => 10, 'user_id' => 1, 'logistics_profile_id' => 20,
            'status' => 'approved', 'is_active' => true]);
        $disk = Storage::fake('r2_private');
        $disk->buildTemporaryUrlsUsing(fn ($path) => 'https://photos.example.test/'.$path.'?signature=synthetic');
    }

    private function photo(string $extension = 'jpg'): UploadedFile
    {
        return new UploadedFile(base_path('tests/Fixtures/delivery-proof.'.$extension),
            'profile.'.$extension, null, null, true);
    }

    public function test_photo_route_exists_and_requires_authentication(): void
    {
        $this->postJson('/api/courier/account/photo')->assertUnauthorized();
    }

    public function test_multipart_photo_is_saved_on_the_courier_and_returned_as_an_absolute_signed_url(): void
    {
        Sanctum::actingAs(User::findOrFail(1));
        Storage::disk('r2_private')->put('courier_photos/10/old.jpg', 'old');
        $this->courier->update(['profile_photo_path' => 'courier_photos/10/old.jpg']);

        $response = $this->postJson('/api/courier/account/photo', ['photo' => $this->photo()])
            ->assertOk()->assertJsonPath('message', 'Photo updated.')
            ->assertJsonPath('courier.id', 10)->assertJsonPath('user.id', 1)
            ->assertJsonMissingPath('courier.profile_photo_path');
        $path = $this->courier->fresh()->profile_photo_path;
        $this->assertStringStartsWith('courier_photos/10/', $path);
        $url = 'https://photos.example.test/'.$path.'?signature=synthetic';
        $response->assertJsonPath('courier.photo_url', $url);
        $this->assertSame(file_get_contents($this->photo()->getRealPath()), Storage::disk('r2_private')->get($path));
        Storage::disk('r2_private')->assertMissing('courier_photos/10/old.jpg');
        $this->getJson('/api/courier/me')->assertOk()->assertJsonPath('courier.photo_url', $url);
    }

    public function test_photo_validation_requires_the_correct_field_a_real_supported_image_and_at_most_five_mb(): void
    {
        Sanctum::actingAs(User::findOrFail(1));
        $oversized = UploadedFile::fake()->createWithContent('large.jpg', file_get_contents($this->photo()->getRealPath()))->size(5121);
        $invalid = UploadedFile::fake()->createWithContent('not-a-photo.jpg', 'not an image');
        foreach ([[], ['image' => $this->photo()],
            ['photo' => new UploadedFile($invalid->getRealPath(), 'not-a-photo.jpg', null, null, true)],
            ['photo' => UploadedFile::fake()->createWithContent('photo.gif', base64_decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'))],
            ['photo' => $oversized]] as $index => $body) {
            $response = $this->postJson('/api/courier/account/photo', $body);
            $this->assertSame(422, $response->status(), 'Invalid photo case '.$index);
            $response->assertJsonValidationErrors('photo');
        }
        $this->assertNull($this->courier->fresh()->profile_photo_path);
        $this->assertSame([], Storage::disk('r2_private')->allFiles());
    }

    public function test_webp_and_png_photos_are_accepted(): void
    {
        Sanctum::actingAs(User::findOrFail(1));
        $png = UploadedFile::fake()->createWithContent('profile.png', base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
        foreach ([$this->photo('webp'), $png] as $photo) {
            $this->postJson('/api/courier/account/photo', ['photo' => $photo])->assertOk()
                ->assertJsonPath('courier.id', 10);
        }
    }

    public function test_failed_storage_does_not_save_a_broken_photo_path_or_delete_the_old_photo(): void
    {
        Sanctum::actingAs(User::findOrFail(1));
        $this->courier->update(['profile_photo_path' => 'courier_photos/10/old.jpg']);
        $disk = \Mockery::mock(Filesystem::class);
        $disk->shouldReceive('put')->once()->withArgs(fn ($path, $stream, $options) => is_resource($stream)
            && $options['visibility'] === 'private')->andReturn(false);
        $disk->shouldNotReceive('delete');
        Storage::shouldReceive('disk')->with('r2_private')->andReturn($disk);
        $this->postJson('/api/courier/account/photo', ['photo' => $this->photo()])->assertStatus(503);
        $this->assertSame('courier_photos/10/old.jpg', $this->courier->fresh()->profile_photo_path);
    }
}
