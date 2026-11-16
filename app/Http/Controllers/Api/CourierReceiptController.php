<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\CourierMoneyService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

class CourierReceiptController extends Controller
{
    public function show(Request $request, string $type, string $reference, CourierMoneyService $money): Response
    {
        return response()->view('courier.money_receipt', $money->receipt(
            $request->attributes->get('courier_profile'), $type, $reference
        ))->header('Cache-Control', 'private, no-store')->header('X-Robots-Tag', 'noindex, nofollow');
    }
}
