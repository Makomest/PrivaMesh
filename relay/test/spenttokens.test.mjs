/**
 * Unit test for the /claim decision FSM (the single-spend core).
 * Run: npx tsx test/spenttokens.test.mjs
 */
import assert from 'node:assert';
import { decideClaim, CLAIM_TTL_MS } from '../src/spenttokens.ts';

const now = 1_000_000;

// free token → claim ok, persist pendingSince=now
let r = decideClaim(undefined, now);
assert.deepStrictEqual(r, { result: 'ok', next: now }, 'free token must be claimable');

// already committed → spent, no write
r = decideClaim('spent', now);
assert.deepStrictEqual(r, { result: 'spent', next: null }, 'spent token must reject');

// fresh in-flight claim → pending, no write (concurrent spend blocked)
r = decideClaim(now - 1, now);
assert.deepStrictEqual(r, { result: 'pending', next: null }, 'fresh claim must block');

// stale claim (crashed request) → reclaimable
r = decideClaim(now - CLAIM_TTL_MS - 1, now);
assert.deepStrictEqual(r, { result: 'ok', next: now }, 'stale claim must be reclaimable');

// exactly at TTL boundary → still stale (>= ttl reclaimable)
r = decideClaim(now - CLAIM_TTL_MS, now);
assert.deepStrictEqual(r, { result: 'ok', next: now }, 'claim at TTL boundary reclaimable');

console.log('PASS: claim FSM — free/spent/fresh-pending/stale/boundary all correct');
console.log('ALL SPENT-TOKEN FSM TESTS PASSED');
