<?php

namespace App\Console\Commands;

use App\Services\RiderRealtime;
use Illuminate\Console\Command;
use Illuminate\Http\Client\RequestException;

class RiderRealtimeTest extends Command
{
    protected $signature = 'rider:realtime-test {courierProfileId}';

    protected $description = 'Send a rider refresh and print only its HTTP status (no credentials)';

    public function handle(): int
    {
        $id = filter_var($this->argument('courierProfileId'), FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
        if ($id === false) {
            $this->error('courierProfileId must be a positive CourierProfile id, not a user id.');

            return self::FAILURE;
        }

        try {
            $response = RiderRealtime::broadcast($id);
            if ($response === null) {
                $this->error('Missing SUPABASE_URL or SUPABASE_SERVICE_KEY. Set them in your own .env and clear config.');

                return self::FAILURE;
            }
            $this->info('HTTP '.$response->status().' - broadcast accepted for rider:'.$id);

            return self::SUCCESS;
        } catch (RequestException $exception) {
            $status = $exception->response->status();
            $this->error('HTTP '.$status.(in_array($status, [401, 403], true)
                ? ' - authorization rejected; check the backend service_role key and project URL.'
                : ' - broadcast rejected.'));
        } catch (\Throwable $exception) {
            // Exception messages/response bodies can contain secrets; never print them.
            $this->error('Broadcast failed before an HTTP response was received. Check connectivity and the project URL.');
        }

        return self::FAILURE;
    }
}
