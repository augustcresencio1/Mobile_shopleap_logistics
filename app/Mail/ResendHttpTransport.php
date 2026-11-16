<?php

namespace App\Mail;

use Illuminate\Support\Facades\Http;
use Symfony\Component\Mailer\Exception\TransportException;
use Symfony\Component\Mailer\SentMessage;
use Symfony\Component\Mailer\Transport\AbstractTransport;
use Symfony\Component\Mime\Address;
use Symfony\Component\Mime\MessageConverter;

/** HTTPS delivery for the rider's OTP/password emails on Render Free. */
class ResendHttpTransport extends AbstractTransport
{
    public function __construct(private readonly string $apiKey)
    {
        parent::__construct();
    }

    protected function doSend(SentMessage $message): void
    {
        if (trim($this->apiKey) === '') {
            throw new TransportException('The HTTPS email provider is not configured.');
        }
        $email = MessageConverter::toEmail($message->getOriginalMessage());
        if ($email->getAttachments()) {
            throw new TransportException('The rider HTTPS email transport does not support attachments.');
        }
        $addresses = fn (array $list) => array_map(fn (Address $address) => $address->toString(), $list);
        $payload = array_filter([
            'from' => $message->getEnvelope()->getSender()->toString(),
            'to' => $addresses($email->getTo()),
            'cc' => $addresses($email->getCc()),
            'bcc' => $addresses($email->getBcc()),
            'reply_to' => $addresses($email->getReplyTo()),
            'subject' => $email->getSubject(),
            'html' => $email->getHtmlBody(),
            'text' => $email->getTextBody(),
        ], fn ($value) => $value !== null && $value !== []);

        try {
            // Do not replay sends or forward the bearer key through redirects.
            $response = Http::withToken($this->apiKey)->acceptJson()
                ->withoutRedirecting()->connectTimeout(5)->timeout(15)
                ->post('https://api.resend.com/emails', $payload);
        } catch (\Throwable) {
            throw new TransportException('The HTTPS email provider could not be reached.');
        }
        if (! $response->successful() || ! is_string($response->json('id')) || trim($response->json('id')) === '') {
            // Provider bodies can contain addresses, request data, or credentials.
            throw new TransportException('The HTTPS email provider did not accept the email.');
        }
    }

    public function __toString(): string
    {
        return 'resend_http';
    }
}
