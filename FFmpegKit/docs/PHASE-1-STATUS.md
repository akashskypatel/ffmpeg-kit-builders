# Phase 1 status tracker — authoritative

**This file is the single source of truth for the status of every Phase 1 goal, work item, acceptance case and gate.** Update it in place. Other documents keep their own roles:

| Document | Role | Status sections |
|---|---|---|
| `.agents/luna-web-wasm-streaming-phase-1-native-abi.md` | Phase 1 requirements (P1.0–P1.6), constraints, HTTP-IO findings and resolution goals | Superseded by this file |
| `.agents/luna-phase-1-wasm-streaming-reviewed-plan.md` | Execution plan (P1.R0–P1.R6), step instructions, execution records | Superseded by this file |
| `.agents/luna-phase-1-r1-blocker-code-review-and-unblock-plan.md` | Closed R1 investigation (R1.D0–D5), retained as history | Superseded by this file |
| [`PHASE-1-CURRENT-STATE-2026-10-14.md`](PHASE-1-CURRENT-STATE-2026-10-14.md) | Dated, append-only evidence log with hashes and raw-record paths | Evidence only; status lives here |
| [`wasm-streaming-design.md`](wasm-streaming-design.md) | Design and contracts | Superseded by this file |

**Last updated:** 2026-10-14 19:47 UTC. **Phase 1: IN PROGRESS. Phase 2 authorized: NO** (see [Gate](#phase-1--phase-2-gate)).

**Evidence rule:** every result below names the artifact it ran on. No result counts as closing evidence until it is rerun on the closing production package (P1.R6). Raw records are under `FFmpegKit/tests/wasm_streaming/evidence/` (`r1/http-io-review/` unless noted).

## Artifacts

| Role | Wasm SHA-256 | Loader SHA-256 | Contents and configuration |
|---|---|---|---|
| **Staged production package** (`build/stage/…/lib`) | `f9a8d51e5e22cf0e5812782c08981df1440a131a7f06ac636eaf2c0f960e861c` | `35471f0c58b27633c9edfdf2b5b2a16f08d8c4c1085001fc97311440d02d2aae` | 1 MiB pthread stacks, P1.1 audio fix, HTTP-IO-1. 527 exports verified. Predates HTTP-IO-2…5 and HTTP-IO-11. |
| **Latest diagnostic** (`FFmpegKit/build`) | `c6b570b0e9aded2e261790730a0fc268220909e59574cced07f63d0c0c4f8b48` | `df7effc73bc5270aa6f2446e1d0895a63f9d9eb378eb9caec563ca216705bca1` | Adds HTTP-IO-2…8 and HTTP-IO-11. Test hooks ON, export verifier OFF, 256 KiB pthread stacks, `-sASSERTIONS=2 -sSTACK_OVERFLOW_CHECK=2`. **Not a release artifact.** |
| Earlier diagnostic | `be9190f38586a66e39844889a8834f383f88030bcc8af52e715dae308eb7331b` | `6adf0be8d93cfd6e94917cc52b75053afd582e96dadd0e0367b2ba6b2703517c` | HTTP-IO-2/3/11 before HTTP-IO-4/5; carries the live-HLS and recording evidence. |
| Historical checkpoints | `b707cd2c…` (P1.1 fix), `b923795c…` (stack fix), `1d0663b2…` (R0 staged) | `911fdba5…`, `69e9e411…`, `0d3537d4…` | Superseded; results on them are history only. |
| Same-target baseline (immutable) | `301c96c460a94ae730f6b02a6315520568f9f21346e7e284d2a71e2f3e3bd5bd` | see baseline manifest | Never modified; still has 64 KiB stacks and fails TS by design. |

**Source:** `801abb5a` (`feat(wasm): add bounded HTTP streaming and FFplay teardown`), `a8db6f19` (`fix(wasm): reject inconsistent HTTP range responses`), `0a1fd274` (`fix(wasm): reject AES-128 HLS explicitly`), and `055d1f7e` (`perf(wasm): adapt progressive HTTP range sizes`), plus the N10 acceptance and fixture-reference follow-up documented below.

## Goal tracker

The goal IDs come from the execution plan. The second column maps them to the requirement IDs in the native-ABI plan.

| Goal | Requirement | Status | What is done, on which artifact | What remains |
|---|---|---|---|---|
| **P1.R0** Baseline and provenance | P1.0 | **DONE** | R0 provenance, upstream immutability, export mappings ([R0 repro](PHASE-1-R0-LOCAL-REPRO.md)). | — |
| **P1.R1** Validated TS fixture; TS failure root cause | P1.0, R1.D0–D5 | **DONE** | Root cause: 64 KiB Emscripten pthread stack overflow in `mpegts_read_header`. Fix: `-sDEFAULT_PTHREAD_STACK_SIZE=1048576`. D2-A…H2 10/10 on `b34751c6`. Legacy MPEG-2/MP2 fixture probes without a trap. ([R1 record](PHASE-1-R1-BLOCKER.md)) | — |
| **P1.R2** HLS normal close | P1.3 | **DONE** (gate met) | Same root cause as R1. N05 PASS on `b34751c6`. | Residual tests in **R2-RES** below. |
| **P1.R3** All three kits over HTTP/HLS | P1.3 | **IN PROGRESS** | N05, N05a, N09, N10 and N15b pass in the current diagnostic full transport matrix; N10 reads all three signed segments and validates H.264/AAC metadata. Earlier N13/A04, N11/A05 and N12/A06 evidence remains on prior diagnostics. | Rerun the required kit matrix on the closing package; N12/A06 and residual HLS cases still need fresh results. |
| **P1.R4** Audio teardown | P1.1 | **DONE** (native-only) | `ffplay_lib.c` coordinator; 20/20 FFplay cases, suspended-context 10/10, hot-swap 10/10 on `b707cd2c`; D2-H1 on `b34751c6`. ([trace](PHASE-1-AUDIO-TEARDOWN-TRACE.md)) | S03–S06, A13 stop in **AUDIO-RES**. |
| **P1.R5** Resource, error and security closure | P1.2, P1.6 | **IN PROGRESS** | HTTP-IO-1…8 and HTTP-IO-11 pass current diagnostic checks; HTTP-IO-7 chose explicit unsupported behavior and HTTP-IO-8 uses adaptive sequential ranges. | MEM-1, closing-package evidence, HTTP-IO-9/10 backlog and residual cases. |
| **P1.R6** Closing package, ABI and docs | P1.4, P1.5 | **OPEN** | Interim builds verified 527 exports through `f9a8d51e`. | Everything in [Next actions](#next-actions) step 5. |

## P1.R5 work items

| Item | Status | Evidence (artifact) | Remaining |
|---|---|---|---|
| **HTTP-IO-1** invalid header/URL wedge | **DONE** | `http-io-1-browser.json` (`f9a8d51e`); also inside the `b34751c6` aggregate. | — |
| **HTTP-IO-2** AVIO buffer leak | **DONE** (fix + numeric gates) | 500 cycles: −248 B (`b34751c6`), −272 B (`be9190f3`). Live 5 min endpoint −663,376 B (`range-fixed-live-heap.json`, `be9190f3`). | Total-memory bound is not proven; tracked as **MEM-1**. |
| **HTTP-IO-3** abort status/log | **DONE** | `abort-logging-*.json`, `range-fixed-transport-matrix-recheck.json` (`be9190f3`). | — |
| **HTTP-IO-4/5** bounded waits, small stack | **DONE** (diagnostic) | Full transport 25/0/1 and no page errors on `c6b570b0`; main-thread stall/timeout/forced-close cases completed in 2,003 ms, 301 ms and 2,003 ms with cleanup and module reuse (`phase1-http-io-8-full-transport-after-fixture-fix.json`). | Closing-package rerun and itemized release evidence remain under **EVID-1**. |
| **HTTP-IO-6** cross-range consistency | **DONE** (diagnostic) | Length, ETag, and Last-Modified changes each return `AVERROR(EIO)`; four ranges re-follow the original redirect URL. All cases pass in the current full matrix (`phase1-http-io-8-full-transport-after-fixture-fix.json`, `c6b570b0`). | Closing-package rerun. |
| **HTTP-IO-7** AES-128 HLS | **DONE** (diagnostic; Option B) | `crypto+http(s)` fails explicitly after the key fetch and before encrypted media; the current full matrix passes this check on `c6b570b0` (`phase1-http-io-8-full-transport-after-fixture-fix.json`). | Closing-package rerun. |
| **HTTP-IO-8** throughput | **DONE** (diagnostic; adaptive sequential ranges) | With 100 ms response latency, 880,930 bytes took 1,429 ms/14 direct 64 KiB ranges vs 425 ms/4 Wasm ranges (3.36×); sizes grew 64→128→256→512 KiB and accounted peak was exactly 1 MiB. The full matrix also passes, including N03/N04 at 131,072-byte peaks (`http-io-8-adaptive.json`, `http-io-8-n03-after.json`, `http-io-8-n04-after.json`, `phase1-http-io-8-full-transport-after-fixture-fix.json`, `c6b570b0`). | Repeat on closing package. |
| **HTTP-IO-9** option handling | BACKLOG | — | Documentation and one warning. |
| **HTTP-IO-10** small items | BACKLOG | Admission clock and queue/request timeout split confirmed still pending (current-state 17:45). | — |
| **HTTP-IO-11** multi-range cache-offset truncation (found 2026-10-14) | **DONE** | Reads stopped after 64 KiB. Fixed in `install_response`. 433/433 native packets match (`range-continuity-before/after.json`, `be9190f3`); packet check PASS on `b34751c6`. | — |
| **MEM-1** total-memory evidence | **OPEN** | The 5 min endpoint passes, but the heap rose 45.97→49.35 MB after 60 s. Session log history is retained; browser XHR memory is outside the 1 MiB budget. | Bound or explicitly scope total memory without changing frozen session semantics. |
| **EVID-1** itemized evidence | **OPEN** | The corrected diagnostic full transport result preserves per-case logs for N01, HTTP-IO-1…8, N03/N04, N10 and the remaining cases (`phase1-http-io-8-full-transport-after-fixture-fix.json`, `c6b570b0`). It records the three HTTP-IO-4/5 stall outcomes at 2,003 ms, 301 ms and 2,003 ms. The first matrix attempt failed only because the default packet-reference route returned a generated fallback body; the route now serves the checked-in JSON and has a regression test. | Repeat and retain itemized results on the closing package; older package rows remain historical. |
| **R2-RES** residual HLS tests | **OPEN** | Live reload ≥3 is covered (N11: 64 reloads; N12: 3). | 10 sequential HLS sessions; duplicate/wrong close; FFprobe-only 1- and 3-segment HLS. |
| **AUDIO-RES** remaining audio cases | **OPEN** | — | S03 stop, S04 ten cycles, S05 two sample rates, S06 pause/resume, A13 stop. |
| **R5-NEG** reviewed-plan §8 negative-case list | **OPEN** | Partly covered by N02–N08. | Not recorded as a set: 416 at EOF, malformed 206, 301/302/307/308, expired signed URL, concurrent independent cancellation, XHR memory measurement. |

## Acceptance cases

| Case(s) | Status | Latest artifact | Evidence |
|---|---|---|---|
| F01–F06 fixture contract | PASS | Node | `server-contract-after-http-io-8.tap.log`: 11/11, including the default packet-reference route regression (2026-10-14). |
| N01, N02, N03, N04, N06, N07, N08, N09 | PASS | `c6b570b0` | `phase1-http-io-8-full-transport-after-fixture-fix.json` (25 passed, 0 failed, 1 manual CORS skip). |
| N06 cross-origin missing CORS | PASS | `b34751c6` | `bounded-wait-deadline-cors.json` |
| N05, N05a | PASS | `c6b570b0` | `phase1-http-io-8-full-transport-after-fixture-fix.json` |
| N10 HLS metadata | PASS | `c6b570b0` | `N10-adaptive-debug.json`; full matrix also passes. All three signed segments, H.264 320×240, AAC 48 kHz stereo, packet counts 150/283 and zero final budget counters. The first harness attempt (`N10-adaptive.json`) hid the debug cleanup record with `-v error`; the assertion was retained and the command now enables debug logging. |
| N11 / A05 live ≥30 s | PASS (endpoint) | `be9190f3` | `range-fixed-live-heap.json`; MEM-1 caveat |
| N12 / A06 live recording | PASS | `be9190f3` | `live-recording.json`, `live-recording-native-validation.json` |
| N13 / A04 HLS VOD | PASS | `ae356afe` | `http-io-7-hls-vod.json` (3 segments, 320×240, return 0) |
| N14 | PASS | `c6b570b0` | `phase1-http-io-8-full-transport-after-fixture-fix.json` |
| N15a, N15b | PASS | `c6b570b0` | `phase1-http-io-8-full-transport-after-fixture-fix.json` |
| D2-A…H2 | PASS 10/10 | `596a99de` | `http-io-6-decode-matrix.json` |
| A01, A03, A07–A12, A14 | PASS (via N equivalents) | `c6b570b0` | `phase1-http-io-8-full-transport-after-fixture-fix.json` (only cases represented in the transport matrix; standalone playback/recording rows below remain separate). |
| A02 progressive FFplay | PASS 20/20 | `b707cd2c` | `audio-teardown-gate/` |
| A13 audio stop/EOF | PARTIAL | — | EOF passes; stop not run |
| A15 ABI and upstream | OPEN | — | 527 exports verified only through `f9a8d51e`; closing-package check and upstream re-hash pending |
| S01, S02, S07, S08 | PASS | `b707cd2c` | `audio-teardown-gate/` |
| S03–S06 | NOT RUN | — | AUDIO-RES |
| HTTP-IO probe cases | HTTP-IO-1…8 and HTTP-IO-11 pass in the current diagnostic full matrix; HTTP-IO-2 500-cycle delta −272 B; packet continuity 433/433; adaptive read 3.36× with 1 MiB peak. | `phase1-http-io-8-full-transport-after-fixture-fix.json`, `http-io-8-adaptive.json` | Closing-package reruns remain open; MEM-1 remains a separate total-memory question. |

## Phase 1 → Phase 2 gate

This merges the reviewed-plan §11 gate with the native-ABI plan's handoff gate.

| Gate item | Status |
|---|---|
| HLS normal completion, no upstream edits, triaged fixture | **MET** |
| Direct HTTP inputs for all three kits: VOD/live HLS, recording, cancellation, MEMFS, resource cleanup | **PARTIAL.** Diagnostic transport matrix and N10 now pass; live recording and other earlier cases have evidence on prior builds. R2-RES, AUDIO-RES, R5-NEG, MEM-1 and closing-package reruns remain open. |
| Audio teardown fixed with generated-SDL proof | **MET**; AUDIO-RES open |
| HTTP-IO-1…6 closed; HTTP-IO-7/8 dispositions recorded | **PARTIAL.** Diagnostics pass HTTP-IO-1…8 and 11; the AES-128 and adaptive-range dispositions are recorded. Closing-package reruns and HTTP-IO-9/10 backlog remain. |
| Closing package: ABI 0.11.2, 527 exports, unchanged upstream (A15) | **OPEN** |
| Docs, hashes, reproducible commands and itemized evidence complete | **PARTIAL** (EVID-1) |

## Decisions recorded

- **Transport model: asynchronous Emscripten Fetch on the main runtime thread, hardened** (implemented by HTTP-IO-4/5). Synchronous Fetch in the worker was **rejected**: it loses mid-request cancellation and the memory bound for servers that ignore Range.
- **HTTP-IO-6 redirects:** each byte range uses the original URL, preserving fresh signed redirects; `responseURL` remains the HLS child-resolution base. The browser fixture verified one redirect per range.
- **HTTP-IO-7 AES-128 HLS:** Option B is selected for Phase 1. HLS reads the key URL before opening the segment through `crypto+http(s)`; the Wasm transport rejects that segment open with `ENOSYS` and an explicit message, before fetching encrypted media.
- **HTTP-IO-8 throughput:** adaptive sequential range growth is implemented, without prefetch. The target grows from 64 KiB to 512 KiB after full sequential cache reads; request admission reserves the Fetch response and C copy inside the shared 1 MiB budget.
- **Rejected alternatives:**
  - FFmpeg `http`/libcurl/libcurl.js and other socket-over-proxy routes: they need a server-side proxy, which violates the P1.2 gate.
  - Custom `URLProtocol`: forbidden.
  - WasmFS fetch backend and lazy files: unbounded memory, no live support, no cancellation.
  - hls.js, MSE, `<video>`: forbidden by the stop rule.
- **Audio:** fixed native-only in `ffplay_lib.c`. No Phase 2 helper is required. The gate depends on SDL 2.32.8's private `Module.SDL2.audio` state; re-verify it on any SDL upgrade.
- **Stack size:** production 1 MiB. 256 KiB is used only for diagnostic headroom checks.

## Next actions

1. **HTTP-IO-8 throughput disposition** is implemented and recorded; repeat its measurements and N03/N04 bounded-response checks on the closing package.
2. **MEM-1** total-memory evidence.
3. **Missing cases:**
   - R2-RES;
   - AUDIO-RES;
   - R5-NEG.
4. **P1.R6 closing package:**
   - turn test hooks OFF, set the stack back to 1 MiB, and turn the export verifier ON;
   - rebuild and stage, and verify 527 exports;
   - re-hash upstream (A15);
   - rerun all required cases with itemized per-case records (EVID-1);
   - update the handoffs and request sign-off.
