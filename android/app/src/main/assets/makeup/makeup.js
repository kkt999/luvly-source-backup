const video = document.querySelector('#camera');
const canvas = document.querySelector('#mirror');
const mirror = document.querySelector('.mirror');
const framingGuide = document.querySelector('.framing-guide');
const start = document.querySelector('#start');
const stop = document.querySelector('#stop');
const reload = document.querySelector('#reload');
const compare = document.querySelector('#compare');
const layer = document.querySelector('#layer');
const lipstickShade = document.querySelector('#lipstick-shade');
const lipstickSwatch = document.querySelector('#lipstick-swatch');
const status = document.querySelector('#status');
const buttons = [...document.querySelectorAll('.look')];
const description = document.querySelector('#description');
const looks = {
  rose: {
    description: 'Rose lips, a soft pink flush and a neutral wash on the eyes.',
    lipstick: '#a33a59', blush: '#c7798c', eyeshadow: '#af827c',
  },
  peach: {
    description: 'Peach lips and cheeks with a warm wash on the eyes.',
    lipstick: '#c56742', blush: '#d28e79', eyeshadow: '#b78364',
  },
  berry: {
    description: 'A deeper berry lip, rose cheeks and a soft plum eye.',
    lipstick: '#671839', blush: '#ae667e', eyeshadow: '#926d83',
  },
};
let session;
let look = 'rose';
let bare = false;
const categories = ['lipstick', 'blush', 'eyeshadow'];
const eyeAndLipLandmarks = [33, 133, 159, 145, 362, 263, 386, 374, 61, 291, 0, 17];

function lipstickColour() {
  return lipstickShade.value || looks[look].lipstick;
}

function setBare(value) {
  bare = value;
  compare.setAttribute('aria-pressed', String(value));
  compare.textContent = value ? 'Show makeup' : 'Show bare face';
}

function hasFramedFeatures(landmarks, wasFramed) {
  if (!landmarks?.length) return false;
  const { clientWidth, clientHeight } = mirror;
  const { offsetLeft, offsetTop, offsetWidth, offsetHeight } = canvas;
  // Check against the visible mirror. The mirrored SDK canvas can extend past it.
  const margin = Math.min(clientWidth, clientHeight) * (wasFramed ? .015 : .035);
  return eyeAndLipLandmarks.every(index => {
    const point = landmarks[index];
    if (!point) return false;
    const x = offsetLeft + (1 - point.x) * offsetWidth;
    const y = offsetTop + point.y * offsetHeight;
    return x > margin && x < clientWidth - margin &&
      y > margin && y < clientHeight - margin;
  });
}

function describeTracking(faceFramed) {
  framingGuide.hidden = Boolean(faceFramed);
  status.textContent = faceFramed
    ? 'Live preview · turn gently to compare.'
    : 'Adjust the phone until both eyes and your lips are inside the mirror.';
}

// OpenMakeup supplies the tracking and renderer. This bridge gives the page
// ownership of camera permission and frame scheduling.
window.Camera = class {
  constructor(source, { onFrame }) {
    this.source = source;
    this.owner = session;
    this.onFrame = onFrame;
  }

  start() {
    const frame = async () => {
      if (!this.owner || session !== this.owner || this.source.srcObject !== this.owner.stream) return;
      try {
        await this.onFrame();
        if (session === this.owner) this.frame = this.source.requestVideoFrameCallback(frame);
      } catch (error) {
        if (session === this.owner) {
          console.error(error);
          end('Face tracking stopped. Try opening the camera again.');
        }
      }
    };
    this.frame = this.source.requestVideoFrameCallback(frame);
  }

  stop() {
    if (this.frame != null) this.source.cancelVideoFrameCallback(this.frame);
  }
};

const FaceMesh = window.FaceMesh;
if (FaceMesh) {
  window.FaceMesh = class extends FaceMesh {
    onResults(handler) {
      const owner = session;
      super.onResults((result) => {
        if (!owner || session !== owner) return;
        const faceFramed = hasFramedFeatures(result.multiFaceLandmarks?.[0], owner.faceFramed);
        if (owner.faceFramed !== faceFramed) {
          owner.faceFramed = faceFramed;
          if (owner.ready) {
            describeTracking(faceFramed);
            applyLook();
          }
        }
        handler(result);
      });
    }
  };
}

function end(message = 'Camera stopped. You can start it again whenever you’re ready.') {
  const closing = session;
  session = undefined;
  clearTimeout(closing?.timer);
  closing?.stream?.getTracks().forEach((track) => track.stop());
  video.srcObject = null;
  closing?.sdk?.dispose();
  mirror.dataset.live = 'false';
  framingGuide.hidden = true;
  start.disabled = false;
  start.textContent = 'Start camera';
  stop.hidden = true;
  reload.hidden = true;
  status.textContent = message;
}

async function applyLook() {
  const owner = session;
  if (!owner?.ready) return;
  const revision = ++owner.revision;
  owner.sdk.clearAll();
  if (bare || !owner.faceFramed) return;
  const selected = layer.value === 'all' ? categories : [layer.value];
  for (const category of selected) {
    if (session !== owner || revision !== owner.revision) return;
    const finish = category === 'lipstick' && look !== 'berry' ? 'glossy' : 'matte';
    const color = category === 'lipstick' ? lipstickColour() : looks[look][category];
    await owner.sdk.apply(category, { color, finish });
  }
}

start.addEventListener('click', async () => {
  if (session) return;
  if (!navigator.mediaDevices?.getUserMedia || !video.requestVideoFrameCallback) {
    status.textContent = 'Update Android System WebView to use the camera.';
    return;
  }
  const owner = { revision: 0 };
  session = owner;
  start.disabled = true;
  start.textContent = 'Opening…';
  status.textContent = 'Allow camera access to open the mirror.';
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: { facingMode: 'user', width: { ideal: 960 }, height: { ideal: 720 } },
    });
    if (session !== owner) {
      stream.getTracks().forEach((track) => track.stop());
      return;
    }
    owner.stream = stream;
    video.srcObject = stream;
    await video.play();
    if (session !== owner) return;
    status.textContent = 'Preparing the makeup mirror…';
    owner.timer = setTimeout(() => {
      if (session === owner) {
        end('The mirror is taking too long to load.');
        start.disabled = true;
        reload.hidden = false;
      }
    }, 25000);
    const { OpenMakeup } = await import('open-makeup-sdk');
    if (session !== owner) return;
    owner.sdk = new OpenMakeup({
      video,
      renderCanvas: canvas,
      assetsBaseUrl: new URL('./makeup-assets/', location.href).href,
      mediapipeBaseUrl: new URL('./face-mesh/', location.href).href,
    });
    await owner.sdk.init();
    if (session !== owner) {
      owner.sdk.dispose();
      return;
    }
    // SDK 0.1.0 reports ready before its asynchronously loaded materials exist.
    // Wait for all three before applying colours so the first preset is complete.
    const engine = owner.sdk.engine;
    while (session === owner && !(engine.lipsMat && engine.blushMat && engine.eyeShadowMat)) {
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    if (session !== owner) return;
    clearTimeout(owner.timer);
    owner.ready = true;
    mirror.dataset.live = 'true';
    stop.hidden = false;
    describeTracking(owner.faceFramed);
    await applyLook();
  } catch (error) {
    if (session !== owner) return;
    if (error.name === 'NotAllowedError') {
      end('Camera access is off. Allow it in Chrome, then try again.');
    } else if (error.name === 'NotFoundError' || error.name === 'NotReadableError') {
      end('The front camera is unavailable. Close other camera apps and try again.');
    } else {
      end('The makeup mirror could not load. Reload the preview and try again.');
      reload.hidden = false;
      console.error(error);
    }
  }
});

for (const button of buttons) {
  button.addEventListener('click', () => {
    look = button.dataset.look;
    setBare(false);
    for (const item of buttons) item.setAttribute('aria-pressed', String(item === button));
    description.textContent = looks[look].description;
    lipstickSwatch.style.setProperty('--swatch', lipstickColour());
    applyLook();
  });
}

compare.addEventListener('click', () => {
  setBare(!bare);
  applyLook();
});
layer.addEventListener('change', () => {
  setBare(false);
  applyLook();
});
lipstickShade.addEventListener('change', () => {
  lipstickSwatch.style.setProperty('--swatch', lipstickColour());
  if (layer.value !== 'all') layer.value = 'lipstick';
  setBare(false);
  applyLook();
});
stop.addEventListener('click', () => end());
reload.addEventListener('click', () => location.reload());
document.addEventListener('visibilitychange', () => {
  if (document.hidden && session?.ready) end();
});
window.addEventListener('pagehide', () => { if (session) end(); });
