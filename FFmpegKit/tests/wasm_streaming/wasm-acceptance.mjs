const STATUS_CREATED = 0;
const STATUS_RUNNING = 1;
const STATUS_COMPLETED = 2;
const STATUS_FAILED = 3;
const PAGE_STARTED_AT = new Date().toISOString();
const PAGE_STARTED_PERFORMANCE = performance.now();
const MAX_RUNTIME_LOG_LINES = 400;
const MAX_RUNTIME_LOG_CHARS = 96 * 1024;
const runtimeLines = [];
const runtimeLogRing = [];
let runtimeLogRingChars = 0;
const browserErrors = [];
const browserErrorRecords = [];
const cleanupErrors = [];
const cleanupSkippedEvents = [];
const logElement = document.getElementById('log');
const statusElement = document.getElementById('status');
const fixtureOrigin = document.getElementById('fixture-origin');
const diagnosticParams = new URLSearchParams(location.search);
const selectedTransportCase = diagnosticParams.get('case');
const bundleIdentity = {
  label: diagnosticParams.get('bundle') || 'unspecified',
  wasmSha256: diagnosticParams.get('wasmSha256') || null,
  loaderSha256: diagnosticParams.get('loaderSha256') || null,
};
const buttons = ['load', 'transport', 'vod', 'live', 'record', 'cancel']
  .map((id) => [id, document.getElementById(id)]);

fixtureOrigin.value = location.origin;

let Module = null;
let activeSession = null;
let operationRunning = false;
let wasmRuntimePoisoned = false;
let firstFatalEvent = null;
let firstWorkerFault = null;
let currentCaseName = null;
let requestedCommand = null;
let lastCaseFailure = null;

function write(message) {
  const line = `[${new Date().toISOString()}] ${message}`;
  logElement.textContent += `${line}\n`;
  logElement.scrollTop = logElement.scrollHeight;
}

function serializeError(error) {
  let name = null;
  let message = null;
  let stack = null;
  let stringValue;
  try { name = error?.name ?? error?.constructor?.name ?? null; } catch { }
  try { message = error?.message == null ? null : String(error.message); } catch { }
  try { stack = error?.stack == null ? null : String(error.stack); } catch { }
  try { stringValue = String(error); } catch { stringValue = '[unprintable error]'; }
  return { name, message, stack, string: stringValue };
}

function runtimeLogTail() {
  return runtimeLogRing.map((entry) => ({ ...entry }));
}

function diagnosticElapsedMs() {
  return Math.round(performance.now() - PAGE_STARTED_PERFORMANCE);
}

function recordFatalEvent(source, detail, { worker = false } = {}) {
  const record = {
    source,
    timestamp: new Date().toISOString(),
    elapsedMs: diagnosticElapsedMs(),
    caseName: currentCaseName,
    requestedCommand: requestedCommand ? { ...requestedCommand } : null,
    detail,
    runtimeLinesTail: runtimeLogTail(),
  };
  if (!firstFatalEvent) firstFatalEvent = record;
  if (worker || /worker/i.test(source)) {
    if (!firstWorkerFault) firstWorkerFault = record;
    else if (firstWorkerFault !== record) {
      firstWorkerFault.relatedEvents ??= [];
      firstWorkerFault.relatedEvents.push({ source, timestamp: record.timestamp, detail });
    }
  }
  browserErrorRecords.push(record);
  browserErrors.push(`${source}: ${detail?.stack || detail?.message || detail?.string || detail?.raw || String(detail)}`);
  wasmRuntimePoisoned = true;
  return record;
}

function diagnosticSnapshot() {
  return {
    pageStartedAt: PAGE_STARTED_AT,
    elapsedMs: diagnosticElapsedMs(),
    browser: {
      userAgent: navigator.userAgent,
      url: location.href,
      crossOriginIsolated,
      sharedArrayBuffer: typeof SharedArrayBuffer !== 'undefined',
    },
    caseName: currentCaseName,
    bundle: { ...bundleIdentity },
    requestedCommand: requestedCommand ? { ...requestedCommand } : null,
    firstWorkerFault: firstWorkerFault ? { ...firstWorkerFault } : null,
    firstFatalEvent: firstFatalEvent ? { ...firstFatalEvent } : null,
    browserErrors: browserErrorRecords.map((record) => ({ ...record })),
    browserErrorMessages: [...browserErrors],
    workerFaultEvents: browserErrorRecords
      .filter((record) => /worker/i.test(record.source))
      .map((record) => ({ ...record })),
    firstWorkerFaultNotObservedReason: firstWorkerFault ? null : firstFatalEvent ?
      `No Emscripten worker-error print, page error, or unhandled rejection was observable before ` +
      `${firstFatalEvent.source} at ${firstFatalEvent.timestamp}; first captured error was ` +
      `${firstFatalEvent.detail?.message || firstFatalEvent.detail?.string || 'unspecified'}.` :
      'No worker fault or fatal runtime event has been captured.',
    playwrightDriverEvents: Array.isArray(window.__playwrightDriverEvents) ?
      window.__playwrightDriverEvents.map((record) => ({ ...record })) : [],
    runtimeLinesTail: runtimeLogTail(),
    cleanupErrors: cleanupErrors.map((record) => ({ ...record })),
    cleanupSkippedEvents: cleanupSkippedEvents.map((record) => ({ ...record })),
    lastCaseFailure: lastCaseFailure ? { ...lastCaseFailure } : null,
    wasmRuntimePoisoned,
    pageStatus: statusElement.textContent,
    pageLogTail: logElement.textContent.slice(-32 * 1024),
  };
}

window.ffmpegKitWasmDiagnostics = diagnosticSnapshot;

window.addEventListener('error', (event) => {
  const detail = {
    ...serializeError(event.error ?? event.message),
    filename: event.filename || null,
    line: event.lineno || null,
    column: event.colno || null,
  };
  const worker = /ffmpegkit\.(mjs|wasm)/i.test(detail.filename || '') ||
    /worker/i.test(detail.message || '');
  recordFatalEvent(worker ? 'worker-window-error' : 'window-error', detail, { worker });
  write(`BROWSER ERROR: ${detail.stack || detail.message || detail.string}`);
}, true);

window.addEventListener('unhandledrejection', (event) => {
  const detail = serializeError(event.reason ?? 'unhandled promise rejection');
  recordFatalEvent('unhandled-rejection', detail);
  write(`BROWSER REJECTION: ${detail.stack || detail.message || detail.string}`);
});

function setStatus(message) {
  statusElement.textContent = message;
}

function check(condition, message) {
  if (!condition) throw new Error(message);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function baseUrl() {
  const value = fixtureOrigin.value.trim() || location.origin;
  const url = new URL(value);
  check(url.protocol === 'http:' || url.protocol === 'https:', 'Fixture origin must use HTTP or HTTPS.');
  return url.origin;
}

function mediaUrl(path, base = baseUrl()) {
  return new URL(path, `${base}/`).href;
}

async function importFixtureToMemfs(url, destination, label) {
  const response = await fetch(mediaUrl(url));
  check(response.ok, `${label} fixture import failed with HTTP ${response.status}.`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const sha256 = [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0')).join('');
  Module.FS.writeFile(destination, bytes);
  write(`${label} imported bytes=${bytes.byteLength}; sha256=${sha256}.`);
  return { bytes, sha256, destination };
}

function ccall(name, returnType, argumentTypes = [], arguments_ = []) {
  check(Module, 'Load the local Wasm bundle first.');
  check(!wasmRuntimePoisoned, 'Wasm runtime is poisoned; subsequent C calls are disabled.');
  try {
    return Module.ccall(name, returnType, argumentTypes, arguments_);
  } catch (error) {
    if (error instanceof WebAssembly.RuntimeError ||
        (typeof WebAssembly.Exception === 'function' && error instanceof WebAssembly.Exception)) {
      recordFatalEvent('wasm-ccall-trap', serializeError(error));
    }
    throw error;
  }
}

function readSessionString(name, handle) {
  const pointer = ccall(name, 'number', ['number'], [handle]);
  if (!pointer) return '';
  const value = Module.UTF8ToString(pointer);
  Module._free(pointer);
  return value;
}

function redactDiagnosticCommand(command) {
  return command
    .replace(/([a-z][a-z0-9+.-]*:\/\/)([^/?#\s"'<>]*@)/gi, '$1<redacted>@')
    .replace(/([?&][^=\s]+)=([^&\s]+)/g, '$1=<redacted>')
    .replace(/(-headers\s+)(?:"[^"]*"|'[^']*'|\S+)/i, '$1<redacted>');
}

function parseProbeJson(output) {
  const start = output.indexOf('{');
  if (start < 0) throw new Error(`FFprobe session output contained no JSON object: ${output.slice(0, 240)}`);

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < output.length; index++) {
    const character = output[index];
    if (inString) {
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === '"') inString = false;
      continue;
    }
    if (character === '"') inString = true;
    else if (character === '{') depth++;
    else if (character === '}' && --depth === 0)
      return JSON.parse(output.slice(start, index + 1));
  }
  throw new Error(`FFprobe session output contained incomplete JSON: ${output.slice(start, start + 240)}`);
}

function startSession(kind, command) {
  requestedCommand = {
    kind,
    command: redactDiagnosticCommand(command),
    caseName: currentCaseName,
    startedAt: new Date().toISOString(),
    elapsedAtStartMs: diagnosticElapsedMs(),
    endedAt: null,
    elapsedMs: null,
  };
  let handle;
  if (kind === 'ffprobe') {
    handle = ccall('ffprobe_kit_execute_async', 'number',
      ['string', 'number', 'number'], [command, 0, 0]);
  } else if (kind === 'ffmpeg') {
    handle = ccall('ffmpeg_kit_execute_async', 'number',
      ['string', 'number', 'number'], [command, 0, 0]);
  } else if (kind === 'ffplay') {
    handle = ccall('ffplay_kit_execute_async', 'number',
      ['string', 'number', 'number', 'bigint'], [command, 0, 0, 0n]);
  } else {
    throw new Error(`Unknown FFmpegKit command kind: ${kind}`);
  }
  check(handle, `${kind} did not return a session handle.`);
  requestedCommand.handle = handle;
  activeSession = { kind, handle };
  updateButtons();
  return handle;
}

function finishCommandTiming(handle) {
  if (!requestedCommand || requestedCommand.handle !== handle || requestedCommand.endedAt) return;
  requestedCommand.endedAt = new Date().toISOString();
  requestedCommand.elapsedMs = diagnosticElapsedMs() - requestedCommand.elapsedAtStartMs;
}

function cancelSession(session = activeSession) {
  if (!session || !Module || wasmRuntimePoisoned) return;
  if (session.kind === 'ffprobe')
    ccall('ffprobe_kit_cancel', 'void');
  else if (session.kind === 'ffmpeg')
    ccall('ffmpeg_kit_cancel', 'void');
  else if (session.kind === 'ffplay')
    ccall('ffplay_kit_session_stop', 'void', ['number'], [session.handle]);
}

function sessionState(handle) {
  check(!wasmRuntimePoisoned, 'Wasm runtime is poisoned; session state polling is disabled.');
  return ccall('ffmpeg_kit_session_get_state', 'number', ['number'], [handle]);
}

async function waitForSession(handle, timeoutMs, { cancelAtMs = null, onPoll = null } = {}) {
  const session = activeSession?.handle === handle ? activeSession : null;
  const start = Date.now();
  let cancelled = false;
  while (true) {
    if (wasmRuntimePoisoned)
      throw new Error('Wasm runtime was poisoned by an earlier fatal event; session polling stopped.');
    const state = sessionState(handle);
    if (state === STATUS_COMPLETED || state === STATUS_FAILED) {
      const rawCode = ccall('ffmpeg_kit_session_get_return_code', 'number',
        ['number'], [handle]);
      const output = readSessionString('ffmpeg_kit_session_get_output', handle);
      return {
        state,
        returnCode: typeof rawCode === 'bigint' ? Number(rawCode) : rawCode,
        output,
        elapsedMs: Date.now() - start,
        cancelled,
      };
    }
    onPoll?.();
    const elapsed = Date.now() - start;
    if (cancelAtMs !== null && !cancelled && elapsed >= cancelAtMs) {
      cancelSession(session);
      cancelled = true;
    }
    if (elapsed >= timeoutMs) {
      cancelSession(session);
      throw new Error(`Session timed out after ${timeoutMs} ms (state ${state}).`);
    }
    await delay(40);
  }
}

async function execute(kind, command, options = {}) {
  const handle = startSession(kind, command);
  try {
    return await waitForSession(handle, options.timeoutMs ?? 15000, options);
  } finally {
    finishCommandTiming(handle);
    if (wasmRuntimePoisoned) {
      if (activeSession?.handle === handle) activeSession = null;
      cleanupSkippedEvents.push({
        timestamp: new Date().toISOString(),
        elapsedMs: diagnosticElapsedMs(),
        caseName: currentCaseName,
        kind,
        handle,
        reason: 'Fatal Wasm event detected; no C API cleanup calls were made.',
      });
      write('Session cleanup skipped: the Wasm runtime is poisoned; no further C calls will be made.');
      updateButtons();
    } else {
      await finishSession(kind, handle);
    }
  }
}

async function runCase(name, callback) {
  if (selectedTransportCase && !name.startsWith(selectedTransportCase)) return 'skip';
  if (wasmRuntimePoisoned || browserErrors.length) {
    write(`SKIP ${name}: browser runtime already reported an uncaught error.`);
    return 'skip';
  }
  currentCaseName = name;
  lastCaseFailure = null;
  const cleanupErrorStart = cleanupErrors.length;
  write(`RUN ${name}`);
  try {
    const result = await callback();
    if (result?.skip) {
      write(`SKIP ${name}: ${result.skip}`);
      return 'skip';
    }
    if (wasmRuntimePoisoned)
      throw new Error('Case returned after a fatal Wasm event; the result cannot be accepted.');
    if (cleanupErrors.length > cleanupErrorStart) {
      const cleanupError = cleanupErrors[cleanupErrors.length - 1];
      throw new Error(`Session cleanup failed: ${cleanupError.error.message || cleanupError.error.string}`);
    }
    write(`PASS ${name}${result?.detail ? ` — ${result.detail}` : ''}`);
    return 'pass';
  } catch (error) {
    if (requestedCommand?.caseName === name)
      finishCommandTiming(requestedCommand.handle);
    const errorRecord = serializeError(error);
    lastCaseFailure = {
      name,
      timestamp: new Date().toISOString(),
      elapsedMs: diagnosticElapsedMs(),
      requestedCommand: requestedCommand ? { ...requestedCommand } : null,
      error: errorRecord,
    };
    write(`FAIL ${name}: ${errorRecord.stack || errorRecord.message || errorRecord.string}`);
    return 'fail';
  }
}

async function resetRequests() {
  const response = await fetch(mediaUrl('/__reset'), { method: 'POST' });
  check(response.ok, `Fixture request reset failed with HTTP ${response.status}.`);
}

async function getRequests() {
  const response = await fetch(mediaUrl('/__requests'));
  check(response.ok, `Fixture request log failed with HTTP ${response.status}.`);
  return response.json();
}

function ffprobeCommand(url, extra = '') {
  return `-v debug ${extra} -show_entries format=format_name,duration -of json ${url}`;
}

async function probe(url, extra = '', options = {}) {
  return execute('ffprobe', ffprobeCommand(url, extra), options);
}

async function inspectBinary() {
  check(crossOriginIsolated && typeof SharedArrayBuffer !== 'undefined',
    'This page is not cross-origin isolated; pthread Wasm requires COOP/COEP and SharedArrayBuffer.');
  const { default: createFFmpegKit } = await import('/wasm/ffmpegkit.mjs');
  const required = [
    '_ffmpeg_kit_initialize', '_ffmpeg_kit_execute_async',
    '_ffprobe_kit_execute_async', '_ffplay_kit_execute_async',
    '_ffmpeg_kit_session_get_state', '_ffmpeg_kit_session_get_return_code',
    '_ffmpeg_kit_session_get_output', '_ffmpeg_kit_session_get_session_id',
    '_ffmpeg_kit_handle_release', '_ffprobe_kit_cancel_session',
    '_ffmpeg_kit_config_set_log_level', '_ffprobe_kit_cancel',
    '_ffplay_kit_session_stop', '_ffplay_kit_session_get_position', '_free',
    '_ffplay_kit_session_get_video_width', '_ffplay_kit_session_get_video_height',
    '_ffplay_kit_session_pause', '_ffplay_kit_session_resume',
    '_ffplay_kit_session_is_paused',
  ];
  const candidate = await createFFmpegKit({
    canvas: document.getElementById('canvas'),
    locateFile: (path) => new URL(`/wasm/${path}`, location.origin).href,
    print: (...values) => captureRuntime('stdout', values),
    printErr: (...values) => captureRuntime('stderr', values),
    onAbort: (reason) => recordFatalEvent('emscripten-onAbort', serializeError(reason)),
  });
  for (const name of required)
    check(typeof candidate[name] === 'function', `The built loader does not expose ${name}.`);
  check(typeof candidate.FS?.writeFile === 'function', 'The built loader does not expose MEMFS.');
  Module = candidate;
  ccall('ffmpeg_kit_initialize', 'void');
  ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [48]);
  write(`Loaded local Wasm loader; crossOriginIsolated=${crossOriginIsolated}; ` +
    `SharedArrayBuffer=${typeof SharedArrayBuffer !== 'undefined'}.`);
}

function captureRuntime(stream, values) {
  const text = values.map((value) => String(value)).join(' ');
  const line = `${stream}: ${text}`;
  const record = {
    timestamp: new Date().toISOString(),
    elapsedMs: diagnosticElapsedMs(),
    stream,
    text,
  };
  runtimeLines.push(line);
  runtimeLogRing.push(record);
  runtimeLogRingChars += line.length;
  while (runtimeLogRing.length > MAX_RUNTIME_LOG_LINES || runtimeLogRingChars > MAX_RUNTIME_LOG_CHARS) {
    const removed = runtimeLogRing.shift();
    runtimeLogRingChars -= `${removed.stream}: ${removed.text}`.length;
  }
  if (/worker sent an error!|WORKER EXCEPTION STACK|Uncaught (?:RuntimeError|WebAssembly\.Exception)|Aborted\(/i.test(text))
    recordFatalEvent('emscripten-worker-error', { raw: line }, { worker: true });
  if (/WASM HTTP (open|budget|request|AVSEEK_SIZE)|worker sent an error!|WORKER EXCEPTION STACK|ffprobe_cancel/i.test(line))
    write(line);
}

async function runTransportMatrix() {
  check(Module, 'Load the local Wasm bundle first.');
  const base = baseUrl();
  const outcomes = [];
  const hasHttpStreamProbe = typeof Module._ffmpeg_kit_test_http_io_stream_start === 'function' &&
    typeof Module._ffmpeg_kit_test_http_io_stream_status === 'function' &&
    typeof Module._ffmpeg_kit_test_http_io_stream_eio === 'function';
  async function readHttpStream(path) {
    const started = ccall('ffmpeg_kit_test_http_io_stream_start', 'number',
      ['string'], [mediaUrl(path, base)]);
    check(started === 0, `HTTP stream diagnostic did not start (return=${started}).`);
    const deadline = performance.now() + 30000;
    let status = 1;
    while (status === 1 && performance.now() < deadline) {
      await delay(20);
      status = ccall('ffmpeg_kit_test_http_io_stream_status', 'number');
    }
    check(status !== 1, `HTTP stream diagnostic did not finish within 30 seconds for ${path}.`);
    return status;
  }
  async function checkConsistencyFailure(path, logPattern) {
    await resetRequests();
    const logStart = runtimeLines.length;
    const status = await readHttpStream(path);
    const expectedEio = ccall('ffmpeg_kit_test_http_io_stream_eio', 'number');
    check(status === expectedEio,
      `Expected AVERROR(EIO)=${expectedEio} for ${path}, got ${status}.`);
    check(runtimeLines.slice(logStart).some((line) => logPattern.test(line)),
      `No clear resource-consistency error was logged for ${path}.`);
    const requests = await getRequests();
    const ranges = requests.filter((request) => request.path === path &&
      request.status === 206);
    check(ranges.length >= 2 && ranges.some((request) =>
      Number(/^bytes=(\d+)-/.exec(request.range ?? '')?.[1]) > 0),
    `The ${path} fixture did not change metadata across successful ranges.`);
    return { status, ranges: ranges.length };
  }

  outcomes.push(await runCase('HTTP-IO-7 AES-128 HLS rejects the encrypted segment explicitly', async () => {
    await resetRequests();
    const logRingStart = runtimeLogRing.length;
    const startedElapsedMs = diagnosticElapsedMs();
    const result = await probe(mediaUrl('/hls/aes128.m3u8', base));
    check(result.state === STATUS_COMPLETED && result.returnCode !== 0,
      `Encrypted HLS FFprobe state=${result.state}, return=${result.returnCode}.`);
    const unsupportedErrors = runtimeLogRing.slice(logRingStart).filter((entry) =>
      entry.text.includes('AES-128 HLS is not supported in the Wasm build'));
    check(unsupportedErrors.length === 1,
      `Expected one explicit unsupported AES-128 HLS message, got ${unsupportedErrors.length}.`);
    const errorElapsedMs = unsupportedErrors[0].elapsedMs - startedElapsedMs;
    check(errorElapsedMs >= 0 && errorElapsedMs <= 1000,
      `AES-128 rejection was logged after ${errorElapsedMs} ms; limit=1000 ms.`);
    const requests = await getRequests();
    check(requests.some((request) => request.path === '/hls/aes128.m3u8'),
      'The AES-128 playlist was not fetched.');
    const keyRequests = requests.filter((request) => request.path === '/hls/key.bin');
    check(keyRequests.length === 1,
      `Expected HLS to read its key before the encrypted-segment open, got ${keyRequests.length} requests.`);
    check(!requests.some((request) => request.path === '/hls/segment-1.ts'),
      'The encrypted media segment was fetched after the transport rejected AES-128.');
    return { detail: `read one HLS key; logged the unsupported scheme in ${Math.round(errorElapsedMs)} ms; fetched no encrypted segment` };
  }));

  outcomes.push(await runCase('HTTP-IO-6 changing total length returns EIO', async () => {
    if (!hasHttpStreamProbe) return { skip: 'requires the opt-in HTTP consistency diagnostic hook' };
    const previousLogLevel = ccall('ffmpeg_kit_config_get_log_level', 'number');
    ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [48]);
    try {
      const result = await checkConsistencyFailure('/range/changing-size.mp4',
        /WASM HTTP resource length changed across ranges/);
      return { detail: `AVERROR(EIO); rejected changed total after ${result.ranges} successful ranges` };
    } finally {
      ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [previousLogLevel]);
    }
  }));

  outcomes.push(await runCase('HTTP-IO-6 changing ETag returns EIO', async () => {
    if (!hasHttpStreamProbe) return { skip: 'requires the opt-in HTTP consistency diagnostic hook' };
    const previousLogLevel = ccall('ffmpeg_kit_config_get_log_level', 'number');
    ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [48]);
    try {
      const result = await checkConsistencyFailure('/range/changing-etag.mp4',
        /WASM HTTP ETag changed across ranges/);
      return { detail: `AVERROR(EIO); rejected changed ETag after ${result.ranges} successful ranges` };
    } finally {
      ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [previousLogLevel]);
    }
  }));

  outcomes.push(await runCase('HTTP-IO-6 changing Last-Modified returns EIO', async () => {
    if (!hasHttpStreamProbe) return { skip: 'requires the opt-in HTTP consistency diagnostic hook' };
    const previousLogLevel = ccall('ffmpeg_kit_config_get_log_level', 'number');
    ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [48]);
    try {
      const result = await checkConsistencyFailure('/range/changing-last-modified.mp4',
        /WASM HTTP Last-Modified changed across ranges/);
      return { detail: `AVERROR(EIO); rejected changed Last-Modified after ${result.ranges} successful ranges` };
    } finally {
      ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [previousLogLevel]);
    }
  }));

  outcomes.push(await runCase('HTTP-IO-6 ranges re-follow the original redirect URL', async () => {
    if (!hasHttpStreamProbe) return { skip: 'requires the opt-in HTTP consistency diagnostic hook' };
    const head = await fetch(mediaUrl('/media/progressive.mp4', base), { method: 'HEAD' });
    check(head.ok, `Progressive MP4 HEAD returned HTTP ${head.status}.`);
    const expectedSize = Number(head.headers.get('content-length'));
    check(Number.isSafeInteger(expectedSize) && expectedSize > 65536,
      `Invalid progressive MP4 size: ${head.headers.get('content-length')}.`);
    await resetRequests();
    const status = await readHttpStream('/redirect/ranged.mp4');
    check(status === 0, `Stable redirected stream returned ${status}, expected EOF success.`);
    const requests = await getRequests();
    const redirects = requests.filter((request) => request.path === '/redirect/ranged.mp4');
    const responses = requests.filter((request) => request.path === '/media/progressive.mp4');
    check(redirects.length > 1 && redirects.length === responses.length,
      `Expected one original-URL redirect per byte range, got redirects=${redirects.length} ` +
      `range responses=${responses.length}.`);
    let nextByte = 0;
    for (let index = 0; index < redirects.length; index++) {
      const range = /^bytes=(\d+)-(\d+)$/.exec(redirects[index].range ?? '');
      const responseRange = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(
        responses[index].contentRange ?? '');
      check(redirects[index].status === 302 && responses[index].status === 206,
        `Redirect/range pair ${index} returned statuses ${redirects[index].status}/` +
        `${responses[index].status}.`);
      check(range && responses[index].range === redirects[index].range,
        `Redirect/range pair ${index} did not preserve its Range header.`);
      check(Number(range[1]) === nextByte,
        `Redirected range ${index} begins at ${range?.[1]}, expected ${nextByte}.`);
      check(responseRange && Number(responseRange[1]) === Number(range[1]) &&
        Number(responseRange[2]) <= Number(range[2]) &&
        Number(responseRange[3]) === expectedSize,
      `Redirected range ${index} returned invalid Content-Range ${responses[index].contentRange}.`);
      nextByte = Number(responseRange[2]) + 1;
    }
    check(nextByte === expectedSize,
      `Redirected ranges covered ${nextByte} bytes, expected ${expectedSize}.`);
    return { detail: `read ${expectedSize} bytes; ${redirects.length} original-URL redirects matched the ranges` };
  }));

  outcomes.push(await runCase('R5-NEG 416 at EOF requires exposed Content-Range', async () => {
    if (typeof Module._ffmpeg_kit_test_http_io_stream_eof !== 'function' ||
        typeof Module._ffmpeg_kit_test_http_io_stream_erange !== 'function')
      return { skip: 'requires the opt-in HTTP stream diagnostic error hooks' };

    await resetRequests();
    const eofStatus = await readHttpStream('/range/empty-416');
    const expectedEof = ccall('ffmpeg_kit_test_http_io_stream_eof', 'number');
    check(eofStatus === expectedEof,
      `Exposed bytes */0 returned ${eofStatus}, expected AVERROR_EOF=${expectedEof}.`);
    const eofRequests = (await getRequests()).filter((request) =>
      request.path === '/range/empty-416');
    check(eofRequests.length === 1 && eofRequests[0].status === 416 &&
        eofRequests[0].range === 'bytes=0-65535' &&
        eofRequests[0].contentRange === 'bytes */0',
    'The EOF fixture did not return one initial 416 with Content-Range: bytes */0.');

    await resetRequests();
    const hiddenStatus = await readHttpStream('/range/empty-416-hidden');
    const expectedRange = ccall('ffmpeg_kit_test_http_io_stream_erange', 'number');
    check(hiddenStatus === expectedRange,
      `416 without exposed range metadata returned ${hiddenStatus}, expected ERANGE=${expectedRange}.`);
    const hiddenRequests = (await getRequests()).filter((request) =>
      request.path === '/range/empty-416-hidden');
    check(hiddenRequests.length === 1 && hiddenRequests[0].status === 416 &&
        hiddenRequests[0].contentRange === null,
    'The missing-Content-Range fixture did not return the intended 416 response.');
    return { detail: 'valid bytes */0 became EOF; a 416 without Content-Range failed with ERANGE' };
  }));

  outcomes.push(await runCase('R5-NEG malformed 206 is rejected before bytes are read', async () => {
    if (typeof Module._ffmpeg_kit_test_http_io_stream_invaliddata !== 'function')
      return { skip: 'requires the opt-in HTTP stream diagnostic error hook' };
    await resetRequests();
    const logStart = runtimeLines.length;
    const status = await readHttpStream('/range/malformed-206');
    const expected = ccall('ffmpeg_kit_test_http_io_stream_invaliddata', 'number');
    check(status === expected,
      `Malformed 206 returned ${status}, expected AVERROR_INVALIDDATA=${expected}.`);
    const requests = (await getRequests()).filter((request) =>
      request.path === '/range/malformed-206');
    check(requests.length === 1 && requests[0].status === 206 &&
        requests[0].range === 'bytes=0-65535' &&
        /^bytes 1-\d+\/\d+$/.test(requests[0].contentRange ?? ''),
    'The malformed-206 fixture did not return its deliberately shifted Content-Range.');
    check(runtimeLines.slice(logStart).some((line) =>
      line.includes('WASM HTTP 206 response has an invalid or hidden Content-Range')),
    'The transport did not report rejecting the malformed Content-Range.');
    return { detail: 'shifted Content-Range returned AVERROR_INVALIDDATA; no response bytes were accepted' };
  }));

  outcomes.push(await runCase('R5-NEG 301/302/307/308 preserve signed ranges and same-origin Authorization', async () => {
    const head = await fetch(mediaUrl('/media/progressive.mp4', base), { method: 'HEAD' });
    check(head.ok, `Progressive MP4 HEAD returned HTTP ${head.status}.`);
    const expectedSize = Number(head.headers.get('content-length'));
    check(Number.isSafeInteger(expectedSize) && expectedSize > 65536,
      `Invalid progressive MP4 size: ${head.headers.get('content-length')}.`);
    const token = 'r5neg-expiring-query-fixture';
    const logStart = runtimeLines.length;
    for (const redirectStatus of [301, 302, 307, 308]) {
      await resetRequests();
      const path = `/redirect/${redirectStatus}/ranged.mp4?token=${token}`;
      const streamResult = await execute('ffmpeg',
        `-v error -i ${mediaUrl(path, base)} -map 0 -f null -`, { timeoutMs: 30000 });
      check(streamResult.returnCode === 0,
        `HTTP ${redirectStatus} signed range decode returned ${streamResult.returnCode}; ` +
        `output=${streamResult.output.slice(-500)}.`);
      const requests = await getRequests();
      const redirects = requests.filter((request) =>
        request.path === `/redirect/${redirectStatus}/ranged.mp4`);
      const responses = requests.filter((request) =>
        request.path === '/media/progressive.mp4');
      check(redirects.length > 1 && redirects.length === responses.length,
        `HTTP ${redirectStatus} had ${redirects.length} redirect requests and ` +
        `${responses.length} final range requests.`);
      const unmatchedResponses = [...responses];
      for (let index = 0; index < redirects.length; index++) {
        const redirect = redirects[index];
        const requestedRange = /^bytes=(\d+)-(\d+)$/.exec(redirect.range ?? '');
        const responseIndex = unmatchedResponses.findIndex((response) =>
          response.range === redirect.range);
        check(responseIndex >= 0,
          `HTTP ${redirectStatus} redirect range ${redirect.range} had no matching final response.`);
        const [response] = unmatchedResponses.splice(responseIndex, 1);
        const returnedRange = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(
          response.contentRange ?? '');
        check(redirect.status === redirectStatus &&
            redirect.query === `?token=${token}` && response.status === 206 &&
            response.query === `?token=${token}`,
        `HTTP ${redirectStatus} redirect/range pair ${index} lost its status or signed query.`);
        check(requestedRange && returnedRange &&
            Number(returnedRange[1]) === Number(requestedRange[1]) &&
            Number(returnedRange[2]) <= Number(requestedRange[2]) &&
            Number(returnedRange[3]) === expectedSize,
        `HTTP ${redirectStatus} range pair ${index} did not return its requested bytes: ` +
          `requested=${redirect.range}, Content-Range=${response.contentRange}.`);
      }
      check(unmatchedResponses.length === 0,
        `HTTP ${redirectStatus} left ${unmatchedResponses.length} unpaired range responses.`);
    }

    await resetRequests();
    const authUrl = new URL('/redirect/302/basic-auth.mp4?token=auth-query-fixture', base);
    const authorization = `Basic ${btoa('alice@wasm:secret:pass')}`;
    const authResult = await probe(authUrl.href,
      `-v error -headers 'Authorization: ${authorization}'`, { timeoutMs: 10000 });
    check(authResult.state === STATUS_COMPLETED && authResult.returnCode === 0,
      `Same-origin 302 with an allowed Authorization header returned ${authResult.returnCode}.`);
    const authTrace = await getRequests();
    const authRedirects = authTrace.filter((request) =>
      request.method === 'GET' && request.path === '/redirect/302/basic-auth.mp4');
    const authRequests = authTrace.filter((request) =>
      request.method === 'GET' && request.path === '/media/basic-auth.mp4');
    const authorizationPreserved = authRequests.length > 0 && authRequests.every((request) =>
      request.status === 206 && request.authenticated === true);
    const authQueryPreserved = authRedirects.length > 0 &&
      authRedirects.every((request) => request.query === '?token=auth-query-fixture') &&
      authRequests.length > 0 &&
      authRequests.every((request) => request.query === '?token=auth-query-fixture');
    check(authorizationPreserved && authQueryPreserved,
      `Same-origin 302 preserved Authorization=${authorizationPreserved} and ` +
      `the signed query=${authQueryPreserved}.`);

    const diagnosticLogs = runtimeLines.slice(logStart);
    check(!diagnosticLogs.some((line) =>
      /r5neg-expiring-query-fixture|auth-query-fixture/.test(line)),
    'A redirect diagnostic log exposed a query token or URL credential.');
    return { detail: `all four redirect statuses decoded with matched signed ranges; ` +
      `302 preserved Authorization; logs contained no query token or credentials` };
  }));

  outcomes.push(await runCase('R5-NEG expired signed URL fails finitely without logging URL secrets', async () => {
    await resetRequests();
    const token = 'r5neg-token-must-not-appear-in-logs';
    const username = 'r5neg-user-must-not-appear-in-logs';
    const password = 'r5neg-pass-must-not-appear-in-logs';
    const expiredUrl = new URL(`/signed/expired.mp4?token=${token}`, base);
    expiredUrl.username = username;
    expiredUrl.password = password;
    const logStart = runtimeLines.length;
    const started = Date.now();
    const result = await probe(expiredUrl.href, '', { timeoutMs: 10000 });
    const elapsedMs = Date.now() - started;
    check(result.returnCode !== 0,
      `Expired signed URL unexpectedly succeeded with return=${result.returnCode}.`);
    check(elapsedMs < 10000,
      `Expired signed URL failed after ${elapsedMs} ms; limit=10000 ms.`);
    const requests = (await getRequests()).filter((request) =>
      request.path === '/signed/expired.mp4');
    check(requests.length === 1 &&
        requests[0].query === `?token=${token}` && requests[0].status === 403,
    'The expired signed URL did not produce exactly one authenticated-fixture 403.');
    const secrets = [token, username, password];
    const newRuntimeLines = runtimeLines.slice(logStart).map((line) => line.text ?? line);
    check(!newRuntimeLines.some((line) => secrets.some((secret) => line.includes(secret))) &&
        !secrets.some((secret) => result.output.includes(secret)),
    'The expired signed URL credentials or query token appeared in logs or error output.');
    return { detail: `HTTP 403 failed in ${elapsedMs} ms; URL credentials and token were absent from logs and output` };
  }));

  outcomes.push(await runCase('HTTP-IO-4/5 worker deadlines survive a stalled main thread', async () => {
    if (typeof Module._ffmpeg_kit_test_http_io_wait_start !== 'function')
      return { skip: 'requires the opt-in HTTP wait diagnostic hooks' };
    const previousLogLevel = ccall('ffmpeg_kit_config_get_log_level', 'number');
    ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [48]);
    const timeoutMs = 2000;
    const errorsBefore = browserErrors.length;
    const measurements = [];
    try {
      for (const { interruptAfterMs, failCloseProxy } of [
        { interruptAfterMs: 0, failCloseProxy: 0 },
        { interruptAfterMs: 250, failCloseProxy: 0 },
        { interruptAfterMs: 0, failCloseProxy: 1 },
      ]) {
        await resetRequests();
        const logStart = runtimeLines.length;
        const started = ccall('ffmpeg_kit_test_http_io_wait_start', 'number',
          ['string', 'number', 'number', 'number'],
          [mediaUrl('/slow', base), timeoutMs, interruptAfterMs, failCloseProxy]);
        check(started === 0, `Wait worker did not start (return=${started}).`);
        let requestSeen = false;
        for (let attempt = 0; attempt < 50; attempt++) {
          requestSeen = (await getRequests()).some((request) => request.path === '/slow');
          if (requestSeen) break;
          await delay(10);
        }
        check(requestSeen, 'The diagnostic request was not active before the main-thread stall.');
        check(ccall('ffmpeg_kit_test_http_io_wait_status', 'number') === 1,
          'The diagnostic request completed before the main-thread stall.');
        const busyStarted = performance.now();
        while (performance.now() - busyStarted < 2 * timeoutMs) { /* Deliberate main-thread stall. */ }
        const status = ccall('ffmpeg_kit_test_http_io_wait_status', 'number');
        const elapsedMs = ccall('ffmpeg_kit_test_http_io_wait_elapsed', 'number');
        check(status < 0, `Worker did not finish with an error during the stall (status=${status}).`);
        const limitMs = (interruptAfterMs || timeoutMs) + 1000;
        check(Number.isFinite(elapsedMs) && elapsedMs > 0 && elapsedMs <= limitMs,
          `Worker returned after ${elapsedMs} ms; limit=${limitMs} ms.`);
        let report;
        let budget;
        for (let attempt = 0; attempt < 100; attempt++) {
          const logs = runtimeLines.slice(logStart);
          report = logs.find((line) => line.includes('WASM HTTP TEST wait timeout_ms='));
          budget = logs.find((line) => line.includes('WASM HTTP budget complete session=0 requests=1 '));
          if (report && budget) break;
          await delay(25);
        }
        const match = report && /result=(-?\d+) expected=(-?\d+)/.exec(report);
        check(match && status === Number(match[1]) && status === Number(match[2]),
          `Worker did not return the specified timeout/cancellation error: ${report ?? 'no report'}.`);
        check(report.includes(`forced_close_failures=${failCloseProxy}`),
          'The requested close-proxy allocation failure was not exercised.');
        check(budget && /cached=0 pending=0 open_streams=0 active_requests=0/.test(budget),
          `Deferred Fetch/request/session cleanup did not complete: ${budget ?? 'no budget'}.`);
        check(browserErrors.length === errorsBefore, 'Deferred request cleanup caused a browser fault.');
        measurements.push({ interruptAfterMs, failCloseProxy, elapsedMs, status });
      }
      const recovery = await probe(mediaUrl('/media/progressive.mp4', base));
      check(recovery.returnCode === 0, 'The same module could not probe after deferred request cleanup.');
      return { detail: `main stalled ${2 * timeoutMs} ms per case; ` +
        `worker measurements=${JSON.stringify(measurements)}; cleanup and module reuse verified` };
    } finally {
      ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [previousLogLevel]);
    }
  }));
  outcomes.push(await runCase('N01 full 200 WAV response reaches EOF within budget', async () => {
    await resetRequests();
    const logStart = runtimeLines.length;
    const result = await probe(mediaUrl('/media/full-response.wav', base));
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `FFprobe state=${result.state}, return=${result.returnCode}; output=${result.output.slice(-600)}`);
    const metadata = parseProbeJson(result.output);
    check(metadata.format?.format_name?.includes('wav'),
      `Expected WAV metadata, got ${JSON.stringify(metadata.format)}.`);
    const requests = await getRequests();
    check(requests.some((request) => request.path === '/media/full-response.wav' &&
      request.range && request.status === 200),
      'The full-response case did not begin with a Range request.');
    check(runtimeLines.slice(logStart).some((line) => /WASM HTTP open .* range=0 /.test(line)),
      'The full response was not identified as non-range/seekable input.');
    const peak = lastBudgetPeak(logStart);
    check(peak !== null && peak <= 1024 * 1024,
      `Full 200 response exceeded or omitted the 1 MiB tracked budget (peak=${peak}).`);
    return { detail: `format=${metadata.format.format_name}; tracked peak=${peak} bytes` };
  }));

  outcomes.push(await runCase('HTTP-IO-1 invalid request input fails atomically', async () => {
    await resetRequests();
    const errorsBefore = browserErrors.length;
    const invalidHeaders = [
      { label: 'invalid header name', value: 'Bad Name: secret-bad-header-value',
        secret: 'secret-bad-header-value' },
      { label: 'non-Latin-1 header value', value: 'X-Test: secret-euro-€',
        secret: 'secret-euro-€' },
      { label: 'control in header value', value: 'X-Test: control-secret-\u0001-value',
        secret: 'control-secret-' },
    ];

    for (const entry of invalidHeaders) {
      const logStart = runtimeLines.length;
      const startedElapsed = diagnosticElapsedMs();
      const command = `-v error -headers '${entry.value}' ` +
        `-show_entries format=format_name -of json ${mediaUrl('/media/progressive.mp4', base)}`;
      const result = await execute('ffprobe', command, { timeoutMs: 8000 });
      check((result.state === STATUS_COMPLETED || result.state === STATUS_FAILED) &&
        result.returnCode !== 0,
      `${entry.label} did not fail with an FFprobe error (state=${result.state}, ` +
        `return=${result.returnCode}).`);
      const logs = runtimeLines.slice(logStart).join('\n');
      check(logs.includes('WASM browser transport rejected invalid request header'),
        `${entry.label} did not produce the bounded header rejection log.`);
      const rejectionLog = runtimeLogRing.find((record) => record.elapsedMs >= startedElapsed &&
        record.text.includes('WASM browser transport rejected invalid request header'));
      check(rejectionLog && rejectionLog.elapsedMs - startedElapsed < 1000,
        `${entry.label} was not rejected within 1 s of the command start.`);
      check(result.elapsedMs < 8000,
        `${entry.label} did not reach a terminal session state within 8 s.`);
      check(!logs.includes(entry.secret), `${entry.label} value leaked into runtime logs.`);
      check(browserErrors.length === errorsBefore,
        `${entry.label} raised an uncaught browser error.`);
    }

    const invalidUrl = `${base}/media/bad path.mp4`;
    const urlLogStart = runtimeLines.length;
    const urlStartedElapsed = diagnosticElapsedMs();
    const invalidUrlResult = await execute('ffprobe',
      `-v error -show_entries format=format_name -of json '${invalidUrl}'`,
      { timeoutMs: 8000 });
    check(invalidUrlResult.returnCode !== 0 && invalidUrlResult.elapsedMs < 8000,
      `Whitespace in an HTTP URL did not reach a terminal failure (return=${invalidUrlResult.returnCode}, ` +
        `elapsed=${invalidUrlResult.elapsedMs} ms).`);
    const urlLogs = runtimeLines.slice(urlLogStart).join('\n');
    check(urlLogs.includes('WASM browser transport rejected whitespace/control in HTTP URL'),
    'Whitespace in an HTTP URL did not use the explicit rejection path.');
    const urlRejectionLog = runtimeLogRing.find((record) => record.elapsedMs >= urlStartedElapsed &&
      record.text.includes('WASM browser transport rejected whitespace/control in HTTP URL'));
    check(urlRejectionLog && urlRejectionLog.elapsedMs - urlStartedElapsed < 1000,
      'Whitespace in an HTTP URL was not rejected within 1 s of the command start.');
    check(browserErrors.length === errorsBefore,
      'Whitespace in an HTTP URL raised an uncaught browser error.');
    const inputRequests = await getRequests();
    check(!inputRequests.some((request) => request.path.startsWith('/media/')),
      'An invalid header or URL reached a media route on the fixture server.');

    const warningStart = runtimeLines.length;
    const forbidden = await probe(mediaUrl('/media/progressive.mp4', base),
      "-v warning -headers 'Sec-FFKit-Probe: secret-value'");
    check(forbidden.returnCode === 0,
      `Browser-controlled header prevented a valid request (return=${forbidden.returnCode}).`);
    const warningLogs = runtimeLines.slice(warningStart).join('\n');
    check(warningLogs.includes('ignored browser-controlled request header(s): Sec-FFKit-Probe'),
      'Dropped browser-controlled headers did not produce one warning naming the field.');
    check((warningLogs.match(/ignored browser-controlled request header\(s\)/g) || []).length === 1,
      'Browser-controlled request headers produced more than one warning in a session.');
    check(!warningLogs.includes('secret-value'),
      'A browser-controlled header value leaked into runtime logs.');
    check(browserErrors.length === errorsBefore,
      'A dropped browser-controlled header raised an uncaught browser error.');

    const ignoredOptionStart = runtimeLines.length;
    const ignoredOptions = await probe(mediaUrl('/media/progressive.mp4', base),
      "-v warning -user_agent 'private-agent-value' " +
      "-referer 'https://private.invalid/private-path' -cookies 'private-cookie=value'");
    check(ignoredOptions.returnCode === 0,
      `Ignored browser-controlled options prevented a valid request (return=${ignoredOptions.returnCode}).`);
    const ignoredOptionLogs = runtimeLines.slice(ignoredOptionStart).join('\n');
    const ignoredOptionWarnings = ignoredOptionLogs.match(
      /WASM browser transport ignored browser-controlled option\(s\):[^\n]*/g) || [];
    check(ignoredOptionWarnings.length === 1 &&
      ignoredOptionWarnings[0].includes('user_agent') &&
      ignoredOptionWarnings[0].includes('referer') &&
      ignoredOptionWarnings[0].includes('cookies'),
    'Ignored browser-controlled options did not produce one warning listing each option.');
    check(!ignoredOptionLogs.includes('private-agent-value') &&
      !ignoredOptionLogs.includes('private.invalid') &&
      !ignoredOptionLogs.includes('private-cookie=value'),
    'An ignored browser-controlled option value leaked into runtime logs.');
    check(browserErrors.length === errorsBefore,
      'Ignored browser-controlled options raised an uncaught browser error.');

    await resetRequests();
    const nonSeekable = await probe(mediaUrl('/media/progressive.mp4', base),
      '-v error -seekable 0');
    check(nonSeekable.returnCode === 0,
      `seekable=0 prevented a valid ranged read (return=${nonSeekable.returnCode}).`);
    const nonSeekableRequests = await getRequests();
    check(nonSeekableRequests.some((request) =>
      request.path === '/media/progressive.mp4' && request.range),
    'seekable=0 unexpectedly suppressed the browser Range request.');
    check(browserErrors.length === errorsBefore,
      'The seekable=0 ranged read raised an uncaught browser error.');

    const followup = await probe(mediaUrl('/media/progressive.mp4', base), '-v error');
    check(followup.returnCode === 0,
      `A valid request did not work on the same module after rejections (return=${followup.returnCode}).`);
    check(browserErrors.length === errorsBefore,
      'The valid follow-up request raised an uncaught browser error.');
    return { detail: `${invalidHeaders.length} invalid headers and one invalid URL failed promptly; ` +
      `the same module completed two valid requests afterward` };
  }));

  outcomes.push(await runCase('HTTP-IO-10 percent-decodes URL Basic credentials', async () => {
    await resetRequests();
    const authUrl = `http://alice%40wasm:secret%3Apass@${new URL(base).host}/media/basic-auth.mp4`;
    const logStart = runtimeLines.length;
    const authResult = await probe(authUrl, '-v error', { timeoutMs: 10000 });
    check(authResult.state === STATUS_COMPLETED && authResult.returnCode === 0,
      `Percent-encoded Basic credentials were rejected (return=${authResult.returnCode}).`);
    const authRequests = (await getRequests()).filter((request) =>
      request.method === 'GET' && request.path === '/media/basic-auth.mp4');
    const acceptedRanges = authRequests.filter((request) =>
      request.range && request.status === 206);
    check(acceptedRanges.length > 0 && acceptedRanges.every((request) =>
      request.authenticated === true),
    `The fixture did not accept decoded credentials on every successful range response: ${JSON.stringify(
      authRequests.map(({ status, range, authenticated }) => ({ status, range, authenticated })))}.`);
    const secrets = ['alice@wasm', 'secret:pass', 'alice%40wasm', 'secret%3Apass'];
    const newRuntimeLines = runtimeLines.slice(logStart).map((line) => line.text ?? line);
    check(!newRuntimeLines.some((line) => secrets.some((secret) => line.includes(secret))) &&
        !secrets.some((secret) => authResult.output.includes(secret)),
    'The credentialed URL appeared in runtime logs or FFprobe output.');
    return { detail: `percent-decoded Basic credentials authenticated ${acceptedRanges.length} ranged request(s); ` +
      `credentials were absent from runtime logs and FFprobe output` };
  }));

  outcomes.push(await runCase('HTTP-IO-10 validates session and separates queue/request timeouts', async () => {
    if (typeof Module._ffmpeg_kit_test_http_io_session_magic !== 'function' ||
        typeof Module._ffmpeg_kit_test_http_io_admission_start !== 'function' ||
        typeof Module._ffmpeg_kit_test_http_io_admission_status !== 'function' ||
        typeof Module._ffmpeg_kit_test_http_io_admission_elapsed !== 'function')
      return { skip: 'requires the opt-in HTTP-IO-10 diagnostic hooks' };

    const magicResult = ccall('ffmpeg_kit_test_http_io_session_magic', 'number');
    check(magicResult === 0,
      `Invalid session magic changed the reference count or cleanup failed (return=${magicResult}).`);

    await resetRequests();
    const timeoutMs = 500;
    const slotHoldMs = 400;
    const started = ccall('ffmpeg_kit_test_http_io_admission_start', 'number',
      ['string', 'number', 'number'],
      [mediaUrl('/media/progressive-queue.mp4', base), timeoutMs, slotHoldMs]);
    check(started === 0, `Admission diagnostic did not start (return=${started}).`);
    let status = 1;
    const deadline = Date.now() + 2500;
    while (status === 1 && Date.now() < deadline) {
      await delay(20);
      status = ccall('ffmpeg_kit_test_http_io_admission_status', 'number');
    }
    const elapsedMs = ccall('ffmpeg_kit_test_http_io_admission_elapsed', 'number');
    check(status === 0,
      `Request timed out or failed after admission (return=${status}, elapsed=${elapsedMs} ms).`);
    check(Number.isFinite(elapsedMs) && elapsedMs >= slotHoldMs + 250 && elapsedMs < 2500,
      `Queued request elapsed ${elapsedMs} ms; expected queue plus response delay within the fresh request deadline.`);
    const queuedRequests = await getRequests();
    check(queuedRequests.some((request) =>
      request.path === '/media/progressive-queue.mp4' && request.range &&
      request.status === 206),
    'The request did not reach the delayed ranged-response fixture.');
    check(browserErrors.length === 0,
      `HTTP-IO-10 raised a browser error: ${browserErrors.join(' | ')}`);
    return { detail: `invalid magic ignored; queue=${slotHoldMs} ms, response=300 ms, ` +
      `timeout=${timeoutMs} ms, elapsed=${Math.round(elapsedMs)} ms` };
  }));

  outcomes.push(await runCase('HTTP-IO-2 release AVIO buffers across 500 HTTP lifecycles', async () => {
    if (typeof Module._ffmpeg_kit_test_http_io_heap_start !== 'function' ||
        typeof Module._ffmpeg_kit_test_http_io_heap_status !== 'function')
      return { skip: 'requires the opt-in Wasm HTTP heap test-hook build' };

    const previousLogLevel = ccall('ffmpeg_kit_config_get_log_level', 'number');
    ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [48]);
    try {
      await resetRequests();
      const logStart = runtimeLines.length;
      const start = ccall('ffmpeg_kit_test_http_io_heap_start', 'number',
        ['string', 'number', 'number'], [mediaUrl('/media/progressive.mp4', base), 10, 500]);
      check(start === 0, `The heap lifecycle worker did not start (return=${start}).`);
      const testStartedAt = Date.now();
      let status = 1;
      while (status === 1 && Date.now() - testStartedAt < 180000) {
        await delay(25);
        status = ccall('ffmpeg_kit_test_http_io_heap_status', 'number');
      }
      check(status === 0,
        `The 500-cycle heap probe did not complete successfully (status=${status}).`);
      let testLogs;
      let heapLine;
      for (let attempt = 0; attempt < 100; attempt++) {
        testLogs = runtimeLines.slice(logStart);
        heapLine = testLogs.find((line) => line.includes(
          'WASM HTTP TEST heap cycles=500 warmup=10'));
        if (heapLine && testLogs.some((line) =>
          line.includes('WASM HTTP budget complete session=0 requests=510'))) break;
        await delay(25);
      }
      check(heapLine, 'The test-only mallinfo heap report was not emitted.');
      const heapMatch = /before=(\d+) after=(\d+) delta=(-?\d+)/.exec(heapLine);
      check(heapMatch, `Could not parse the mallinfo heap report: ${heapLine}`);
      const heapDelta = Number(heapMatch[3]);
      check(Number.isSafeInteger(heapDelta) && Math.abs(heapDelta) <= 4096,
        `500 HTTP AVIO lifecycles changed uordblks by ${heapDelta} bytes.`);

      const requests = await getRequests();
      const mediaRequests = requests.filter((request) =>
        request.path === '/media/progressive.mp4' && request.range);
      check(mediaRequests.length === 510,
        `Expected 510 ranged opens including warm-up, observed ${mediaRequests.length}.`);
      const summary = testLogs.find((line) =>
        line.includes('WASM HTTP budget complete session=0 requests=510'));
      check(summary && /cached=0 pending=0 open_streams=0 active_requests=0/.test(summary),
        `HTTP resources did not settle after the lifecycle probe: ${summary || 'no summary'}`);
      return { detail: `warmup=10; measured=500; uordblks delta=${heapDelta} bytes; ` +
        `ranged opens=${mediaRequests.length}; all HTTP counters returned to zero` };
    } finally {
      ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [previousLogLevel]);
    }
  }));

  outcomes.push(await runCase('N09 direct progressive MP4 metadata via byte ranges', async () => {
    await resetRequests();
    const logStart = runtimeLines.length;
    const result = await probe(mediaUrl('/media/progressive.mp4', base));
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `FFprobe state=${result.state}, return=${result.returnCode}.`);
    const metadata = parseProbeJson(result.output);
    check(metadata.format?.format_name?.includes('mp4'),
      `Expected MP4 metadata, got ${JSON.stringify(metadata.format)}.`);
    const requests = await getRequests();
    check(requests.some((request) => request.path === '/media/progressive.mp4' &&
      request.range && request.status === 206),
      'No successful 206 byte-range response was observed for progressive MP4.');
    const workers = workerIdsSince(logStart);
    check(workers.length > 0, 'No HTTP open worker identity was logged.');
    return { detail: `format=${metadata.format.format_name}; requests=${requests.length}; ` +
      `worker IDs=${[...new Set(workers)].join(',')}` };
  }));

  outcomes.push(await runCase('HTTP-IO-8 adaptive ranges halve progressive MP4 round trips', async () => {
    if (!hasHttpStreamProbe)
      return { skip: 'requires the opt-in raw HTTP AVIO diagnostic hook' };
    const url = mediaUrl('/media/progressive-latency.mp4', base);
    const head = await fetch(url, { method: 'HEAD', cache: 'no-store' });
    check(head.ok, `Latency fixture HEAD returned HTTP ${head.status}.`);
    const size = Number(head.headers.get('content-length'));
    check(Number.isSafeInteger(size) && size > 0, `Invalid latency fixture size ${size}.`);

    const baselineChunkSize = 64 * 1024;
    const baselineRequestCount = Math.ceil(size / baselineChunkSize);
    check(baselineRequestCount >= 6,
      `The progressive fixture is too small for a meaningful latency comparison (${size} bytes).`);
    await resetRequests();
    const baselineStart = performance.now();
    let baselineBytes = 0;
    for (let start = 0; start < size; start += baselineChunkSize) {
      const end = Math.min(start + baselineChunkSize, size) - 1;
      const response = await fetch(url, {
        headers: { Range: `bytes=${start}-${end}` },
        cache: 'no-store',
      });
      check(response.status === 206,
        `64 KiB baseline range ${start}-${end} returned HTTP ${response.status}.`);
      const contentRange = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(
        response.headers.get('content-range') ?? '',
      );
      check(contentRange && Number(contentRange[1]) === start &&
        Number(contentRange[2]) === end && Number(contentRange[3]) === size,
      `64 KiB baseline range ${start}-${end} returned an invalid Content-Range.`);
      baselineBytes += (await response.arrayBuffer()).byteLength;
    }
    const baselineElapsed = Math.round(performance.now() - baselineStart);
    check(baselineBytes === size,
      `64 KiB baseline read ${baselineBytes} of ${size} bytes.`);
    const baselineRequests = await getRequests();
    const observedBaselineRanges = baselineRequests.filter((request) =>
      request.path === '/media/progressive-latency.mp4' && request.range &&
      request.status === 206);
    check(observedBaselineRanges.length === baselineRequestCount,
      `Expected ${baselineRequestCount} delayed baseline ranges; observed ${observedBaselineRanges.length}.`);

    await resetRequests();
    const logStart = runtimeLines.length;
    const previousLogLevel = ccall('ffmpeg_kit_config_get_log_level', 'number');
    ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [48]);
    const readStart = performance.now();
    try {
      const status = await readHttpStream('/media/progressive-latency.mp4');
      const readElapsed = Math.round(performance.now() - readStart);
      check(status === 0, `Raw progressive MP4 AVIO read returned ${status}, expected EOF success.`);
      const readRequests = await getRequests();
      const adaptiveRanges = readRequests.filter((request) =>
        request.path === '/media/progressive-latency.mp4' && request.range &&
        request.status === 206);
      const adaptiveRangeSizes = adaptiveRanges.map((request) => {
        const match = /^bytes=(\d+)-(\d+)$/.exec(request.range);
        return match ? Number(match[2]) - Number(match[1]) + 1 : 0;
      });
      const peak = lastBudgetPeak(logStart);
      const speedup = baselineElapsed / readElapsed;
      write(`HTTP-IO-8 measurement bytes=${size}; direct 64 KiB reference=` +
        `${baselineElapsed} ms/${observedBaselineRanges.length} ranges; ` +
        `raw Wasm AVIO=${readElapsed} ms/${adaptiveRanges.length} ranges ` +
        `[${adaptiveRangeSizes.join(',')} bytes]; speedup=${speedup.toFixed(2)}x; peak=${peak}`);
      check(adaptiveRanges.length > 0, 'The Wasm read issued no successful MP4 ranges.');
      check(adaptiveRangeSizes.some((rangeSize) => rangeSize > baselineChunkSize),
        `No adaptive range grew beyond ${baselineChunkSize} bytes.`);
      check(adaptiveRangeSizes.every((rangeSize) => rangeSize <= 512 * 1024),
        `An adaptive range exceeded 512 KiB: ${adaptiveRangeSizes.join(', ')}.`);
      check(adaptiveRanges.length * 2 <= observedBaselineRanges.length,
        `Adaptive Wasm read used ${adaptiveRanges.length} ranges versus ` +
        `${observedBaselineRanges.length} 64 KiB baseline ranges.`);
      check(readElapsed * 2 <= baselineElapsed,
        `Raw Wasm AVIO read took ${readElapsed} ms; the 64 KiB reference took ` +
        `${baselineElapsed} ms, below the required 2x throughput gain.`);
      check(peak !== null, 'No session response-memory peak was emitted.');
      check(peak <= 1024 * 1024,
        `Adaptive response-memory peak exceeded 1 MiB (${peak} bytes).`);
      return { detail: `bytes=${size}; baseline=${baselineElapsed} ms/` +
        `${observedBaselineRanges.length} ranges; Wasm=${readElapsed} ms/` +
        `${adaptiveRanges.length} ranges (${adaptiveRangeSizes.join(',')} bytes); ` +
        `speedup=${speedup.toFixed(2)}x; peak=${peak} bytes` };
    } finally {
      ccall('ffmpeg_kit_config_set_log_level', 'void', ['number'], [previousLogLevel]);
    }
  }));

  outcomes.push(await runCase('N02 range seek and size behavior', async () => {
    await resetRequests();
    const head = await fetch(mediaUrl('/media/progressive.mp4', base), { method: 'HEAD' });
    check(head.ok, `MP4 HEAD request returned HTTP ${head.status}.`);
    const expectedSize = Number(head.headers.get('content-length'));
    check(Number.isSafeInteger(expectedSize) && expectedSize > 0,
      `Invalid MP4 Content-Length: ${head.headers.get('content-length')}.`);
    const logStart = runtimeLines.length;
    const result = await probe(mediaUrl('/media/progressive.mp4', base),
      '-read_intervals 1%+0.25 -show_packets -show_entries packet=pts');
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `FFprobe state=${result.state}, return=${result.returnCode}.`);
    const requests = await getRequests();
    const nonzeroRange = requests.some((request) => {
      const match = /^bytes=(\d+)-/.exec(request.range ?? '');
      return match && Number(match[1]) > 0 && request.status === 206;
    });
    check(nonzeroRange, 'The seek probe did not request a nonzero byte range.');
    const sizeLog = runtimeLines.slice(logStart)
      .find((line) => /WASM HTTP AVSEEK_SIZE .* size=\d+(?:\s|$)/.test(line));
    const reportedSize = sizeLog && /\bsize=(\d+)\b/.exec(sizeLog);
    check(Number(reportedSize?.[1]) === expectedSize,
      `AVSEEK_SIZE returned ${reportedSize?.[1] ?? 'no size'}, expected ${expectedSize}.`);
    return { detail: `AVSEEK_SIZE=${expectedSize}; nonzero 206 range observed; requests=${requests.length}` };
  }));

  outcomes.push(await runCase('HTTP range continuity matches every native MPEG-TS packet', async () => {
    await resetRequests();
    const referenceResponse = await fetch(mediaUrl('/media/live-template-packets.json', base));
    check(referenceResponse.ok, `Native packet reference returned HTTP ${referenceResponse.status}.`);
    const reference = await referenceResponse.json();
    check(reference.sourceBytes > 2 * 65536 && reference.packets.length > 0,
      'The independent native packet reference does not cover multiple HTTP ranges.');
    const result = await probe(mediaUrl('/media/live-template.ts', base),
      '-show_packets -show_data_hash sha256 -show_entries packet=stream_index,pts,dts,size,data_hash',
      { timeoutMs: 30000 });
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `Full MPEG-TS packet probe state=${result.state}, return=${result.returnCode}.`);
    const actual = parseProbeJson(result.output).packets;
    check(Array.isArray(actual) && actual.length === reference.packets.length,
      `HTTP returned ${actual?.length ?? 0} packets; native returned ${reference.packets.length}.`);
    for (let index = 0; index < reference.packets.length; index++) {
      for (const key of ['stream_index', 'pts', 'dts', 'size', 'data_hash']) {
        check(actual[index][key] === reference.packets[index][key],
          `HTTP packet ${index} ${key}=${actual[index][key]}; native=${reference.packets[index][key]}.`);
      }
    }
    const requests = await getRequests();
    check(requests.some((request) => request.path === '/media/live-template.ts' &&
      Number(/^bytes=(\d+)-/.exec(request.range ?? '')?.[1]) >= 131072 && request.status === 206),
    'The full packet probe did not reach the third HTTP range.');
    return { detail: `all ${actual.length} native packet hashes/timestamps/sizes match; ` +
      `source=${reference.sourceBytes} bytes; SHA-256=${reference.sourceSha256}` };
  }));

  outcomes.push(await runCase('N03 invalid response that ignores Range fails within budget', async () => {
    const logStart = runtimeLines.length;
    const start = Date.now();
    const result = await probe(mediaUrl('/range/ignored', base));
    check(result.returnCode !== 0, 'Invalid Range-ignoring response unexpectedly succeeded.');
    check(Date.now() - start < 10000, 'Range-ignoring response did not fail promptly.');
    const peak = lastBudgetPeak(logStart);
    check(peak !== null, 'No response-memory budget summary was emitted.');
    check(peak <= 1024 * 1024, `Range-ignoring response peak exceeded 1 MiB (${peak} bytes).`);
    const logs = runtimeLines.slice(logStart);
    check(!logs.some((line) => line.includes('HTTP 65535')),
      'The buffer-limit abort was misreported as HTTP 65535.');
    check(logs.filter((line) => line.includes('WASM HTTP response exceeded')).length === 1,
      'The buffer-limit failure was not logged exactly once with its real cause.');
    return { detail: `finite failure in ${Date.now() - start} ms; tracked peak=${peak} bytes` };
  }));

  outcomes.push(await runCase('N04 truncated response fails finitely', async () => {
    const logStart = runtimeLines.length;
    const start = Date.now();
    const result = await probe(mediaUrl('/truncated', base));
    check(result.returnCode !== 0, 'Truncated response unexpectedly succeeded.');
    check(Date.now() - start < 10000, 'Truncated response did not fail promptly.');
    const peak = lastBudgetPeak(logStart);
    check(peak !== null, 'No response-memory budget summary was emitted.');
    check(peak <= 1024 * 1024, `Tracked response memory peak exceeded 1 MiB (${peak} bytes).`);
    return { detail: `finite failure in ${Date.now() - start} ms; tracked peak=${peak} bytes` };
  }));

  outcomes.push(await runCase('N06 HTTP status errors', async () => {
    for (const status of [403, 404, 500]) {
      const logStart = runtimeLines.length;
      const result = await probe(mediaUrl(`/status/${status}`, base));
      check(result.returnCode !== 0, `HTTP ${status} unexpectedly succeeded.`);
      const logs = runtimeLines.slice(logStart);
      check(!logs.some((line) => line.includes('HTTP 65535')),
        `HTTP ${status} was overwritten by the fetch-close sentinel.`);
      check(logs.filter((line) => line.includes(`WASM HTTP request failed: HTTP ${status} `)).length === 1,
        `HTTP ${status} was not logged exactly once with the original status.`);
    }
    return { detail: '403, 404, and 500 all returned finite FFprobe failures' };
  }));

  outcomes.push(await runCase('N06 dropped connection produces a finite network failure', async () => {
    const start = Date.now();
    const result = await probe(mediaUrl('/offline', base));
    check(result.returnCode !== 0, 'Dropped connection unexpectedly succeeded.');
    check(Date.now() - start < 10000, 'Dropped connection did not fail promptly.');
    return { detail: `finite network failure in ${Date.now() - start} ms` };
  }));

  outcomes.push(await runCase('N06 cross-origin missing CORS response', async () => {
    if (new URL(base).origin === location.origin)
      return { skip: 'open this page at http://localhost and set Fixture origin to the printed 127.0.0.1 URL' };
    const result = await probe(mediaUrl('/cors/absent', base));
    check(result.returnCode !== 0, 'Cross-origin request without CORS unexpectedly succeeded.');
    return { detail: `finite CORS failure, return=${result.returnCode}` };
  }));

  outcomes.push(await runCase('N07 cancel an active slow HTTP request', async () => {
    const start = Date.now();
    const logStart = runtimeLines.length;
    await resetRequests();
    const handle = startSession('ffprobe', ffprobeCommand(mediaUrl('/slow', base)));
    try {
      let slowRequestSeen = false;
      for (let attempt = 0; attempt < 100; attempt++) {
        const requests = await getRequests();
        slowRequestSeen = requests.some((request) => request.path === '/slow');
        if (slowRequestSeen) break;
        if (sessionState(handle) === STATUS_COMPLETED || sessionState(handle) === STATUS_FAILED) break;
        await delay(40);
      }
      check(slowRequestSeen, 'Slow HTTP request did not start before cancellation.');
      check(sessionState(handle) === STATUS_RUNNING, 'Slow FFprobe was not still running before cancellation.');
      const sessionId = ccall('ffmpeg_kit_session_get_session_id', 'bigint', ['number'], [handle]);
      check(sessionId > 0n, 'FFprobe session did not expose a valid session ID.');
      const cancelStarted = Date.now();
      ccall('ffprobe_kit_cancel_session', 'void', ['bigint'], [sessionId]);
      const result = await waitForSession(handle, 12000);
      check(result.returnCode !== 0, 'Cancelled FFprobe returned success.');
      const cancelElapsed = Date.now() - cancelStarted;
      const interruptObserved = runtimeLines.slice(logStart).some((line) =>
        line.includes('ffprobe_cancel_requested') || line.includes('WASM HTTP request interrupted'));
      check(interruptObserved, 'The interrupt callback did not report observing cancellation.');
      check(cancelElapsed < 12000, `Cancellation took ${cancelElapsed} ms after the slow request started.`);
      const budget = runtimeLines.slice(logStart)
        .find((line) => line.includes('WASM HTTP budget complete'));
      check(budget && /open_streams=0 active_requests=0/.test(budget),
        'The cancelled HTTP request did not release its stream and request budget.');
      const logs = runtimeLines.slice(logStart);
      check(!logs.some((line) => /HTTP 65535|ERROR:.*WASM (?:HTTP|browser)/.test(line)),
        'The cancelled HTTP request produced a transport error log.');
      check(logs.filter((line) => line.includes('WASM HTTP request interrupted')).length === 1,
        'The HTTP cancellation was not logged exactly once at DEBUG level.');
      return { detail: `interrupt observed; cancelled in ${cancelElapsed} ms after request start; streams released` };
    } finally {
      await finishSession('ffprobe', handle);
    }
  }));

  outcomes.push(await runCase('R5-NEG concurrent sessions cancel independently', async () => {
    await resetRequests();
    const logStart = runtimeLines.length;
    let priorHandle = 0;
    let leftHandle = 0;
    let rightHandle = 0;
    try {
      priorHandle = startSession('ffprobe', ffprobeCommand(mediaUrl('/slow', base)));
      const priorId = ccall('ffmpeg_kit_session_get_session_id', 'bigint',
        ['number'], [priorHandle]);
      let priorOpen = false;
      for (let attempt = 0; attempt < 125; attempt++) {
        priorOpen = runtimeLines.some((line) => line.includes('WASM HTTP open') &&
          line.includes(`session=${priorId} `) && line.includes('/slow'));
        if (priorOpen) break;
        await delay(40);
      }
      check(priorOpen && sessionState(priorHandle) === STATUS_RUNNING,
        'The cancellation-recovery request did not become active.');
      ccall('ffprobe_kit_cancel_session', 'void', ['bigint'], [priorId]);
      const priorResult = await waitForSession(priorHandle, 12000);
      check(priorResult.returnCode !== 0,
        'The cancellation-recovery FFprobe unexpectedly succeeded.');
      await finishSession('ffprobe', priorHandle);
      priorHandle = 0;

      leftHandle = startSession('ffprobe',
        ffprobeCommand(mediaUrl('/slow/independent-left', base)));
      rightHandle = startSession('ffprobe',
        ffprobeCommand(mediaUrl('/slow/independent-right', base)));
      const leftId = ccall('ffmpeg_kit_session_get_session_id', 'bigint',
        ['number'], [leftHandle]);
      const rightId = ccall('ffmpeg_kit_session_get_session_id', 'bigint',
        ['number'], [rightHandle]);
      check(leftId > 0n && rightId > 0n && leftId !== rightId,
        'Concurrent FFprobe sessions did not receive distinct IDs.');

      let leftRequestSeen = false;
      let rightRequestSeen = false;
      for (let attempt = 0; attempt < 125; attempt++) {
        leftRequestSeen = runtimeLines.some((line) => line.includes('WASM HTTP open') &&
          line.includes(`session=${leftId} `) && line.includes('/slow/independent-left'));
        rightRequestSeen = runtimeLines.some((line) => line.includes('WASM HTTP open') &&
          line.includes(`session=${rightId} `) && line.includes('/slow/independent-right'));
        if (leftRequestSeen && rightRequestSeen) break;
        await delay(40);
      }
      check(leftRequestSeen && rightRequestSeen,
        'Both independent slow HTTP requests did not start concurrently.');
      check(sessionState(leftHandle) === STATUS_RUNNING &&
          sessionState(rightHandle) === STATUS_RUNNING,
      'Both FFprobe sessions were not still running before cancellation.');
      write(`R5-NEG concurrent: both HTTP streams opened; cancelling session ${leftId}.`);

      ccall('ffprobe_kit_cancel_session', 'void', ['bigint'], [leftId]);
      const leftResult = await waitForSession(leftHandle, 12000);
      check(leftResult.returnCode !== 0,
        'The explicitly cancelled left FFprobe session returned success.');
      await delay(200);
      check(sessionState(rightHandle) === STATUS_RUNNING,
        'Cancelling the left FFprobe session also stopped the independent right session.');
      write(`R5-NEG concurrent: session ${leftId} ended; session ${rightId} remains running.`);

      ccall('ffprobe_kit_cancel_session', 'void', ['bigint'], [rightId]);
      const rightResult = await waitForSession(rightHandle, 12000);
      check(rightResult.returnCode !== 0,
        'The explicitly cancelled right FFprobe session returned success.');

      const logs = runtimeLines.slice(logStart);
      for (const id of [priorId, leftId, rightId]) {
        const budget = logs.find((line) =>
          line.includes(`WASM HTTP budget complete session=${id} `));
        check(budget && /cached=0 pending=0 open_streams=0 active_requests=0/.test(budget),
          `Session ${id} did not release its independent HTTP budget after cancellation.`);
      }
      for (const [id, path] of [[priorId, '/slow'], [leftId, '/slow/independent-left'],
        [rightId, '/slow/independent-right']]) {
        check(logs.some((line) => line.includes('WASM HTTP request interrupted') &&
          line.includes(path)),
        `Session ${id} did not log its own request interruption.`);
      }
      return { detail: `sessions=${leftId}/${rightId}; left cancellation left right running; ` +
        'both later cancelled with zeroed independent HTTP budgets after prior cancellation recovery' };
    } finally {
      if (priorHandle) await finishSession('ffprobe', priorHandle);
      if (leftHandle) await finishSession('ffprobe', leftHandle);
      if (rightHandle) await finishSession('ffprobe', rightHandle);
    }
  }));

  outcomes.push(await runCase('N08 sequential sessions release their resources', async () => {
    const logStart = runtimeLines.length;
    const heapBefore = Module.HEAPU8.buffer.byteLength;
    for (let index = 0; index < 5; index++) {
      const result = await probe(mediaUrl('/media/progressive.mp4', base));
      check(result.state === STATUS_COMPLETED && result.returnCode === 0,
        `Session ${index + 1} state=${result.state}, return=${result.returnCode}.`);
    }
    const heapMiddle = Module.HEAPU8.buffer.byteLength;
    for (let index = 5; index < 10; index++) {
      const result = await probe(mediaUrl('/media/progressive.mp4', base));
      check(result.state === STATUS_COMPLETED && result.returnCode === 0,
        `Session ${index + 1} state=${result.state}, return=${result.returnCode}.`);
    }
    const heapAfter = Module.HEAPU8.buffer.byteLength;
    const budgets = runtimeLines.slice(logStart)
      .filter((line) => line.includes('WASM HTTP budget complete'));
    const cleanBudgets = budgets.filter((line) =>
      /cached=0 pending=0 open_streams=0 active_requests=0/.test(line));
    check(cleanBudgets.length >= 10,
      `Expected 10 clean budget summaries; observed ${cleanBudgets.length}.`);
    check(heapAfter <= heapMiddle + 8 * 1024 * 1024,
      `Wasm heap grew by more than 8 MiB over the second five sessions (${heapMiddle}→${heapAfter}).`);
    const workers = workerIdsSince(logStart);
    check(workers.length >= 10, `Expected worker identity for all 10 sessions; observed ${workers.length}.`);
    return { detail: `10 sessions; clean summaries=${cleanBudgets.length}; ` +
      `heap=${heapBefore}→${heapMiddle}→${heapAfter}; worker IDs=${[...new Set(workers)].join(',')}` };
  }));

  outcomes.push(await runCase('N15a imported and generated MEMFS MP4', async () => {
    const mp4Response = await fetch(mediaUrl('/media/progressive.mp4', base));
    check(mp4Response.ok, `MP4 import failed with HTTP ${mp4Response.status}.`);
    Module.FS.writeFile('/wasm-streaming-import.mp4',
      new Uint8Array(await mp4Response.arrayBuffer()));
    const imported = await probe('/wasm-streaming-import.mp4');
    check(imported.returnCode === 0, `Imported MEMFS MP4 return=${imported.returnCode}.`);

    const generated = await execute('ffmpeg',
      `-nostdin -v error -i /wasm-streaming-import.mp4 -c copy /wasm-streaming-generated.mp4`);
    check(generated.returnCode === 0, `Generated MEMFS MP4 return=${generated.returnCode}.`);
    const generatedProbe = await probe('/wasm-streaming-generated.mp4');
    check(generatedProbe.returnCode === 0, `Generated MEMFS MP4 probe return=${generatedProbe.returnCode}.`);
    return { detail: 'imported and generated MP4 probed from MEMFS' };
  }));

  if (selectedTransportCase?.startsWith('N15c')) outcomes.push(await runCase('N15c read-interval FFprobe options on MEMFS MP4 (metadata only)', async () => {
    const mp4Response = await fetch(mediaUrl('/media/progressive.mp4', base));
    check(mp4Response.ok, `MP4 import failed with HTTP ${mp4Response.status}.`);
    Module.FS.writeFile('/wasm-streaming-one-packet-control.mp4',
      new Uint8Array(await mp4Response.arrayBuffer()));
    const result = await execute('ffprobe',
      `-v error -read_intervals %+#1 ` +
      `-show_entries format=format_name:stream=codec_name,profile,width,height,sample_rate,channels ` +
      `-of json /wasm-streaming-one-packet-control.mp4`);
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `Metadata-only interval-options MP4 FFprobe state=${result.state}, return=${result.returnCode}.`);
    const metadata = parseProbeJson(result.output);
    check(metadata.format?.format_name?.includes('mp4'),
      `Metadata-only interval-options MP4 format was ${JSON.stringify(metadata.format)}.`);
    return { detail: `metadata-only interval options returned format=${metadata.format.format_name}` };
  }));

  if (selectedTransportCase?.startsWith('N15d')) outcomes.push(await runCase('N15d explicit MPEG-TS demuxer with interval options on MEMFS TS (metadata only)', async () => {
    const tsResponse = await fetch(mediaUrl('/hls/segment-1.ts', base));
    check(tsResponse.ok, `TS import failed with HTTP ${tsResponse.status}.`);
    const tsBytes = new Uint8Array(await tsResponse.arrayBuffer());
    Module.FS.writeFile('/wasm-streaming-forced-mpegts.ts', tsBytes);
    const result = await execute('ffprobe',
      `-v error -f mpegts -read_intervals %+#1 ` +
      `-show_entries format=format_name:stream=codec_name,profile,width,height,sample_rate,channels ` +
      `-of json /wasm-streaming-forced-mpegts.ts`);
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `Explicit MPEG-TS MEMFS FFprobe state=${result.state}, return=${result.returnCode}.`);
    const metadata = parseProbeJson(result.output);
    const video = metadata.streams?.find((stream) => stream.codec_name === 'h264');
    const audio = metadata.streams?.find((stream) => stream.codec_name === 'aac');
    check(metadata.format?.format_name?.includes('mpegts'),
      `Explicit MPEG-TS format metadata was ${JSON.stringify(metadata.format)}.`);
    check(video?.width === 320 && video.height === 240,
      `Explicit MPEG-TS video metadata was ${JSON.stringify(video)}.`);
    check(audio?.sample_rate === '48000' && audio.channels === 2,
      `Explicit MPEG-TS audio metadata was ${JSON.stringify(audio)}.`);
    return { detail: `bytes=${tsBytes.byteLength}; format=${metadata.format.format_name}; ` +
      `video=${video.codec_name}/${video.width}x${video.height}; ` +
      `audio=${audio.codec_name}/${audio.sample_rate}Hz/${audio.channels}ch` };
  }));

  outcomes.push(await runCase('N14 cancel while an HLS segment is pending', async () => {
    await resetRequests();
    const start = Date.now();
    const logStart = runtimeLines.length;
    const handle = startSession('ffprobe', ffprobeCommand(mediaUrl('/hls/slow.m3u8', base)));
    try {
      let segmentSeen = false;
      for (let attempt = 0; attempt < 50; attempt++) {
        const requests = await getRequests();
        segmentSeen = requests.some((request) => request.path === '/hls/slow-segment.ts');
        if (segmentSeen) break;
        if (sessionState(handle) === STATUS_COMPLETED || sessionState(handle) === STATUS_FAILED) break;
        await delay(40);
      }
      check(segmentSeen, 'The slow HLS segment request did not start.');
      const sessionId = ccall('ffmpeg_kit_session_get_session_id', 'bigint', ['number'], [handle]);
      check(sessionId > 0n, 'FFprobe session did not expose a valid session ID.');
      ccall('ffprobe_kit_cancel_session', 'void', ['bigint'], [sessionId]);
      const result = await waitForSession(handle, 8000);
      check(result.returnCode !== 0, 'Cancelled HLS probe returned success.');
      const logs = runtimeLines.slice(logStart);
      check(!logs.some((line) => /HTTP 65535|ERROR:.*WASM (?:HTTP|browser)/.test(line)),
        'The cancelled HLS segment produced a transport error log.');
      check(logs.filter((line) => line.includes('WASM HTTP request interrupted')).length === 1,
        'The HLS cancellation was not logged exactly once at DEBUG level.');
      return { detail: `segment request cancelled in ${Date.now() - start} ms` };
    } finally {
      await finishSession('ffprobe', handle);
    }
  }));

  outcomes.push(await runCase('N05a direct MPEG-TS segment probe', async () => {
    await resetRequests();
    const result = await probe(mediaUrl('/hls/segment-1.ts?token=wasm-direct-ts', base));
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `FFprobe state=${result.state}, return=${result.returnCode}.`);
    const requests = await getRequests();
    check(requests.some((request) => request.path === '/hls/segment-1.ts' &&
      request.query.includes('token=wasm-direct-ts') && request.status === 206),
      'The direct TS probe did not complete a ranged segment request.');
    return { detail: `format=${parseProbeJson(result.output).format.format_name}; requests=${requests.length}` };
  }));

  outcomes.push(await runCase('N05 redirected HLS preserves nested query URLs', async () => {
    await resetRequests();
    const result = await probe(mediaUrl('/redirect/master.m3u8?token=wasm-case', base));
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `FFprobe state=${result.state}, return=${result.returnCode}.`);
    const requests = await getRequests();
    const nested = requests.filter((request) =>
      ['/hls/master.m3u8', '/hls/variant.m3u8', '/hls/segment-1.ts'].includes(request.path));
    // The Wasm transport always requests a byte range, so the fixture answers
    // playlists with 206 rather than 200.
    const succeeded = (request) => request.status === 200 || request.status === 206;
    check(nested.some((request) => request.path === '/hls/master.m3u8' && succeeded(request)),
      'No successful master playlist response was observed.');
    check(nested.some((request) => request.path === '/hls/variant.m3u8' &&
      request.query.includes('token=wasm-case') && succeeded(request)),
      'No signed variant playlist request was observed.');
    check(nested.some((request) => request.path === '/hls/segment-1.ts' &&
      request.query.includes('token=wasm-case') && request.status === 206),
      'No signed HLS segment request was observed.');
    return { detail: `nested requests=${nested.length}` };
  }));

  outcomes.push(await runCase('N10 FFprobe reads HLS master, variant, and all segment metadata', async () => {
    await resetRequests();
    const logStart = runtimeLines.length;
    const token = 'wasm-n10';
    const url = mediaUrl(`/redirect/master.m3u8?token=${token}`, base);
    const result = await execute('ffprobe',
      `-v debug -count_packets ` +
      `-show_entries format=format_name,duration:` +
      `stream=index,codec_name,width,height,sample_rate,channels,nb_read_packets ` +
      `-of json ${url}`, { timeoutMs: 60000 });
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `HLS FFprobe state=${result.state}, return=${result.returnCode}; ` +
      `output=${result.output.slice(-1000)}`);

    const metadata = parseProbeJson(result.output);
    check(metadata.format?.format_name?.split(',').includes('hls'),
      `Expected HLS format metadata, got ${JSON.stringify(metadata.format)}.`);
    const video = metadata.streams?.find((stream) => stream.codec_name === 'h264');
    const audio = metadata.streams?.find((stream) => stream.codec_name === 'aac');
    check(video?.width === 320 && video.height === 240,
      `Expected 320x240 H.264 metadata, got ${JSON.stringify(video)}.`);
    check(audio?.sample_rate === '48000' && audio.channels === 2,
      `Expected 48 kHz stereo AAC metadata, got ${JSON.stringify(audio)}.`);
    for (const stream of [video, audio])
      check(Number.parseInt(stream.nb_read_packets, 10) > 0,
        `FFprobe did not count packets for ${stream.codec_name}: ${stream.nb_read_packets}.`);

    const requests = await getRequests();
    check(requests.some((request) => request.path === '/redirect/master.m3u8' &&
      request.query === `?token=${token}` && request.status === 302),
    'The signed HLS master redirect was not followed.');
    check(requests.some((request) => request.path === '/hls/master.m3u8' &&
      request.query === `?token=${token}` && request.status === 206),
    'The signed master playlist was not fetched.');
    check(requests.some((request) => request.path === '/hls/variant.m3u8' &&
      request.query === `?token=${token}` && request.status === 206),
    'The signed variant playlist was not fetched.');
    const segmentRequests = requests.filter((request) =>
      /^\/hls\/segment-[1-3]\.ts$/.test(request.path) &&
      request.query === `?token=${token}` && request.status === 206);
    const segments = [...new Set(segmentRequests.map((request) => request.path))].sort();
    check(segments.length === 3,
      `Expected all 3 signed HLS segments; observed ${segments.join(', ') || 'none'}.`);

    const cleanBudget = runtimeLines.slice(logStart).some((line) =>
      line.includes('WASM HTTP budget complete') &&
      /cached=0 pending=0 open_streams=0 active_requests=0/.test(line));
    check(cleanBudget,
      'HLS FFprobe completed without a clean HTTP stream/request budget summary.');
    return { detail: `format=${metadata.format.format_name}; ` +
      `video=${video.codec_name}/${video.width}x${video.height}; ` +
      `audio=${audio.codec_name}/${audio.sample_rate}Hz/${audio.channels}ch; ` +
      `packets=${video.nb_read_packets}/${audio.nb_read_packets}; ` +
      `signed segments=${segments.length}; HTTP budgets settled` };
  }));

  outcomes.push(await runCase('R2-RES one- and three-segment FFprobe-only HLS natural close', async () => {
    const results = [];
    for (const { count, path } of [
      { count: 1, path: '/hls/one-segment.m3u8' },
      { count: 3, path: '/hls/three-segment.m3u8' },
    ]) {
      await resetRequests();
      const token = `r2-hls-${count}`;
      const logStart = runtimeLines.length;
      const url = mediaUrl(`${path}?token=${token}`, base);
      const result = await execute('ffprobe',
        `-v debug -count_packets -show_entries ` +
        `format=format_name:stream=codec_name,nb_read_packets -of json ${url}`,
        { timeoutMs: 60000 });
      check(result.state === STATUS_COMPLETED && result.returnCode === 0,
        `${count}-segment HLS state=${result.state}, return=${result.returnCode}; ` +
        `output=${result.output.slice(-700)}`);

      const metadata = parseProbeJson(result.output);
      check(metadata.format?.format_name?.split(',').includes('hls'),
        `${count}-segment input did not report HLS format: ${JSON.stringify(metadata.format)}.`);
      const video = metadata.streams?.find((stream) => stream.codec_name === 'h264');
      const audio = metadata.streams?.find((stream) => stream.codec_name === 'aac');
      check(video && Number.parseInt(video.nb_read_packets, 10) > 0,
        `${count}-segment HLS did not count H.264 packets: ${JSON.stringify(metadata.streams)}.`);
      check(audio && Number.parseInt(audio.nb_read_packets, 10) > 0,
        `${count}-segment HLS did not count AAC packets: ${JSON.stringify(metadata.streams)}.`);

      const requests = await getRequests();
      check(requests.some((request) => request.path === path &&
        request.query === `?token=${token}` && request.status === 206),
      `${count}-segment standalone playlist was not fetched with its signed query.`);
      const segments = [...new Set(requests.filter((request) =>
        /^\/hls\/segment-[1-3]\.ts$/.test(request.path) &&
        request.query === `?token=${token}` && request.status === 206)
        .map((request) => request.path))].sort();
      check(segments.length === count,
        `${count}-segment playlist fetched ${segments.length} distinct segments: ${segments.join(', ')}.`);

      const budgets = runtimeLines.slice(logStart)
        .filter((line) => line.includes('WASM HTTP budget complete'));
      check(budgets.length === 1 &&
        /cached=0 pending=0 open_streams=0 active_requests=0/.test(budgets[0]),
      `${count}-segment HLS did not close exactly one clean HTTP session: ${budgets.join(' | ')}`);
      results.push(`${count} segment(s), packets=${video.nb_read_packets}/${audio.nb_read_packets}`);
    }
    return { detail: `${results.join('; ')}; natural close and request budgets settled` };
  }));

  outcomes.push(await runCase('R2-RES foreign AVIO close callback handles null and duplicate close', async () => {
    if (typeof Module._ffmpeg_kit_test_http_io_close_callback_contract !== 'function')
      return { skip: 'requires the opt-in HTTP close-callback diagnostic hook' };
    const result = ccall('ffmpeg_kit_test_http_io_close_callback_contract', 'number');
    check(result === 0,
      `Foreign AVIO close callback contract returned ${result}; expected 0.`);
    check(!wasmRuntimePoisoned,
      'Foreign or duplicate close poisoned the Wasm runtime.');
    return { detail: 'NULL close is a no-op; foreign AVIO close delegates twice without freeing it' };
  }));

  outcomes.push(await runCase('R2-RES ten sequential single-segment HLS sessions close cleanly', async () => {
    await resetRequests();
    const logStart = runtimeLines.length;
    const sessionTokens = [];
    for (let index = 0; index < 10; index++) {
      const token = `r2-sequential-${index + 1}`;
      sessionTokens.push(token);
      const result = await probe(mediaUrl(`/hls/one-segment.m3u8?token=${token}`, base), '',
        { timeoutMs: 30000 });
      check(result.state === STATUS_COMPLETED && result.returnCode === 0,
        `HLS session ${index + 1} state=${result.state}, return=${result.returnCode}.`);
      const metadata = parseProbeJson(result.output);
      check(metadata.format?.format_name?.split(',').includes('hls'),
        `HLS session ${index + 1} did not report HLS format.`);
    }

    const budgets = runtimeLines.slice(logStart)
      .filter((line) => line.includes('WASM HTTP budget complete'));
    const cleanBudgets = budgets.filter((line) =>
      /cached=0 pending=0 open_streams=0 active_requests=0/.test(line));
    check(cleanBudgets.length === 10,
      `Expected 10 clean HLS close summaries; observed ${cleanBudgets.length}/${budgets.length}.`);
    const requests = await getRequests();
    for (const token of sessionTokens) {
      check(requests.some((request) => request.path === '/hls/one-segment.m3u8' &&
        request.query === `?token=${token}` && request.status === 206),
      `No playlist request was observed for HLS session ${token}.`);
      check(requests.some((request) => request.path === '/hls/segment-1.ts' &&
        request.query === `?token=${token}` && request.status === 206),
      `No segment request was observed for HLS session ${token}.`);
    }
    check(!wasmRuntimePoisoned, 'The runtime was poisoned by repeated HLS natural close.');
    return { detail: `10/10 FFprobe HLS sessions completed; clean budgets=${cleanBudgets.length}` };
  }));

  outcomes.push(await runCase('R2-RES wrong and duplicate FFprobe handle close is harmless', async () => {
    await resetRequests();
    const logStart = runtimeLines.length;
    const token = 'r2-wrong-duplicate-close';
    const handle = startSession('ffprobe',
      ffprobeCommand(mediaUrl(`/hls/one-segment.m3u8?token=${token}`, base)));
    let handleReleased = false;
    try {
      const result = await waitForSession(handle, 30000);
      check(result.state === STATUS_COMPLETED && result.returnCode === 0,
        `HLS session state=${result.state}, return=${result.returnCode}.`);
      check(parseProbeJson(result.output).format?.format_name?.split(',').includes('hls'),
        'The HLS session did not produce parseable HLS metadata before close checks.');

      const invalidHandle = 0x7fffffff;
      ccall('ffprobe_kit_close_session', 'void', ['number'], [invalidHandle]);
      ccall('ffprobe_kit_close_session', 'void', ['number'], [handle]);
      ccall('ffprobe_kit_close_session', 'void', ['number'], [handle]);
      check(sessionState(handle) === STATUS_COMPLETED,
        'Wrong or duplicate close changed the completed HLS session state.');

      const budgets = runtimeLines.slice(logStart)
        .filter((line) => line.includes('WASM HTTP budget complete'));
      check(budgets.length === 1 &&
        /cached=0 pending=0 open_streams=0 active_requests=0/.test(budgets[0]),
      `HLS natural close did not settle before the duplicate-close checks: ${budgets.join(' | ')}`);

      finishCommandTiming(handle);
      ccall('ffmpeg_kit_handle_release', 'void', ['number'], [invalidHandle]);
      ccall('ffmpeg_kit_handle_release', 'void', ['number'], [handle]);
      handleReleased = true;
      if (activeSession?.handle === handle) activeSession = null;
      ccall('ffmpeg_kit_handle_release', 'void', ['number'], [handle]);
      updateButtons();

      const recovery = await probe(mediaUrl('/hls/one-segment.m3u8?token=r2-close-recovery', base), '',
        { timeoutMs: 30000 });
      check(recovery.state === STATUS_COMPLETED && recovery.returnCode === 0,
        `The module did not survive wrong/duplicate close (state=${recovery.state}, ` +
        `return=${recovery.returnCode}).`);
      return { detail: 'unknown and duplicate session handles ignored; later HLS probe succeeded' };
    } finally {
      if (handleReleased) finishCommandTiming(handle);
      else await finishSession('ffprobe', handle);
    }
  }));

  outcomes.push(await runCase('AUDIO-RES S03 audio-only FFplay stop midstream closes once', async () => {
    await resetRequests();
    const result = await runFfplayToStop(
      `-nodisp ${mediaUrl('/media/full-response.wav?token=audio-s03', base)}`, 0.05);
    check(result.position < 0.8,
      `Audio-only playback reached ${result.position}s before stop; expected stop within the 1s fixture.`);
    check(result.width === 0 && result.height === 0,
      `The audio-only fixture unexpectedly opened video (${result.width}x${result.height}).`);
    return { detail: `stopped at ${result.position.toFixed(2)}s; audio generation=${result.lifecycle.audioGeneration}; terminal state=${result.result.state}` };
  }));

  outcomes.push(await runCase('AUDIO-RES S04 ten audio-only FFplay play-stop cycles', async () => {
    await resetRequests();
    const playbackGenerations = [];
    const audioGenerations = [];
    for (let index = 0; index < 10; index++) {
      const token = `audio-s04-${index + 1}`;
      const result = await runFfplayToStop(
        `-nodisp ${mediaUrl(`/media/full-response.wav?token=${token}`, base)}`, 0.03);
      check(result.position < 0.8,
        `Cycle ${index + 1} reached ${result.position}s before stop; expected the 1s fixture to remain active.`);
      playbackGenerations.push(result.lifecycle.playbackGeneration);
      audioGenerations.push(result.lifecycle.audioGeneration);
    }
    check(new Set(playbackGenerations).size === 10,
      `Expected ten distinct playback generations, got ${playbackGenerations.join(', ')}.`);
    check(new Set(audioGenerations).size === 10,
      `Expected ten distinct SDL audio generations, got ${audioGenerations.join(', ')}.`);
    const requests = await getRequests();
    for (let index = 0; index < 10; index++) {
      const token = `audio-s04-${index + 1}`;
      check(requests.some((request) => request.path === '/media/full-response.wav' &&
        request.query === `?token=${token}` && request.status === 200),
      `No full-response WAV request was observed for cycle ${index + 1}.`);
    }
    return { detail: `10/10 cycles closed; distinct playback/audio generations=${new Set(playbackGenerations).size}/${new Set(audioGenerations).size}` };
  }));

  outcomes.push(await runCase('AUDIO-RES S05 PCM 8 kHz and HLS AAC 48 kHz playback reopen', async () => {
    const sources = [
      { url: mediaUrl('/media/full-response.wav?token=audio-s05-pcm', base), codec: 'pcm_s16le', sampleRate: 8000 },
      { url: mediaUrl('/hls/one-segment.m3u8?token=audio-s05-aac', base), codec: 'aac', sampleRate: 48000 },
    ];
    const results = [];
    const playbackGenerations = [];
    const audioGenerations = [];
    for (const source of sources) {
      const probeResult = await execute('ffprobe',
        `-v error -select_streams a:0 -show_entries stream=codec_name,sample_rate ` +
        `-of json ${source.url}`, { timeoutMs: 30000 });
      check(probeResult.state === STATUS_COMPLETED && probeResult.returnCode === 0,
        `Audio source probe state=${probeResult.state}, return=${probeResult.returnCode}.`);
      const stream = parseProbeJson(probeResult.output).streams?.[0];
      check(stream?.codec_name === source.codec && Number(stream.sample_rate) === source.sampleRate,
        `Expected ${source.codec}/${source.sampleRate} Hz, got ${JSON.stringify(stream)}.`);
      const playback = await runFfplayToEof(`-nodisp -autoexit ${source.url}`);
      playbackGenerations.push(playback.lifecycle.playbackGeneration);
      audioGenerations.push(playback.lifecycle.audioGeneration);
      results.push(`${source.codec}/${source.sampleRate} Hz audio generation=${playback.lifecycle.audioGeneration}`);
    }
    check(new Set(playbackGenerations).size === 2,
      `Expected two playback generations for the codec transition, got ${playbackGenerations.join(', ')}.`);
    check(new Set(audioGenerations).size === 2,
      `Expected two SDL audio generations for the sample-rate transition, got ${audioGenerations.join(', ')}.`);
    return { detail: results.join('; ') };
  }));

  outcomes.push(await runCase('AUDIO-RES S06 FFplay and browser AudioContext pause-resume', async () => {
    await resetRequests();
    const logStart = runtimeLines.length;
    const errorsBefore = browserErrors.length;
    const cleanupBefore = cleanupErrors.length;
    const handle = startSession('ffplay',
      mediaUrl('/hls/live.m3u8?token=audio-s06-pause-resume', base));
    let audioContext = null;
    let result;
    let positionBeforePause = 0;
    let positionAfterPause = 0;
    let positionAfterResume = 0;
    let positionAfterContextResume = 0;
    let audioContextAfterResume = 'unknown';

    try {
      positionBeforePause = await waitForFfplayAudioOpen(handle, logStart, 0.25);
      audioContext = Module.SDL2?.audioContext;
      check(audioContext && typeof audioContext.suspend === 'function' &&
        typeof audioContext.resume === 'function',
      'Generated SDL did not expose a suspendable AudioContext.');
      if (audioContext.state === 'suspended') await audioContext.resume();
      check(audioContext.state === 'running',
        `AudioContext was not running before pause (${audioContext.state}).`);

      ccall('ffplay_kit_session_pause', 'void', ['number'], [handle]);
      const pauseDeadline = Date.now() + 2000;
      while (!ccall('ffplay_kit_session_is_paused', 'number', ['number'], [handle]) &&
          Date.now() < pauseDeadline)
        await delay(20);
      check(ccall('ffplay_kit_session_is_paused', 'number', ['number'], [handle]) === 1,
        'FFplay did not enter its paused state.');
      check(sessionState(handle) === STATUS_RUNNING,
        'FFplay session stopped instead of remaining open while paused.');
      positionAfterPause = ccall('ffplay_kit_session_get_position', 'number', ['number'], [handle]);
      await delay(350);
      const pausedPositionLater = ccall('ffplay_kit_session_get_position', 'number', ['number'], [handle]);
      check(ccall('ffplay_kit_session_is_paused', 'number', ['number'], [handle]) === 1,
        'FFplay left its paused state without a resume request.');
      check(Math.abs(pausedPositionLater - positionAfterPause) <= 0.25,
        `FFplay position advanced while paused (${positionAfterPause}s to ${pausedPositionLater}s).`);

      ccall('ffplay_kit_session_resume', 'void', ['number'], [handle]);
      const resumeDeadline = Date.now() + 3000;
      while ((ccall('ffplay_kit_session_is_paused', 'number', ['number'], [handle]) === 1 ||
          ccall('ffplay_kit_session_get_position', 'number', ['number'], [handle]) <= pausedPositionLater + 0.15) &&
          Date.now() < resumeDeadline)
        await delay(30);
      check(ccall('ffplay_kit_session_is_paused', 'number', ['number'], [handle]) === 0,
        'FFplay did not leave its paused state after resume.');
      positionAfterResume = ccall('ffplay_kit_session_get_position', 'number', ['number'], [handle]);
      check(positionAfterResume > pausedPositionLater + 0.15,
        `FFplay position did not advance after resume (${pausedPositionLater}s to ${positionAfterResume}s).`);

      await audioContext.suspend();
      check(audioContext.state === 'suspended',
        `AudioContext did not suspend (${audioContext.state}).`);
      await delay(250);
      check(sessionState(handle) === STATUS_RUNNING,
        'The FFplay session stopped while the browser AudioContext was suspended.');
      await audioContext.resume();
      check(audioContext.state === 'running',
        `AudioContext did not resume (${audioContext.state}).`);
      audioContextAfterResume = audioContext.state;
      positionAfterContextResume = ccall('ffplay_kit_session_get_position', 'number', ['number'], [handle]);
      await delay(300);
      check(sessionState(handle) === STATUS_RUNNING,
        'The FFplay live session did not remain usable after AudioContext resume.');
      ccall('ffplay_kit_session_stop', 'void', ['number'], [handle]);
      result = await waitForSession(handle, 15000);
    } finally {
      if (audioContext?.state === 'suspended') await audioContext.resume().catch(() => {});
      await finishSession('ffplay', handle);
    }
    await delay(300);

    check(result.state === STATUS_COMPLETED || result.state === STATUS_FAILED,
      `FFplay did not terminate after the pause/resume scenario (state=${result.state}).`);
    const lifecycle = assertFfplayAudioClosed(logStart);
    check(browserErrors.length === errorsBefore,
      `Browser errors during pause/resume: ${browserErrors.slice(errorsBefore).join(' | ')}`);
    check(cleanupErrors.length === cleanupBefore,
      `Pause/resume cleanup errors: ${cleanupErrors.slice(cleanupBefore).map((entry) => entry.error.string).join(' | ')}`);
    return { detail: `position ${positionBeforePause.toFixed(2)}s → paused ${positionAfterPause.toFixed(2)}s → ` +
      `${positionAfterResume.toFixed(2)}s; AudioContext after resume=${audioContextAfterResume}; ` +
      `post-context-resume position=${positionAfterContextResume.toFixed(2)}s; audio generation=${lifecycle.audioGeneration}` };
  }));

  outcomes.push(await runCase('AUDIO-RES A13 audio-only EOF and A/V stop', async () => {
    const audio = await runFfplayToEof(
      `-nodisp -autoexit ${mediaUrl('/media/full-response.wav?token=audio-a13-eof', base)}`);
    await resetRequests();
    const av = await runFfplayToStop(
      `-autoexit ${mediaUrl('/media/progressive.mp4?token=audio-a13-stop', base)}`, 0.25);
    check(av.width > 0 && av.height > 0,
      `A/V stop fixture reported no video (${av.width}x${av.height}).`);
    return { detail: `audio EOF generation=${audio.lifecycle.audioGeneration}; ` +
      `A/V stopped at ${av.position.toFixed(2)}s with video=${av.width}x${av.height}; ` +
      `terminal state=${av.result.state}` };
  }));

  outcomes.push(await runCase('N15b imported MEMFS MPEG-TS', async () => {
    const tsResponse = await fetch(mediaUrl('/hls/segment-1.ts', base));
    check(tsResponse.ok, `TS import failed with HTTP ${tsResponse.status}.`);
    const tsBytes = new Uint8Array(await tsResponse.arrayBuffer());
    const digest = await crypto.subtle.digest('SHA-256', tsBytes);
    const sourceHash = [...new Uint8Array(digest)]
      .map((byte) => byte.toString(16).padStart(2, '0')).join('');
    const importedPath = '/wasm-streaming-import.ts';
    Module.FS.writeFile(importedPath, tsBytes);
    write(`N15b imported bytes=${tsBytes.byteLength}; sha256=${sourceHash}; starting Wasm FFprobe.`);

    const importedTs = await execute('ffprobe',
      `-v error -read_intervals %+#1 ` +
      `-show_entries format=format_name:stream=codec_name,profile,width,height,sample_rate,channels ` +
      `-of json ${importedPath}`);
    check(importedTs.state === STATUS_COMPLETED && importedTs.returnCode === 0,
      `Imported MEMFS TS FFprobe state=${importedTs.state}, return=${importedTs.returnCode}.`);
    const metadata = parseProbeJson(importedTs.output);
    const video = metadata.streams?.find((stream) => stream.codec_name === 'h264');
    const audio = metadata.streams?.find((stream) => stream.codec_name === 'aac');
    check(metadata.format?.format_name?.includes('mpegts'),
      `Imported MEMFS TS format metadata was ${JSON.stringify(metadata.format)}.`);
    check(video?.width === 320 && video.height === 240,
      `Imported MEMFS TS video metadata was ${JSON.stringify(video)}.`);
    check(audio?.sample_rate === '48000' && audio.channels === 2,
      `Imported MEMFS TS audio metadata was ${JSON.stringify(audio)}.`);
    write(`N15b metadata-only Wasm FFprobe=${video.codec_name}/${video.profile} ${video.width}x${video.height} ` +
      `${audio.codec_name}/${audio.profile} ${audio.sample_rate}Hz/${audio.channels}ch.`);

    const playback = await runFfplay(`-autoexit ${importedPath}`);
    return { detail: `MEMFS FFprobe passed before FFplay; bytes=${tsBytes.byteLength}; ` +
      `sha256=${sourceHash}; video=${playback.width}x${playback.height}; ` +
      `FFplay return=${playback.returnCode}` };
  }));

  if (selectedTransportCase?.startsWith('D2-')) {
    const tsPath = '/wasm-streaming-d2-original.ts';
    const d2ImportTs = (label = 'D2 fixture') =>
      importFixtureToMemfs('/hls/segment-1.ts', tsPath, label);
    const requireProbeSuccess = (result, label) => check(
      result.state === STATUS_COMPLETED && result.returnCode === 0,
      `${label} FFprobe state=${result.state}, return=${result.returnCode}; output=${result.output.slice(-500)}.`,
    );

    outcomes.push(await runCase('D2-A TS open without find_stream_info', async () => {
      const fixture = await d2ImportTs('D2-A');
      const command = `-v debug -nofind_stream_info -show_entries format=format_name ` +
        `-of json ${tsPath}`;
      const result = await execute('ffprobe', command, { timeoutMs: 15000 });
      requireProbeSuccess(result, 'D2-A');
      const metadata = parseProbeJson(result.output);
      check(metadata.format?.format_name?.includes('mpegts'),
        `D2-A format metadata was ${JSON.stringify(metadata.format)}.`);
      return { detail: `format=${metadata.format.format_name}; bytes=${fixture.bytes.byteLength}; sha256=${fixture.sha256}` };
    }));

    outcomes.push(await runCase('D2-B TS open with normal find_stream_info', async () => {
      const fixture = await d2ImportTs('D2-B');
      const command = `-v debug -show_entries format=format_name -of json ${tsPath}`;
      const result = await execute('ffprobe', command, { timeoutMs: 15000 });
      requireProbeSuccess(result, 'D2-B');
      const metadata = parseProbeJson(result.output);
      check(metadata.format?.format_name?.includes('mpegts'),
        `D2-B format metadata was ${JSON.stringify(metadata.format)}.`);
      return { detail: `format=${metadata.format.format_name}; bytes=${fixture.bytes.byteLength}; sha256=${fixture.sha256}` };
    }));

    outcomes.push(await runCase('D2-C TS stream enumeration', async () => {
      const fixture = await d2ImportTs('D2-C');
      const command = `-v debug -show_entries stream=codec_name -of json ${tsPath}`;
      const result = await execute('ffprobe', command, { timeoutMs: 15000 });
      requireProbeSuccess(result, 'D2-C');
      const metadata = parseProbeJson(result.output);
      const codecs = (metadata.streams ?? []).map((stream) => stream.codec_name);
      check(codecs.includes('h264') && codecs.includes('aac'),
        `D2-C expected H.264 and AAC streams, got ${JSON.stringify(codecs)}.`);
      return { detail: `streams=${codecs.join(',')}; bytes=${fixture.bytes.byteLength}; sha256=${fixture.sha256}` };
    }));

    outcomes.push(await runCase('D2-D actual one-packet TS read', async () => {
      const fixture = await d2ImportTs('D2-D');
      const command = `-v debug -show_packets -read_intervals %+#1 ` +
        `-show_entries packet=stream_index,size,pts_time -of json ${tsPath}`;
      const result = await execute('ffprobe', command, { timeoutMs: 15000 });
      requireProbeSuccess(result, 'D2-D');
      const metadata = parseProbeJson(result.output);
      check(Array.isArray(metadata.packets) && metadata.packets.length > 0,
        `D2-D did not return a packet: ${JSON.stringify(metadata).slice(0, 500)}.`);
      return { detail: `packets=${metadata.packets.length}; first=${JSON.stringify(metadata.packets[0])}; ` +
        `bytes=${fixture.bytes.byteLength}; sha256=${fixture.sha256}` };
    }));

    outcomes.push(await runCase('D2-E forced MPEG-TS open without find_stream_info', async () => {
      const fixture = await d2ImportTs('D2-E');
      const command = `-v debug -f mpegts -nofind_stream_info ` +
        `-show_entries format=format_name -of json ${tsPath}`;
      const result = await execute('ffprobe', command, { timeoutMs: 15000 });
      requireProbeSuccess(result, 'D2-E');
      const metadata = parseProbeJson(result.output);
      check(metadata.format?.format_name?.includes('mpegts'),
        `D2-E format metadata was ${JSON.stringify(metadata.format)}.`);
      return { detail: `format=${metadata.format.format_name}; bytes=${fixture.bytes.byteLength}; sha256=${fixture.sha256}` };
    }));

    outcomes.push(await runCase('D2-F stream-copy MP4 MEMFS probe', async () => {
      const path = '/wasm-streaming-d2-same-h264-aac.mp4';
      const fixture = await importFixtureToMemfs('/media/d2-same-h264-aac.mp4', path, 'D2-F');
      const command = `-v debug -show_entries format=format_name:stream=codec_name -of json ${path}`;
      const result = await execute('ffprobe', command, { timeoutMs: 15000 });
      requireProbeSuccess(result, 'D2-F');
      const metadata = parseProbeJson(result.output);
      const codecs = (metadata.streams ?? []).map((stream) => stream.codec_name);
      check(metadata.format?.format_name?.includes('mp4'),
        `D2-F format metadata was ${JSON.stringify(metadata.format)}.`);
      check(codecs.includes('h264') && codecs.includes('aac'),
        `D2-F expected the copied H.264 and AAC streams, got ${JSON.stringify(codecs)}.`);
      return { detail: `format=${metadata.format.format_name}; streams=${codecs.join(',')}; ` +
        `bytes=${fixture.bytes.byteLength}; sha256=${fixture.sha256}` };
    }));

    outcomes.push(await runCase('D2-GV video-only TS MEMFS probe', async () => {
      const path = '/wasm-streaming-d2-video-only.ts';
      const fixture = await importFixtureToMemfs('/hls/segment-d2-video-only.ts', path, 'D2-GV');
      const command = `-v debug -show_entries format=format_name:stream=codec_name -of json ${path}`;
      const result = await execute('ffprobe', command, { timeoutMs: 15000 });
      requireProbeSuccess(result, 'D2-GV');
      const metadata = parseProbeJson(result.output);
      const codecs = (metadata.streams ?? []).map((stream) => stream.codec_name);
      check(metadata.format?.format_name?.includes('mpegts') && codecs.includes('h264') && codecs.length === 1,
        `D2-GV expected a single H.264 TS stream, got ${JSON.stringify(metadata)}.`);
      return { detail: `format=${metadata.format.format_name}; streams=${codecs.join(',')}; ` +
        `bytes=${fixture.bytes.byteLength}; sha256=${fixture.sha256}` };
    }));

    outcomes.push(await runCase('D2-GA audio-only TS MEMFS probe', async () => {
      const path = '/wasm-streaming-d2-audio-only.ts';
      const fixture = await importFixtureToMemfs('/hls/segment-d2-audio-only.ts', path, 'D2-GA');
      const command = `-v debug -show_entries format=format_name:stream=codec_name -of json ${path}`;
      const result = await execute('ffprobe', command, { timeoutMs: 15000 });
      requireProbeSuccess(result, 'D2-GA');
      const metadata = parseProbeJson(result.output);
      const codecs = (metadata.streams ?? []).map((stream) => stream.codec_name);
      check(metadata.format?.format_name?.includes('mpegts') && codecs.includes('aac') && codecs.length === 1,
        `D2-GA expected a single AAC TS stream, got ${JSON.stringify(metadata)}.`);
      return { detail: `format=${metadata.format.format_name}; streams=${codecs.join(',')}; ` +
        `bytes=${fixture.bytes.byteLength}; sha256=${fixture.sha256}` };
    }));

    outcomes.push(await runCase('D2-H1 standalone FFplay TS without FFprobe', async () => {
      const path = '/wasm-streaming-d2-ffplay.ts';
      const fixture = await importFixtureToMemfs('/hls/segment-1.ts', path, 'D2-H1');
      const playback = await runFfplay(`-autoexit ${path}`, 15000);
      return { detail: `video=${playback.width}x${playback.height}; return=${playback.returnCode}; ` +
        `bytes=${fixture.bytes.byteLength}; sha256=${fixture.sha256}; FFprobe was not run.` };
    }));

    outcomes.push(await runCase('D2-H2 standalone FFmpeg TS stream-copy remux', async () => {
      const source = '/wasm-streaming-d2-remux-source.ts';
      const output = '/wasm-streaming-d2-remux.mp4';
      const fixture = await importFixtureToMemfs('/hls/segment-1.ts', source, 'D2-H2');
      const command = `-nostdin -v debug -i ${source} -map 0:v:0 -map 0:a:0 -c copy ${output}`;
      const result = await execute('ffmpeg', command, { timeoutMs: 15000 });
      check(result.state === STATUS_COMPLETED && result.returnCode === 0,
        `D2-H2 FFmpeg state=${result.state}, return=${result.returnCode}; output=${result.output.slice(-500)}.`);
      const size = Module.FS.stat(output).size;
      check(size > 0, 'D2-H2 produced an empty stream-copy MP4.');
      return { detail: `outputBytes=${size}; inputBytes=${fixture.bytes.byteLength}; inputSha256=${fixture.sha256}` };
    }));
  }

  const passed = outcomes.filter((value) => value === 'pass').length;
  const failed = outcomes.filter((value) => value === 'fail').length;
  const skipped = outcomes.filter((value) => value === 'skip').length;
  setStatus(`Transport matrix: ${passed} passed, ${failed} failed, ${skipped} skipped.`);
  showTelemetry();
}

function showTelemetry() {
  const lines = runtimeLines.filter((line) => line.includes('WASM HTTP budget complete'));
  if (lines.length)
    write(`Wasm transport emitted ${lines.length} budget summaries; latest: ${lines.slice(-3).join(' | ')}`);
  else
    write('No Wasm HTTP budget summary was observed in the loader log.');
}

function releaseWhenTerminal(handle) {
  if (wasmRuntimePoisoned) return;
  const state = sessionState(handle);
  if (state === STATUS_COMPLETED || state === STATUS_FAILED) {
    ccall('ffmpeg_kit_handle_release', 'void', ['number'], [handle]);
    if (activeSession?.handle === handle) activeSession = null;
  }
  updateButtons();
}

async function finishSession(kind, handle, timeoutMs = 8000) {
  finishCommandTiming(handle);
  if (wasmRuntimePoisoned) {
    if (activeSession?.handle === handle) activeSession = null;
    cleanupSkippedEvents.push({
      timestamp: new Date().toISOString(),
      elapsedMs: diagnosticElapsedMs(),
      caseName: currentCaseName,
      kind,
      handle,
      reason: 'Fatal Wasm event detected; no C API cleanup calls were made.',
    });
    write('Session cleanup skipped: the Wasm runtime is poisoned; no further C calls will be made.');
    updateButtons();
    return;
  }
  try {
    const state = sessionState(handle);
    if (state !== STATUS_COMPLETED && state !== STATUS_FAILED) {
      cancelSession({ kind, handle });
      await waitForSession(handle, timeoutMs);
    }
    releaseWhenTerminal(handle);
  } catch (error) {
    const record = {
      timestamp: new Date().toISOString(),
      elapsedMs: diagnosticElapsedMs(),
      caseName: currentCaseName,
      requestedCommand: requestedCommand ? { ...requestedCommand } : null,
      error: serializeError(error),
    };
    cleanupErrors.push(record);
    write(`Session cleanup error: ${record.error.stack || record.error.message || record.error.string}`);
    if (activeSession?.handle === handle) activeSession = null;
    updateButtons();
  }
  finishCommandTiming(handle);
}

function lastBudgetPeak(startIndex = 0) {
  const lines = runtimeLines.slice(startIndex)
    .filter((line) => line.includes('WASM HTTP budget complete'));
  for (let index = lines.length - 1; index >= 0; index--) {
    const match = /peak_retained=(\d+)/.exec(lines[index]);
    if (match) return Number(match[1]);
  }
  return null;
}

function workerIdsSince(startIndex) {
  return runtimeLines.slice(startIndex).flatMap((line) => {
    const match = /WASM HTTP open .* worker=(\d+) /.exec(line);
    return match ? [match[1]] : [];
  });
}

async function runFfplay(command, timeoutMs = 90000) {
  const browserErrorStart = browserErrors.length;
  const runtimeStart = runtimeLines.length;
  const handle = startSession('ffplay', command);
  try {
    // The session releases its FFplay context at completion, after which the
    // size getters return 0, so sample the dimensions while playback is live.
    let width = 0;
    let height = 0;
    const result = await waitForSession(handle, timeoutMs, {
      onPoll: () => {
        width = Math.max(width, ccall('ffplay_kit_session_get_video_width', 'number', ['number'], [handle]));
        height = Math.max(height, ccall('ffplay_kit_session_get_video_height', 'number', ['number'], [handle]));
      },
    });
    await delay(300);
    check(result.state === STATUS_COMPLETED && result.returnCode === 0,
      `FFplay state=${result.state}, return=${result.returnCode}.`);
    check(width > 0 && height > 0, `FFplay reported no video dimensions (${width}x${height}).`);
    check(runtimeLines.slice(runtimeStart).some((line) => line.includes('[ffplay-wasm] event=audio_open')),
      'FFplay did not report opening an audio device.');
    check(browserErrors.length === browserErrorStart,
      `Browser errors during FFplay: ${browserErrors.slice(browserErrorStart).join(' | ')}`);
    return { ...result, width, height };
  } finally {
    await finishSession('ffplay', handle);
  }
}

function ffplayAudioEventsSince(startIndex) {
  return runtimeLines.slice(startIndex).flatMap((line) => {
    const match = /\[ffplay-wasm\] event=([a-z_]+) playback=(\d+) audio=(\d+) device=(\d+) result=(-?\d+)/.exec(line);
    if (!match) return [];
    return [{
      event: match[1],
      playback: Number(match[2]),
      audio: Number(match[3]),
      device: Number(match[4]),
      result: Number(match[5]),
      line,
    }];
  });
}

async function waitForFfplayAudioOpen(handle, logStart, minPositionSeconds, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs;
  let position = 0;
  while (Date.now() < deadline) {
    const state = sessionState(handle);
    position = ccall('ffplay_kit_session_get_position', 'number', ['number'], [handle]);
    const opened = ffplayAudioEventsSince(logStart).some((event) => event.event === 'audio_open');
    if (state === STATUS_COMPLETED || state === STATUS_FAILED)
      throw new Error(`FFplay ended before audio became active (state=${state}, position=${position}).`);
    if (state === STATUS_RUNNING && opened && position >= minPositionSeconds)
      return position;
    await delay(40);
  }
  throw new Error(`FFplay audio did not become active within ${timeoutMs} ms ` +
    `(position=${position}, state=${sessionState(handle)}).`);
}

function assertFfplayAudioClosed(logStart) {
  const events = ffplayAudioEventsSince(logStart);
  const starts = events.filter((event) => event.event === 'playback_start');
  const opens = events.filter((event) => event.event === 'audio_open');
  const closes = events.filter((event) => event.event === 'audio_close');
  const terminals = events.filter((event) => event.event === 'playback_terminal');
  check(starts.length === 1, `Expected one playback_start event, got ${starts.length}.`);
  check(opens.length === 1, `Expected one audio_open event, got ${opens.length}.`);
  check(closes.length === 1, `Expected one audio_close event, got ${closes.length}.`);
  check(terminals.length === 1, `Expected one playback_terminal event, got ${terminals.length}.`);
  check(opens[0].playback > 0 && opens[0].audio > 0 && opens[0].device > 0,
    `Invalid audio generations/device in open event: ${opens[0].line}.`);
  check(starts[0].playback === opens[0].playback &&
    closes[0].playback === opens[0].playback &&
    terminals[0].playback === opens[0].playback,
  'Audio open, close, and terminal events did not belong to one playback generation.');
  check(closes[0].audio === opens[0].audio && closes[0].device === opens[0].device,
    'Audio close did not match the opened device generation.');
  check(!events.some((event) => event.event === 'audio_gate_unavailable'),
    'Generated SDL did not expose the ScriptProcessor callback gate.');
  return { playbackGeneration: opens[0].playback, audioGeneration: opens[0].audio };
}

async function runFfplayToEof(command, timeoutMs = 30000) {
  const logStart = runtimeLines.length;
  const errorsBefore = browserErrors.length;
  const cleanupBefore = cleanupErrors.length;
  const handle = startSession('ffplay', command);
  let result;
  try {
    result = await waitForSession(handle, timeoutMs);
  } finally {
    await finishSession('ffplay', handle);
  }
  await delay(300);
  check(result.state === STATUS_COMPLETED && result.returnCode === 0,
    `FFplay EOF state=${result.state}, return=${result.returnCode}.`);
  const lifecycle = assertFfplayAudioClosed(logStart);
  check(browserErrors.length === errorsBefore,
    `Browser errors during FFplay EOF: ${browserErrors.slice(errorsBefore).join(' | ')}`);
  check(cleanupErrors.length === cleanupBefore,
    `FFplay EOF cleanup errors: ${cleanupErrors.slice(cleanupBefore).map((entry) => entry.error.string).join(' | ')}`);
  return { result, lifecycle };
}

async function runFfplayToStop(command, minPositionSeconds, timeoutMs = 15000) {
  const logStart = runtimeLines.length;
  const errorsBefore = browserErrors.length;
  const cleanupBefore = cleanupErrors.length;
  const handle = startSession('ffplay', command);
  let result;
  let position = 0;
  let width = 0;
  let height = 0;
  try {
    position = await waitForFfplayAudioOpen(handle, logStart, minPositionSeconds, timeoutMs);
    width = ccall('ffplay_kit_session_get_video_width', 'number', ['number'], [handle]);
    height = ccall('ffplay_kit_session_get_video_height', 'number', ['number'], [handle]);
    check(sessionState(handle) === STATUS_RUNNING,
      'FFplay was not running when stop was requested.');
    ccall('ffplay_kit_session_stop', 'void', ['number'], [handle]);
    result = await waitForSession(handle, 15000);
  } finally {
    await finishSession('ffplay', handle);
  }
  await delay(300);
  check(result.state === STATUS_COMPLETED || result.state === STATUS_FAILED,
    `FFplay stop did not reach a terminal state (state=${result.state}).`);
  const lifecycle = assertFfplayAudioClosed(logStart);
  check(browserErrors.length === errorsBefore,
    `Browser errors during FFplay stop: ${browserErrors.slice(errorsBefore).join(' | ')}`);
  check(cleanupErrors.length === cleanupBefore,
    `FFplay stop cleanup errors: ${cleanupErrors.slice(cleanupBefore).map((entry) => entry.error.string).join(' | ')}`);
  return { result, position, width, height, lifecycle };
}

async function runVod() {
  const base = baseUrl();
  const outcomes = [];
  outcomes.push(await runCase('A02 FFplay progressive MP4 with audio/video EOF', async () => {
    const result = await runFfplay(`-autoexit ${mediaUrl('/media/progressive.mp4', base)}`);
    return { detail: `video=${result.width}x${result.height}; terminal state=${result.state}, return=${result.returnCode}` };
  }));
  outcomes.push(await runCase('N13/A04 FFplay HLS VOD through all segments', async () => {
    await resetRequests();
    const result = await runFfplay(`-autoexit ${mediaUrl('/redirect/master.m3u8?token=wasm-vod', base)}`);
    const requests = await getRequests();
    const segments = new Set(requests.filter((request) => /^\/hls\/segment-\d+\.ts$/.test(request.path))
      .map((request) => request.path));
    check(segments.size >= 3, `Only ${segments.size} distinct HLS segments were requested.`);
    return { detail: `distinct HLS segments=${segments.size}; video=${result.width}x${result.height}; return=${result.returnCode}` };
  }));
  setStatus(`VOD checks: ${outcomes.filter((value) => value === 'pass').length} passed, ` +
    `${outcomes.filter((value) => value === 'fail').length} failed.`);
}

async function runLive() {
  const base = baseUrl();
  await runCase('N11/A05 FFplay live HLS for 30 seconds', async () => {
    const browserErrorStart = browserErrors.length;
    await resetRequests();
    const handle = startSession('ffplay',
      mediaUrl('/hls/live.m3u8?token=wasm-live', base));
    let positionBefore = 0;
    let positionAfter = 0;
    let width = 0;
    let height = 0;
    const runtimeStart = runtimeLines.length;
    try {
      await delay(2000);
      positionBefore = ccall('ffplay_kit_session_get_position', 'number',
        ['number'], [handle]);
      width = ccall('ffplay_kit_session_get_video_width', 'number',
        ['number'], [handle]);
      height = ccall('ffplay_kit_session_get_video_height', 'number',
        ['number'], [handle]);
      await delay(30000);
      const requests = await getRequests();
      const reloads = requests.filter((request) => request.path === '/hls/live.m3u8').length;
      const wasRunning = sessionState(handle) === STATUS_RUNNING;
      positionAfter = ccall('ffplay_kit_session_get_position', 'number',
        ['number'], [handle]);
      ccall('ffplay_kit_session_stop', 'void', ['number'], [handle]);
      const result = await waitForSession(handle, 15000);
      await delay(300);
      check(wasRunning, 'FFplay stopped before the 30 second live interval ended.');
      check(reloads >= 3, `Only ${reloads} live playlist requests were observed.`);
      check(width > 0 && height > 0, `No active video dimensions were reported (${width}x${height}).`);
      check(positionAfter > positionBefore + 5,
        `Playback position did not advance sufficiently (${positionBefore}s to ${positionAfter}s).`);
      check(runtimeLines.slice(runtimeStart).some((line) => line.includes('[ffplay-wasm] event=audio_open')),
        'Live FFplay did not report opening an audio device.');
      check(browserErrors.length === browserErrorStart,
        `Browser errors during live FFplay: ${browserErrors.slice(browserErrorStart).join(' | ')}`);
      check(result.state === STATUS_COMPLETED || result.state === STATUS_FAILED,
        `FFplay did not reach a terminal state after stop (state ${result.state}).`);
      return { detail: `playlist reloads=${reloads}; video=${width}x${height}; ` +
        `position=${positionBefore.toFixed(1)}s→${positionAfter.toFixed(1)}s; stopped state=${result.state}` };
    } finally {
      await finishSession('ffplay', handle);
    }
  });

  await runCase('HTTP-IO-2-live N11/A05 FFplay live HLS heap after 30-second warm-up', async () => {
    if (typeof Module._ffmpeg_kit_test_http_io_heap_snapshot !== 'function')
      return { skip: 'requires the opt-in Wasm HTTP heap test-hook build' };

    const browserErrorStart = browserErrors.length;
    await resetRequests();
    const handle = startSession('ffplay',
      mediaUrl('/hls/live.m3u8?token=wasm-live-heap', base));
    const runtimeStart = runtimeLines.length;
    const samples = [];
    let positionBefore = 0;
    let positionAfter = 0;
    let width = 0;
    let height = 0;

    try {
      await delay(30000);
      check(sessionState(handle) === STATUS_RUNNING,
        'Live FFplay did not remain active through the 30-second warm-up.');
      positionBefore = ccall('ffplay_kit_session_get_position', 'number',
        ['number'], [handle]);
      width = ccall('ffplay_kit_session_get_video_width', 'number',
        ['number'], [handle]);
      height = ccall('ffplay_kit_session_get_video_height', 'number',
        ['number'], [handle]);
      const heapBefore = ccall('ffmpeg_kit_test_http_io_heap_snapshot', 'number');
      check(Number.isFinite(heapBefore) && heapBefore > 0,
        `The test-only heap snapshot was invalid (${heapBefore}).`);
      samples.push({ elapsedMs: 0, uordblks: heapBefore });
      write(`HTTP-IO-2-live heap baseline after warm-up: ${heapBefore} bytes.`);

      const measurementStartedAt = Date.now();
      for (let elapsedMs = 30000; elapsedMs <= 300000; elapsedMs += 30000) {
        await delay(30000);
        const state = sessionState(handle);
        check(state === STATUS_RUNNING,
          `Live FFplay stopped during the heap interval at ${elapsedMs} ms (state=${state}).`);
        const uordblks = ccall('ffmpeg_kit_test_http_io_heap_snapshot', 'number');
        check(Number.isFinite(uordblks) && uordblks > 0,
          `The test-only heap snapshot was invalid at ${elapsedMs} ms (${uordblks}).`);
        samples.push({ elapsedMs: Date.now() - measurementStartedAt, uordblks });
        write(`HTTP-IO-2-live heap sample ${elapsedMs} ms: ${uordblks} bytes ` +
          `(delta=${uordblks - heapBefore}).`);
      }

      positionAfter = ccall('ffplay_kit_session_get_position', 'number',
        ['number'], [handle]);
      const requests = await getRequests();
      const reloads = requests.filter((request) => request.path === '/hls/live.m3u8').length;
      const wasRunning = sessionState(handle) === STATUS_RUNNING;
      ccall('ffplay_kit_session_stop', 'void', ['number'], [handle]);
      const result = await waitForSession(handle, 15000);
      await delay(300);

      const heapAfter = samples[samples.length - 1].uordblks;
      const heapDelta = heapAfter - heapBefore;
      const heapAfterStop = ccall('ffmpeg_kit_test_http_io_heap_snapshot', 'number');
      const heapAfterStopDelta = heapAfterStop - heapBefore;
      write(`HTTP-IO-2-live heap after FFplay stop: ${heapAfterStop} bytes ` +
        `(delta=${heapAfterStopDelta}).`);
      check(heapDelta <= 4096,
        `Five-minute live HLS increased uordblks by ${heapDelta} bytes (limit=4096).`);
      check(wasRunning, 'FFplay stopped before the five-minute heap interval ended.');
      check(reloads >= 3, `Only ${reloads} live playlist requests were observed.`);
      check(width > 0 && height > 0, `No active video dimensions were reported (${width}x${height}).`);
      check(positionAfter > positionBefore + 5,
        `Playback position did not advance sufficiently (${positionBefore}s to ${positionAfter}s).`);
      check(runtimeLines.slice(runtimeStart).some((line) =>
        line.includes('[ffplay-wasm] event=audio_open')),
      'Live FFplay did not report opening an audio device.');
      check(browserErrors.length === browserErrorStart,
        `Browser errors during live FFplay: ${browserErrors.slice(browserErrorStart).join(' | ')}`);
      check(result.state === STATUS_COMPLETED || result.state === STATUS_FAILED,
        `FFplay did not reach a terminal state after stop (state ${result.state}).`);
      return { detail: `warm-up=30s; live measurement=300s; playlist reloads=${reloads}; ` +
        `video=${width}x${height}; position=${positionBefore.toFixed(1)}s→${positionAfter.toFixed(1)}s; ` +
        `uordblks=${heapBefore}→${heapAfter} bytes (delta=${heapDelta}, after-stop=${heapAfterStopDelta}); ` +
        `heap samples=${samples.length}; stopped state=${result.state}` };
    } finally {
      await finishSession('ffplay', handle);
    }
  });
}

async function runRecording() {
  const base = baseUrl();
  await runCase('N12/A06 FFmpeg records 15 seconds of live HLS to MEMFS MKV', async () => {
    await resetRequests();
    const result = await execute('ffmpeg',
      `-v error -i ${mediaUrl('/hls/live.m3u8?token=wasm-record', base)} ` +
      '-t 15 -map 0 -c copy -f matroska /wasm-streaming-live.mkv',
      { timeoutMs: 60000 });
    check(result.returnCode === 0, `FFmpeg return=${result.returnCode}.`);
    const stat = Module.FS.stat('/wasm-streaming-live.mkv');
    check(stat.size > 0, 'The live MKV recording is empty.');
    const probed = await probe('/wasm-streaming-live.mkv',
      '-show_streams -show_packets -show_entries ' +
      'stream=codec_name,width,height,sample_rate,channels:packet=stream_index,pts_time,dts_time');
    check(probed.returnCode === 0, `Recorded MKV probe return=${probed.returnCode}.`);
    const metadata = parseProbeJson(probed.output);
    const video = metadata.streams?.find((stream) => stream.codec_name === 'h264');
    const audio = metadata.streams?.find((stream) => stream.codec_name === 'aac');
    check(video?.width === 320 && video.height === 240 &&
      audio?.sample_rate === '48000' && audio.channels === 2,
    `Recorded streams do not match the native fixture: ${JSON.stringify(metadata.streams)}.`);
    const duration = Number(metadata.format?.duration);
    check(duration >= 14.5 && duration <= 16.5,
      `Recorded duration=${metadata.format?.duration}, expected approximately 15 seconds.`);
    for (const stream of [0, 1]) {
      const packets = metadata.packets?.filter((packet) => packet.stream_index === stream);
      check(packets?.length > 0, `Recorded stream ${stream} has no packets.`);
      const timestamps = packets.map((packet) => Number(packet.dts_time));
      check(timestamps.every((time) => Number.isFinite(time)) &&
        timestamps.every((time, index) => index === 0 || time >= timestamps[index - 1]),
      `Recorded stream ${stream} has missing or decreasing DTS values.`);
      check(timestamps.at(-1) - timestamps[0] >= 14,
        `Recorded stream ${stream} spans less than 14 seconds.`);
    }
    const requests = await getRequests();
    const reloads = requests.filter((request) => request.path === '/hls/live.m3u8').length;
    check(reloads >= 3, `Only ${reloads} live playlist reloads were observed.`);
    // The headless driver saves these exact bytes for independent native decode.
    window.ffmpegKitWasmRecordingBytes = () => Array.from(
      Module.FS.readFile('/wasm-streaming-live.mkv'));
    return { detail: `size=${stat.size}; duration=${duration}s; streams=h264/aac; ` +
      `packet DTS verified; live playlist reloads=${reloads}` };
  });
}

async function cancelActive() {
  if (!activeSession) {
    write('No active FFmpegKit session to cancel.');
    return;
  }
  cancelSession(activeSession);
  write(`Cancellation requested for ${activeSession.kind}.`);
}

function updateButtons() {
  const loaded = Boolean(Module);
  for (const [id, button] of buttons) {
    if (id === 'load') button.disabled = operationRunning || loaded;
    else if (id === 'cancel') button.disabled = !loaded || !activeSession;
    else button.disabled = !loaded || operationRunning;
  }
}

async function runExclusive(callback) {
  if (operationRunning) {
    write('Another acceptance operation is already running.');
    return;
  }
  operationRunning = true;
  updateButtons();
  try {
    await callback();
  } catch (error) {
    write(`FAIL operation: ${error?.stack ?? error}`);
    setStatus('Acceptance operation failed.');
  } finally {
    operationRunning = false;
    updateButtons();
  }
}

document.getElementById('load').addEventListener('click', async () => {
  await runExclusive(async () => {
    setStatus('Loading the local Wasm package…');
    try {
      await inspectBinary();
      setStatus('Local Wasm package loaded. Run the transport matrix or playback checks.');
    } catch (error) {
      Module = null;
      setStatus('Wasm package load failed.');
      throw error;
    }
  });
});

document.getElementById('transport').addEventListener('click', () => runExclusive(runTransportMatrix));
document.getElementById('vod').addEventListener('click', () => runExclusive(runVod));
document.getElementById('live').addEventListener('click', () => runExclusive(runLive));
document.getElementById('record').addEventListener('click', () => runExclusive(runRecording));
document.getElementById('cancel').addEventListener('click', cancelActive);

updateButtons();
