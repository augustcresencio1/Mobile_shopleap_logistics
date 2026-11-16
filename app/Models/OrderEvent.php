<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** The notifications endpoint reads these events, rather than a notifications table. */
class OrderEvent extends Model
{
    protected $guarded = [];
}
