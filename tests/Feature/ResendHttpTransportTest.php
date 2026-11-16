<?php

namespace Tests\Feature;

use App\Mail\ResendHttpTransport;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Mail;
use Symfony\Component\Mailer\Exception\TransportException;
use Symfony\Component\Mime\Email;
use Tests\TestCase;

class ResendHttpTransportTest extends TestCase
{
    public function test_configured_mailer_sends_otp_via_https_without_following_redirects(): void
    {
        config(['mail.default' => 'resend_http', 'services.resend.key' => 'synthetic-test-key',
            'mail.from.address' => 'rider@example.test', 'mail.from.name' => 'Shopleap']);
        Http::fake(['https://api.resend.com/emails' => Http::response(['id' => 'test-email-id'])]);
        Mail::send('emails.rider-otp', ['otp' => '123456', 'minutes' => 10],
            fn ($message) => $message->to('recipient@example.test')->subject('Rider verification'));

        Http::assertSent(fn ($request) => $request->url() === 'https://api.resend.com/emails'
            && $request->hasHeader('Authorization', 'Bearer synthetic-test-key')
            && $request['to'] === ['recipient@example.test']
            && str_contains($request['html'], '123456'));
        Http::assertSentCount(1);
    }

    public function test_missing_provider_key_fails_without_sending_a_request(): void
    {
        Http::fake();
        try {
            (new ResendHttpTransport(''))->send($this->email());
            $this->fail('A missing provider key must not report delivery.');
        } catch (TransportException $exception) {
            $this->assertStringContainsString('not configured', $exception->getMessage());
        }
        Http::assertNothingSent();
    }

    public function test_provider_failures_are_sanitized_and_never_retried(): void
    {
        foreach ([302, 422, 429, 503, 200] as $status) {
            Http::fake(['https://api.resend.com/emails' => Http::response(['message' => 'private provider data'], $status)]);
            try {
                (new ResendHttpTransport('synthetic-test-key'))->send($this->email());
                $this->fail('An unconfirmed send must fail.');
            } catch (TransportException $exception) {
                $this->assertStringNotContainsString('private', $exception->getMessage());
                $this->assertStringNotContainsString('synthetic', $exception->getMessage());
            }
            Http::assertSentCount(1);
        }
    }

    private function email(): Email
    {
        return (new Email)->from('sender@example.test')->to('recipient@example.test')
            ->subject('Verification')->text('123456');
    }
}
