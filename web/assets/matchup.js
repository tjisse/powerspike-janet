/* Presentation only: configuration state, chart geometry and server trace inspection. */
(() => {
  const app = document.getElementById('powerspike');
  if (app?.dataset.layout !== 'matchup') return;
  const $ = selector => document.querySelector(selector);
  const format = value => new Intl.NumberFormat('en-US', {maximumFractionDigits: 0}).format(value || 0);
  const tabs = new Map(), expanded = new Map(), undo = new Map(), lockState = new Map();
  const unavailableIcons = new Set();
  let baseline = null, pending = null, identity = '', result = null, rows = [], events = [];
  let time = 0, metric = 'health', selected = null, narrow = null, scheduled = false;
  const node = (tag, className, text) => {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  };
  function configuration() {
    const form = $('#scenario');
    if (!form) return '';
    const values = new Map(new FormData(form));
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
    requestAnimationFrame(() => {
      dirty();
      app.dispatchEvent(new Event('configurationchange'));
    });
  }
  function cards() {
    // Fragment parsers can turn noscript fallback selects into live form
    // controls. Keep those duplicates out of the JavaScript configuration.
    document.querySelectorAll('.matchup-tray noscript').forEach(fallback => fallback.remove());
    const nextNarrow = innerWidth <= 650;
    if (nextNarrow !== narrow) {
      narrow = nextNarrow;
      for (const who of ['player', 'opponent']) expanded.set(who, !narrow);
      const detail = $('#matchup-events');
      if (detail) detail.open = !narrow;
    }
    document.querySelectorAll('.matchup-card').forEach(card => {
      const who = card.dataset.who, open = expanded.get(who) !== false, tab = tabs.get(who) || 'items';
      card.classList.toggle('is-collapsed', !open);
      const toggle = card.querySelector('[data-collapse]');
      toggle.setAttribute('aria-expanded', String(open));
      toggle.textContent = open ? 'Collapse −' : 'Edit build +';
      card.querySelector('.matchup-loadout').hidden = !open;
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
    if (panel.dataset.job && panel.dataset.searchWho !== who) panel.hidden = true;
    $('#optimizer-dialog').dataset.who = who;
  }
  document.addEventListener('input', event => {
    if (event.target.form?.id === 'scenario') requestAnimationFrame(dirty);
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
    if (button.dataset.tab) { tabs.set(button.dataset.who, button.dataset.tab); cards(); }
    if (button.dataset.collapse) { const who = button.dataset.collapse; expanded.set(who, !expanded.get(who)); cards(); }
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
    baseline = pending || configuration(); pending = null;
    const select = $('.matchup-event-select');
    select.replaceChildren(new Option('Select event', ''));
    events.forEach((record, i) => select.add(new Option(`${record.at.toFixed(2)} s · ${eventName(record)}`, String(i))));
    select.addEventListener('change', () => { selected = select.value === '' ? null : Number(select.value); if (selected !== null) time = events[selected].at; draw(); });
    const range = $('.matchup-scrubber input');
    range.max = result.end;
    range.addEventListener('input', () => { time = Number(range.value); selected = null; draw(); });
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
  function selectEvent(index) { selected = index; time = events[index].at; draw(); }
  function recordAt(t) {
    let lo = 0, hi = rows.length;
    while (lo < hi) { const mid = (lo + hi) >>> 1; if (rows[mid].at <= t) lo = mid + 1; else hi = mid; }
    return rows[Math.max(0, lo - 1)];
  }
  function draw() {
    const box = $('#matchup-chart');
    if (!box || !result || !rows.length) return;
    const width = Math.max(220, box.clientWidth), height = 235, left = 57, right = width - 23, top = 27, bottom = 200;
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
    function inspect(event) { const rect = svg.getBoundingClientRect(); time = Math.max(0, Math.min(result.end, ((event.clientX - rect.left) * width / rect.width - left) / (right - left) * result.duration)); selected = null; draw(); }
    overlay.addEventListener('pointermove', event => { if (event.pointerType !== 'touch') inspect(event); }); overlay.addEventListener('click', inspect); svg.append(overlay); box.replaceChildren(svg);
    const healthBox = $('.matchup-health');
    healthBox.replaceChildren(...result.actors.map((actor, i) => { const cell = node('div'); cell.append(node('strong', '', result.names[i]), node('span', '', health ? `${format(current.participants[i]?.health)} / ${format(actor.hp)} HP (${format(percent[i])}%)` : `${format(current.dealt[i])} damage · ${format(percent[i])}% health`)); return cell; }));
    const difference = percent[0] - percent[1];
    $('.matchup-advantage').textContent = Math.abs(difference) < .5 ? 'Equal remaining health (%)' : `${result.names[difference >= 0 ? 0 : 1]} · ${format(Math.abs(difference))} percentage points more health`;
    $('.matchup-scrubber input').value = time; $('.matchup-scrubber output').textContent = `${time.toFixed(2)} s`;
    document.querySelectorAll('[data-matchup-metric]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.matchupMetric === metric)));
    drawEvents(width, left, right);
  }
  function drawEvents(width, left, right) {
    const lanes = $('.matchup-event-lanes'), minDistance = matchMedia('(pointer: coarse)').matches ? 48 : 36;
    const focused = document.activeElement?.dataset.traceEvent;
    lanes.replaceChildren(...result.actors.map((actor, side) => {
      const lane = node('div', 'matchup-event-lane'), label = node('span', 'matchup-lane-name', result.names[side]), track = node('div', 'matchup-event-track');
      track.style.marginLeft = `${left}px`; track.style.width = `${right - left}px`;
      let previous = -Infinity;
      events.forEach((record, index) => {
        if (actorIndex(record) !== side) return;
        const position = record.at / result.duration * (right - left);
        if (position - previous < minDistance && selected !== index) return;
        previous = position;
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
        button.type = 'button'; button.dataset.traceEvent = index; button.style.left = `${position}px`; button.setAttribute('aria-label', `${record.at.toFixed(2)} seconds, ${eventName(record)}`); button.title = button.getAttribute('aria-label'); button.setAttribute('aria-pressed', String(selected === index)); track.append(button);
      });
      lane.append(label, track); return lane;
    }));
    if (focused !== undefined) [...lanes.querySelectorAll('[data-trace-event]')].find(button => button.dataset.traceEvent === focused)?.focus({preventScroll: true});
    const detail = $('.matchup-event-detail'); detail.hidden = selected === null;
    $('.matchup-event-select').value = selected === null ? '' : String(selected);
    if (selected !== null) {
      const event = events[selected], values = [];
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
      detail.replaceChildren(node('strong', '', `${event.at.toFixed(2)} s · ${eventName(event)}`), node('span', '', values.join(' · ')));
    }
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
  new ResizeObserver(schedule).observe(app);
  requestAnimationFrame(update);
})();
