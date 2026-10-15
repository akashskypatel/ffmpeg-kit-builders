/*
 * Supplemental model of WebAudio callback quiescence and close ordering.
 * This is test infrastructure, not a production Flutter/RN adapter.
 */
export class AudioCloseCoordinator {
  constructor(module) {
    this.module = module;
    this.generations = new Map();
  }

  observeOpen(generation, deviceId) {
    const node = this.module?.SDL2?.audio?.scriptProcessorNode;
    if (!node || typeof node.onaudioprocess !== 'function')
      throw new Error('SDL ScriptProcessor callback is unavailable');
    if (this.generations.has(generation))
      throw new Error(`playback generation ${generation} was already observed`);

    const state = {
      generation,
      deviceId,
      node,
      callback: node.onaudioprocess,
      active: 0,
      closing: false,
      closePromise: null,
      resolveQuiescent: null,
      completionCalled: false,
    };

    state.wrappedCallback = function wrappedAudioProcess(event) {
      if (state.closing)
        return;
      state.active++;
      try {
        return state.callback.call(this, event);
      } finally {
        state.active--;
        if (state.closing && state.active === 0 && state.resolveQuiescent) {
          const resolve = state.resolveQuiescent;
          state.resolveQuiescent = null;
          resolve();
        }
      }
    };
    node.onaudioprocess = state.wrappedCallback;
    this.generations.set(generation, state);
    return state.wrappedCallback;
  }

  beginClose(generation, completeNativeClose) {
    const state = this.generations.get(generation);
    if (!state)
      return Promise.reject(new Error(`unknown playback generation ${generation}`));
    if (state.closePromise)
      return state.closePromise;

    state.closing = true;
    if (state.node.onaudioprocess === state.wrappedCallback)
      state.node.onaudioprocess = null;

    state.closePromise = new Promise((resolve, reject) => {
      const finish = () => {
        if (state.completionCalled)
          return;
        state.completionCalled = true;
        Promise.resolve()
          .then(() => completeNativeClose(state.deviceId, state.generation))
          .then(resolve, reject);
      };

      if (state.active === 0)
        finish();
      else
        state.resolveQuiescent = finish;
    });
    return state.closePromise;
  }
}
