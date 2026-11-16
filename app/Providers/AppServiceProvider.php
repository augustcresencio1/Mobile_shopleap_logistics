<?php

namespace App\Providers;

use App\Mail\ResendHttpTransport;
use App\Models\Message;
use App\Models\Order;
use App\Models\OrderEvent;
use App\Observers\MessageObserver;
use App\Observers\OrderEventObserver;
use App\Observers\OrderObserver;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Mail::extend('resend_http', fn () => new ResendHttpTransport(
            (string) config('services.resend.key', '')
        ));
        Order::observe(OrderObserver::class);
        Message::observe(MessageObserver::class);
        OrderEvent::observe(OrderEventObserver::class);
    }
}
