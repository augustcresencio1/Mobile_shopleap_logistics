import test from 'node:test';
import assert from 'node:assert/strict';
import { setImmediate } from 'node:timers/promises';
import { createRiderLocationPoller } from '../../resources/js/rider-location-poller.js';

const body = (id = 100, lastPage = 1) => ({
    data: [{ courier_id: id, status: 'live', location: { latitude: 14.6, longitude: 120.98 } }],
    meta: { last_page: lastPage }, server_time: '2026-11-08T04:00:00Z',
});
const response = value => ({ ok: true, json: async () => value });

test('authenticated polling reads all pages and combines riders', async () => {
    const ready = Promise.withResolvers();
    const urls = [];
    const locations = createRiderLocationPoller({
        getToken: () => 'hub-token', onUpdate: ready.resolve,
        fetchImpl: async (url, options) => {
            urls.push(url);
            assert.equal(options.headers.Authorization, 'Bearer hub-token');
            assert.equal(options.cache, 'no-store');
            return response(body(urls.length === 1 ? 100 : 200, 2));
        },
    });
    locations.start();
    try {
        const result = await ready.promise;
        assert.deepEqual(result.data.map(rider => rider.courier_id), [100, 200]);
        assert.equal(urls.length, 2);
        assert.match(urls[1], /page=2$/);
    } finally { locations.stop(); }
});

test('requests cannot overlap and disposal ignores a delayed response', async () => {
    const pending = Promise.withResolvers();
    let requests = 0, updates = 0;
    const locations = createRiderLocationPoller({
        getToken: () => 'token', onUpdate: () => updates++,
        fetchImpl: async () => { requests++; return pending.promise; },
    });
    locations.start();
    await setImmediate();
    await locations.refresh();
    assert.equal(requests, 1);
    locations.stop();
    pending.resolve(response(body()));
    await setImmediate();
    assert.equal(updates, 0);
});

test('failed refresh marks previous locations stale and keeps retry available', async () => {
    const ready = Promise.withResolvers();
    const updates = [], errors = [];
    let requests = 0;
    const locations = createRiderLocationPoller({
        getToken: () => 'token',
        onUpdate: value => { updates.push(value); ready.resolve(); },
        onError: error => errors.push(error),
        fetchImpl: async () => ++requests === 1 ? response(body()) : { ok: false, status: 503 },
    });
    locations.start();
    try {
        await ready.promise;
        await locations.refresh();
        assert.equal(updates.at(-1).data[0].status, 'stale');
        assert.equal(errors[0].status, 503);
        await locations.refresh();
        assert.equal(requests, 3);
    } finally { locations.stop(); }
});

test('an unauthorized dashboard stops polling', async () => {
    const failed = Promise.withResolvers();
    let requests = 0;
    const locations = createRiderLocationPoller({
        getToken: () => 'expired-token', onUpdate: () => assert.fail('Unauthorized data'),
        onError: failed.resolve,
        fetchImpl: async () => { requests++; return { ok: false, status: 401 }; },
    });
    locations.start();
    assert.equal((await failed.promise).status, 401);
    await locations.refresh();
    assert.equal(requests, 1);
    locations.stop();
});

test('restarting after logout never reuses another hubs last location', async () => {
    const ready = Promise.withResolvers();
    const failed = Promise.withResolvers();
    let requests = 0, updates = 0;
    const locations = createRiderLocationPoller({
        getToken: () => 'token',
        onUpdate: () => { updates++; ready.resolve(); }, onError: failed.resolve,
        fetchImpl: async () => ++requests === 1 ? response(body()) : { ok: false, status: 503 },
    });
    locations.start();
    await ready.promise;
    locations.stop();
    locations.start();
    try {
        await failed.promise;
        assert.equal(updates, 1);
    } finally { locations.stop(); }
});

test('a hanging connection times out and marks live fixes stale', async context => {
    context.mock.timers.enable({ apis: ['setTimeout'] });
    const ready = Promise.withResolvers();
    const updates = [], errors = [];
    let requests = 0;
    const locations = createRiderLocationPoller({
        getToken: () => 'token',
        onUpdate: value => { updates.push(value); ready.resolve(); },
        onError: error => errors.push(error),
        fetchImpl: async (url, options) => {
            if (++requests === 1) return response(body());
            return new Promise((resolve, reject) => options.signal.addEventListener('abort',
                () => reject(new DOMException('Timeout', 'AbortError')), { once: true }));
        },
    });
    locations.start();
    try {
        await ready.promise;
        const refresh = locations.refresh();
        await setImmediate();
        context.mock.timers.tick(10000);
        await refresh;
        assert.equal(updates.at(-1).data[0].status, 'stale');
        assert.equal(errors.length, 1);
    } finally { locations.stop(); }
});
