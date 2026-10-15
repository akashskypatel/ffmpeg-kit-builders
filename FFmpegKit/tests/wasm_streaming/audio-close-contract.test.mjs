import test from 'node:test';
import assert from 'node:assert/strict';
import { AudioCloseCoordinator } from './audio-close-contract.mjs';

function fakeModule(callback) {
  return {
    SDL2: {
      audio: {
        scriptProcessorNode: { onaudioprocess: callback },
      },
    },
  };
}

test('native close waits for the active callback and runs exactly once', async () => {
  const order = [];
  let coordinator;
  let duplicateClose;
  const module = fakeModule(() => {
    order.push('callback-enter');
    duplicateClose = coordinator.beginClose(41, (device, generation) => {
      order.push(`native-close:${device}:${generation}`);
    });
    order.push('callback-exit');
  });
  coordinator = new AudioCloseCoordinator(module);
  const wrapped = coordinator.observeOpen(41, 7);
  const node = module.SDL2.audio.scriptProcessorNode;

  wrapped({});
  const close = coordinator.beginClose(41, () => order.push('duplicate-native-close'));
  assert.equal(close, duplicateClose);
  assert.deepEqual(order, ['callback-enter', 'callback-exit']);
  await close;

  assert.deepEqual(order, ['callback-enter', 'callback-exit', 'native-close:7:41']);
  assert.equal(node.onaudioprocess, null);
  wrapped({});
  assert.equal(order.length, 3, 'a retained stale callback must not re-enter SDL');
});

test('module state is isolated and a rapid reopen gets a fresh generation', async () => {
  let firstCalls = 0;
  let secondCalls = 0;
  const firstModule = fakeModule(() => firstCalls++);
  const secondModule = fakeModule(() => secondCalls++);
  const firstCoordinator = new AudioCloseCoordinator(firstModule);
  const secondCoordinator = new AudioCloseCoordinator(secondModule);
  const staleHandler = firstCoordinator.observeOpen(1, 3);

  await firstCoordinator.beginClose(1, () => {});
  firstModule.SDL2.audio.scriptProcessorNode = {
    onaudioprocess: () => secondCalls++,
  };
  const reopenedHandler = firstCoordinator.observeOpen(2, 4);
  secondCoordinator.observeOpen(1, 3);

  staleHandler({});
  reopenedHandler({});
  secondModule.SDL2.audio.scriptProcessorNode.onaudioprocess({});
  assert.equal(firstCalls, 0);
  assert.equal(secondCalls, 2);
  await Promise.all([
    firstCoordinator.beginClose(2, () => {}),
    secondCoordinator.beginClose(1, () => {}),
  ]);
});
