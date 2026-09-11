#!/usr/bin/env node

import {readFile} from 'node:fs/promises';
import process from 'node:process';

const artifactPath = process.argv[2];
if (!artifactPath) {
  throw new Error('usage: g10_table_growth_test.mjs <ffmpegkit.wasm>');
}

const assert = (condition, message) => {
  if (!condition) throw new Error(`G10 assertion failed: ${message}`);
};

const module = await WebAssembly.compile(await readFile(artifactPath));
const importObject = {};
for (const descriptor of WebAssembly.Module.imports(module)) {
  importObject[descriptor.module] ??= {};
  if (descriptor.kind === 'memory') {
    importObject[descriptor.module][descriptor.name] =
      new WebAssembly.Memory({initial: 1024, maximum: 32768, shared: true});
  } else if (descriptor.kind === 'function') {
    importObject[descriptor.module][descriptor.name] = () => 0;
  } else {
    throw new Error(`unsupported Wasm import: ${descriptor.module}.${descriptor.name} (${descriptor.kind})`);
  }
}

const instance = await WebAssembly.instantiate(module, importObject);
let tableDiscoveryCount = 0;
const discoverTable = (exports) => {
  tableDiscoveryCount += 1;
  const tables = Object.values(exports).filter(
    (value) => value instanceof WebAssembly.Table,
  );
  assert(tables.length === 1, `expected one exported WebAssembly.Table, found ${tables.length}`);
  return tables[0];
};

const table = discoverTable(instance.exports);
assert(tableDiscoveryCount === 1, `table discovered ${tableDiscoveryCount} times`);
assert(table instanceof WebAssembly.Table, 'discovered value is not a WebAssembly.Table');

let oldFunctionIndex = -1;
for (let index = 0; index < table.length; index += 1) {
  const value = table.get(index);
  if (typeof value === 'function' && value.length === 0) {
    oldFunctionIndex = index;
    break;
  }
}
assert(oldFunctionIndex >= 0, 'could not find an existing zero-argument table function');
const oldFunction = table.get(oldFunctionIndex);
assert(typeof oldFunction === 'function', 'existing table entry is not callable');

const before = table.length;
const old = table.grow(1);
const after = table.length;
assert(old === before, `first grow returned ${old}, expected ${before}`);
assert(after === before + 1, `first grow produced ${after}, expected ${before + 1}`);

const writableFunction = oldFunction;
table.set(before, writableFunction);
assert(table.get(before) === writableFunction, 'new table slot did not retain its function');
table.get(before)();

for (const amount of [3, 7, 16]) {
  const previous = table.length;
  const returned = table.grow(amount);
  assert(returned === previous, `grow(${amount}) returned ${returned}, expected ${previous}`);
  assert(table.length === previous + amount, `grow(${amount}) produced ${table.length}`);
  table.set(previous, writableFunction);
  assert(table.get(previous) === writableFunction, `grow(${amount}) slot was not writable`);
}

assert(table.get(oldFunctionIndex) === oldFunction, 'existing function changed after growth');
oldFunction();
assert(table.get(before) === writableFunction, 'writable function changed after repeated growth');
table.get(before)();

console.log(JSON.stringify({
  artifact: artifactPath,
  tableDiscoveryCount,
  initialLength: before,
  firstGrowReturn: old,
  finalLength: table.length,
  oldFunctionIndex,
  writableIndex: before,
  repeatedGrowth: [3, 7, 16],
  status: 'PASS',
}));
