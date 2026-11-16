<?php

namespace App\Observers;

use App\Models\Message;
use App\Services\RiderRefresh;

class MessageObserver
{
    public function saved(Message $message): void
    {
        RiderRefresh::conversations([
            $message->conversation_id,
            $message->getOriginal('conversation_id'),
        ]);
    }

    public function deleted(Message $message): void
    {
        $this->saved($message);
    }
}
