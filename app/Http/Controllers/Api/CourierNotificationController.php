<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Support\OrderCodes;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Schema;

class CourierNotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $request->validate(['page' => 'sometimes|integer|min:1']);
        abort_unless(Schema::hasTable('notifications'), 503, 'Notifications are not available on this server yet.');
        $user = $request->user();
        $unreadOnly = $request->query('filter') === 'unread';

        $page = ($unreadOnly ? $user->unreadNotifications() : $user->notifications())->paginate(20);

        OrderCodes::presentNotifications($page->getCollection());

        return response()->json([
            'unread' => $user->unreadNotifications()->count(),
            'data' => $page->getCollection()->map(fn ($n) => [
                'id' => $n->id,
                'kind' => $n->data['kind'] ?? '',
                'title' => $n->data['title'] ?? 'Update',
                'body' => $n->data['body'] ?? '',
                'url' => $n->data['url'] ?? null,
                'meta' => $n->data['meta'] ?? [],      // order_id etc., for opening the right screen
                'read' => $n->read_at !== null,
                'created_at' => $n->created_at->toIso8601String(),
            ])->values(),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage()],
        ]);
    }

    public function read(Request $request, string $id): JsonResponse
    {
        abort_unless(Schema::hasTable('notifications'), 503, 'Notifications are not available on this server yet.');
        $request->user()->notifications()->whereKey($id)->firstOrFail()->markAsRead();

        return response()->json(['unread' => $request->user()->unreadNotifications()->count()]);
    }

    public function readAll(Request $request): JsonResponse
    {
        abort_unless(Schema::hasTable('notifications'), 503, 'Notifications are not available on this server yet.');
        $request->user()->unreadNotifications->markAsRead();

        return response()->json(['unread' => 0]);
    }
}
