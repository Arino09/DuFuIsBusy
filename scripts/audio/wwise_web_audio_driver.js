// Refill Wwise from the audio clock, independently of browser visual frames.
(() => {
  if (window.wwiseAudioDriverInstalled) return;
  window.wwiseAudioDriverInstalled = true;
  // Phones only grant audio permission when a touch ends, but the engine creates its context on touch start.
  // Keep every context and resume it on each gesture so it never stays suspended.
  const contexts = new Set();
  const NativeContext = window.AudioContext || window.webkitAudioContext;
  if (NativeContext) {
    const TrackedContext = class extends NativeContext {
      constructor(...args) { super(...args); contexts.add(this); }
    };
    window.AudioContext = TrackedContext;
    window.webkitAudioContext = TrackedContext;
  }
  const resume = () => contexts.forEach(context => { if (context.state !== 'running') context.resume().catch(() => {}); });
  for (const name of ['pointerup', 'touchend', 'mouseup', 'click', 'keydown'])
    document.addEventListener(name, resume, {capture: true, passive: true});
  document.addEventListener('visibilitychange', () => { if (!document.hidden) resume(); });
  // Add ?audiodebug to the address to see why a device stays silent.
  if (new URLSearchParams(location.search).has('audiodebug')) {
    const errors = [];
    const report = message => { errors.push(String(message).slice(0, 120)); if (errors.length > 4) errors.shift(); };
    window.addEventListener('error', event => report(event.message));
    window.addEventListener('unhandledrejection', event => report(event.reason));
    const originalError = console.error;
    console.error = (...args) => { report(args.join(' ')); originalError.apply(console, args); };
    const panel = document.createElement('pre');
    panel.style.cssText = 'position:fixed;left:0;top:0;z-index:99999;margin:0;padding:6px;max-width:100vw;background:#000c;color:#9f9;font:11px/1.3 monospace;white-space:pre-wrap;pointer-events:none';
    document.body.appendChild(panel);
    setInterval(() => {
      panel.textContent = [
        'isolated=' + window.crossOriginIsolated + ' sab=' + (typeof SharedArrayBuffer) + ' sw=' + !!(navigator.serviceWorker && navigator.serviceWorker.controller),
        'contexts=' + [...contexts].map(context => context.state + '@' + context.sampleRate).join(',') + ' worklet=' + !!window.AudioWorkletNode,
        ...errors,
      ].join('\n');
    }, 500);
  }
  const NativeWorklet = window.AudioWorkletNode;
  const processor = `
    class WwiseAudioRefill extends AudioWorkletProcessor {
      constructor() { super(); this.frames = 0; }
      process(inputs, outputs) {
        this.frames += outputs[0][0].length;
        if (this.frames >= 1024) {
          this.port.postMessage('refill');
          this.frames = 0;
        }
        return true;
      }
    }
    registerProcessor('wwise-audio-refill', WwiseAudioRefill);
  `;
  window.AudioWorkletNode = class extends NativeWorklet {
    constructor(context, name, options) {
      super(context, name, options);
      if (name !== 'wwise-worklet-processor') return;
      const url = URL.createObjectURL(new Blob([processor], {type: 'application/javascript'}));
      context.audioWorklet.addModule(url).then(() => {
        const pump = new NativeWorklet(context, 'wwise-audio-refill');
        const mute = context.createGain();
        mute.gain.value = 0;
        this.connect(pump);
        pump.connect(mute);
        mute.connect(context.destination);
        pump.port.onmessage = () => window.wwiseRenderAudio?.();
      }).catch(error => console.error('Wwise audio refill initialization failed:', error))
        .finally(() => URL.revokeObjectURL(url));
    }
  };
})();
