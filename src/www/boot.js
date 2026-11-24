"use strict";

const falling = (() => {
  const MAX_PIXELS = 2_500_000;   // perf cap on the backing store

  function backingSize(canvas) {
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    let w = rect.width * dpr;
    let h = rect.height * dpr;
    const over = Math.sqrt((w * h) / MAX_PIXELS);
    if (over > 1) {
      w /= over;
      h /= over;
    }
    return [Math.round(w), Math.round(h)];
  }

  let pending = false;
  function syncSize(module) {
    if (pending) return;
    pending = true;

    requestAnimationFrame(() => {
      pending = false;
      const [w, h] = backingSize(module.canvas);
      module._app_set_canvas_size(w, h);
    });
  }

  const ready = new Promise((resolve) => {
    if (document.readyState === "complete") resolve();
    else window.addEventListener("load", resolve);
  });

  function whenLive(module) {
    return new Promise((resolve) => {
      (function poll() {
        if (module._app_is_ready()) resolve(module);
        else requestAnimationFrame(poll);
      })();
    });
  }

  return {
    ready,

    start(canvas) {
      // See http://www.khronos.org/registry/webgl/specs/latest/1.0/#5.15.2
      canvas.addEventListener("webglcontextlost", (e) => e.preventDefault(), false);

      return ready
        .then(() => Module({ canvas }))
        .then(whenLive)
        .then((module) => {
          window.module = module;
          canvas.focus();
          syncSize(module);
          window.addEventListener("resize", () => syncSize(module));
          window.addEventListener("orientationchange", () => syncSize(module));
          return module;
        });
    },
  };
})();
