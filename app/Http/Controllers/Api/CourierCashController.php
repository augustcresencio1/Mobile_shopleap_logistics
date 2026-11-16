<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\CourierMoneyService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CourierCashController extends Controller
{
    public function summary(Request $request, CourierMoneyService $money): JsonResponse
    {
        return response()->json($money->cashSummary($request->attributes->get('courier_profile')->id));
    }

    public function history(Request $request, CourierMoneyService $money): JsonResponse
    {
        $request->validate(['page' => 'sometimes|integer|min:1']);

        return response()->json($money->cashHistory($request->attributes->get('courier_profile')->id));
    }
}
