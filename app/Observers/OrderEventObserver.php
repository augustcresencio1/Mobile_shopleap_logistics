<?php

namespace App\Observers;

use App\Models\OrderEvent;
use App\Services\RiderRefresh;

class OrderEventObserver
{
    public function saved(OrderEvent $event): void
    {
        RiderRefresh::orders([$event->order_id, $event->getOriginal('order_id')]);
    }

    public function deleted(OrderEvent $event): void
    {
        $this->saved($event);
    }
}
