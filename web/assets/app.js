/* Presentation only. Janet supplies every combat event and numeric result. */
(() => {
  const app = document.getElementById('powerspike');
  document.documentElement.classList.add('has-js');
  // Catalog searching is presentation only; selections and calculations use Datastar/Janet.
  const normalize = value => value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  for (const dialog of document.querySelectorAll('.catalog-dialog')) {
    dialog.addEventListener('keydown', event => {
      if (event.key === 'Escape') { event.preventDefault(); dialog.close(); }
    });
    const search = dialog.querySelector('.catalog-search');
    const scope = dialog.querySelector('.catalog-scope');
    const cards = [...dialog.querySelectorAll('.catalog-card')];
    const indexed = cards.map(card => [card, normalize(card.dataset.search)]);
    function filter() {
      const terms = normalize(search.value).trim().split(/\s+/).filter(Boolean);
      let visible = 0;
      for (const [card, text] of indexed) {
        card.hidden = !(terms.every(term => text.includes(term)) &&
          (!scope || scope.value === 'all' || card.dataset.rift === 'true'));
        if (!card.hidden) visible++;
      }
      dialog.querySelector('.catalog-count').textContent = `${visible} / ${cards.length} ${scope ? 'items' : 'champions'}`;
      dialog.querySelector('.picker-empty').hidden = visible > 0;
    }
    search.addEventListener('input', filter);
    scope?.addEventListener('change', filter);
    filter();
  }
  setInterval(() => {
    if (document.getElementById('search-panel')?.dataset.poll === 'true') app.dispatchEvent(new Event('searchtick'));
    if (document.getElementById('patch-panel')?.dataset.poll === 'true') app.dispatchEvent(new Event('jobtick'));
  }, 1000);
  const ns = 'http://www.w3.org/2000/svg';
  const format = value => new Intl.NumberFormat('en-US', {maximumFractionDigits: 0}).format(value);
  function element(name, attrs, text) {
    const node = document.createElementNS(ns, name);
    for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value));
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function draw() {
    const box = document.getElementById('timeline');
    if (!box) return;
    const events = JSON.parse(box.dataset.events);
    const duration = Number(box.dataset.duration), total = Number(box.dataset.total);
    const width = Math.max(220, box.clientWidth), height = 185, left = 47, right = 12;
    const ceiling = Math.max(1, total * 1.15);
    const x = time => left + time / duration * (width - left - right);
    const y = damage => 157 - damage / ceiling * 145;
    const label = box.dataset.label;
    const svg = element('svg', {viewBox: `0 0 ${width} ${height}`, role: 'img', 'aria-label': `${label}: ${format(total)} damage over ${duration} seconds`});
    svg.append(element('title', {}, label));
    for (const fraction of [0, 0.5, 1]) {
      const value = fraction * ceiling;
      svg.append(element('line', {x1: left, x2: width - right, y1: y(value), y2: y(value), class: 'chart-grid'}));
      svg.append(element('text', {x: left - 8, y: y(value) + 4, 'text-anchor': 'end'}, format(value)));
    }
    for (const time of [0, duration / 2, duration]) svg.append(element('text', {x: x(time), y: 178, 'text-anchor': time === 0 ? 'start' : time === duration ? 'end' : 'middle'}, `${time} s`));
    let cumulative = 0, path = `M ${x(0)} ${y(0)}`;
    const points = [];
    for (const event of events) {
      cumulative += event.damage;
      path += ` H ${x(event.at)} V ${y(cumulative)}`;
      points.push([event, cumulative]);
    }
    path += ` H ${x(duration)}`;
    svg.append(element('path', {d: path, class: 'chart-line'}));
    for (const [event, damage] of points) {
      const dot = element('circle', {cx: x(event.at), cy: y(damage), r: 3, class: 'chart-point'});
      dot.append(element('title', {}, `${event.source === 'attack' ? 'Attack' : event.source.replace('Annie', '')}: ${event.at.toFixed(2)} s, ${format(event.damage)} damage`));
      svg.append(dot);
    }
    box.replaceChildren(svg);
  }
  draw();
  new ResizeObserver(draw).observe(app);
  new MutationObserver(records => {
    if (records.some(record => record.type === 'attributes' || !(record.target.nodeType === 1 ? record.target : record.target.parentElement)?.closest('#timeline'))) draw();
  }).observe(app, {subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['data-events', 'data-duration', 'data-total', 'data-label']});
})();
