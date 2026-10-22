/* Presentation only: configuration state, chart geometry and server trace inspection. */
(() => {
  const app = document.getElementById('powerspike');
  if (app?.dataset.layout !== 'matchup') return;
  const $ = selector => document.querySelector(selector);
  const format = value => new Intl.NumberFormat('en-US', {maximumFractionDigits: 0}).format(value || 0);
  const tabs = new Map(), undo = new Map(), lockState = new Map();
  const unavailableIcons = new Set();
  const championSlotsKey = 'powerspike.champions.v1';
  const commandFields = new Set(['championaction', 'championwho', 'championjson']);
  let configurationPending = false;
  let championActionPending = false;
  let baseline = null, pending = null, identity = '', result = null, rows = [], events = [], statuses = [];
  const timelineTargets = '[data-trace-event],[data-status-index]';
  const statusNames = {stun: 'Stun', silence: 'Silence', slow: 'Slow', root: 'Root', charm: 'Charm', fear: 'Fear', airborne: 'Airborne', suppression: 'Suppression', blind: 'Blind', disarm: 'Disarm', grounded: 'Grounded', shield: 'Shield', parry: 'Parry', spellblade: 'Spellblade', 'outgoing-multiplier': 'Damage reduction', 'healing-multiplier': 'Healing reduction', 'move-speed': 'Movement speed', tenacity: 'Tenacity', armor: 'Armor', mr: 'Magic resistance'};
  const statusColors = {stun: '#efb85c', silence: '#c59aff', slow: '#68b9ed', root: '#8cce75', charm: '#f58db4', fear: '#e99062', airborne: '#d6e3ef', suppression: '#a7a1f4', blind: '#8e9aab', disarm: '#f0ca91', grounded: '#b2b68c', shield: '#5fdfca', parry: '#f3d88a', spellblade: '#67cdd9', 'outgoing-multiplier': '#df8878', 'healing-multiplier': '#d59dbc', 'move-speed': '#8ade9d', tenacity: '#9caff0', armor: '#c4b06b', mr: '#83c4a0'};
  const statusName = status => status.kind === 'empowerment' ? `${result.sources?.[status.effect]?.name || 'Empowered attack'} ready` : statusNames[status.effect] || String(status.effect).replace(/[-_]/g, ' ').replace(/\b\w/g, letter => letter.toUpperCase());
  const statusColor = status => {
    if (statusColors[status.effect]) return statusColors[status.effect];
    let hash = 0;
    for (const letter of String(status.effect)) hash = (Math.imul(hash, 31) + letter.charCodeAt(0)) | 0;
    return `hsl(${(hash >>> 0) % 360} 65% 72%)`;
  };
  let time = 0, metric = 'health', selected = null, scheduled = false;
  let eventTooltipAnchor = null, eventTooltipTimer, restoringEventFocus = false;
  const node = (tag, className, text) => {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  };
  function configuration() {
    const form = $('#scenario');
    if (!form) return '';
    const values = new Map([...new FormData(form)].filter(([name]) => !commandFields.has(name)));
    for (const field of form.elements) if (field.type === 'checkbox') values.set(field.name, String(field.checked));
    return JSON.stringify([...values].sort(([a], [b]) => a.localeCompare(b)));
  }
  function dirty() {
    if (!baseline) return;
    const changed = configuration() !== baseline;
    app.dataset.stale = String(changed);
    const notice = $('.matchup-stale');
    if (notice) notice.hidden = !changed;
  }
  function setField(name, value) {
    const fields = [...(document.forms.scenario?.elements || [])].filter(field => field.name === name);
    const field = fields.find(field => field.type === 'hidden') || fields[0];
    if (!field) return;
    if (field.type === 'checkbox') field.checked = Boolean(value); else field.value = String(value);
    field.dispatchEvent(new Event('input', {bubbles: true}));
  }
  function refreshConfiguration() {
    configurationPending = true;
    requestAnimationFrame(() => {
      dirty();
      app.dispatchEvent(new Event('configurationchange'));
    });
  }
  function championStatus(message) {
    $('#champion-slots-status').textContent = message;
  }
  function championSlots() {
    const text = localStorage.getItem(championSlotsKey);
    if (!text) return [null, null, null, null];
    if (text.length > 80000) throw new Error('Champion save collection exceeds its allowance.');
    const value = JSON.parse(text);
    if (value.version !== 1 || !Array.isArray(value.slots) || value.slots.length !== 4 || value.slots.some(entry =>
      entry !== null && (typeof entry.name !== 'string' || entry.name.length > 80 || typeof entry.document !== 'string' || entry.document.length > 16384))) {
      throw new Error('Champion save slots are invalid. Your saved data has been kept.');
    }
    return value.slots;
  }
  function currentChampion(who) {
    if (configurationPending || !document.forms.scenario.reportValidity() || app.classList.contains('is-pending')) {
      throw new Error('Wait for valid champion details to finish updating before saving or loading.');
    }
    return JSON.parse($('#champion-configurations').dataset.json)[who];
  }
  function writeChampionSlots(slots) {
    const bytes = JSON.stringify({version: 1, slots});
    if (new TextEncoder().encode(bytes).length > 128 * 1024) throw new Error('Champion save allowance reached.');
    localStorage.setItem(championSlotsKey, bytes);
  }
  function populateChampionSlots() {
    const slots = championSlots(), dialog = $('#champion-slots-dialog'), who = dialog.dataset.who;
    const current = JSON.parse($('#champion-configurations').dataset.json)[who];
    $('#champion-slots-title').textContent = `${$(`#${who}-card`).dataset.name} · Champion save slots`;
    $('#champion-slots-description').textContent = `Save this configuration or load a slot onto ${who === 'player' ? 'your champion' : 'the opponent'}.`;
    $('#champion-slots-list').replaceChildren(...slots.map((entry, index) => {
      const row = node('section', 'champion-save-slot');
      const label = node('label', '', `Slot ${index + 1}`), name = node('input');
      name.type = 'text'; name.maxLength = 80; name.placeholder = 'Name this configuration'; name.value = entry?.name || '';
      name.id = `champion-slot-name-${index}`; label.htmlFor = name.id; label.append(name); row.append(label);
      let compatible = false;
      if (entry) {
        const saved = JSON.parse(entry.document);
        compatible = saved.patch === current.patch && saved.snapshot === current.snapshot;
        const summary = node('p', 'muted', `${saved.champion?.champion || 'Champion'} · Level ${saved.champion?.level || '—'} · Patch ${saved.patch || 'unknown'}`);
        if (!compatible) summary.append(node('span', '', ' · Switch to the saved patch snapshot to load.'));
        row.append(summary);
      } else row.append(node('p', 'muted', 'Empty slot'));
      const actions = node('div', 'champion-slot-actions');
      for (const [action, caption] of [['save', entry ? 'Replace' : 'Save here'], ['load', 'Load'], ['clear', 'Clear']]) {
        const button = node('button', '', caption); button.type = 'button'; button.dataset.championSlotAction = action;
        button.dataset.slot = index; button.setAttribute('aria-label', `${caption} slot ${index + 1}`);
        button.disabled = action === 'load' ? !entry || !compatible : action === 'clear' && !entry;
        actions.append(button);
      }
      row.append(actions); return row;
    }));
  }
  function applyChampionAction(action, who, documentText = '') {
    currentChampion(who);
    undo.clear(); lockState.clear();
    setField('championaction', action); setField('championwho', who); setField('championjson', documentText);
    configurationPending = true;
    championActionPending = true;
    app.dispatchEvent(new Event('championconfigure'));
  }
  document.addEventListener('datastar-fetch', event => {
    if (championActionPending && event.detail.type === 'finished' && event.detail.el === app) {
      championActionPending = false; configurationPending = false;
    }
  });
  function cards() {
    // Fragment parsers can turn noscript fallback selects into live form
    // controls. Keep those duplicates out of the JavaScript configuration.
    document.querySelectorAll('.matchup-tray noscript').forEach(fallback => fallback.remove());
    document.querySelectorAll('.matchup-card').forEach(card => {
      const who = card.dataset.who, tab = tabs.get(who) || 'items';
      card.querySelectorAll('[data-tab]').forEach(button => button.setAttribute('aria-selected', String(button.dataset.tab === tab)));
      card.querySelectorAll('[role="tabpanel"]').forEach(panel => { panel.hidden = panel.id !== `${who}-panel-${tab}`; });
      card.querySelector('[data-undo-row]').hidden = !undo.has(who);
    });
  }
  function snapshotItems(who) {
    const card = $(`#${who}-card`);
    return {items: JSON.parse(card.dataset.items), champion: card.dataset.name, snapshot: document.forms.scenario.elements.snapshot.value};
  }
  function openItemSearch(who) {
    const card = $(`#${who}-card`), other = $(`#${who === 'player' ? 'opponent' : 'player'}-card`);
    $('#optimizer-dialog').dataset.who = who;
    $('#optimizer-title').textContent = `${card.dataset.name} · Optimize items`;
    $('#optimizer-description').textContent = `Against ${other.dataset.name} · opponent build fixed`;
    const ids = JSON.parse(card.dataset.items), currentLocks = lockState.get(who) || [];
    document.querySelectorAll('[data-lock-slot]').forEach((label, i) => {
      const holder = label.querySelector('.matchup-lock-icon'), checkbox = label.querySelector('input');
      holder.replaceChildren();
      const slotImage = card.querySelectorAll('.inventory .item-slot')[i]?.querySelector('img');
      if (slotImage) holder.append(slotImage.cloneNode()); else holder.textContent = '—';
      checkbox.checked = Boolean(ids[i] && currentLocks[i]);
      checkbox.disabled = !ids[i];
      checkbox.dispatchEvent(new Event('input', {bubbles: true}));
    });
    const panel = $('#search-panel');
    panel.classList.toggle('other-champion', Boolean(panel.dataset.job && panel.dataset.searchWho !== who));
    $('#optimizer-dialog').dataset.who = who;
  }
  document.addEventListener('input', event => {
    if (event.target.form?.id === 'scenario') {
      if (!commandFields.has(event.target.name)) configurationPending = true;
      requestAnimationFrame(dirty);
    }
  });
  document.addEventListener('change', event => {
    if (event.target.form?.id === 'scenario') refreshConfiguration();
    const lock = event.target.closest('[data-lock-slot]');
    if (lock) {
      const who = $('#optimizer-dialog').dataset.who || 'player';
      lockState.set(who, [...document.querySelectorAll('[data-lock-slot] input')].map(input => input.checked));
    }
  });
  app.addEventListener('configurationchange', () => requestAnimationFrame(dirty), true);
  app.addEventListener('evaluate', () => { pending = configuration(); }, true);
  document.addEventListener('submit', event => {
    if (event.target.id === 'scenario') pending = configuration();
  }, true);
  document.addEventListener('click', event => {
    const button = event.target.closest('button');
    if (!button) return;
    if (button.dataset.championSlots) {
      const dialog = $('#champion-slots-dialog'); dialog.dataset.who = button.dataset.championSlots;
      dialog.showModal(); championStatus('');
      try { populateChampionSlots(); } catch (error) { championStatus(error.message); }
    }
    if (button.hasAttribute('data-close-champion-slots')) $('#champion-slots-dialog').close();
    if (button.dataset.championSlotAction) {
      try {
        const slots = championSlots(), index = Number(button.dataset.slot), action = button.dataset.championSlotAction;
        const who = $('#champion-slots-dialog').dataset.who;
        if (action === 'save') {
          const document = currentChampion(who);
          const name = $(`#champion-slot-name-${index}`).value.trim() || `${document.champion.champion} · Level ${document.champion.level}`;
          slots[index] = {name, document: JSON.stringify(document)};
          writeChampionSlots(slots); populateChampionSlots(); championStatus(`Saved ${name} in slot ${index + 1}.`);
        } else if (action === 'clear') {
          slots[index] = null; writeChampionSlots(slots); populateChampionSlots(); championStatus(`Slot ${index + 1} cleared.`);
        } else if (action === 'load') {
          if (!slots[index]) throw new Error('Choose a saved champion.');
          applyChampionAction('load', who, slots[index].document); $('#champion-slots-dialog').close();
        }
      } catch (error) { championStatus(error.message); }
    }
    if (button.hasAttribute('data-swap-champions')) {
      try { applyChampionAction('swap', 'player'); }
      catch (error) { $('#config-status').textContent = error.message; }
    }
    if (button.dataset.tab) { tabs.set(button.dataset.who, button.dataset.tab); cards(); }
    if (button.hasAttribute('data-matchup-jump')) $('#results').scrollIntoView({block: 'start', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth'});
    if (button.dataset.searchOpen && ['player', 'opponent'].includes(button.dataset.searchOpen)) openItemSearch(button.dataset.searchOpen);
    if (button.dataset.applyBuild) undo.set(button.dataset.applyBuild, snapshotItems(button.dataset.applyBuild));
    if (button.dataset.undo) {
      const who = button.dataset.undo, previous = undo.get(who), current = snapshotItems(who);
      if (!previous || previous.champion !== current.champion || previous.snapshot !== current.snapshot) { undo.delete(who); cards(); return; }
      previous.items.forEach((id, i) => setField(`${who === 'opponent' ? 'enemyslot' : 'slot'}${i + 1}`, id));
      if (who === 'player') setField('selected', 'custom');
      undo.delete(who); refreshConfiguration(); cards();
    }
    if (button.dataset.matchupMetric) { metric = button.dataset.matchupMetric; draw(); }
    if (button.hasAttribute('data-trace-event')) selectEvent(Number(button.dataset.traceEvent));
    if (button.hasAttribute('data-status-index')) showStatusTooltip(Number(button.dataset.statusIndex), button);
  }, true);

  const ns = 'http://www.w3.org/2000/svg';
  function svgNode(tag, attrs, text) {
    const el = document.createElementNS(ns, tag);
    Object.entries(attrs).forEach(([key, value]) => el.setAttribute(key, String(value)));
    if (text !== undefined) el.textContent = text;
    return el;
  }
  function loadResult() {
    const container = $('[data-matchup-result]');
    if (!container || container.dataset.runId === identity) return false;
    identity = container.dataset.runId;
    result = JSON.parse(container.dataset.matchupResult);
    selected = null; time = Math.min(4, result.end);
    const totals = [0, 0];
    rows = result.trace.filter(record => record.at <= result.end).map(record => {
      const actor = result.actors.findIndex(a => a.id === record.actor);
      if (record.kind === 'damage' && actor >= 0) totals[actor] += record.damage;
      return {...record, dealt: [...totals]};
    });
    events = rows.filter(record => ['damage', 'heal', 'shield', 'control', 'death', 'parry-start', 'parried'].includes(record.kind));
    statuses = (result.statuses || []).map(status => ({...status, start: Math.max(0, status.start), end: Math.min(status.end, result.end)}))
      .filter(status => Number.isFinite(status.start) && Number.isFinite(status.end) && status.end > status.start && result.actors.some(actor => actor.id === status.actor));
    const legend = $('.matchup-status-legend');
    legend.replaceChildren(...[...new Map(statuses.map(status => [status.effect, status])).values()].map(status => {
      const key = node('span', 'matchup-status-key', statusName(status));
      key.style.setProperty('--status-color', statusColor(status));
      return key;
    }));
    legend.hidden = !statuses.length;
    baseline = pending || configuration(); pending = null;
    const select = $('.matchup-event-select');
    select.replaceChildren(new Option('Select event', ''));
    events.forEach((record, i) => select.add(new Option(`${record.at.toFixed(2)} s · ${eventName(record)}`, String(i))));
    select.addEventListener('change', () => { if (select.value === '') { selected = null; draw(); } else selectEvent(Number(select.value), select); });
    $('#matchup-chart').onkeydown = event => {
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      time = event.key === 'Home' ? 0 : event.key === 'End' ? result.end : Math.max(0, Math.min(result.end, time + (event.key === 'ArrowLeft' ? -1 : 1) * (event.shiftKey ? 1 : .1)));
      selected = null; draw();
    };
    return true;
  }
  function actorIndex(record) {
    return result.actors.findIndex(actor => actor.id === (record.actor || record.target));
  }
  function eventName(record) {
    const who = actorIndex(record), source = result.sources?.[record.source]?.name || (record.source === 'attack' ? 'Basic attack' : record.source || record.kind);
    if (record.kind === 'parry-start') return `${result.names[who] || ''} · ${source} begins`;
    if (record.kind === 'parried') {
      const target = result.actors.findIndex(actor => actor.id === record.target);
      return `${result.names[who] || ''} · ${source} · parried${target >= 0 ? ' by ' + result.names[target] : ''}`;
    }
    return `${who >= 0 ? result.names[who] + ' · ' : ''}${source} · ${record.kind === 'control' ? 'control received' : record.kind}`;
  }
  function hideEventTooltip() {
    clearTimeout(eventTooltipTimer);
    const detail = $('#combat-event-tooltip');
    if (detail?.matches(':popover-open')) detail.hidePopover();
    if (detail) detail.hidden = true;
    eventTooltipAnchor?.removeAttribute('aria-describedby');
    eventTooltipAnchor = null;
  }
  function eventValues(event) {
    const values = [];
    if (event.kind === 'damage') { values.push(`${format(event.damage)} ${event.type || ''} damage`); if (event.absorbed) values.push(`${format(event.absorbed)} absorbed`); }
    if (['heal', 'shield'].includes(event.kind)) values.push(`${format(event.amount)} ${event.kind === 'heal' ? 'HP healed' : 'shield'}`);
    if (event.kind === 'control') values.push(`${event.control} · ${Number(event.duration).toFixed(2)} s`);
    if (event.kind === 'death') values.push('Knockout');
    if (event.kind === 'parry-start') values.push(`Defense active for ${Number(Math.max(0, event.expires - event.at).toFixed(2))} s`);
    if (event.kind === 'parried') {
      values.push(event['effect-kind'] === 'damage' ? '0 damage' : event['effect-kind'] === 'control' ? 'Control blocked' : 'Effect blocked');
      const consumption = result.sources?.[event.source]?.consumption;
      if (consumption) values.push(consumption);
    }
    return values.join(' · ');
  }
  function showEventTooltip(index, anchor) {
    const detail = $('#combat-event-tooltip'), event = events[index];
    if (!detail || !event || !anchor) return;
    const group = JSON.parse(anchor.dataset.traceEvents || '[]');
    if (group.length > 1) {
      const first = events[group[0]], last = events[group.at(-1)];
      showTimelineTooltip(`${first.at.toFixed(2)}–${last.at.toFixed(2)} s · ${group.length} events`,
        group.map(i => `${events[i].at.toFixed(2)} s · ${eventName(events[i])}\n${eventValues(events[i])}`).join('\n\n'), anchor);
      return;
    }
    showTimelineTooltip(`${event.at.toFixed(2)} s · ${eventName(event)}`, eventValues(event), anchor);
  }
  function showStatusTooltip(index, anchor) {
    const status = statuses[index];
    if (!status || !anchor) return;
    const who = result.actors.findIndex(actor => actor.id === status.actor);
    showTimelineTooltip(`${result.names[who]} · ${statusName(status)}`,
      `${Number(status.start.toFixed(3))}–${Number(status.end.toFixed(3))} s · ${Number((status.end - status.start).toFixed(3))} s active`, anchor);
  }
  function showTimelineTooltip(title, values, anchor) {
    const detail = $('#combat-event-tooltip');
    hideEventTooltip();
    eventTooltipAnchor = anchor;
    detail.replaceChildren(node('strong', '', title), node('span', '', values));
    anchor.setAttribute('aria-describedby', detail.id);
    detail.hidden = false;
    if (typeof detail.showPopover === 'function') detail.showPopover();
    positionEventTooltip();
  }
  function positionEventTooltip() {
    const detail = $('#combat-event-tooltip');
    if (!eventTooltipAnchor || !detail || detail.hidden) return;
    const rect = eventTooltipAnchor.getBoundingClientRect(), width = detail.offsetWidth, height = detail.offsetHeight;
    if (rect.bottom < 0 || rect.top > innerHeight) { hideEventTooltip(); return; }
    detail.style.left = `${Math.max(12, Math.min(innerWidth - width - 12, rect.left + rect.width / 2 - width / 2))}px`;
    detail.style.top = `${Math.max(12, Math.min(innerHeight - height - 12, rect.top > height + 20 ? rect.top - height - 8 : rect.bottom + 8))}px`;
  }
  function selectEvent(index, anchor) {
    selected = index; time = events[index].at; draw();
    showEventTooltip(index, anchor || $(`[data-trace-event="${index}"]`));
  }
  app.addEventListener('pointerover', event => {
    const anchor = event.target.closest(timelineTargets);
    if (anchor && !anchor.contains(event.relatedTarget) && event.pointerType !== 'touch') {
      if (anchor.hasAttribute('data-status-index')) showStatusTooltip(Number(anchor.dataset.statusIndex), anchor);
      else showEventTooltip(Number(anchor.dataset.traceEvent), anchor);
    }
    if (event.target.closest('#combat-event-tooltip')) clearTimeout(eventTooltipTimer);
  });
  app.addEventListener('pointerout', event => {
    const anchor = event.target.closest(`${timelineTargets},#combat-event-tooltip`);
    if (anchor && !anchor.contains(event.relatedTarget) && document.activeElement !== eventTooltipAnchor) eventTooltipTimer = setTimeout(hideEventTooltip, 120);
  });
  app.addEventListener('focusin', event => {
    const anchor = event.target.closest(timelineTargets);
    if (anchor && !restoringEventFocus) {
      if (anchor.hasAttribute('data-status-index')) showStatusTooltip(Number(anchor.dataset.statusIndex), anchor);
      else showEventTooltip(Number(anchor.dataset.traceEvent), anchor);
    }
  });
  app.addEventListener('focusout', event => { if (event.target === eventTooltipAnchor) eventTooltipTimer = setTimeout(hideEventTooltip, 120); });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') hideEventTooltip(); });
  document.addEventListener('click', event => { if (!event.target.closest(`${timelineTargets},#combat-event-tooltip,.matchup-event-select`)) hideEventTooltip(); });
  document.addEventListener('scroll', event => { if (!event.target.closest?.('#combat-event-tooltip')) positionEventTooltip(); }, true);
  function recordAt(t) {
    let lo = 0, hi = rows.length;
    while (lo < hi) { const mid = (lo + hi) >>> 1; if (rows[mid].at <= t) lo = mid + 1; else hi = mid; }
    return rows[Math.max(0, lo - 1)];
  }
  function draw() {
    const box = $('#matchup-chart');
    if (!box || !result || !rows.length) return;
    const width = Math.max(220, box.clientWidth), height = 235, left = 76, right = width - 23, top = 27, bottom = 200;
    const health = metric === 'health', points = rows.map(record => ({at: record.at, values: result.actors.map((actor, i) => health ? (record.participants[i]?.health || 0) / Math.max(1, actor.hp) * 100 : record.dealt[i])}));
    const max = health ? Math.max(100, ...points.flatMap(p => p.values)) : Math.max(1, ...points.flatMap(p => p.values));
    const ceiling = health ? Math.ceil(max / 25) * 25 : Math.ceil(max / Math.max(1, 10 ** Math.floor(Math.log10(max)))) * Math.max(1, 10 ** Math.floor(Math.log10(max)));
    const x = t => left + t / result.duration * (right - left), y = value => bottom - value / ceiling * (bottom - top);
    const svg = svgNode('svg', {width, height, viewBox: `0 0 ${width} ${height}`, role: 'img', 'aria-label': `${health ? 'Health remaining (%)' : 'Damage dealt (HP)'} for ${result.names.join(' and ')}`});
    svg.append(svgNode('text', {x: left, y: 15}, health ? 'Health remaining (%)' : 'Damage dealt (HP)'));
    [0, .25, .5, .75, 1].forEach(fraction => {
      const value = fraction * ceiling;
      svg.append(svgNode('line', {x1: left, x2: right, y1: y(value), y2: y(value), class: 'matchup-grid'}));
      svg.append(svgNode('text', {x: left - 9, y: y(value) + 4, 'text-anchor': 'end'}, format(value)));
    });
    (width < 450 ? [0, .5, 1] : [0, .2, .4, .6, .8, 1]).forEach(fraction => svg.append(svgNode('text', {x: x(fraction * result.duration), y: bottom + 21, 'text-anchor': fraction === 0 ? 'start' : fraction === 1 ? 'end' : 'middle'}, `${Number((fraction * result.duration).toFixed(2))} s`)));
    for (let side = 0; side < 2; side++) {
      let path = `M ${x(points[0].at)} ${y(points[0].values[side])}`;
      for (const p of points.slice(1)) path += ` H ${x(p.at)} V ${y(p.values[side])}`;
      if (points.at(-1).at < result.end) path += ` H ${x(result.end)}`;
      svg.append(svgNode('path', {d: path, class: `matchup-line ${side ? 'opponent' : 'player'}`}));
    }
    if (result.end < result.duration) {
      svg.append(svgNode('line', {x1: x(result.end), x2: x(result.end), y1: top, y2: bottom, class: 'matchup-grid'}));
      svg.append(svgNode('text', {x: x(result.end) - 4, y: top + 12, 'text-anchor': 'end'}, 'KO'));
    }
    const current = recordAt(time), percent = result.actors.map((a, i) => (current.participants[i]?.health || 0) / Math.max(1, a.hp) * 100);
    svg.append(svgNode('line', {x1: x(time), x2: x(time), y1: top, y2: bottom, class: 'matchup-guide'}));
    result.actors.forEach((actor, i) => svg.append(svgNode('circle', {cx: x(time), cy: y(health ? percent[i] : current.dealt[i]), r: 4, class: `matchup-marker ${i ? 'opponent' : 'player'}`})));
    const overlay = svgNode('rect', {x: left, y: top, width: right - left, height: bottom - top, fill: 'transparent'});
    function inspect(event) { const rect = svg.getBoundingClientRect(); time = Math.max(0, Math.min(result.end, ((event.clientX - rect.left) * width / rect.width - left) / (right - left) * result.duration)); selected = null; hideEventTooltip(); draw(); }
    overlay.addEventListener('pointermove', event => { if (event.pointerType !== 'touch') inspect(event); }); overlay.addEventListener('click', inspect); svg.append(overlay); box.replaceChildren(svg);
    const healthBox = $('.matchup-health');
    healthBox.replaceChildren(...result.actors.map((actor, i) => { const cell = node('div'); cell.append(node('strong', '', result.names[i]), node('span', '', health ? `${format(current.participants[i]?.health)} / ${format(actor.hp)} HP (${format(percent[i])}%)` : `${format(current.dealt[i])} damage · ${format(percent[i])}% health`)); return cell; }));
    $('.matchup-time').textContent = `${time.toFixed(2)} s`;
    box.setAttribute('aria-valuenow', time.toFixed(2));
    box.setAttribute('aria-valuetext', `${time.toFixed(2)} seconds`);
    $('.matchup-timeline-guide').style.left = `${x(time)}px`;
    document.querySelectorAll('[data-matchup-metric]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.matchupMetric === metric)));
    drawEvents(width, left, right);
  }
  function drawEvents(width, left, right) {
    const selectorTooltip = eventTooltipAnchor?.matches('.matchup-event-select');
    const tooltipIndex = selectorTooltip ? selected : eventTooltipAnchor?.dataset.traceEvent;
    const statusIndex = eventTooltipAnchor?.dataset.statusIndex;
    hideEventTooltip();
    const lanes = $('.matchup-event-lanes'), minDistance = matchMedia('(pointer: coarse)').matches ? 56 : 42;
    const focused = document.activeElement?.dataset.traceEvent;
    const focusedStatus = document.activeElement?.dataset.statusIndex;
    lanes.replaceChildren(...result.actors.map((actor, side) => {
      const lane = node('div', 'matchup-event-lane'), label = node('span', 'matchup-lane-name', result.names[side]), track = node('div', 'matchup-event-track');
      label.title = result.names[side];
      track.style.marginLeft = `${left}px`; track.style.width = `${right - left}px`;
      const effects = [...new Set(statuses.filter(status => status.actor === actor.id).map(status => status.effect))].sort();
      statuses.forEach((status, index) => {
        if (status.actor !== actor.id) return;
        const band = node('button', 'matchup-status-band');
        band.type = 'button'; band.dataset.statusIndex = index; band.dataset.statusEffect = status.effect;
        band.setAttribute('aria-label', `${result.names[side]}, ${statusName(status)}, ${Number(status.start.toFixed(3))} to ${Number(status.end.toFixed(3))} seconds`);
        band.style.setProperty('--status-color', statusColor(status));
        band.style.left = `${status.start / result.duration * 100}%`;
        band.style.width = `${(status.end - status.start) / result.duration * 100}%`;
        band.style.top = `${effects.indexOf(status.effect) / effects.length * 100}%`;
        band.style.height = `${100 / effects.length}%`;
        track.append(band);
      });
      const groups = [];
      events.forEach((record, index) => {
        if (actorIndex(record) !== side) return;
        const position = record.at / result.duration * (right - left);
        const previous = groups.at(-1);
        if (previous && position - previous.position < minDistance) previous.indices.push(index);
        else groups.push({position, indices: [index]});
      });
      groups.forEach(({position, indices}) => {
        const index = indices.includes(selected) ? selected : indices.includes(Number(focused)) ? Number(focused) : indices[0];
        const record = events[index];
        const source = result.sources?.[record.source];
        const label = record.kind === 'parried' ? '×' : record.kind === 'death' ? 'KO' : record.source === 'attack' ? 'AA' : record.kind === 'control' ? 'CC' : source?.slot?.toUpperCase() || (record.kind === 'heal' ? '+' : record.kind === 'shield' ? 'S' : record.source?.match(/[QWER]$/)?.[0] || 'Hit');
        const button = node('button', `matchup-event ${['parried', 'parry-start'].includes(record.kind) ? record.kind : ''}`);
        const artwork = record.kind === 'death' ? null : record.source === 'attack' ? actor.icon : source?.icon;
        if (artwork && !unavailableIcons.has(artwork)) {
          const img = node('img'); img.alt = ''; img.setAttribute('aria-hidden', 'true'); img.draggable = false;
          img.addEventListener('error', () => { unavailableIcons.add(artwork); img.remove(); button.classList.remove('has-icon'); }, {once: true});
          img.src = artwork; button.classList.add('has-icon'); button.append(img);
        }
        button.append(node('span', 'matchup-event-label', label));
        if (indices.length > 1) button.append(node('span', 'matchup-event-count', `+${indices.length - 1}`));
        button.type = 'button'; button.dataset.traceEvent = index; button.dataset.traceEvents = JSON.stringify(indices);
        button.style.left = `${position}px`;
        button.setAttribute('aria-label', `${record.at.toFixed(2)} seconds, ${eventName(record)}, ${eventValues(record)}${indices.length > 1 ? `; ${indices.length} events grouped here` : ''}`);
        button.setAttribute('aria-pressed', String(selected === index)); track.append(button);
      });
      lane.append(label, track); return lane;
    }));
    restoringEventFocus = true;
    if (focused !== undefined) [...lanes.querySelectorAll('[data-trace-event]')].find(button => button.dataset.traceEvent === focused)?.focus({preventScroll: true});
    if (focusedStatus !== undefined) lanes.querySelector(`[data-status-index="${focusedStatus}"]`)?.focus({preventScroll: true});
    restoringEventFocus = false;
    if (tooltipIndex !== undefined && tooltipIndex !== null) showEventTooltip(Number(tooltipIndex), selectorTooltip ? $('.matchup-event-select') : lanes.querySelector(`[data-trace-event="${tooltipIndex}"]`));
    if (statusIndex !== undefined) showStatusTooltip(Number(statusIndex), lanes.querySelector(`[data-status-index="${statusIndex}"]`));
    $('.matchup-event-select').value = selected === null ? '' : String(selected);
  }
  function update() {
    scheduled = false;
    cards(); loadResult();
    if (!baseline) baseline = configuration();
    dirty(); draw();
  }
  function schedule() { if (!scheduled) { scheduled = true; requestAnimationFrame(update); } }
  new MutationObserver(records => {
    if (records.some(record => ['data-run-id', 'data-matchup-result'].includes(record.attributeName) || [...record.addedNodes].some(n => n.nodeType === 1 && (['loadout-tray', 'results'].includes(n.id) || n.querySelector?.('#loadout-tray,#results'))))) schedule();
  }).observe(app, {childList: true, subtree: true, attributes: true, attributeFilter: ['data-run-id', 'data-matchup-result']});
  new MutationObserver(records => {
    if (records.some(record => ['configuration-data', 'champion-configurations'].includes(record.target.id) ||
      [...record.addedNodes].some(n => n.nodeType === 1 && (n.id === 'loadout-tray' || n.querySelector?.('#configuration-data'))))) {
      configurationPending = false;
    }
  }).observe(app, {childList: true, subtree: true, attributes: true, attributeFilter: ['data-json']});
  window.addEventListener('storage', event => {
    if ((event.key === championSlotsKey || event.key === null) && $('#champion-slots-dialog')?.open) {
      try { populateChampionSlots(); championStatus('Save slots updated from another tab.'); } catch (error) { championStatus(error.message); }
    }
  });
  new ResizeObserver(schedule).observe(app);
  requestAnimationFrame(update);
})();
