import { MoveShift } from '/data/UserData/schwung/shared/constants.mjs';

import { isCapacitiveTouchMessage } from '/data/UserData/schwung/shared/input_filter.mjs';

import { createAction } from '/data/UserData/schwung/shared/menu_items.mjs';
import { createMenuState, handleMenuInput } from '/data/UserData/schwung/shared/menu_nav.mjs';
import { createMenuStack } from '/data/UserData/schwung/shared/menu_stack.mjs';
import { drawStackMenu } from '/data/UserData/schwung/shared/menu_render.mjs';
import {
  openTextEntry,
  isTextEntryActive,
  handleTextEntryMidi,
  drawTextEntry,
  tickTextEntry
} from '/data/UserData/schwung/shared/text_entry.mjs';

const SPINNER = ['-', '/', '|', '\\'];
const DEFAULT_PORT = 8554;
const DEFAULT_PATH = 'screen';
const MAX_HISTORY_ENTRIES = 5;

let status = 'stopped';
let networkPrefix = '192.168.0';
let suffixInput = '';
let portInput = DEFAULT_PORT;
let pathInput = DEFAULT_PATH;
let lastError = '';
let historyEndpoints = [];
let showHistory = false;
let shiftHeld = false;

let menuState = createMenuState();
let menuStack = createMenuStack();

let tickCounter = 0;
let spinnerTick = 0;
let spinnerFrame = 0;
let needsRedraw = true;

function clampPort(value) {
  if (!Number.isFinite(value)) return DEFAULT_PORT;
  const n = Math.trunc(value);
  if (n < 1) return 1;
  if (n > 65535) return 65535;
  return n;
}

function parseSuffixInput(text) {
  const raw = String(text || '').trim();
  if (!raw) return '';
  const match = raw.match(/(\d{1,3})$/);
  if (!match) return null;
  const parsed = Number.parseInt(match[1], 10);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 254) return null;
  return String(parsed);
}

function parsePortInput(text) {
  const raw = String(text || '').trim();
  if (!raw) return null;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) return null;
  return parsed;
}

function parsePathInput(text) {
  const raw = String(text || '').trim();
  if (!raw) return DEFAULT_PATH;
  const cleaned = raw.replace(/^\/+/, '').trim();
  if (!cleaned) return DEFAULT_PATH;
  return cleaned.slice(0, 96);
}

function trackPrefix(value, maxLen) {
  if (!value) return '';
  if (value.length <= maxLen) return value;
  return `${value.slice(0, maxLen - 1)}…`;
}

function applyManualFieldsToPlugin() {
  const suffix = suffixInput ? Number.parseInt(suffixInput, 10) : 0;
  host_module_set_param('manual_suffix', String(Number.isFinite(suffix) ? suffix : 0));
  host_module_set_param('manual_port', String(clampPort(portInput)));
  host_module_set_param('manual_path', pathInput || DEFAULT_PATH);
}

function openSuffixEditor() {
  openTextEntry({
    title: 'IP Suffix',
    initialText: suffixInput,
    onConfirm: (value) => {
      const parsed = parseSuffixInput(value);
      if (parsed === null) return;
      suffixInput = parsed;
      applyManualFieldsToPlugin();
      rebuildMenu();
      needsRedraw = true;
    },
    onCancel: () => {
      needsRedraw = true;
    }
  });
  needsRedraw = true;
}

function openPortEditor() {
  openTextEntry({
    title: 'RTSP Port',
    initialText: String(portInput),
    onConfirm: (value) => {
      const parsed = parsePortInput(value);
      if (parsed === null) return;
      portInput = clampPort(parsed);
      applyManualFieldsToPlugin();
      rebuildMenu();
      needsRedraw = true;
    },
    onCancel: () => {
      needsRedraw = true;
    }
  });
  needsRedraw = true;
}

function openPathEditor() {
  openTextEntry({
    title: 'RTSP Path',
    initialText: pathInput,
    onConfirm: (value) => {
      pathInput = parsePathInput(value);
      applyManualFieldsToPlugin();
      rebuildMenu();
      needsRedraw = true;
    },
    onCancel: () => {
      needsRedraw = true;
    }
  });
  needsRedraw = true;
}

function parseEndpointParts(endpoint) {
  const raw = String(endpoint || '').trim();
  const m = raw.match(/^rtsp:\/\/([^/:]+)(?::(\d+))?(\/[^?#]*)?/i);
  if (!m) return null;

  const host = m[1];
  const port = Number.parseInt(m[2] || String(DEFAULT_PORT), 10);
  const path = parsePathInput((m[3] || '').replace(/^\//, ''));
  const hostMatch = host.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);

  if (!hostMatch) {
    return {
      prefix: '',
      suffix: '',
      port: Number.isInteger(port) ? clampPort(port) : DEFAULT_PORT,
      path
    };
  }

  return {
    prefix: `${hostMatch[1]}.${hostMatch[2]}.${hostMatch[3]}`,
    suffix: hostMatch[4],
    port: Number.isInteger(port) ? clampPort(port) : DEFAULT_PORT,
    path
  };
}

function loadHistory() {
  const rawCount = Number.parseInt(host_module_get_param('history_count') || '0', 10);
  const count = Number.isInteger(rawCount) && rawCount > 0 ? Math.min(rawCount, MAX_HISTORY_ENTRIES) : 0;
  const next = [];
  for (let i = 0; i < count; i++) {
    const endpoint = host_module_get_param(`history_${i}`) || '';
    if (!endpoint) continue;
    next.push(endpoint);
  }
  return next;
}

function historyLabel(endpoint) {
  const parsed = parseEndpointParts(endpoint);
  if (!parsed) return trackPrefix(endpoint, 20);
  const suffix = parsed.suffix || '---';
  const path = parsed.path || DEFAULT_PATH;
  return trackPrefix(`${suffix}/${path}`, 20);
}

function refreshState() {
  const prevStatus = status;
  const prevLastError = lastError;
  const prevPrefix = networkPrefix;
  const prevSuffix = suffixInput;
  const prevPort = portInput;
  const prevPath = pathInput;
  const prevHistorySig = JSON.stringify(historyEndpoints);

  status = host_module_get_param('status') || 'stopped';
  networkPrefix = host_module_get_param('network_prefix') || '192.168.0';
  lastError = host_module_get_param('last_error') || '';

  const manualSuffixRaw = Number.parseInt(host_module_get_param('manual_suffix') || '0', 10);
  if (Number.isInteger(manualSuffixRaw) && manualSuffixRaw >= 1 && manualSuffixRaw <= 254) {
    suffixInput = String(manualSuffixRaw);
  } else {
    suffixInput = '';
  }

  const manualPortRaw = Number.parseInt(host_module_get_param('manual_port') || String(DEFAULT_PORT), 10);
  portInput = clampPort(manualPortRaw);
  pathInput = parsePathInput(host_module_get_param('manual_path') || DEFAULT_PATH);

  historyEndpoints = loadHistory();

  const nextHistorySig = JSON.stringify(historyEndpoints);

  if (
    prevStatus !== status ||
    prevLastError !== lastError ||
    prevPrefix !== networkPrefix ||
    prevSuffix !== suffixInput ||
    prevPort !== portInput ||
    prevPath !== pathInput ||
    prevHistorySig !== nextHistorySig
  ) {
    rebuildMenu();
    needsRedraw = true;
  }
}

function connectManual() {
  applyManualFieldsToPlugin();
  host_module_set_param('connect_manual', '1');
  needsRedraw = true;
}

function disconnectManual() {
  host_module_set_param('disconnect', '1');
  needsRedraw = true;
}

function selectHistory(index) {
  if (index < 0 || index >= historyEndpoints.length) return;

  const endpoint = historyEndpoints[index];
  const parsed = parseEndpointParts(endpoint);
  if (parsed) {
    if (parsed.prefix) {
      networkPrefix = parsed.prefix;
    }
    suffixInput = parsed.suffix || '';
    portInput = clampPort(parsed.port || DEFAULT_PORT);
    pathInput = parsePathInput(parsed.path || DEFAULT_PATH);
    applyManualFieldsToPlugin();
  }

  host_module_set_param('connect_history', String(index));
  showHistory = false;
  rebuildMenu();
  needsRedraw = true;
}

function resetClient() {
  suffixInput = '';
  portInput = DEFAULT_PORT;
  pathInput = DEFAULT_PATH;
  showHistory = false;
  applyManualFieldsToPlugin();
  host_module_set_param('reset_client', '1');
  rebuildMenu();
  needsRedraw = true;
}

function buildRootItems() {
  const items = [];
  const suffixLabel = suffixInput || '---';
  const lastErrorLabel = lastError ? trackPrefix(lastError, 12) : 'none';

  items.push(createAction(`IP Suffix: ${suffixLabel}`, () => {
    openSuffixEditor();
  }));

  items.push(createAction(`Port: ${portInput}`, () => {
    openPortEditor();
  }));

  items.push(createAction(`Path: /${trackPrefix(pathInput, 14)}`, () => {
    openPathEditor();
  }));

  items.push(createAction('[Connect]', () => {
    connectManual();
  }));

  items.push(createAction('[Disconnect]', () => {
    disconnectManual();
  }));

  items.push(createAction(`Last error: ${lastErrorLabel}`, () => {}));

  items.push(createAction('[Past Connections]', () => {
    showHistory = true;
    rebuildMenu();
    needsRedraw = true;
  }));

  items.push(createAction('[Reset]', () => {
    resetClient();
  }));

  return items;
}

function buildHistoryItems() {
  const items = [];

  if (historyEndpoints.length === 0) {
    items.push(createAction('(No saved connections)', () => {}));
  } else {
    for (let i = 0; i < historyEndpoints.length; i++) {
      const endpoint = historyEndpoints[i];
      items.push(createAction(historyLabel(endpoint), () => {
        selectHistory(i);
      }));
    }
  }

  items.push(createAction('[Back]', () => {
    showHistory = false;
    rebuildMenu();
    needsRedraw = true;
  }));

  return items;
}

function rebuildMenu() {
  const items = showHistory ? buildHistoryItems() : buildRootItems();
  const title = showHistory ? 'Past Connections' : 'StreamRTSP';
  const current = menuStack.current();

  if (!current) {
    menuStack.push({
      title,
      items,
      selectedIndex: 0
    });
    menuState.selectedIndex = 0;
  } else {
    current.title = title;
    current.items = items;
    if (menuState.selectedIndex >= items.length) {
      menuState.selectedIndex = Math.max(0, items.length - 1);
    }
  }

  needsRedraw = true;
}

function statusLabel() {
  if (status === 'connecting') return `Connecting ${SPINNER[spinnerFrame]}`;
  if (status === 'reconnecting') return `Retrying ${SPINNER[spinnerFrame]}`;
  if (status === 'buffering') return `Buffering ${SPINNER[spinnerFrame]}`;
  if (status === 'waiting_for_sender') return `Waiting ${SPINNER[spinnerFrame]}`;
  if (status === 'streaming' || status === 'playing') return 'Connected';
  if (status === 'error' && lastError) return trackPrefix(lastError, 20);
  return trackPrefix(status || 'disconnected', 20);
}

globalThis.init = function () {
  status = 'stopped';
  networkPrefix = '192.168.0';
  suffixInput = '';
  portInput = DEFAULT_PORT;
  pathInput = DEFAULT_PATH;
  lastError = '';
  historyEndpoints = [];
  showHistory = false;
  shiftHeld = false;

  menuState = createMenuState();
  menuStack = createMenuStack();
  tickCounter = 0;
  spinnerTick = 0;
  spinnerFrame = 0;
  needsRedraw = true;

  refreshState();
  rebuildMenu();
};

globalThis.tick = function () {
  if (isTextEntryActive()) {
    if (tickTextEntry()) {
      needsRedraw = true;
    }
    drawTextEntry();
    return;
  }

  tickCounter = (tickCounter + 1) % 6;
  if (tickCounter === 0) {
    refreshState();
  }

  if (
    status === 'connecting' ||
    status === 'reconnecting' ||
    status === 'buffering' ||
    status === 'waiting_for_sender'
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
      footer: statusLabel()
    });

    needsRedraw = false;
  }
};

globalThis.onMidiMessageInternal = function (data) {
  if (isTextEntryActive()) {
    if (handleTextEntryMidi(data)) {
      needsRedraw = true;
    }
    return;
  }

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
      if (showHistory) {
        showHistory = false;
        rebuildMenu();
        needsRedraw = true;
        return;
      }
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
