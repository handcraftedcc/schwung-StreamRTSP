import { MoveShift } from '/data/UserData/move-anything/shared/constants.mjs';

import { isCapacitiveTouchMessage } from '/data/UserData/move-anything/shared/input_filter.mjs';

import { createAction } from '/data/UserData/move-anything/shared/menu_items.mjs';
import { createMenuState, handleMenuInput } from '/data/UserData/move-anything/shared/menu_nav.mjs';
import { createMenuStack } from '/data/UserData/move-anything/shared/menu_stack.mjs';
import { drawStackMenu } from '/data/UserData/move-anything/shared/menu_render.mjs';

const SPINNER = ['-', '/', '|', '\\'];
const TRANSPORT_CONTROLS_VISIBLE = false;

let status = 'stopped';
let deviceName = 'Move Everything';
let controlsEnabled = false;
let trackName = '';
let trackArtist = '';
let playbackEvent = '';
let quality = 320;
let lastError = '';
let candidateCount = 0;
let candidates = [];
let shiftHeld = false;

let menuState = createMenuState();
let menuStack = createMenuStack();

let tickCounter = 0;
let spinnerTick = 0;
let spinnerFrame = 0;
let needsRedraw = true;

function loadCandidates() {
  const rawCount = Number.parseInt(host_module_get_param('candidate_count') || '0', 10);
  const count = Number.isInteger(rawCount) && rawCount > 0 ? Math.min(rawCount, 12) : 0;
  const next = [];
  for (let i = 0; i < count; i++) {
    const name = host_module_get_param(`candidate_${i}_name`) || `Device ${i + 1}`;
    const url = host_module_get_param(`candidate_${i}_url`) || '';
    if (!url) continue;
    next.push({ index: i, name, url });
  }
  return next;
}

function refreshState() {
  const prevStatus = status;
  const prevControls = controlsEnabled;
  const prevTrackName = trackName;
  const prevTrackArtist = trackArtist;
  const prevQuality = quality;
  const prevPlaybackEvent = playbackEvent;
  const prevLastError = lastError;
  const prevCandidateSignature = JSON.stringify(candidates);

  status = host_module_get_param('status') || 'stopped';
  deviceName = host_module_get_param('device_name') || 'Move Everything';
  controlsEnabled = host_module_get_param('controls_enabled') === '1';
  trackName = host_module_get_param('track_name') || '';
  trackArtist = host_module_get_param('track_artist') || '';
  playbackEvent = host_module_get_param('playback_event') || '';
  quality = parseInt(host_module_get_param('quality') || '320', 10);
  lastError = host_module_get_param('last_error') || '';
  candidates = loadCandidates();
  candidateCount = candidates.length;
  if (![96, 160, 320].includes(quality)) quality = 320;

  const nextCandidateSignature = JSON.stringify(candidates);

  if (
    prevStatus !== status ||
    prevControls !== controlsEnabled ||
    prevTrackName !== trackName ||
    prevTrackArtist !== trackArtist ||
    prevQuality !== quality ||
    prevPlaybackEvent !== playbackEvent ||
    prevLastError !== lastError ||
    prevCandidateSignature !== nextCandidateSignature
  ) {
    rebuildMenu();
    needsRedraw = true;
  }
}

function statusLabel() {
  if (status === 'starting') return 'Starting receiver';
  if (status === 'disconnected') return 'Disconnected';
  if (status === 'scanning') return 'Scanning LAN';
  if (status === 'connecting') return 'Connecting';
  if (status === 'buffering') return 'Buffering';
  if (status === 'streaming') return 'Streaming';
  if (status === 'reconnecting') return 'Reconnecting';
  if (status === 'waiting_for_spotify' || status === 'waiting_for_sender') return 'Waiting for sender';
  if (status === 'authenticating') return 'Negotiating session';
  if (status === 'ready') return 'Ready for playback';
  if (status === 'playing') return 'Receiving audio';
  if (status === 'stopped') return 'Stopped';
  if (status === 'error') return 'Error';
  return status;
}

function qualityLabel(value) {
  if (value === 96) return 'Normal';
  if (value === 160) return 'Safe';
  return 'Max Stability';
}

function nextQuality(value) {
  if (value === 96) return 160;
  if (value === 160) return 320;
  return 96;
}

function trackPrefix(value, maxLen) {
  if (!value) return '';
  if (value.length <= maxLen) return value;
  return `${value.slice(0, maxLen - 1)}…`;
}

function isDiscoveryInProgress() {
  return (
    status === 'starting' ||
    status === 'scanning' ||
    status === 'connecting' ||
    status === 'buffering' ||
    status === 'reconnecting' ||
    status === 'authenticating'
  );
}

function shouldShowDeviceList() {
  if (candidateCount <= 0) return false;
  if (isDiscoveryInProgress()) return false;
  if (status === 'streaming' || status === 'playing' || status === 'ready') return false;
  return true;
}

function buildRootItems() {
  const items = [];
  const sourceLabel = trackName || '(none)';
  const detailsLabel = status === 'error' && lastError
    ? `Error: ${trackPrefix(lastError, 16)}`
    : (trackArtist ? trackPrefix(trackArtist, 18) : '(none)');
  const showDeviceList = shouldShowDeviceList();
  const scanningDevices = isDiscoveryInProgress();

  items.push(createAction(`Sender: ${deviceName}`, () => {}));

  items.push(createAction(`Source: ${trackPrefix(sourceLabel, 19)}`, () => {}));
  items.push(createAction(`Details: ${detailsLabel}`, () => {}));

  if (showDeviceList) {
    for (const candidate of candidates) {
      const title = candidate.name || candidate.url;
      items.push(createAction(`[Device: ${trackPrefix(title, 16)}]`, () => {
        host_module_set_param('connect_candidate', String(candidate.index));
        needsRedraw = true;
      }));
    }
  } else if (scanningDevices) {
    items.push(createAction('Devices: scanning...', () => {}));
  } else {
    items.push(createAction('Devices: (none found)', () => {}));
  }

  items.push(createAction(`[Buffer: ${qualityLabel(quality)}]`, () => {
    const updated = nextQuality(quality);
    host_module_set_param('quality', String(updated));
    needsRedraw = true;
  }));

  items.push(createAction('[Scan LAN]', () => {
    host_module_set_param('scan', '1');
    needsRedraw = true;
  }));

  items.push(createAction('[Connect Last]', () => {
    host_module_set_param('connect_last', '1');
    needsRedraw = true;
  }));

  items.push(createAction('[Disconnect]', () => {
    host_module_set_param('disconnect', '1');
    needsRedraw = true;
  }));

  items.push(createAction('[Restart Session]', () => {
    host_module_set_param('restart', '1');
    needsRedraw = true;
  }));

  return items;
}

function rebuildMenu() {
  const items = buildRootItems();
  const current = menuStack.current();
  if (!current) {
    menuStack.push({
      title: 'StreamRTSP',
      items,
      selectedIndex: 0
    });
    menuState.selectedIndex = 0;
  } else {
    current.title = 'StreamRTSP';
    current.items = items;
    if (menuState.selectedIndex >= items.length) {
      menuState.selectedIndex = Math.max(0, items.length - 1);
    }
  }
  needsRedraw = true;
}

function currentFooter() {
  if (status === 'error' && lastError) {
    return trackPrefix(lastError, 20);
  }

  const waitingStates = status === 'starting' ||
    status === 'scanning' ||
    status === 'connecting' ||
    status === 'buffering' ||
    status === 'reconnecting' ||
    status === 'waiting_for_spotify' ||
    status === 'authenticating';
  const activity = waitingStates ? 'Working' : '';
  if (activity) return `${activity} ${SPINNER[spinnerFrame]}`;
  if (status === 'streaming' || status === 'playing') return 'Connected';
  if (status === 'ready') return 'Idle';
  return statusLabel();
}

globalThis.init = function () {
  status = 'stopped';
  deviceName = 'Move Everything';
  controlsEnabled = false;
  trackName = '';
  trackArtist = '';
  playbackEvent = '';
  quality = 320;
  lastError = '';
  candidateCount = 0;
  candidates = [];
  shiftHeld = false;

  menuState = createMenuState();
  menuStack = createMenuStack();
  tickCounter = 0;
  spinnerTick = 0;
  spinnerFrame = 0;
  needsRedraw = true;

  rebuildMenu();
};

globalThis.tick = function () {
  tickCounter = (tickCounter + 1) % 6;
  if (tickCounter === 0) {
    refreshState();
  }

  if (
    status === 'starting' ||
    status === 'scanning' ||
    status === 'connecting' ||
    status === 'buffering' ||
    status === 'reconnecting' ||
    status === 'waiting_for_spotify' ||
    status === 'authenticating'
  ) {
    spinnerTick = (spinnerTick + 1) % 3;
    if (spinnerTick === 0) {
      spinnerFrame = (spinnerFrame + 1) % SPINNER.length;
      needsRedraw = true;
    }
  } else {
    spinnerTick = 0;
  }

  if (needsRedraw) {
    const current = menuStack.current();
    if (!current) {
      rebuildMenu();
    }

    clear_screen();
    drawStackMenu({
      stack: menuStack,
      state: menuState,
      footer: currentFooter()
    });

    needsRedraw = false;
  }
};

globalThis.onMidiMessageInternal = function (data) {
  const statusByte = data[0] & 0xF0;
  const cc = data[1];
  const val = data[2];

  if (isCapacitiveTouchMessage(data)) return;

  if (statusByte === 0xB0 && cc === MoveShift) {
    shiftHeld = val > 0;
    return;
  }

  if (statusByte !== 0xB0) return;

  const current = menuStack.current();
  if (!current) {
    rebuildMenu();
    return;
  }

  const result = handleMenuInput({
    cc,
    value: val,
    items: current.items,
    state: menuState,
    stack: menuStack,
    onBack: () => {
      host_return_to_menu();
    },
    shiftHeld
  });

  if (result.needsRedraw) {
    needsRedraw = true;
  }
};

globalThis.onMidiMessageExternal = function (data) {
  /* No external MIDI handling needed */
};

globalThis.chain_ui = {
  init: globalThis.init,
  tick: globalThis.tick,
  onMidiMessageInternal: globalThis.onMidiMessageInternal,
  onMidiMessageExternal: globalThis.onMidiMessageExternal
};
