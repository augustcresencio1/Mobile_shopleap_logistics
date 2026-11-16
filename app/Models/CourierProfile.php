<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CourierProfile extends Model
{
    protected $table = 'courier_profiles';

    protected $guarded = [];

    // Huwag ilabas ang storage keys ng ID documents sa JSON.
    // Gumagana pa rin ang $courier->or_cr_upload_path sa loob ng PHP.
    protected $hidden = [
        'or_cr_upload_path',
        'license_upload_path',
    ];

    protected function casts(): array
    {
        return [
            'birthday' => 'date:Y-m-d',
            'is_active' => 'boolean',
            'reviewed_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}