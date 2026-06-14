(function () {
  const storageKey = 'schedai.web.state.v1';
  const authKey = 'schedai.web.auth.v1';
  const clientKey = 'schedai.web.client.v1';
  const priorityRank = { high: 0, medium: 1, low: 2 };
  const reminderTimers = new Map();

  const seedTasks = [
    task({ title: 'Finish calculus homework', estimatedMinutes: 55, priority: 'high', isPinned: true, scheduledStart: todayAt('15:00') }),
    task({ title: 'Study biology notes', estimatedMinutes: 45, priority: 'medium' }),
    task({ title: 'Email advisor', estimatedMinutes: 15, priority: 'medium' }),
    task({ title: 'Gym', estimatedMinutes: 50, priority: 'low', isPinned: true, scheduledStart: todayAt('18:00') }),
  ];

  const state = loadState();
  let auth = loadAuth();
  let appleConfig = null;

  const el = {
    app: document.getElementById('app'),
    dateLine: document.getElementById('date-line'),
    greeting: document.getElementById('greeting'),
    appleSignIn: document.getElementById('apple-sign-in'),
    appleGate: document.getElementById('apple-sign-in-gate'),
    appleLabel: document.getElementById('apple-button-label'),
    localAppleName: document.getElementById('local-apple-name'),
    localNameInput: document.getElementById('local-name-input'),
    signOut: document.getElementById('sign-out'),
    authMessage: document.getElementById('auth-message'),
    themeToggle: document.getElementById('theme-toggle'),
    brainDump: document.getElementById('brain-dump'),
    improveButton: document.getElementById('improve-button'),
    planButton: document.getElementById('plan-button'),
    addBlankTask: document.getElementById('add-blank-task'),
    parserStatus: document.getElementById('parser-status'),
    aiModePill: document.getElementById('ai-mode-pill'),
    timeline: document.getElementById('timeline'),
    taskList: document.getElementById('task-list'),
    taskTemplate: document.getElementById('task-template'),
    taskFilter: document.getElementById('task-filter'),
    exportCalendar: document.getElementById('export-calendar'),
    scheduledCount: document.getElementById('scheduled-count'),
    openCount: document.getElementById('open-count'),
    doneCount: document.getElementById('done-count'),
    sidebarProgress: document.getElementById('sidebar-progress'),
    sidebarProgressBar: document.getElementById('sidebar-progress-bar'),
    privacySummary: document.getElementById('privacy-summary'),
    workWindowEnabled: document.getElementById('work-window-enabled'),
    workStart: document.getElementById('work-start'),
    workEnd: document.getElementById('work-end'),
    remindersEnabled: document.getElementById('reminders-enabled'),
    reminderLead: document.getElementById('reminder-lead'),
    reminderLeadLabel: document.getElementById('reminder-lead-label'),
    reminderCopy: document.getElementById('reminder-copy'),
    hostedAI: document.getElementById('hosted-ai'),
    privateReminders: document.getElementById('private-reminders'),
  };

  document.addEventListener('DOMContentLoaded', init);

  async function init() {
    el.dateLine.textContent = new Intl.DateTimeFormat(undefined, {
      weekday: 'long',
      month: 'long',
      day: 'numeric',
    }).format(new Date());

    document.documentElement.dataset.theme = state.settings.theme;
    bindEvents();
    syncControls();
    render();
    appleConfig = await loadAppleConfig();
    updateAuthUI();
    scheduleBrowserReminders();
  }

  function bindEvents() {
    el.appleSignIn.addEventListener('click', signInWithApple);
    el.appleGate.addEventListener('click', signInWithApple);
    el.localAppleName.addEventListener('click', useLocalAppleName);
    el.signOut.addEventListener('click', signOut);
    el.themeToggle.addEventListener('click', toggleTheme);
    el.improveButton.addEventListener('click', improveTasks);
    el.planButton.addEventListener('click', () => {
      planToday();
      setStatus('Open tasks were placed into your day.');
    });
    el.addBlankTask.addEventListener('click', () => {
      state.tasks.unshift(task({ title: 'New task', estimatedMinutes: 30, priority: 'medium' }));
      saveAndRender();
    });
    el.taskFilter.addEventListener('change', renderTasks);
    el.exportCalendar.addEventListener('click', exportCalendarFile);

    for (const item of document.querySelectorAll('[data-nav]')) {
      item.addEventListener('click', () => {
        document.querySelectorAll('[data-nav]').forEach((nav) => nav.classList.remove('is-active'));
        item.classList.add('is-active');
      });
    }

    const settingsControls = [
      el.workWindowEnabled,
      el.workStart,
      el.workEnd,
      el.remindersEnabled,
      el.reminderLead,
      el.hostedAI,
      el.privateReminders,
    ];

    settingsControls.forEach((control) => {
      control.addEventListener('change', persistSettingsFromControls);
      control.addEventListener('input', persistSettingsFromControls);
    });
  }

  function loadState() {
    const fallback = {
      tasks: seedTasks,
      settings: {
        theme: window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light',
        workWindowEnabled: true,
        workStart: '09:00',
        workEnd: '18:30',
        remindersEnabled: false,
        reminderLead: 5,
        hostedAI: true,
        privateReminders: false,
      },
    };

    try {
      const parsed = JSON.parse(localStorage.getItem(storageKey));
      if (!parsed || !Array.isArray(parsed.tasks)) return fallback;
      return {
        tasks: parsed.tasks.map(normalizeTask),
        settings: { ...fallback.settings, ...(parsed.settings || {}) },
      };
    } catch {
      return fallback;
    }
  }

  function loadAuth() {
    try {
      return JSON.parse(localStorage.getItem(authKey)) || null;
    } catch {
      return null;
    }
  }

  function saveState() {
    localStorage.setItem(storageKey, JSON.stringify(state));
  }

  function saveAuth() {
    if (auth) localStorage.setItem(authKey, JSON.stringify(auth));
    else localStorage.removeItem(authKey);
  }

  function saveAndRender() {
    saveState();
    render();
    scheduleBrowserReminders();
  }

  function task(input) {
    const scheduledStart = input.scheduledStart || null;
    return normalizeTask({
      id: input.id || cryptoId(),
      title: input.title || 'Untitled task',
      priority: input.priority || 'medium',
      estimatedMinutes: input.estimatedMinutes || 30,
      isCompleted: Boolean(input.isCompleted),
      completedAt: input.completedAt || null,
      createdAt: input.createdAt || new Date().toISOString(),
      planState: input.planState || 'ready',
      isPinned: Boolean(input.isPinned),
      scheduledStart,
      scheduledEnd: input.scheduledEnd || addMinutesISO(scheduledStart, input.estimatedMinutes || 30),
      preferredStart: input.preferredStart || null,
      preferredEnd: input.preferredEnd || null,
      notes: input.notes || '',
    });
  }

  function normalizeTask(raw) {
    const minutes = clamp(Number(raw.estimatedMinutes) || 30, 5, 600);
    const scheduledStart = raw.scheduledStart || null;
    return {
      id: raw.id || cryptoId(),
      title: String(raw.title || 'Untitled task').trim().slice(0, 160),
      priority: ['high', 'medium', 'low'].includes(raw.priority) ? raw.priority : 'medium',
      estimatedMinutes: minutes,
      isCompleted: Boolean(raw.isCompleted),
      completedAt: raw.completedAt || null,
      createdAt: raw.createdAt || new Date().toISOString(),
      planState: raw.planState || 'ready',
      isPinned: Boolean(raw.isPinned),
      scheduledStart,
      scheduledEnd: raw.scheduledEnd || addMinutesISO(scheduledStart, minutes),
      preferredStart: raw.preferredStart || null,
      preferredEnd: raw.preferredEnd || null,
      notes: raw.notes || '',
    };
  }

  async function loadAppleConfig() {
    try {
      const response = await fetch('/api/apple-config');
      const config = await response.json();
      if (!config.configured) {
        setAuthMessage('Apple web sign-in needs APPLE_CLIENT_ID on Vercel. Local name mode is available for testing.');
        return config;
      }
      await loadScript('https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js');
      window.AppleID.auth.init({
        clientId: config.clientId,
        scope: config.scope || 'name email',
        redirectURI: config.redirectURI,
        state: getClientId(),
        usePopup: true,
      });
      return config;
    } catch {
      setAuthMessage('Apple sign-in config could not load. Local name mode is available.');
      return { configured: false };
    }
  }

  async function signInWithApple() {
    if (!appleConfig?.configured || !window.AppleID?.auth) {
      useLocalAppleName();
      return;
    }

    setAuthMessage('Opening Apple sign-in...');
    try {
      const response = await window.AppleID.auth.signIn();
      const name = response?.user?.name
        ? [response.user.name.firstName, response.user.name.lastName].filter(Boolean).join(' ')
        : 'Apple user';
      auth = {
        provider: 'apple',
        name,
        email: response?.user?.email || '',
        signedInAt: new Date().toISOString(),
      };
      saveAuth();
      setAuthMessage('Signed in with Apple.');
      updateAuthUI();
      render();
    } catch {
      setAuthMessage('Apple name sharing was cancelled or failed.');
    }
  }

  function useLocalAppleName() {
    const name = el.localNameInput.value.trim() || auth?.name || 'Apple User';
    if (!name) {
      setAuthMessage('Sign in is needed before planning.');
      return;
    }
    auth = {
      provider: 'apple-local',
      name: name.trim().slice(0, 80),
      email: '',
      signedInAt: new Date().toISOString(),
    };
    saveAuth();
    setAuthMessage('Using Apple name locally in this browser.');
    updateAuthUI();
    render();
  }

  function signOut() {
    auth = null;
    saveAuth();
    updateAuthUI();
    render();
  }

  function updateAuthUI() {
    const ready = Boolean(auth?.name);
    el.app.dataset.auth = ready ? 'ready' : 'locked';
    el.appleLabel.textContent = ready ? auth.name : 'Sign in with Apple';
    el.signOut.classList.toggle('hidden', !ready);
    if (ready) setAuthMessage(`Signed in as ${auth.name}.`);
  }

  async function improveTasks() {
    const input = el.brainDump.value.trim();
    if (!input) {
      setStatus('Add a brain dump first.');
      return;
    }

    const offlinePreview = offlineParse(input);
    if (!state.settings.hostedAI) {
      mergePreview(offlinePreview);
      setStatus('Hosted AI is off. Offline preview added.');
      return;
    }

    el.improveButton.disabled = true;
    setStatus('Improving with hosted AI...');
    try {
      const response = await fetch('/api/parse-tasks', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-SchedAI-Client-ID': getClientId(),
        },
        body: JSON.stringify({
          input,
          nowISO8601: new Date().toISOString(),
          planningDateISO8601: new Date().toISOString(),
          timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
          locale: navigator.language || 'en-US',
          offlinePreview,
        }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || 'Hosted parser failed');
      mergePreview((data.tasks || []).map(fromApiTask));
      setStatus(data.needsClarification && data.clarificationQuestion
        ? data.clarificationQuestion
        : 'Improved tasks were added to your preview.');
    } catch (error) {
      mergePreview(offlinePreview);
      setStatus(`${error.message || 'Hosted parser unavailable'}. Offline preview added.`);
    } finally {
      el.improveButton.disabled = false;
    }
  }

  function mergePreview(preview) {
    const incoming = preview.map((item) => task(item));
    state.tasks = [...incoming, ...state.tasks];
    el.brainDump.value = '';
    saveAndRender();
  }

  function fromApiTask(raw) {
    return {
      title: raw.title,
      estimatedMinutes: raw.estimatedMinutes,
      priority: raw.priority,
      isPinned: Boolean(raw.isPinned || raw.scheduledStartISO8601),
      scheduledStart: raw.scheduledStartISO8601,
      scheduledEnd: raw.scheduledEndISO8601,
      preferredStart: raw.preferredStartISO8601,
      preferredEnd: raw.preferredEndISO8601,
      notes: raw.notes || '',
    };
  }

  function offlineParse(input) {
    return splitTaskText(input).map((part) => {
      const time = parseTimeHint(part);
      const minutes = parseDuration(part) || 30;
      const title = cleanTitle(part);
      return {
        title,
        estimatedMinutes: minutes,
        priority: parsePriority(part),
        isPinned: Boolean(time),
        scheduledStart: time,
        scheduledEnd: addMinutesISO(time, minutes),
      };
    }).filter((item) => item.title);
  }

  function splitTaskText(input) {
    return input
      .replace(/\band then\b/gi, ',')
      .replace(/\bthen\b/gi, ',')
      .split(/\n|;|,(?=\s*[a-z0-9])/gi)
      .map((part) => part.trim())
      .filter(Boolean)
      .slice(0, 20);
  }

  function cleanTitle(part) {
    return part
      .replace(/\b(at|around|about|near|by)\s+\d{1,2}(:\d{2})?\s*(am|pm)?\b/gi, '')
      .replace(/\b(for)?\s*\d+\s*(minutes|minute|mins|min|hours|hour|hrs|hr)\b/gi, '')
      .replace(/\b(urgent|important|low priority|high priority|medium priority)\b/gi, '')
      .replace(/\s+/g, ' ')
      .trim()
      .replace(/^[,-]\s*/, '')
      .slice(0, 160);
  }

  function parsePriority(part) {
    if (/\b(urgent|asap|important|high priority)\b/i.test(part)) return 'high';
    if (/\b(low priority|whenever|sometime)\b/i.test(part)) return 'low';
    return 'medium';
  }

  function parseDuration(part) {
    const match = part.match(/\b(?:(\d+(?:\.\d+)?)\s*(hours|hour|hrs|hr)|(\d+)\s*(minutes|minute|mins|min))\b/i);
    if (!match) return null;
    if (match[1]) return clamp(Math.round(Number(match[1]) * 60), 5, 600);
    return clamp(Number(match[3]), 5, 600);
  }

  function parseTimeHint(part) {
    const match = part.match(/\b(?:at|around|about|near|by)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/i);
    if (!match) return null;
    let hour = Number(match[1]);
    const minute = Number(match[2] || 0);
    const meridiem = match[3]?.toLowerCase();
    if (meridiem === 'pm' && hour < 12) hour += 12;
    if (meridiem === 'am' && hour === 12) hour = 0;
    if (!meridiem && hour > 0 && hour < 8) hour += 12;
    if (hour > 23 || minute > 59) return null;
    return todayAt(`${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`);
  }

  function planToday() {
    const start = timeToDate(state.settings.workWindowEnabled ? state.settings.workStart : '08:00');
    const end = timeToDate(state.settings.workWindowEnabled ? state.settings.workEnd : '20:00');
    let cursor = new Date(Math.max(start.getTime(), Date.now() + 10 * 60 * 1000));
    if (cursor > end) cursor = start;

    const busy = state.tasks
      .filter((item) => item.isPinned && item.scheduledStart && !item.isCompleted)
      .map((item) => ({
        start: new Date(item.scheduledStart),
        end: new Date(item.scheduledEnd || addMinutesISO(item.scheduledStart, item.estimatedMinutes)),
      }))
      .sort((a, b) => a.start - b.start);

    const flexible = state.tasks
      .filter((item) => !item.isCompleted && !item.isPinned)
      .sort((a, b) => priorityRank[a.priority] - priorityRank[b.priority] || b.estimatedMinutes - a.estimatedMinutes);

    flexible.forEach((item) => {
      const slot = findSlot(cursor, end, item.estimatedMinutes, busy);
      if (!slot) {
        item.scheduledStart = null;
        item.scheduledEnd = null;
        return;
      }
      item.scheduledStart = slot.start.toISOString();
      item.scheduledEnd = slot.end.toISOString();
      busy.push(slot);
      busy.sort((a, b) => a.start - b.start);
      cursor = new Date(slot.end.getTime() + 6 * 60 * 1000);
    });

    saveAndRender();
  }

  function findSlot(cursor, dayEnd, minutes, busy) {
    let start = new Date(cursor);
    const duration = minutes * 60 * 1000;

    for (let guard = 0; guard < 100; guard += 1) {
      const end = new Date(start.getTime() + duration);
      if (end > dayEnd) return null;
      const conflict = busy.find((block) => block.start < end && block.end > start);
      if (!conflict) return { start, end };
      start = new Date(conflict.end.getTime() + 6 * 60 * 1000);
    }
    return null;
  }

  function render() {
    updateAuthUI();
    syncControls();
    renderStats();
    renderTimeline();
    renderTasks();
    renderSettingsSummary();
  }

  function syncControls() {
    el.workWindowEnabled.checked = state.settings.workWindowEnabled;
    el.workStart.value = state.settings.workStart;
    el.workEnd.value = state.settings.workEnd;
    el.remindersEnabled.checked = state.settings.remindersEnabled;
    el.reminderLead.value = state.settings.reminderLead;
    el.hostedAI.checked = state.settings.hostedAI;
    el.privateReminders.checked = state.settings.privateReminders;
    el.reminderLeadLabel.textContent = `${state.settings.reminderLead} min`;
    el.aiModePill.textContent = state.settings.hostedAI ? 'Hosted AI ready' : 'Offline only';
    el.greeting.textContent = auth?.name ? `Plan today, ${firstName(auth.name)}` : 'Plan today';
  }

  function persistSettingsFromControls() {
    state.settings.workWindowEnabled = el.workWindowEnabled.checked;
    state.settings.workStart = el.workStart.value || '09:00';
    state.settings.workEnd = el.workEnd.value || '18:30';
    state.settings.remindersEnabled = el.remindersEnabled.checked;
    state.settings.reminderLead = Number(el.reminderLead.value) || 5;
    state.settings.hostedAI = el.hostedAI.checked;
    state.settings.privateReminders = el.privateReminders.checked;
    if (el.remindersEnabled.checked) requestNotificationPermission();
    saveAndRender();
  }

  function renderStats() {
    const scheduled = state.tasks.filter((item) => item.scheduledStart && !item.isCompleted).length;
    const done = state.tasks.filter((item) => item.isCompleted).length;
    const open = state.tasks.filter((item) => !item.isCompleted).length;
    const total = state.tasks.length;
    const pct = total ? Math.round((done / total) * 100) : 0;
    el.scheduledCount.textContent = scheduled;
    el.openCount.textContent = open;
    el.doneCount.textContent = done;
    el.sidebarProgress.textContent = `${done} of ${total} done`;
    el.sidebarProgressBar.style.width = `${pct}%`;
  }

  function renderTimeline() {
    const scheduled = state.tasks
      .filter((item) => item.scheduledStart && !item.isCompleted)
      .sort((a, b) => new Date(a.scheduledStart) - new Date(b.scheduledStart));

    el.timeline.replaceChildren();

    if (!scheduled.length) {
      el.timeline.appendChild(timelineRow(state.settings.workStart, 'No tasks scheduled yet', 'Tap Plan today to place your open tasks.'));
      return;
    }

    scheduled.forEach((item) => {
      const row = timelineRow(formatTime(item.scheduledStart), item.title, `${item.estimatedMinutes} min · ${item.priority} priority`, true);
      row.querySelector('.timeline-block').dataset.priority = item.priority;
      el.timeline.appendChild(row);
    });
  }

  function timelineRow(time, title, subtitle, isTask) {
    const row = document.createElement('div');
    row.className = 'timeline-row';
    row.innerHTML = `
      <div class="timeline-time">${escapeHTML(time)}</div>
      <article class="timeline-block ${isTask ? 'timeline-task' : 'timeline-empty'}">
        <strong>${escapeHTML(title)}</strong>
        <span>${escapeHTML(subtitle)}</span>
      </article>
    `;
    return row;
  }

  function renderTasks() {
    const filter = el.taskFilter.value;
    const filtered = state.tasks.filter((item) => {
      if (filter === 'open') return !item.isCompleted;
      if (filter === 'scheduled') return Boolean(item.scheduledStart);
      if (filter === 'done') return item.isCompleted;
      if (filter === 'high') return item.priority === 'high';
      return true;
    });

    el.taskList.replaceChildren();

    if (!filtered.length) {
      const empty = document.createElement('div');
      empty.className = 'empty-state';
      empty.textContent = 'No tasks match this view. Add a task or change the filter.';
      el.taskList.appendChild(empty);
      return;
    }

    filtered.forEach((item) => el.taskList.appendChild(renderTaskCard(item)));
  }

  function renderTaskCard(item) {
    const node = el.taskTemplate.content.firstElementChild.cloneNode(true);
    node.dataset.id = item.id;
    node.dataset.completed = String(item.isCompleted);
    node.querySelector('.done-toggle').addEventListener('click', () => {
      item.isCompleted = !item.isCompleted;
      item.completedAt = item.isCompleted ? new Date().toISOString() : null;
      saveAndRender();
    });

    const title = node.querySelector('.task-title');
    title.value = item.title;
    title.addEventListener('change', () => {
      item.title = title.value.trim() || 'Untitled task';
      saveAndRender();
    });

    const priority = node.querySelector('.task-priority');
    priority.value = item.priority;
    priority.addEventListener('change', () => {
      item.priority = priority.value;
      saveAndRender();
    });

    const minutes = node.querySelector('.task-minutes');
    minutes.value = item.estimatedMinutes;
    minutes.addEventListener('change', () => {
      item.estimatedMinutes = clamp(Number(minutes.value) || 30, 5, 600);
      if (item.scheduledStart) item.scheduledEnd = addMinutesISO(item.scheduledStart, item.estimatedMinutes);
      saveAndRender();
    });

    const pinned = node.querySelector('.task-pinned');
    pinned.checked = item.isPinned;
    pinned.addEventListener('change', () => {
      item.isPinned = pinned.checked;
      if (item.isPinned && !item.scheduledStart) {
        item.scheduledStart = todayAt('09:00');
        item.scheduledEnd = addMinutesISO(item.scheduledStart, item.estimatedMinutes);
      }
      saveAndRender();
    });

    const time = node.querySelector('.task-time');
    time.value = item.scheduledStart ? toInputTime(item.scheduledStart) : '';
    time.addEventListener('change', () => {
      item.scheduledStart = time.value ? todayAt(time.value) : null;
      item.scheduledEnd = addMinutesISO(item.scheduledStart, item.estimatedMinutes);
      item.isPinned = Boolean(item.scheduledStart);
      saveAndRender();
    });

    node.querySelector('.delete-task').addEventListener('click', () => {
      state.tasks = state.tasks.filter((taskItem) => taskItem.id !== item.id);
      saveAndRender();
    });
    node.querySelector('.move-up').addEventListener('click', () => moveTask(item.id, -1));
    node.querySelector('.move-down').addEventListener('click', () => moveTask(item.id, 1));
    return node;
  }

  function moveTask(id, delta) {
    const index = state.tasks.findIndex((item) => item.id === id);
    const target = index + delta;
    if (index < 0 || target < 0 || target >= state.tasks.length) return;
    const [item] = state.tasks.splice(index, 1);
    state.tasks.splice(target, 0, item);
    saveAndRender();
  }

  function renderSettingsSummary() {
    el.privacySummary.textContent = state.settings.hostedAI
      ? 'Improve can send text to the hosted parser. Tasks stay in this browser.'
      : 'Hosted AI is off. Parsing stays local in this browser.';
    el.reminderCopy.textContent = notificationAvailable()
      ? 'Browser notifications before tasks start'
      : 'Notifications need a supported browser and permission';
  }

  async function requestNotificationPermission() {
    if (!notificationAvailable()) return;
    if (Notification.permission === 'default') await Notification.requestPermission();
  }

  function scheduleBrowserReminders() {
    reminderTimers.forEach((timer) => window.clearTimeout(timer));
    reminderTimers.clear();
    if (!state.settings.remindersEnabled || !notificationAvailable() || Notification.permission !== 'granted') return;

    state.tasks.forEach((item) => {
      if (!item.scheduledStart || item.isCompleted) return;
      const notifyAt = new Date(item.scheduledStart).getTime() - state.settings.reminderLead * 60 * 1000;
      const delay = notifyAt - Date.now();
      if (delay < 0 || delay > 2147483647) return;
      const timer = window.setTimeout(() => {
        const body = state.settings.privateReminders ? 'A planned task starts soon.' : `${item.title} starts soon.`;
        new Notification('SchedAI reminder', { body, icon: '/favicon.png' });
      }, delay);
      reminderTimers.set(item.id, timer);
    });
  }

  function exportCalendarFile() {
    const events = state.tasks.filter((item) => item.scheduledStart && item.scheduledEnd);
    if (!events.length) {
      setStatus('Plan at least one task before exporting a calendar file.');
      return;
    }

    const lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//SchedAI//Web Planner//EN',
      'CALSCALE:GREGORIAN',
    ];
    events.forEach((item) => {
      lines.push(
        'BEGIN:VEVENT',
        `UID:${item.id}@schedai-web`,
        `DTSTAMP:${icsDate(new Date())}`,
        `DTSTART:${icsDate(new Date(item.scheduledStart))}`,
        `DTEND:${icsDate(new Date(item.scheduledEnd))}`,
        `SUMMARY:${escapeICS(item.title)}`,
        `DESCRIPTION:${escapeICS(`Priority: ${item.priority}. Created by SchedAI.`)}`,
        'END:VEVENT',
      );
    });
    lines.push('END:VCALENDAR');

    const blob = new Blob([lines.join('\r\n')], { type: 'text/calendar;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `schedai-plan-${new Date().toISOString().slice(0, 10)}.ics`;
    link.click();
    URL.revokeObjectURL(url);
    setStatus('Calendar file exported.');
  }

  function toggleTheme() {
    state.settings.theme = state.settings.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = state.settings.theme;
    saveAndRender();
  }

  function setStatus(message) {
    el.parserStatus.textContent = message;
  }

  function setAuthMessage(message) {
    el.authMessage.textContent = message;
  }

  function getClientId() {
    let value = localStorage.getItem(clientKey);
    if (!/^schedai\.[a-z0-9]{32}$/i.test(value || '')) {
      value = `schedai.${cryptoId().replace(/-/g, '').slice(0, 32).padEnd(32, '0')}`;
      localStorage.setItem(clientKey, value);
    }
    return value;
  }

  function cryptoId() {
    if (crypto?.randomUUID) return crypto.randomUUID();
    return `${Date.now().toString(16)}${Math.random().toString(16).slice(2)}`;
  }

  function firstName(name) {
    return String(name).trim().split(/\s+/)[0] || 'there';
  }

  function todayAt(value) {
    const [hour, minute] = String(value).split(':').map(Number);
    const date = new Date();
    date.setHours(hour || 0, minute || 0, 0, 0);
    return date.toISOString();
  }

  function timeToDate(value) {
    return new Date(todayAt(value));
  }

  function toInputTime(value) {
    const date = new Date(value);
    return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  function formatTime(value) {
    return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(value));
  }

  function addMinutesISO(value, minutes) {
    if (!value) return null;
    return new Date(new Date(value).getTime() + minutes * 60 * 1000).toISOString();
  }

  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function notificationAvailable() {
    return 'Notification' in window && window.isSecureContext;
  }

  function icsDate(date) {
    return date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  }

  function escapeICS(value) {
    return String(value).replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n');
  }

  function escapeHTML(value) {
    return String(value).replace(/[&<>"']/g, (char) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;',
    }[char]));
  }

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      if (document.querySelector(`script[src="${src}"]`)) {
        resolve();
        return;
      }
      const script = document.createElement('script');
      script.src = src;
      script.async = true;
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }
})();
