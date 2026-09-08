(() => {
  const $ = (sel) => document.querySelector(sel);
  const live = $('#live');
  const overlay = $('#overlay');
  const overlayTitle = $('#overlayTitle');
  const overlayText = $('#overlayText');
  const timerBadge = $('#timerBadge');
  const modeBadge = $('#modeBadge');
  const statusLine = $('#statusLine');
  const loginPanel = $('#loginPanel');
  const mainPanel = $('#mainPanel');
  const timeoutLabel = $('#timeoutLabel');

  let token = localStorage.getItem('v380_access_token') || '';
  let streamTimeoutSec = 120;
  let endsAt = 0;
  let tickTimer = null;
  let streaming = false;
  let sessionId = 0;

  function setStatus(msg) {
    statusLine.textContent = msg;
  }

  function authHeaders(extra = {}) {
    const h = { ...extra };
    if (token) h.Authorization = `Bearer ${token}`;
    return h;
  }

  function streamUrl() {
    const u = new URL('/stream.mjpg', window.location.origin);
    u.searchParams.set('_', String(Date.now()));
    if (token) u.searchParams.set('token', token);
    return u.toString();
  }

  function showOverlay(title, text, showReconnect = true) {
    overlayTitle.textContent = title;
    overlayText.textContent = text;
    $('#reconnectBtn').classList.toggle('hidden', !showReconnect);
    overlay.classList.remove('hidden');
  }

  function hideOverlay() {
    overlay.classList.add('hidden');
  }

  function clearTick() {
    if (tickTimer) {
      clearInterval(tickTimer);
      tickTimer = null;
    }
  }

  function formatRemain(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${m}:${String(r).padStart(2, '0')}`;
  }

  function startTicker() {
    clearTick();
    tickTimer = setInterval(() => {
      const left = endsAt - Date.now();
      if (left <= 0) {
        timerBadge.textContent = 'Timed out';
        timerBadge.className = 'badge badge-warn';
        onStreamTimeout();
        return;
      }
      timerBadge.textContent = `Live · ${formatRemain(left)}`;
      timerBadge.className = 'badge badge-ok';
    }, 250);
  }

  function stopStream({ timedOut = false } = {}) {
    streaming = false;
    clearTick();
    // Break the MJPEG connection
    live.removeAttribute('src');
    live.src = '';
    if (timedOut) {
      showOverlay(
        'Live session ended',
        `Feed auto-stopped after ${streamTimeoutSec} seconds. Tap Refresh / Reconnect for a new 2-minute session.`,
        true
      );
      timerBadge.textContent = 'Timed out';
      timerBadge.className = 'badge badge-warn';
      setStatus('Stream timed out');
    } else {
      showOverlay('Stopped', 'Press Start live to begin a new session.', true);
      timerBadge.textContent = 'Idle';
      timerBadge.className = 'badge badge-muted';
      setStatus('Stream stopped');
    }
  }

  function onStreamTimeout() {
    if (!streaming) return;
    stopStream({ timedOut: true });
  }

  function startStream() {
    sessionId += 1;
    const mySession = sessionId;
    streaming = true;
    endsAt = Date.now() + streamTimeoutSec * 1000;
    hideOverlay();
    setStatus('Connecting to live feed…');
    timerBadge.textContent = `Live · ${formatRemain(streamTimeoutSec * 1000)}`;
    timerBadge.className = 'badge badge-ok';
    startTicker();

    live.onload = () => {
      if (mySession !== sessionId) return;
      setStatus('Live');
    };
    live.onerror = () => {
      if (mySession !== sessionId) return;
      // Server closes after timeout — treat as timeout if near end
      const left = endsAt - Date.now();
      if (left < 2000) {
        onStreamTimeout();
      } else {
        showOverlay('Stream error', 'Could not load the live feed. Try reconnecting.', true);
        streaming = false;
        clearTick();
        timerBadge.textContent = 'Error';
        timerBadge.className = 'badge badge-warn';
        setStatus('Stream error');
      }
    };
    live.src = streamUrl();

    // Hard client-side stop aligned with server timeout
    setTimeout(() => {
      if (mySession !== sessionId) return;
      if (streaming) onStreamTimeout();
    }, streamTimeoutSec * 1000 + 200);
  }

  async function api(path, opts = {}) {
    const res = await fetch(path, {
      ...opts,
      headers: authHeaders(opts.headers || {}),
      credentials: 'same-origin',
    });
    if (res.status === 401) {
      throw Object.assign(new Error('Unauthorized'), { status: 401 });
    }
    const ct = res.headers.get('content-type') || '';
    if (ct.includes('application/json')) {
      const data = await res.json();
      if (!res.ok) throw Object.assign(new Error(data.error || res.statusText), { status: res.status, data });
      return data;
    }
    if (!res.ok) throw Object.assign(new Error(res.statusText), { status: res.status });
    return res;
  }

  async function ensureSession() {
    try {
      const s = await api('/api/session');
      streamTimeoutSec = s.streamTimeoutSec || 120;
      timeoutLabel.textContent = String(streamTimeoutSec);
      modeBadge.textContent = s.mode === 'real' ? 'Real camera' : 'Mock camera';
      modeBadge.className = s.mode === 'real' ? 'badge badge-ok' : 'badge';
      loginPanel.classList.add('hidden');
      mainPanel.classList.remove('hidden');
      showOverlay('Ready', `Sessions last ${streamTimeoutSec} seconds.`, true);
      return true;
    } catch (err) {
      if (err.status === 401) {
        loginPanel.classList.remove('hidden');
        mainPanel.classList.add('hidden');
        return false;
      }
      throw err;
    }
  }

  $('#loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const value = $('#tokenInput').value.trim();
    $('#loginError').classList.add('hidden');
    try {
      const res = await fetch('/api/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${value}` },
        body: JSON.stringify({ token: value }),
        credentials: 'same-origin',
      });
      if (!res.ok) {
        $('#loginError').textContent = 'Invalid token';
        $('#loginError').classList.remove('hidden');
        return;
      }
      token = value;
      localStorage.setItem('v380_access_token', token);
      await ensureSession();
    } catch (_) {
      $('#loginError').textContent = 'Login failed';
      $('#loginError').classList.remove('hidden');
    }
  });

  $('#startBtn').addEventListener('click', () => startStream());
  $('#reconnectBtn').addEventListener('click', () => startStream());
  $('#stopBtn').addEventListener('click', () => stopStream());

  $('#snapBtn').addEventListener('click', async () => {
    try {
      const res = await fetch('/api/snapshot', {
        headers: authHeaders(),
        credentials: 'same-origin',
      });
      if (!res.ok) throw new Error('Snapshot failed');
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `v380-snapshot-${Date.now()}.jpg`;
      a.click();
      URL.revokeObjectURL(url);
      setStatus('Snapshot saved');
    } catch (err) {
      setStatus(err.message || 'Snapshot error');
    }
  });

  $('#logoutBtn').addEventListener('click', async () => {
    stopStream();
    token = '';
    localStorage.removeItem('v380_access_token');
    try {
      await fetch('/api/logout', { method: 'POST', credentials: 'same-origin' });
    } catch (_) {
      /* ignore */
    }
    loginPanel.classList.remove('hidden');
    mainPanel.classList.add('hidden');
  });

  document.querySelectorAll('[data-ptz]').forEach((btn) => {
    const send = async (dir) => {
      try {
        await api(`/api/ptz/${dir}`, { method: 'POST' });
        setStatus(`PTZ ${dir}`);
      } catch (err) {
        setStatus(err.message || 'PTZ failed');
      }
    };
    btn.addEventListener('pointerdown', (ev) => {
      ev.preventDefault();
      send(btn.dataset.ptz);
    });
    btn.addEventListener('pointerup', (ev) => {
      if (btn.dataset.ptz !== 'stop') {
        ev.preventDefault();
        send('stop');
      }
    });
    btn.addEventListener('pointerleave', () => {
      if (btn.dataset.ptz !== 'stop' && btn.matches(':active')) send('stop');
    });
  });

  document.querySelectorAll('[data-ctrl]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const raw = btn.dataset.ctrl;
      const path =
        raw === 'flip' ? '/api/control/flip' : `/api/control/${raw}`;
      try {
        await api(path, { method: 'POST' });
        setStatus(`Control ${raw}`);
      } catch (err) {
        setStatus(err.message || 'Control failed');
      }
    });
  });

  // Boot: if ?token= present, persist and clean URL
  const bootParams = new URLSearchParams(window.location.search);
  if (bootParams.get('token')) {
    token = bootParams.get('token');
    localStorage.setItem('v380_access_token', token);
    fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({ token }),
      credentials: 'same-origin',
    }).finally(() => {
      bootParams.delete('token');
      const next = `${window.location.pathname}${bootParams.toString() ? `?${bootParams}` : ''}`;
      window.history.replaceState({}, '', next);
      ensureSession();
    });
  } else {
    ensureSession().catch(() => {
      loginPanel.classList.remove('hidden');
    });
  }
})();
