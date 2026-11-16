/** Read the hub's authorized rider locations; wire onUpdate to the web's UI/map. */
export function createRiderLocationPoller({
    apiBaseUrl = '/api', getToken, onUpdate, onError = () => {},
    fetchImpl = globalThis.fetch, intervalMs = 5000,
}) {
    let running = false, timer, controller, lastGood, generation = 0;
    const visible = () => typeof document === 'undefined' || !document.hidden;
    const schedule = () => {
        clearTimeout(timer);
        if (running && visible()) timer = setTimeout(poll, intervalMs);
    };

    async function poll() {
        if (!running || !visible() || controller) return;
        clearTimeout(timer);
        const version = generation;
        const request = new AbortController();
        let timedOut = false;
        const timeout = setTimeout(() => { timedOut = true; request.abort(); }, 10000);
        controller = request;
        try {
            const token = await getToken();
            if (!running || version !== generation) return;
            if (!token) throw Object.assign(new Error('Hub sign-in is required.'), { status: 401 });
            const riders = new Map();
            let page = 1, lastPage = 1, serverTime;
            do {
                const response = await fetchImpl(`${apiBaseUrl.replace(/\/$/, '')}/logistics/rider-locations?per_page=100&page=${page}`, {
                    headers: { Accept: 'application/json', Authorization: `Bearer ${token}` },
                    cache: 'no-store', credentials: 'omit', signal: request.signal,
                });
                if (!response.ok) throw Object.assign(new Error(`Cannot load live riders (${response.status}).`), { status: response.status });
                const body = await response.json();
                if (!running || version !== generation) return;
                if (!Array.isArray(body.data)) throw new Error('Unexpected rider location response.');
                for (const rider of body.data) riders.set(rider.courier_id, rider);
                serverTime = body.server_time;
                lastPage = body.meta?.last_page ?? 1;
                page++;
            } while (page <= lastPage);
            lastGood = { data: [...riders.values()], server_time: serverTime };
            onUpdate(lastGood);
        } catch (error) {
            if (!running || version !== generation || (error.name === 'AbortError' && !timedOut)) return;
            if (lastGood) onUpdate({ ...lastGood, data: lastGood.data.map(rider => ({
                ...rider, status: rider.status === 'live' ? 'stale' : rider.status,
            })) });
            if (error.status === 401 || error.status === 403) stop();
            onError(error);
        } finally {
            clearTimeout(timeout);
            if (controller === request) controller = undefined;
            if (version === generation) schedule();
        }
    }

    function onVisibility() {
        clearTimeout(timer);
        if (visible()) poll();
    }

    function start() {
        if (running) return;
        running = true;
        generation++;
        if (typeof document !== 'undefined') document.addEventListener('visibilitychange', onVisibility);
        poll();
    }

    function stop() {
        running = false;
        generation++;
        clearTimeout(timer);
        controller?.abort();
        controller = undefined;
        lastGood = undefined;
        if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVisibility);
    }

    return { start, stop, refresh: poll };
}
