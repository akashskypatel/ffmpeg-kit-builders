import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createStreamingFixtureServer } from './server.mjs';

const mediaFixtureDir = fileURLToPath(new URL('./fixtures/h264-aac/', import.meta.url));
let fixture;
let baseUrl;

function pesStartRecords(ts) {
  const records = [];
  for (let packetOffset = 0; packetOffset < ts.length; packetOffset += 188) {
    const packet = ts.subarray(packetOffset, packetOffset + 188);
    assert.equal(packet[0], 0x47);
    if (!(packet[1] & 0x40)) continue;
    const control = (packet[3] >> 4) & 3;
    if (control !== 1 && control !== 3) continue;
    const payload = control === 3 ? 5 + packet[4] : 4;
    if (payload + 14 > 188 || packet[payload] !== 0 ||
        packet[payload + 1] !== 0 || packet[payload + 2] !== 1) continue;
    const streamId = packet[payload + 3];
    if (((packet[payload + 7] >> 6) & 3) < 2) continue;
    const ptsOffset = payload + 9;
    const pts = ((packet[ptsOffset] & 0x0e) * 2 ** 29) +
      (packet[ptsOffset + 1] * 2 ** 22) +
      ((packet[ptsOffset + 2] & 0xfe) * 2 ** 14) +
      (packet[ptsOffset + 3] * 2 ** 7) +
      ((packet[ptsOffset + 4] & 0xfe) >> 1);
    records.push({ streamId, pts });
  }
  return records;
}

function payloadContinuity(ts) {
  const records = new Map();
  for (let packetOffset = 0; packetOffset < ts.length; packetOffset += 188) {
    const packet = ts.subarray(packetOffset, packetOffset + 188);
    const control = (packet[3] >> 4) & 3;
    if (control !== 1 && control !== 3) continue;
    const pid = ((packet[1] & 0x1f) << 8) | packet[2];
    const counter = packet[3] & 0x0f;
    const previous = records.get(pid);
    records.set(pid, { first: previous?.first ?? counter, last: counter });
  }
  return records;
}

function firstPcr(ts) {
  for (let packetOffset = 0; packetOffset < ts.length; packetOffset += 188) {
    const packet = ts.subarray(packetOffset, packetOffset + 188);
    const control = (packet[3] >> 4) & 3;
    if ((control !== 2 && control !== 3) || packet[4] < 7 || !(packet[5] & 0x10))
      continue;
    const base = (BigInt(packet[6]) << 25n) | (BigInt(packet[7]) << 17n) |
      (BigInt(packet[8]) << 9n) | (BigInt(packet[9]) << 1n) |
      BigInt(packet[10] >> 7);
    const extension = (BigInt(packet[10] & 1) << 8n) | BigInt(packet[11]);
    return base * 300n + extension;
  }
  return null;
}

before(async () => {
  fixture = createStreamingFixtureServer({ fixtureDir: mediaFixtureDir });
  baseUrl = await fixture.listen();
});

after(async () => fixture?.close());

test('serves bounded 200 and 206 responses with exposed range metadata', async () => {
  const full = await fetch(`${baseUrl}/media/progressive.mp4`);
  assert.equal(full.status, 200);
  const fullBody = Buffer.from(await full.arrayBuffer());
  assert.equal(Number(full.headers.get('content-length')), fullBody.length);
  assert.equal(fullBody.toString('ascii', 4, 8), 'ftyp');

  const fullWithoutRanges = await fetch(`${baseUrl}/media/full-response.wav`, {
    headers: { Range: 'bytes=0-65535' },
  });
  assert.equal(fullWithoutRanges.status, 200);
  assert.equal(fullWithoutRanges.headers.get('accept-ranges'), 'none');
  assert.equal(fullWithoutRanges.headers.get('content-type'), 'audio/wav');
  assert.equal(Buffer.from(await fullWithoutRanges.arrayBuffer()).toString('ascii', 8, 12), 'WAVE');

  const partial = await fetch(`${baseUrl}/media/progressive.mp4`, {
    headers: { Range: 'bytes=17-79' },
  });
  assert.equal(partial.status, 206);
  assert.equal(partial.headers.get('content-range'), `bytes 17-79/${fullBody.length}`);
  assert.equal((await partial.arrayBuffer()).byteLength, 63);
  assert.match(partial.headers.get('access-control-expose-headers'), /Content-Range/i);

  const requestLog = await (await fetch(`${baseUrl}/__requests`)).json();
  assert.ok(requestLog.some((request) => request.path === '/media/progressive.mp4' && request.status === 206));
  assert.ok(requestLog.some((request) => request.path === '/media/full-response.wav' && request.status === 200));

  const segment = await fetch(`${baseUrl}/hls/segment-1.ts`, {
    headers: { Range: 'bytes=0-187' },
  });
  assert.equal(segment.status, 206);
  assert.equal(segment.headers.get('content-type'), 'video/mp2t');
  const segmentBody = Buffer.from(await segment.arrayBuffer());
  assert.equal(segmentBody.length, 188);
  const fullSegment = await fetch(`${baseUrl}/hls/segment-1.ts`);
  const fullSegmentBody = Buffer.from(await fullSegment.arrayBuffer());
  assert.equal(segment.headers.get('content-range'), `bytes 0-187/${fullSegmentBody.length}`);
  assert.equal(fullSegmentBody.length % 188, 0);
  assert.ok(fullSegmentBody.every((byte, index) => index % 188 !== 0 || byte === 0x47));
  assert.deepEqual(segmentBody, fullSegmentBody.subarray(0, 188));
});

test('serves the native live-packet reference without a custom fixture directory', async () => {
  const defaultFixture = createStreamingFixtureServer({
    host: '127.0.0.1', port: 0, fixtureDir: null, bundleDir: null,
  });
  try {
    const defaultUrl = await defaultFixture.listen();
    const response = await fetch(`${defaultUrl}/media/live-template-packets.json`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type'), /application\/json/);
    const reference = await response.json();
    const source = readFileSync(join(mediaFixtureDir, 'live-template.ts'));
    assert.equal(reference.sourceBytes, source.length);
    assert.equal(reference.sourceSha256, createHash('sha256').update(source).digest('hex'));
    assert.ok(reference.packets.length > 0);
  } finally {
    await defaultFixture.close();
  }
});

test('serves the native-probed three-segment VOD playlist and preserves the old confound fixture', async () => {
  const vod = await fetch(`${baseUrl}/hls/variant.m3u8`);
  assert.equal(vod.status, 200);
  const playlist = await vod.text();
  assert.match(playlist, /^#EXT-X-TARGETDURATION:3$/m);
  assert.deepEqual([...playlist.matchAll(/^#EXTINF:([0-9.]+),$/gm)].map((match) => Number(match[1])),
    [2.021333, 2, 2]);
  const segmentNames = [...playlist.matchAll(/^(segment-\d+\.ts)$/gm)].map((match) => match[1]);
  assert.deepEqual(segmentNames, ['segment-1.ts', 'segment-2.ts', 'segment-3.ts']);
  const hashes = [];
  for (const name of segmentNames) {
    const response = await fetch(`${baseUrl}/hls/${name}`);
    assert.equal(response.status, 200);
    const bytes = Buffer.from(await response.arrayBuffer());
    assert.equal(bytes.length % 188, 0);
    hashes.push(createHash('sha256').update(bytes).digest('hex'));
  }
  assert.equal(new Set(hashes).size, 3, 'VOD segment hashes must be distinct');

  const legacy = await fetch(`${baseUrl}/hls/legacy-segment.ts`);
  const legacyBytes = Buffer.from(await legacy.arrayBuffer());
  assert.equal(legacy.status, 200);
  assert.equal(legacyBytes.length, 513804);
  assert.equal(createHash('sha256').update(legacyBytes).digest('hex'),
    'fb2885f0689b166c6d23532944d826b73d1e03c45837ad3dea514a6cc9791aa7');
});

test('range-ignoring endpoint returns a finite 200 body', async () => {
  const response = await fetch(`${baseUrl}/range/ignored`, {
    headers: { Range: 'bytes=0-1023' },
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('accept-ranges'), 'none');
  assert.equal((await response.arrayBuffer()).byteLength, 192 * 1024);
});

test('redirect and playlist keep the signed query while resolving nested URLs', async () => {
  const response = await fetch(`${baseUrl}/redirect/master.m3u8?token=case-7`);
  assert.equal(response.status, 200);
  assert.equal(new URL(response.url).pathname, '/hls/master.m3u8');
  assert.equal(new URL(response.url).searchParams.get('token'), 'case-7');
  const body = await response.text();
  assert.match(body, /variant\.m3u8\?token=case-7/);

  const variantUrl = new URL(body.match(/([^\n]+\.m3u8\?token=case-7)/)[1], response.url);
  assert.equal(variantUrl.pathname, '/hls/variant.m3u8');
  assert.equal(variantUrl.searchParams.get('token'), 'case-7');
  const variantResponse = await fetch(variantUrl);
  assert.equal(variantResponse.status, 200);
  const variantBody = await variantResponse.text();
  assert.match(variantBody, /segment-1\.ts\?token=case-7/);
  const segmentUrl = new URL(
    variantBody.match(/([^\n]+\.ts\?token=case-7)/)[1], variantUrl,
  );
  assert.equal(segmentUrl.pathname, '/hls/segment-1.ts');
  assert.equal(segmentUrl.searchParams.get('token'), 'case-7');
  const segment = await fetch(segmentUrl, { headers: { Range: 'bytes=0-187' } });
  assert.equal(segment.status, 206);
  assert.equal((await segment.arrayBuffer()).byteLength, 188);
});

test('live playlist advances timestamps and continuity across three distinct segments', async () => {
  const segments = [];
  const durations = [];
  for (let offset = 0; offset < 3; offset++) {
    const sequence = 100 + offset;
    const response = await fetch(`${baseUrl}/hls/live.m3u8`);
    const playlist = await response.text();
    assert.match(playlist, new RegExp(`MEDIA-SEQUENCE:${sequence}(?:\\n|$)`));
    const duration = Number(playlist.match(/#EXTINF:([0-9.]+)/)?.[1]);
    assert.ok(duration >= 3 && duration < 6, `unexpected live segment duration ${duration}`);
    const segmentPath = playlist.match(/(live-segment-\d+\.ts)/)?.[1];
    assert.equal(segmentPath, `live-segment-${sequence}.ts`);
    const segmentResponse = await fetch(`${baseUrl}/hls/${segmentPath}`);
    assert.equal(segmentResponse.status, 200);
    const bytes = Buffer.from(await segmentResponse.arrayBuffer());
    assert.ok(bytes.length > 188);
    assert.equal(bytes.length % 188, 0);
    assert.ok(bytes.every((byte, index) => index % 188 !== 0 || byte === 0x47));
    durations.push(duration);
    segments.push({ bytes, pts: pesStartRecords(bytes), continuity: payloadContinuity(bytes),
      pcr: firstPcr(bytes), hash: createHash('sha256').update(bytes).digest('hex') });
  }

  assert.equal(new Set(segments.map((segment) => segment.hash)).size, 3,
    'timestamp-shifted live segments must have distinct hashes');
  const pcrModulus = (1n << 33n) * 300n;
  for (let index = 0; index < 2; index++) {
    const current = segments[index];
    const next = segments[index + 1];
    const currentVideo = current.pts.find((packet) => packet.streamId >= 0xe0 && packet.streamId <= 0xef);
    const nextVideo = next.pts.find((packet) => packet.streamId >= 0xe0 && packet.streamId <= 0xef);
    const currentAudio = current.pts.find((packet) => packet.streamId >= 0xc0 && packet.streamId <= 0xdf);
    const nextAudio = next.pts.find((packet) => packet.streamId >= 0xc0 && packet.streamId <= 0xdf);
    assert.ok(currentVideo && nextVideo && currentAudio && nextAudio,
      'live fixture must contain timed video and audio PES packets');
    const expectedOffset = Math.round(durations[index] * 90000);
    assert.equal(nextVideo.pts - currentVideo.pts, expectedOffset,
      'live video timestamp did not advance by the advertised duration');
    assert.equal(nextAudio.pts - currentAudio.pts, expectedOffset,
      'live audio timestamp did not advance by the advertised duration');
    assert.notEqual(current.pcr, null, 'live fixture must contain a PCR clock');
    assert.notEqual(next.pcr, null, 'next live segment must contain a PCR clock');
    assert.equal((next.pcr - current.pcr + pcrModulus) % pcrModulus,
      BigInt(expectedOffset) * 300n, 'PCR did not advance by the advertised duration');
    assert.deepEqual([...next.continuity.keys()].sort(), [...current.continuity.keys()].sort());
    for (const [pid, previous] of current.continuity) {
      assert.equal(next.continuity.get(pid).first, (previous.last + 1) & 0x0f,
        `PID ${pid} continuity counter did not advance across live segments`);
    }
  }
});

test('status and CORS cases are deterministic', async () => {
  for (const status of [403, 404, 500])
    assert.equal((await fetch(`${baseUrl}/status/${status}`)).status, status);
  const cors = await fetch(`${baseUrl}/cors/absent`);
  assert.equal(cors.status, 200);
  assert.equal(cors.headers.get('access-control-allow-origin'), null);
  await assert.rejects(fetch(`${baseUrl}/offline`));
});

test('serves the standalone audio close harness and its module', async () => {
  const page = await fetch(`${baseUrl}/audio-close-contract.html`);
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-type'), /text\/html/);
  assert.match(await page.text(), /audio-close-contract\.mjs/);

  const module = await fetch(`${baseUrl}/audio-close-contract.mjs`);
  assert.equal(module.status, 200);
  assert.match(module.headers.get('content-type'), /javascript/);
  assert.match(await module.text(), /class AudioCloseCoordinator/);

  const wasmPage = await fetch(`${baseUrl}/wasm-acceptance.html`);
  assert.equal(wasmPage.status, 200);
  assert.equal(wasmPage.headers.get('cross-origin-opener-policy'), 'same-origin');
  assert.equal(wasmPage.headers.get('cross-origin-embedder-policy'), 'require-corp');
  assert.match(await wasmPage.text(), /Run transport matrix/);

  const wasmModule = await fetch(`${baseUrl}/wasm-acceptance.mjs`);
  assert.equal(wasmModule.status, 200);
  assert.match(await wasmModule.text(), /ffprobe_kit_execute_async/);

  const bundleLoader = await fetch(`${baseUrl}/wasm/ffmpegkit.mjs`);
  if (process.env.WASM_STREAMING_BUNDLE_DIR) {
    assert.equal(bundleLoader.status, 200);
    assert.match(bundleLoader.headers.get('content-type'), /javascript/);
    assert.match(await bundleLoader.text(), /createFFmpegKit/);
    const bundleWasm = await fetch(`${baseUrl}/wasm/ffmpegkit.wasm`);
    assert.equal(bundleWasm.status, 200);
    assert.match(bundleWasm.headers.get('content-type'), /application\/wasm/);
    assert.ok(Number(bundleWasm.headers.get('content-length')) > 0);
  } else {
    assert.equal(bundleLoader.status, 503);
  }
});

test('serves the configured Wasm bundle with its required MIME type', async () => {
  const bundleDir = mkdtempSync(join(tmpdir(), 'wasm-streaming-bundle-'));
  const bundledLoader = Buffer.from('export default async function createFFmpegKit() {}\n');
  const bundledWasm = Buffer.from([0x00, 0x61, 0x73, 0x6d]);
  writeFileSync(join(bundleDir, 'ffmpegkit.mjs'), bundledLoader);
  writeFileSync(join(bundleDir, 'ffmpegkit.wasm'), bundledWasm);
  const bundleFixture = createStreamingFixtureServer({ bundleDir });
  try {
    const bundleBase = await bundleFixture.listen();
    const response = await fetch(`${bundleBase}/wasm/ffmpegkit.mjs`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'text/javascript; charset=utf-8');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), bundledLoader);

    const wasm = await fetch(`${bundleBase}/wasm/ffmpegkit.wasm`);
    assert.equal(wasm.status, 200);
    assert.equal(wasm.headers.get('content-type'), 'application/wasm');
    assert.deepEqual(Buffer.from(await wasm.arrayBuffer()), bundledWasm);
  } finally {
    await bundleFixture.close();
    rmSync(bundleDir, { recursive: true, force: true });
  }
});

test('slow endpoint accepts an abort and records the Range request', async () => {
  await fetch(`${baseUrl}/__reset`, { method: 'POST' });
  const controller = new AbortController();
  const pending = fetch(`${baseUrl}/slow`, {
    headers: { Range: 'bytes=0-65535' },
    signal: controller.signal,
  }).then((response) => response.arrayBuffer());
  setTimeout(() => controller.abort(), 20);
  await assert.rejects(pending, { name: 'AbortError' });
  await new Promise((resolveWait) => setTimeout(resolveWait, 20));
  const requests = await (await fetch(`${baseUrl}/__requests`)).json();
  assert.ok(requests.some((request) => request.path === '/slow' && request.range === 'bytes=0-65535'));
});

test('slow HLS segment accepts an abort and the truncated route fails finitely', async () => {
  await fetch(`${baseUrl}/__reset`, { method: 'POST' });
  const playlist = await fetch(`${baseUrl}/hls/slow.m3u8`);
  assert.equal(playlist.status, 200);
  assert.match(await playlist.text(), /slow-segment\.ts/);

  const controller = new AbortController();
  const pending = fetch(`${baseUrl}/hls/slow-segment.ts`, {
    headers: { Range: 'bytes=0-65535' },
    signal: controller.signal,
  }).then((response) => response.arrayBuffer());
  setTimeout(() => controller.abort(), 20);
  await assert.rejects(pending, { name: 'AbortError' });

  await assert.rejects(fetch(`${baseUrl}/truncated`).then((response) => response.arrayBuffer()));
  const requests = await (await fetch(`${baseUrl}/__requests`)).json();
  assert.ok(requests.some((request) => request.path === '/hls/slow-segment.ts' && request.range === 'bytes=0-65535'));
  assert.ok(requests.some((request) => request.path === '/truncated'));
});
