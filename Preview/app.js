// FocuSee-Style UI Controller & Interactive Simulator

// State management
const focuseeState = {
  activeScreen: 'editor', // 'launcher' or 'editor'
  recordingMode: 'fullscreen',
  currentTime: 3.0, // Initial time matching Screenshot 2: 00:03
  totalDuration: 12.0, // 00:12
  isPlaying: false,
  canvasRatio: '16:9',
  padding: 10,
  inset: 0,
  roundness: 4,
  shadow: 20,
  zoomScale: 1.5,
  isZoomActive: true
};

// DOM Elements
const btnShowLauncher = document.getElementById('btnShowLauncher');
const btnShowEditor = document.getElementById('btnShowEditor');
const screenLauncher = document.getElementById('screenLauncher');
const screenEditor = document.getElementById('screenEditor');

// Launcher Elements
const modeCards = document.querySelectorAll('.mode-card');
const btnStartRecording = document.getElementById('btnStartRecordingFromLauncher');

// Editor Elements
const artboardFrame = document.getElementById('artboardFrame');
const artboardZoomContainer = document.getElementById('artboardZoomContainer');
const recordedBrowserWindow = document.getElementById('recordedBrowserWindow');
const focuseeCursor = document.getElementById('focuseeCursor');
const focuseeClickRing = document.getElementById('focuseeClickRing');

// Sliders & Values
const sliderPadding = document.getElementById('sliderEditorPadding');
const valPadding = document.getElementById('valEditorPadding');
const sliderInset = document.getElementById('sliderEditorInset');
const valInset = document.getElementById('valEditorInset');
const sliderRoundness = document.getElementById('sliderEditorRoundness');
const valRoundness = document.getElementById('valEditorRoundness');
const sliderShadow = document.getElementById('sliderEditorShadow');
const valShadow = document.getElementById('valEditorShadow');

// Timeline Elements
const btnPlayPause = document.getElementById('btnFocuseePlayPause');
const playIcon = document.getElementById('focuseePlayIcon');
const pauseIcon = document.getElementById('focuseePauseIcon');
const timecodeDisplay = document.getElementById('focuseeTimecode');
const focuseePlayhead = document.getElementById('focuseePlayhead');
const timelineScroller = document.getElementById('timelineScroller');
const zoomPill = document.getElementById('zoomPill1');
const clipBlock1 = document.getElementById('clipBlock1');
const clipBlock2 = document.getElementById('clipBlock2');

// ====================================================================
// SCREEN TOGGLING (Screen 1 vs Screen 2)
// ====================================================================
function setScreen(screen) {
  focuseeState.activeScreen = screen;
  if (screen === 'launcher') {
    screenLauncher.style.display = 'flex';
    screenEditor.style.display = 'none';
    btnShowLauncher.classList.add('active');
    btnShowEditor.classList.remove('active');
  } else {
    screenLauncher.style.display = 'none';
    screenEditor.style.display = 'grid';
    btnShowEditor.classList.add('active');
    btnShowLauncher.classList.remove('active');
  }
}

btnShowLauncher.addEventListener('click', () => setScreen('launcher'));
btnShowEditor.addEventListener('click', () => setScreen('editor'));

// ====================================================================
// SCREEN 1: LAUNCHER LOGIC
// ====================================================================
modeCards.forEach(card => {
  card.addEventListener('click', () => {
    modeCards.forEach(c => c.classList.remove('active'));
    card.classList.add('active');
    focuseeState.recordingMode = card.dataset.mode;
  });
});

btnStartRecording.addEventListener('click', () => {
  btnStartRecording.textContent = '● Recording (3s)...';
  setTimeout(() => {
    btnStartRecording.innerHTML = '<div class="rec-red-circle"></div> Start Recording';
    setScreen('editor');
    startPlayback();
  }, 1000);
});

// ====================================================================
// SCREEN 2: EDITOR PROPERTIES & TIMELINE
// ====================================================================

// 1. Ratio Pills
document.querySelectorAll('.ratio-pill').forEach(pill => {
  pill.addEventListener('click', () => {
    document.querySelectorAll('.ratio-pill').forEach(p => p.classList.remove('active'));
    pill.classList.add('active');
    const ratio = pill.dataset.ratio;
    focuseeState.canvasRatio = ratio;

    if (ratio === '9:16') {
      artboardFrame.style.maxWidth = '320px';
      artboardFrame.style.maxHeight = '568px';
    } else if (ratio === '1:1') {
      artboardFrame.style.maxWidth = '460px';
      artboardFrame.style.maxHeight = '460px';
    } else if (ratio === '4:3') {
      artboardFrame.style.maxWidth = '640px';
      artboardFrame.style.maxHeight = '480px';
    } else {
      artboardFrame.style.maxWidth = '860px';
      artboardFrame.style.maxHeight = '484px';
    }
  });
});

// 2. Sliders
sliderPadding.addEventListener('input', (e) => {
  const val = e.target.value;
  valPadding.textContent = val;
  artboardFrame.style.padding = `${val * 2}px`;
});

sliderInset.addEventListener('input', (e) => {
  const val = e.target.value;
  valInset.textContent = val;
  recordedBrowserWindow.style.borderWidth = `${val}px`;
});

sliderRoundness.addEventListener('input', (e) => {
  const val = e.target.value;
  valRoundness.textContent = val;
  recordedBrowserWindow.style.borderRadius = `${val * 2}px`;
});

sliderShadow.addEventListener('input', (e) => {
  const val = e.target.value;
  valShadow.textContent = val;
  recordedBrowserWindow.style.boxShadow = `0 ${val}px ${val * 2}px rgba(0, 0, 0, 0.5)`;
});

// 3. Wallpapers & Swatches
document.querySelectorAll('.bg-thumb').forEach(thumb => {
  thumb.addEventListener('click', () => {
    document.querySelectorAll('.bg-thumb').forEach(t => t.classList.remove('active'));
    thumb.classList.add('active');
    artboardFrame.style.background = thumb.style.background;
  });
});

document.querySelectorAll('.swatch-cell:not(.color-wheel-picker)').forEach(swatch => {
  swatch.addEventListener('click', () => {
    artboardFrame.style.background = swatch.style.background;
  });
});

// 4. Zoom Engine & Timeline Playback
let animationLoop = null;
let lastTimestamp = null;

function updateTimelineUI() {
  const progressPercent = (focuseeState.currentTime / focuseeState.totalDuration) * 100;
  focuseePlayhead.style.left = `${progressPercent}%`;

  const secs = Math.floor(focuseeState.currentTime);
  const total = Math.floor(focuseeState.totalDuration);
  timecodeDisplay.textContent = `00:${secs < 10 ? '0' : ''}${secs} / 00:${total}`;

  // Evaluate Zoom Pill (from ~2.4s to 5.2s)
  const isInsideZoomPill = focuseeState.currentTime >= 2.4 && focuseeState.currentTime <= 5.2;
  if (isInsideZoomPill) {
    // Zoomed into headline / product hunt badge
    artboardZoomContainer.style.transform = 'scale(1.48) translate(-4%, -2%)';
    focuseeCursor.style.top = '44%';
    focuseeCursor.style.left = '52%';
    zoomPill.style.boxShadow = '0 0 12px rgba(37, 99, 235, 0.7)';
  } else {
    // Standard 1.0x Full Canvas
    artboardZoomContainer.style.transform = 'scale(1.0) translate(0, 0)';
    zoomPill.style.boxShadow = 'none';
  }

  // Active clip selection
  if (focuseeState.currentTime < 3.0) {
    clipBlock1.classList.add('active-clip');
    clipBlock2.classList.remove('active-clip');
  } else {
    clipBlock2.classList.add('active-clip');
    clipBlock1.classList.remove('active-clip');
  }
}

function startPlayback() {
  focuseeState.isPlaying = true;
  playIcon.style.display = 'none';
  pauseIcon.style.display = 'block';
  lastTimestamp = performance.now();
  runLoop();
}

function pausePlayback() {
  focuseeState.isPlaying = false;
  playIcon.style.display = 'block';
  pauseIcon.style.display = 'none';
  if (animationLoop) cancelAnimationFrame(animationLoop);
}

function runLoop() {
  if (!focuseeState.isPlaying) return;
  const now = performance.now();
  const delta = (now - lastTimestamp) / 1000;
  lastTimestamp = now;

  focuseeState.currentTime += delta;
  if (focuseeState.currentTime >= focuseeState.totalDuration) {
    focuseeState.currentTime = 0;
  }

  updateTimelineUI();
  animationLoop = requestAnimationFrame(runLoop);
}

btnPlayPause.addEventListener('click', () => {
  if (focuseeState.isPlaying) {
    pausePlayback();
  } else {
    startPlayback();
  }
});

// Click anywhere on timeline to scrub
timelineScroller.addEventListener('click', (e) => {
  const rect = timelineScroller.getBoundingClientRect();
  const clickX = e.clientX - rect.left - 16;
  const trackWidth = rect.width - 32;
  if (clickX >= 0 && clickX <= trackWidth) {
    focuseeState.currentTime = (clickX / trackWidth) * focuseeState.totalDuration;
    updateTimelineUI();
  }
});

// Initialize to 00:03 state matching screenshot
updateTimelineUI();
