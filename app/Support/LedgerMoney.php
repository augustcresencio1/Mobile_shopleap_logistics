<?php

namespace App\Support;

use InvalidArgumentException;

/** Exact money conversion from Shopleap-Web-App's LedgerService. */
class LedgerMoney
{
    public static function cents(string|int $amount): int
    {
        if (! preg_match('/^(-?)(\d{1,16})(?:\.(\d{1,2}))?$/D', (string) $amount, $match)) {
            throw new InvalidArgumentException('Money must have at most two fractional digits.');
        }

        return ($match[1] === '-' ? -1 : 1) * ((int) $match[2] * 100 + (int) str_pad($match[3] ?? '', 2, '0'));
    }

    public static function decimal(int $cents): string
    {
        return ($cents < 0 ? '-' : '').intdiv(abs($cents), 100).'.'.str_pad((string) (abs($cents) % 100), 2, '0', STR_PAD_LEFT);
    }

    public static function peso(string $amount): string
    {
        $cents = self::cents($amount);

        return ($cents < 0 ? '-₱' : '₱').number_format(intdiv(abs($cents), 100), 0, '.', ',').'.'.str_pad((string) (abs($cents) % 100), 2, '0', STR_PAD_LEFT);
    }
}
