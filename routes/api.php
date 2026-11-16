<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CourierAuthController;
use App\Http\Controllers\Api\CourierDeliveryController;
use App\Http\Controllers\Api\CourierEarningsController;
use App\Http\Controllers\Api\CourierProfileController;
use App\Http\Controllers\Api\RiderNavigationController;
use App\Http\Controllers\Api\RiderTrackingController;
use Illuminate\Support\Facades\Route;

// ---------- Login ----------
Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:5,1');

// ---------- Courier / Rider ----------
Route::prefix('courier')->group(function () {
    Route::get('hubs', [CourierAuthController::class, 'hubs']); // dagdag
    Route::post('register', [CourierAuthController::class, 'register'])->middleware('throttle:10,1');
    Route::post('otp/verify', [CourierAuthController::class, 'verifyOtp'])->middleware('throttle:10,1');
    Route::post('otp/resend', [CourierAuthController::class, 'resendOtp'])->middleware('throttle:5,1');
    Route::post('login', [CourierAuthController::class, 'login'])->middleware('throttle:5,1');
    Route::post('password/forgot', [CourierAuthController::class, 'forgotPassword'])->middleware('throttle:5,1');
    Route::post('password/verify', [CourierAuthController::class, 'verifyResetCode'])->middleware('throttle:10,1');
    Route::post('password/reset', [CourierAuthController::class, 'resetPassword'])->middleware('throttle:5,1');
    // v4-style paths (ginagamit ng app kapag useV4 = true)
    Route::post('forgot-password', [CourierAuthController::class, 'forgotPassword'])->middleware('throttle:5,1');
    Route::post('reset-password', [CourierAuthController::class, 'resetPasswordV4'])->middleware('throttle:5,1');
});

Route::middleware(['auth:sanctum', 'role:courier'])->prefix('courier')->group(function () {
    Route::get('me', [CourierProfileController::class, 'show']);
    Route::post('logout', [CourierAuthController::class, 'logout']);

    Route::middleware('courier.approved')->group(function () {
        // BAGO: lahat ng kailangan ng Home tab at ng bell sa iisang request
        Route::get('home', [CourierDeliveryController::class, 'home']);
        Route::get('dashboard', [CourierEarningsController::class, 'dashboard']);

        Route::get('pickup-requests', [CourierDeliveryController::class, 'pickupRequests']);
        Route::get('pickups', [CourierDeliveryController::class, 'pickups']);
        Route::get('deliveries', [CourierDeliveryController::class, 'deliveries']);
        Route::get('navigation/route', [RiderNavigationController::class, 'route']);
        Route::post('orders/{id}/arrived', [RiderNavigationController::class, 'arrived']);
        Route::post('tracking/start', [RiderTrackingController::class, 'start'])->middleware('throttle:30,1');
        Route::put('tracking/location', [RiderTrackingController::class, 'update'])->middleware('throttle:30,1');
        Route::post('tracking/stop', [RiderTrackingController::class, 'stop'])->middleware('throttle:30,1');
        Route::get('notifications', [CourierDeliveryController::class, 'notifications']);
        // Accept WB-/SL- references and legacy IDs, plus encoded QR URLs containing slashes.
        Route::get('orders/scan/{code}', [CourierDeliveryController::class, 'scan'])->where('code', '.*');

        Route::post('orders/{id}/pickup/accept', [CourierDeliveryController::class, 'acceptPickup']);
        Route::post('orders/{id}/pickup/decline', [CourierDeliveryController::class, 'declinePickup']);
        Route::post('orders/{id}/pickup', [CourierDeliveryController::class, 'pickup']);
        // Public courier actions use order_number; legacy orders/{id} routes remain available.
        Route::post('pickups/{orderNumber}/accept', [CourierDeliveryController::class, 'acceptPickupOrder']);
        Route::post('pickups/{orderNumber}/decline', [CourierDeliveryController::class, 'declinePickupOrder']);
        Route::post('pickups/{orderNumber}/confirm', [CourierDeliveryController::class, 'confirmPickupOrder']);

        Route::post('orders/{id}/start-delivery', [CourierDeliveryController::class, 'startDelivery']);
        Route::post('orders/{id}/deliver', [CourierDeliveryController::class, 'deliver']);
        Route::post('deliveries/{orderNumber}/out', [CourierDeliveryController::class, 'outForDelivery']);
        Route::post('deliveries/{orderNumber}/delivered', [CourierDeliveryController::class, 'delivered']);
        Route::post('deliveries/{orderNumber}/failed', [CourierDeliveryController::class, 'failDeliveryOrder']);
        Route::post('orders/{id}/fail', [CourierDeliveryController::class, 'failDelivery']);

        Route::get('history', [CourierDeliveryController::class, 'history']);
        Route::get('earnings/rate', [CourierEarningsController::class, 'rate']);
        Route::get('earnings/overview', [CourierEarningsController::class, 'overview']);
        Route::get('earnings/summary', [CourierEarningsController::class, 'show']);
        Route::get('earnings/history', [CourierEarningsController::class, 'history']);
        // Backwards-compatible alias for the same saved-earnings summary.
        Route::get('earnings', [CourierEarningsController::class, 'show']);

        // BAGO: listahan ng chat threads
        Route::get('chats', [CourierDeliveryController::class, 'chats']);

        Route::get('orders/{id}/messages', [CourierDeliveryController::class, 'messages']);
        Route::post('orders/{id}/messages', [CourierDeliveryController::class, 'sendMessage']);

        Route::get('account', [CourierDeliveryController::class, 'account']);
        Route::put('account', [CourierDeliveryController::class, 'updateAccount']);
        Route::post('account/password', [CourierDeliveryController::class, 'changePassword'])
            ->middleware('throttle:5,1');

        Route::post('account/profile', [CourierProfileController::class, 'update'])
            ->middleware('throttle:20,1');
        Route::post('account/photo', [CourierProfileController::class, 'uploadPhoto'])
            ->middleware('throttle:10,1');
    });
});
Route::get('/hubs', [CourierAuthController::class, 'hubs']);

Route::middleware(['auth:sanctum', 'role:logistics'])->get('logistics/rider-locations', [RiderTrackingController::class, 'index']);

Route::post('/courier/verify-otp', [CourierAuthController::class, 'verifyOtp']);
Route::post('/courier/resend-otp', [CourierAuthController::class, 'resendOtp']);
