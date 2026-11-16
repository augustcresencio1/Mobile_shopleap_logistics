<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasColumn('courier_profiles', 'profile_photo_path')) {
            Schema::table('courier_profiles', function (Blueprint $table) {
                $table->string('profile_photo_path', 255)->nullable();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('courier_profiles', 'profile_photo_path')) {
            Schema::table('courier_profiles', function (Blueprint $table) {
                $table->dropColumn('profile_photo_path');
            });
        }
    }
};