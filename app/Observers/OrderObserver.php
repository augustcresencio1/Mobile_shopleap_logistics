<?php

namespace App\Observers;

use App\Models\Order;
use App\Services\RiderRefresh;

class OrderObserver
{
    public function saved(Order $order): void
    {
        // Capture originals now: Eloquent syncs them before afterCommit runs.
        $ids = [];
        foreach (['pickup_rider_id', 'delivery_rider_id', 'earning_courier_id'] as $column) {
            $ids[] = $order->getAttribute($column);
            $ids[] = $order->getOriginal($column);
        }
        RiderRefresh::riders($ids);
    }

    public function deleted(Order $order): void
    {
        $this->saved($order);
    }
}
