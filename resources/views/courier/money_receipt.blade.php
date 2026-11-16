<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $title }} · {{ $reference }}</title>
    <style>
        body { margin: 0; padding: 20px; background: #f3f6fa; color: #17283f; font: 16px system-ui, sans-serif; }
        main { max-width: 680px; margin: auto; padding: 24px; border-radius: 16px; background: white; }
        h1 { font-size: 24px; } h2 { margin-top: 28px; font-size: 18px; } .brand { color: #1b5bb8; font-weight: 700; }
        dl div { padding: 10px 0; border-bottom: 1px solid #e4eaf2; } dt { color: #54657b; } dd { margin: 4px 0 0; overflow-wrap: anywhere; }
        .amount { font-size: 32px; font-weight: 700; } table { width: 100%; border-collapse: collapse; } th, td { padding: 10px; text-align: left; border-bottom: 1px solid #e4eaf2; }
        .note { color: #54657b; font-size: 14px; margin-top: 24px; } @media print { body { background: white; padding: 0; } }
    </style>
</head>
<body>
<main>
    <p class="brand">Shopleap</p>
    <h1>{{ $title }}</h1>
    <dl>
        <div><dt>Reference number</dt><dd>{{ $reference }}</dd></div>
        <div><dt>Record date and time</dt><dd>{{ $date }}</dd></div>
        <div><dt>From</dt><dd>{{ $from }}</dd></div>
        <div><dt>To</dt><dd>{{ $to }}</dd></div>
        <div><dt>Status</dt><dd>{{ ucfirst($status) }}</dd></div>
    </dl>
    <h2>Amount (PHP)</h2><p class="amount">{{ \App\Support\LedgerMoney::peso($amount) }}</p>
    <dl>@foreach ($details as $label => $value)<div><dt>{{ $label }}</dt><dd>{{ $value }}</dd></div>@endforeach</dl>
    @if ($items->isNotEmpty())
        <h2>Parcels covered</h2>
        <table><thead><tr><th>Order number</th><th>Amount (PHP)</th></tr></thead><tbody>
        @foreach ($items as $item)<tr><td>{{ $item->order_number }}</td><td>{{ \App\Support\LedgerMoney::peso((string) $item->amount) }}</td></tr>@endforeach
        </tbody></table>
    @endif
    <h2>Status history</h2><dl>@foreach ($timeline as $label => $timestamp)<div><dt>{{ $label }}</dt><dd>{{ $timestamp }}</dd></div>@endforeach</dl>
    <p class="note">This document reflects the recorded status above. Pending, processing, disputed, cancelled and rejected records do not confirm payment receipt.</p>
</main>
</body>
</html>
