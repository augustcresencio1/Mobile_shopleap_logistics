<?php

namespace App\Support;

/** Select a stored reference or legacy internal ID without guessing a new ID. */
class CourierScanCode
{
    /** @return array{column: string, value: int|string}|null */
    public static function parse(string $raw): ?array
    {
        $code = trim($raw);
        if ($code === '' || strlen($code) > 256) {
            return null;
        }
        if (preg_match('/^SHOPLEAP:ORDER:(.+)$/i', $code, $matches)) {
            $code = trim($matches[1]);
        }
        // QR payloads / order links: use the last part of the URL path
        // (e.g. https://shopleap.shop/track/SL-PZ7NKDPW -> SL-PZ7NKDPW).
        if (preg_match('~^https?://~i', $code)) {
            $code = urldecode(basename(rtrim((string) parse_url($code, PHP_URL_PATH), '/')));
        }

        // Older printed format: prefix + 14 characters, no hyphen.
        if (preg_match('/^(WB|SL)[A-Z0-9]{14}$/i', $code, $matches)) {
            return ['column' => strtoupper($matches[1]) === 'WB' ? 'waybill_code' : 'order_number',
                'value' => strtoupper($code)];
        }
        // Current format: WB-HEJ22FP3JJ (waybill) and SL-PZ7NKDPW (order).
        // The hyphen is optional on input; the stored value always has it.
        if (preg_match('/^(WB|SL)-?([A-Z0-9]{6,20})$/i', $code, $matches)) {
            $prefix = strtoupper($matches[1]);

            return ['column' => $prefix === 'WB' ? 'waybill_code' : 'order_number',
                'value' => $prefix.'-'.strtoupper($matches[2])];
        }

        // Preserve old printed numeric labels.
        if (! preg_match('/^(?:SL-ORDER-)?([0-9]+)$/i', $code, $matches)) {
            return null;
        }
        $id = filter_var(ltrim($matches[1], '0') ?: '0', FILTER_VALIDATE_INT,
            ['options' => ['min_range' => 1]]);

        return $id === false ? null : ['column' => 'id', 'value' => $id];
    }
}