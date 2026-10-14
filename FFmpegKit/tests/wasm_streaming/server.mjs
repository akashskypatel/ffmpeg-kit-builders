import http from 'node:http';
import { createReadStream, readFileSync, statSync } from 'node:fs';
import { resolve, dirname, basename, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const defaultH264AacFixtureDir = resolve(here, 'fixtures/h264-aac');
const FALLBACK_SIZE = 192 * 1024;
const HARNESS_ASSETS = {
  '/audio-close-contract.html': {
    file: 'audio-close-contract.html',
    contentType: 'text/html; charset=utf-8',
  },
  '/audio-close-contract.mjs': {
    file: 'audio-close-contract.mjs',
    contentType: 'text/javascript; charset=utf-8',
  },
  '/wasm-acceptance.html': {
    file: 'wasm-acceptance.html',
    contentType: 'text/html; charset=utf-8',
  },
  '/wasm-acceptance.mjs': {
    file: 'wasm-acceptance.mjs',
    contentType: 'text/javascript; charset=utf-8',
  },
};
const BUNDLE_CONTENT_TYPES = {
  '.data': 'application/octet-stream',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
};

function payload(label, size = FALLBACK_SIZE) {
  const result = Buffer.allocUnsafe(size);
  let seed = 2166136261;
  for (const byte of Buffer.from(label)) seed = Math.imul(seed ^ byte, 16777619) >>> 0;
  for (let i = 0; i < size; i++) {
    seed = (Math.imul(seed ^ (seed >>> 13), 0x5bd1e995) + i) >>> 0;
    result[i] = seed & 0xff;
  }
  return result;
}

function pcmWave() {
  const sampleRate = 8000;
  const sampleCount = sampleRate;
  const dataSize = sampleCount * 2;
  const result = Buffer.alloc(44 + dataSize);
  result.write('RIFF', 0, 'ascii');
  result.writeUInt32LE(36 + dataSize, 4);
  result.write('WAVEfmt ', 8, 'ascii');
  result.writeUInt32LE(16, 16);
  result.writeUInt16LE(1, 20);
  result.writeUInt16LE(1, 22);
  result.writeUInt32LE(sampleRate, 24);
  result.writeUInt32LE(sampleRate * 2, 28);
  result.writeUInt16LE(2, 32);
  result.writeUInt16LE(16, 34);
  result.write('data', 36, 'ascii');
  result.writeUInt32LE(dataSize, 40);
  return result;
}

function packetPayloadOffset(packet) {
  const control = (packet[3] >> 4) & 3;
  if (control !== 1 && control !== 3) return -1;
  const offset = control === 3 ? 5 + packet[4] : 4;
  return offset < packet.length ? offset : -1;
}

function readPts(bytes, offset) {
  return (BigInt(bytes[offset] & 0x0e) << 29n) |
    (BigInt(bytes[offset + 1]) << 22n) |
    (BigInt(bytes[offset + 2] & 0xfe) << 14n) |
    (BigInt(bytes[offset + 3]) << 7n) |
    BigInt((bytes[offset + 4] & 0xfe) >> 1);
}

function writePts(bytes, offset, value) {
  const mask = (1n << 33n) - 1n;
  const pts = value & mask;
  const prefix = bytes[offset] & 0xf0;
  bytes[offset] = prefix | Number((pts >> 29n) & 0x0en) | 1;
  bytes[offset + 1] = Number((pts >> 22n) & 0xffn);
  bytes[offset + 2] = Number((pts >> 14n) & 0xfen) | 1;
  bytes[offset + 3] = Number((pts >> 7n) & 0xffn);
  bytes[offset + 4] = Number((pts << 1n) & 0xfen) | 1;
}

function greatestCommonDivisor(left, right) {
  let a = left;
  let b = right;
  while (b !== 0n) [a, b] = [b, a % b];
  return a;
}

function firstTimestampStep(records, streamName) {
  for (let index = 1; index < records.length; index++) {
    const difference = records[index].pts - records[index - 1].pts;
    if (difference > 0n) return difference;
  }
  throw new Error(`Live MPEG-TS fixture has no advancing ${streamName} timestamps.`);
}

function liveSegmentTemplate(source) {
  if (source.length % 188 !== 0) throw new Error('Live MPEG-TS fixture is not packet aligned.');
  const videoStarts = [];
  const audioStarts = [];
  for (let packetIndex = 0; packetIndex < source.length / 188; packetIndex++) {
    const offset = packetIndex * 188;
    const packet = source.subarray(offset, offset + 188);
    if (packet[0] !== 0x47) throw new Error('Live MPEG-TS fixture has a lost sync byte.');
    if (!(packet[1] & 0x40)) continue;
    const payload = packetPayloadOffset(packet);
    if (payload < 0 || payload + 14 > packet.length ||
        packet[payload] !== 0 || packet[payload + 1] !== 0 ||
        packet[payload + 2] !== 1) continue;
    const streamId = packet[payload + 3];
    const flags = (packet[payload + 7] >> 6) & 3;
    if (flags < 2) continue;
    const record = { packetIndex, pts: readPts(packet, payload + 9) };
    if (streamId >= 0xe0 && streamId <= 0xef) videoStarts.push(record);
    else if (streamId >= 0xc0 && streamId <= 0xdf) audioStarts.push(record);
  }
  if (videoStarts.length < 2) throw new Error('Live MPEG-TS fixture has no timed video PES packets.');
  if (audioStarts.length < 2) throw new Error('Live MPEG-TS fixture has no timed audio PES packets.');
  const first = videoStarts[0];
  const videoStep = firstTimestampStep(videoStarts, 'video');
  const audioStep = firstTimestampStep(audioStarts, 'audio');
  const alignmentTicks = videoStep / greatestCommonDivisor(videoStep, audioStep) * audioStep;
  const minimumTicks = 3n * 90000n;
  const targetOffset = ((minimumTicks + alignmentTicks - 1n) / alignmentTicks) * alignmentTicks;
  const target = first.pts + targetOffset;
  const boundary = videoStarts.find((record) => record.pts >= target);
  if (!boundary || boundary.packetIndex < 2 || boundary.pts !== target)
    throw new Error('Live MPEG-TS fixture has no shared audio/video timestamp boundary after three seconds.');
  const durationTicks = boundary.pts - first.pts;
  const continuity = new Map();
  for (let packetIndex = 0; packetIndex < boundary.packetIndex; packetIndex++) {
    const packet = source.subarray(packetIndex * 188, (packetIndex + 1) * 188);
    const adaptationControl = (packet[3] >> 4) & 3;
    if (adaptationControl !== 1 && adaptationControl !== 3) continue;
    const pid = ((packet[1] & 0x1f) << 8) | packet[2];
    const counter = packet[3] & 0x0f;
    const previous = continuity.get(pid);
    continuity.set(pid, { first: previous?.first ?? counter, last: counter });
  }
  const continuityOffsets = new Map();
  for (const [pid, counters] of continuity)
    continuityOffsets.set(pid, (counters.last + 1 - counters.first) & 0x0f);
  return {
    bytes: Buffer.from(source.subarray(0, boundary.packetIndex * 188)),
    durationTicks,
    durationSeconds: Number(durationTicks) / 90000,
    continuityOffsets,
  };
}

function shiftMpegTsTimestamps(source, offsetTicks, continuityOffsets, sequenceOffset) {
  if (offsetTicks === 0n && sequenceOffset === 0) return Buffer.from(source);
  const result = Buffer.from(source);
  const pcrModulus = (1n << 33n) * 300n;
  for (let packetOffset = 0; packetOffset < result.length; packetOffset += 188) {
    const packet = result.subarray(packetOffset, packetOffset + 188);
    if (packet[0] !== 0x47) throw new Error('Live MPEG-TS fixture has a lost sync byte.');
    const pid = ((packet[1] & 0x1f) << 8) | packet[2];
    const continuityOffset = ((continuityOffsets.get(pid) ?? 0) * (sequenceOffset & 0x0f)) & 0x0f;
    packet[3] = (packet[3] & 0xf0) | ((packet[3] + continuityOffset) & 0x0f);
    const payload = packetPayloadOffset(packet);
    if (payload >= 0 && (packet[1] & 0x40) &&
        packet[payload] === 0 && packet[payload + 1] === 0 && packet[payload + 2] === 1) {
      const flags = (packet[payload + 7] >> 6) & 3;
      if (flags >= 2 && payload + 14 <= packet.length) {
        writePts(packet, payload + 9, readPts(packet, payload + 9) + offsetTicks);
        if (flags === 3 && payload + 19 <= packet.length)
          writePts(packet, payload + 14, readPts(packet, payload + 14) + offsetTicks);
      }
    }

    const adaptationControl = (packet[3] >> 4) & 3;
    if ((adaptationControl === 2 || adaptationControl === 3) && packet[4] >= 7 &&
        (packet[5] & 0x10)) {
      const pcr = packet.subarray(6, 12);
      const base = (BigInt(pcr[0]) << 25n) | (BigInt(pcr[1]) << 17n) |
        (BigInt(pcr[2]) << 9n) | (BigInt(pcr[3]) << 1n) | BigInt(pcr[4] >> 7);
      const extension = (BigInt(pcr[4] & 1) << 8n) | BigInt(pcr[5]);
      const shifted = ((base * 300n + extension + offsetTicks * 300n) % pcrModulus + pcrModulus) % pcrModulus;
      const shiftedBase = shifted / 300n;
      const shiftedExtension = shifted % 300n;
      pcr[0] = Number((shiftedBase >> 25n) & 0xffn);
      pcr[1] = Number((shiftedBase >> 17n) & 0xffn);
      pcr[2] = Number((shiftedBase >> 9n) & 0xffn);
      pcr[3] = Number((shiftedBase >> 1n) & 0xffn);
      pcr[4] = Number(((shiftedBase & 1n) << 7n) | 0x7en | (shiftedExtension >> 8n));
      pcr[5] = Number(shiftedExtension & 0xffn);
    }
  }
  return result;
}

function corsHeaders(enabled = true) {
  const headers = {
    'Access-Control-Expose-Headers': 'Accept-Ranges, Content-Range, Content-Length',
    'Access-Control-Allow-Headers': 'Range, Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
  };
  if (enabled) headers['Access-Control-Allow-Origin'] = '*';
  return headers;
}

function parseRange(value, size) {
  if (!value) return null;
  const match = /^bytes=(\d+)-(\d*)$/.exec(value);
  if (!match) return { invalid: true };
  const start = Number(match[1]);
  const end = match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
  if (!Number.isSafeInteger(start) || start >= size || end < start)
    return { invalid: true };
  return { start, end };
}

function sendSlowBuffer(req, res, body, { type = 'application/octet-stream' } = {}) {
  const headers = {
    ...corsHeaders(),
    'Accept-Ranges': 'bytes',
    'Cache-Control': 'no-store',
    'Content-Type': type,
  };
  const requested = parseRange(req.headers.range, body.length);
  if (requested?.invalid) {
    res.writeHead(416, { ...headers, 'Content-Range': `bytes */${body.length}` });
    res.end();
    return;
  }
  const start = requested?.start ?? 0;
  const end = requested?.end ?? body.length - 1;
  res.writeHead(requested ? 206 : 200, {
    ...headers,
    'Content-Length': end - start + 1,
    ...(requested ? { 'Content-Range': `bytes ${start}-${end}/${body.length}` } : {}),
  });
  let offset = start;
  const pump = () => {
    if (res.destroyed || offset > end) return res.end();
    const next = Math.min(end + 1, offset + 4096);
    res.write(body.subarray(offset, next));
    offset = next;
    setTimeout(pump, 100);
  };
  pump();
}

export function createStreamingFixtureServer({
  host = '127.0.0.1',
  port = 0,
  fixtureDir = process.env.WASM_STREAMING_FIXTURE_DIR,
  bundleDir = process.env.WASM_STREAMING_BUNDLE_DIR,
} = {}) {
  const mediaRoot = fixtureDir ? resolve(fixtureDir) : null;
  const wasmBundleRoot = bundleDir ? resolve(bundleDir) : null;
  const requests = [];
  let liveReload = 0;
  let cachedLiveSegment = null;

  function asset(name) {
    if (name === 'legacy-segment.ts')
      return readFileSync(resolve(here, 'fixtures/segment.ts'));
    if (mediaRoot) {
      const choices = [
        name,
        ...(name === 'segment.ts' ? ['segment-1.ts'] : []),
        name.replace(/^segment-\d+\.ts$/, 'segment.ts'),
      ];
      for (const choice of choices) {
        try { return readFileSync(resolve(mediaRoot, basename(choice))); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
      }
    }
    if (name === 'progressive.mp4')
      return readFileSync(resolve(here, '../dummy_video.mp4'));
    if (name === 'segment.ts')
      return readFileSync(resolve(defaultH264AacFixtureDir, 'segment-1.ts'));
    if (name === 'live-template.ts')
      return readFileSync(resolve(defaultH264AacFixtureDir, 'live-template.ts'));
    if (/^segment-\d+\.ts$/.test(name))
      return readFileSync(resolve(defaultH264AacFixtureDir, name));
    return payload(name);
  }

  function vodPlaylist(token = null) {
    const playlistPath = resolve(mediaRoot ?? defaultH264AacFixtureDir, 'vod.m3u8');
    const suffix = token ? `?token=${encodeURIComponent(token)}` : '';
    return readFileSync(playlistPath, 'utf8')
      .replace(/^(segment-\d+\.ts)$/gm, `$1${suffix}`);
  }

  function getLiveSegmentTemplate() {
    cachedLiveSegment ??= liveSegmentTemplate(asset('live-template.ts'));
    return cachedLiveSegment;
  }

  function sendBuffer(req, res, body, {
    type = 'application/octet-stream',
    range = true,
    cors = true,
    cache = 'no-store',
    extraHeaders = {},
  } = {}) {
    const headers = {
      ...corsHeaders(cors),
      'Accept-Ranges': range ? 'bytes' : 'none',
      'Cache-Control': cache,
      'Content-Type': type,
      ...extraHeaders,
    };
    const requested = range ? parseRange(req.headers.range, body.length) : null;
    if (requested?.invalid) {
      res.writeHead(416, { ...headers, 'Content-Range': `bytes */${body.length}` });
      res.end();
      return;
    }
    if (requested) {
      const chunk = body.subarray(requested.start, requested.end + 1);
      res.writeHead(206, {
        ...headers,
        'Content-Length': chunk.length,
        'Content-Range': `bytes ${requested.start}-${requested.end}/${body.length}`,
      });
      if (req.method === 'HEAD') res.end();
      else res.end(chunk);
      return;
    }
    res.writeHead(200, { ...headers, 'Content-Length': body.length });
    if (req.method === 'HEAD') res.end();
    else res.end(body);
  }

  const server = http.createServer((req, res) => {
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    const url = new URL(req.url, `http://${req.headers.host}`);
    const requestRecord = {
      method: req.method,
      path: url.pathname,
      query: url.search,
      range: req.headers.range ?? null,
    };
    requests.push(requestRecord);
    const recordResponseStatus = () => {
      if (res.headersSent) {
        requestRecord.status = res.statusCode;
        requestRecord.contentRange = res.getHeader('Content-Range') ?? null;
      }
    };
    res.once('finish', recordResponseStatus);
    res.once('close', recordResponseStatus);

    if (req.method === 'OPTIONS') {
      res.writeHead(204, corsHeaders());
      res.end();
      return;
    }
    const harnessAsset = HARNESS_ASSETS[url.pathname];
    if (harnessAsset) {
      const body = readFileSync(resolve(here, harnessAsset.file));
      res.writeHead(200, {
        'Cache-Control': 'no-store',
        'Content-Length': body.length,
        'Content-Type': harnessAsset.contentType,
      });
      res.end(body);
      return;
    }
    if (url.pathname.startsWith('/wasm/')) {
      if (!wasmBundleRoot) {
        res.writeHead(503, { ...corsHeaders(), 'Content-Type': 'text/plain' });
        res.end('set WASM_STREAMING_BUNDLE_DIR to the freshly built package lib directory\n');
        return;
      }
      const name = basename(url.pathname.slice('/wasm/'.length));
      const bundlePath = resolve(wasmBundleRoot, name);
      if (!name || name.includes('..') ||
          !bundlePath.startsWith(`${wasmBundleRoot}${sep}`) ||
          !Object.hasOwn(BUNDLE_CONTENT_TYPES, name.slice(name.lastIndexOf('.')))) {
        res.writeHead(404, { ...corsHeaders(), 'Content-Type': 'text/plain' });
        res.end('Wasm bundle asset not found\n');
        return;
      }
      let size;
      try { size = statSync(bundlePath).size; }
      catch (error) {
        if (error.code !== 'ENOENT') throw error;
        res.writeHead(404, { ...corsHeaders(), 'Content-Type': 'text/plain' });
        res.end('Wasm bundle asset not found\n');
        return;
      }
      res.writeHead(200, {
        'Cache-Control': 'no-store',
        'Content-Length': size,
        'Content-Type': BUNDLE_CONTENT_TYPES[name.slice(name.lastIndexOf('.'))],
      });
      if (req.method === 'HEAD') res.end();
      else createReadStream(bundlePath).pipe(res);
      return;
    }
    if (url.pathname === '/__requests') {
      res.writeHead(200, { ...corsHeaders(), 'Content-Type': 'application/json' });
      res.end(JSON.stringify(requests));
      return;
    }
    if (url.pathname === '/__reset') {
      requests.length = 0;
      liveReload = 0;
      res.writeHead(204, corsHeaders());
      res.end();
      return;
    }
    if (url.pathname === '/health') {
      res.writeHead(200, { ...corsHeaders(), 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, fixtureDir: mediaRoot, bundleDir: wasmBundleRoot }));
      return;
    }

    if (url.pathname === '/redirect/master.m3u8') {
      res.writeHead(302, {
        ...corsHeaders(),
        Location: `/hls/master.m3u8${url.search}`,
        'Cache-Control': 'no-store',
      });
      res.end();
      return;
    }
    if (url.pathname === '/redirect/ranged.mp4') {
      res.writeHead(302, {
        ...corsHeaders(),
        Location: '/media/progressive.mp4',
        'Cache-Control': 'no-store',
      });
      res.end();
      return;
    }
    if (url.pathname === '/hls/master.m3u8') {
      const token = url.searchParams.get('token');
      const suffix = token ? `?token=${encodeURIComponent(token)}` : '';
      const playlist = `#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=256000\nvariant.m3u8${suffix}\n`;
      sendBuffer(req, res, Buffer.from(playlist), { type: 'application/vnd.apple.mpegurl' });
      return;
    }
    if (url.pathname === '/hls/variant.m3u8') {
      const token = url.searchParams.get('token');
      const playlist = vodPlaylist(token);
      sendBuffer(req, res, Buffer.from(playlist), { type: 'application/vnd.apple.mpegurl' });
      return;
    }
    if (url.pathname === '/hls/live.m3u8') {
      const base = 100 + liveReload++;
      const token = url.searchParams.get('token');
      const suffix = token ? `?token=${encodeURIComponent(token)}` : '';
      const segment = getLiveSegmentTemplate();
      const targetDuration = Math.ceil(segment.durationSeconds);
      const playlist = `#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:${targetDuration}\n#EXT-X-MEDIA-SEQUENCE:${base}\n` +
        `#EXTINF:${segment.durationSeconds.toFixed(3)},\nlive-segment-${base}.ts${suffix}\n`;
      sendBuffer(req, res, Buffer.from(playlist), { type: 'application/vnd.apple.mpegurl' });
      return;
    }
    if (url.pathname === '/hls/slow.m3u8') {
      const sourcePlaylist = vodPlaylist();
      const targetDuration = /^#EXT-X-TARGETDURATION:(\d+)$/m.exec(sourcePlaylist)?.[1] ?? '3';
      const firstDuration = /^#EXTINF:([0-9.]+),$/m.exec(sourcePlaylist)?.[1] ?? '2.0';
      const playlist = `#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:${targetDuration}\n` +
        `#EXT-X-MEDIA-SEQUENCE:1\n#EXTINF:${firstDuration},\nslow-segment.ts\n`;
      sendBuffer(req, res, Buffer.from(playlist), { type: 'application/vnd.apple.mpegurl' });
      return;
    }
    if (url.pathname === '/hls/slow-segment.ts') {
      sendSlowBuffer(req, res, asset('segment-1.ts'), { type: 'video/mp2t' });
      return;
    }
    const liveSegmentMatch = /^\/hls\/live-segment-(\d+)\.ts$/.exec(url.pathname);
    if (liveSegmentMatch) {
      const sequence = Number(liveSegmentMatch[1]);
      if (!Number.isSafeInteger(sequence) || sequence < 100) {
        res.writeHead(404, { ...corsHeaders(), 'Content-Type': 'text/plain' });
        res.end('live segment sequence not found\n');
        return;
      }
      const template = getLiveSegmentTemplate();
      const sequenceOffset = sequence - 100;
      const offsetTicks = BigInt(sequenceOffset) * template.durationTicks;
      const body = shiftMpegTsTimestamps(
        template.bytes, offsetTicks, template.continuityOffsets, sequenceOffset,
      );
      sendBuffer(req, res, body, { type: 'video/mp2t' });
      return;
    }
    if (url.pathname === '/hls/legacy-segment.ts') {
      sendBuffer(req, res, asset('legacy-segment.ts'), { type: 'video/mp2t' });
      return;
    }
    if (url.pathname.startsWith('/hls/segment-') && url.pathname.endsWith('.ts')) {
      sendBuffer(req, res, asset(basename(url.pathname)), { type: 'video/mp2t' });
      return;
    }
    if (url.pathname === '/hls/key.bin') {
      sendBuffer(req, res, Buffer.from('0123456789abcdef'), { type: 'application/octet-stream' });
      return;
    }
    if (url.pathname === '/media/full-response.wav') {
      sendBuffer(req, res, pcmWave(), { type: 'audio/wav', range: false });
      return;
    }
    if (url.pathname === '/media/progressive.mp4' || url.pathname === '/progressive.mp4') {
      sendBuffer(req, res, asset('progressive.mp4'), { type: 'video/mp4' });
      return;
    }
    if (/^\/range\/changing-(size|etag|last-modified)\.mp4$/.test(url.pathname)) {
      const kind = /^\/range\/changing-(size|etag|last-modified)\.mp4$/.exec(url.pathname)[1];
      const requestedStart = Number(/^bytes=(\d+)-/.exec(req.headers.range ?? '')?.[1] ?? 0);
      let body = asset('progressive.mp4');
      const extraHeaders = {};
      if (kind === 'size' && requestedStart > 0)
        body = Buffer.concat([body, Buffer.from([0])]);
      if (kind === 'etag') {
        extraHeaders.ETag = requestedStart > 0 ? '"wasm-range-v2"' : '"wasm-range-v1"';
        extraHeaders['Access-Control-Expose-Headers'] = 'ETag';
      }
      if (kind === 'last-modified') {
        extraHeaders['Last-Modified'] = requestedStart > 0
          ? 'Tue, 02 Jan 2024 00:00:00 GMT'
          : 'Mon, 01 Jan 2024 00:00:00 GMT';
      }
      sendBuffer(req, res, body, { type: 'video/mp4', extraHeaders });
      return;
    }
    if (url.pathname === '/media/live-template.ts') {
      sendBuffer(req, res, asset('live-template.ts'), { type: 'video/mp2t' });
      return;
    }
    if (url.pathname === '/media/live-template-packets.json') {
      sendBuffer(req, res, asset('live-template-packets.json'), {
        type: 'application/json', range: false,
      });
      return;
    }
    if (url.pathname === '/media/d2-same-h264-aac.mp4') {
      sendBuffer(req, res, asset('same-h264-aac.mp4'), { type: 'video/mp4' });
      return;
    }
    if (url.pathname === '/range/ignored') {
      sendBuffer(req, res, payload('ignored-range'), { type: 'application/octet-stream', range: false });
      return;
    }
    if (url.pathname === '/truncated') {
      res.writeHead(206, {
        ...corsHeaders(),
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-store',
        'Content-Length': 65536,
        'Content-Range': 'bytes 0-65535/131072',
        'Content-Type': 'application/octet-stream',
      });
      res.write(payload('truncated-response', 16384));
      setTimeout(() => res.socket?.destroy(), 10);
      return;
    }
    if (url.pathname === '/cors/absent') {
      sendBuffer(req, res, payload('no-cors'), { cors: false });
      return;
    }
    if (url.pathname === '/slow') {
      sendSlowBuffer(req, res, payload('slow', 1024 * 1024));
      return;
    }
    if (url.pathname === '/offline') {
      req.socket.destroy();
      return;
    }
    const statusMatch = /^\/status\/(403|404|500)$/.exec(url.pathname);
    if (statusMatch) {
      const status = Number(statusMatch[1]);
      res.writeHead(status, { ...corsHeaders(), 'Content-Type': 'text/plain' });
      res.end(`fixture status ${status}\n`);
      return;
    }

    res.writeHead(404, { ...corsHeaders(), 'Content-Type': 'text/plain' });
    res.end('fixture route not found\n');
  });

  return {
    server,
    async listen() {
      await new Promise((resolveListen, reject) => {
        server.once('error', reject);
        server.listen(port, host, resolveListen);
      });
      const address = server.address();
      return `http://${host}:${address.port}`;
    },
    async close() {
      if (!server.listening) return;
      await new Promise((resolveClose, reject) => server.close((error) => error ? reject(error) : resolveClose()));
    },
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const fixtureDir = process.argv[2];
  const fixture = createStreamingFixtureServer({ fixtureDir });
  const baseUrl = await fixture.listen();
  process.stdout.write(`${baseUrl}\n`);
  const stop = async () => { await fixture.close(); process.exit(0); };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}
