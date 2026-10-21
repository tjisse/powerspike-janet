/* Presentation only. Janet supplies every combat event and numeric result. */
(() => {
  const app = document.getElementById('powerspike');
  document.documentElement.classList.add('has-js');
  // Catalog records are presentation only, loaded once per selected snapshot.
  const normalize = value => value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const catalogLoaders = [];
  function catalogSnapshot() {
    const text = document.getElementById('configuration-data')?.dataset.json || document.getElementById('scenario-data')?.dataset.json;
    if (text) {
      const scenario = JSON.parse(text).scenario;
      return {patch: scenario.patch, snapshot: scenario.snapshot};
    }
    // The original legacy view has no canonical scenario document.
    const form = document.forms.scenario;
    const patch = form?.elements.namedItem('patch')?.value, snapshot = form?.elements.namedItem('snapshot')?.value;
    if (!patch || !snapshot) throw new Error('No catalog snapshot');
    return {patch, snapshot};
  }
  for (const dialog of document.querySelectorAll('.catalog-dialog')) {
    dialog.addEventListener('keydown', event => {
      if (event.key === 'Escape') { event.preventDefault(); dialog.close(); }
    });
    const kind = dialog.dataset.catalog, search = dialog.querySelector('.catalog-search');
    const scope = dialog.querySelector('.catalog-scope'), grid = dialog.querySelector('.catalog-grid');
    const status = dialog.querySelector('.catalog-status'), retry = dialog.querySelector('.catalog-retry');
    let indexed = [], loadedKey = '', pending = null, requestedKey = '';
    function filter() {
      if (!loadedKey) return;
      const terms = normalize(search.value).trim().split(/\s+/).filter(Boolean);
      let visible = 0;
      for (const [card, text] of indexed) {
        card.hidden = !(terms.every(term => text.includes(term)) &&
          (!scope || scope.value === 'all' || card.dataset.rift === 'true'));
        if (!card.hidden) visible++;
      }
      dialog.querySelector('.catalog-count').textContent = `${visible} / ${indexed.length} ${kind}`;
      dialog.querySelector('.picker-empty').hidden = visible > 0;
    }
    function cardFor(record) {
      const card = document.createElement('button'); card.type = 'button'; card.className = 'catalog-card';
      const image = document.createElement('img'); image.src = record.icon; image.alt = record.name;
      image.width = image.height = 64; image.loading = 'lazy';
      const name = document.createElement('span'); name.textContent = record.name; card.append(image, name);
      if (kind === 'champions') card.dataset.championId = record.id;
      else {
        card.dataset.itemId = record.id; card.dataset.detailItem = record.id;
        card.dataset.rift = String(Boolean(record.rift));
        card.dataset.detailPin = 'false'; card.setAttribute('aria-haspopup', 'dialog');
        card.dataset.details = JSON.stringify({name: record.name, icon: record.icon, subtitle: `${record.gold} gold · item`,
          body: ['Loading item description…'], coverage: 'Values load for the current build. See Simulation details for effects not included.',
          loading: true, 'patch-description': record.description, action: 'item-picker', 'action-label': 'Change item'});
        const price = document.createElement('small'); price.textContent = `${record.gold} gold · ${record.id}`; card.append(price);
      }
      return [card, normalize([record.name, record.id, record.description || '', ...(record.tags || [])].join(' '))];
    }
    async function load() {
      if (!dialog.open) return;
      let snapshot;
      try { snapshot = catalogSnapshot(); } catch { return; }
      const key = JSON.stringify(snapshot);
      if (loadedKey === key) { filter(); return; }
      if (pending && requestedKey === key) return;
      pending?.abort();
      const request = new AbortController(); pending = request; requestedKey = key;
      loadedKey = ''; indexed = []; dialog.dispatchEvent(new Event('catalogreset')); grid.replaceChildren();
      delete dialog.dataset.catalogReady;
      dialog.querySelector('.catalog-count').textContent = kind === 'items' ? 'Items' : 'Champions';
      dialog.setAttribute('aria-busy', 'true'); retry.hidden = true;
      status.hidden = false; status.textContent = `Loading ${kind}…`;
      dialog.querySelector('.picker-empty').hidden = true;
      const timeout = setTimeout(() => request.abort(), 15000);
      try {
        const response = await fetch(`/catalog?${new URLSearchParams({...snapshot, kind})}`, {signal: request.signal});
        if (!response.ok) throw new Error('Catalog unavailable');
        const data = await response.json();
        if (data.kind !== kind || data.patch !== snapshot.patch || data.snapshot !== snapshot.snapshot || !Array.isArray(data.records) || data.records.length > 5000) throw new Error('Invalid catalog');
        if (request.signal.aborted || pending !== request) return;
        if (JSON.stringify(catalogSnapshot()) !== key) { load(); return; }
        indexed = data.records.map(cardFor);
        grid.replaceChildren(...indexed.map(([card]) => card));
        loadedKey = key; dialog.dataset.catalogReady = 'true'; status.hidden = true; filter();
      } catch {
        if (pending !== request) return;
        status.hidden = false; status.textContent = `Could not load ${kind}. Please retry.`; retry.hidden = false;
      } finally {
        clearTimeout(timeout);
        if (pending === request) { pending = null; dialog.setAttribute('aria-busy', 'false'); }
      }
    }
    search.addEventListener('input', filter); scope?.addEventListener('change', filter);
    retry.addEventListener('click', load);
    new MutationObserver(load).observe(dialog, {attributes: true, attributeFilter: ['open']});
    catalogLoaders.push(load);
  }
  new MutationObserver(records => {
    if (records.some(record => ['configuration-data', 'scenario-data'].includes(record.target.id) ||
      [...record.addedNodes].some(node => node.nodeType === 1 && (['loadout-tray', 'configuration-data', 'scenario-data'].includes(node.id) || node.querySelector?.('#configuration-data,#scenario-data'))))) {
      catalogLoaders.forEach(load => load());
    }
  }).observe(app, {childList: true, subtree: true, attributes: true, attributeFilter: ['data-json']});
  setInterval(() => {
    if (document.getElementById('search-panel')?.dataset.poll === 'true') document.getElementById('optimizer-dialog').dispatchEvent(new Event('searchtick'));
    if (document.getElementById('patch-panel')?.dataset.poll === 'true') document.getElementById('patch-settings').dispatchEvent(new Event('jobtick'));
  }, 1000);
  // Keep optimization visible from the click onward. Closing the native dialog
  // never cancels the worker; opening it again resumes the same progress view.
  const optimizer=document.getElementById('optimizer-dialog');
  const requestStatus=document.getElementById('search-request-status');
  let awaitingSearch=false,previousJob='',lastApplied='',searchOpener=null;
  const searchPanel=()=>document.getElementById('search-panel');
  function openOptimizer(opener) {
    searchOpener=opener;
    if(!optimizer.open)optimizer.showModal();
    document.getElementById('optimizer-title').focus({preventScroll:true});
  }
  function updateSearch() {
    const panel=searchPanel();if(!panel)return;
    if(awaitingSearch && (panel.dataset.job!==previousJob || panel.dataset.error==='true')){
      awaitingSearch=false;requestStatus.hidden=true;panel.hidden=false;
      requestAnimationFrame(()=>{if(optimizer.open)panel.scrollIntoView({block:'start'});});
    }
    const ongoing=panel.dataset.poll==='true';
    document.getElementById('search-start').disabled=awaitingSearch || ongoing;
    optimizer.querySelectorAll('#optimizer input,#optimizer select').forEach(node=>{node.disabled=awaitingSearch || ongoing;});
    if(panel.dataset.applied && panel.dataset.applied!==lastApplied){
      lastApplied=panel.dataset.applied;awaitingSearch=false;requestStatus.hidden=true;
      optimizer.close();document.querySelector('#loadout-tray [data-search-open]')?.focus({preventScroll:true});
    }
  }
  document.addEventListener('click',event=>{
    const open=event.target.closest('[data-search-open]');
    if(open){openOptimizer(open);updateSearch();return;}
    if(event.target.closest('[data-search-close]')){optimizer.close();return;}
    const start=event.target.closest('[data-search-start]');if(!start)return;
    const ongoing=searchPanel()?.dataset.poll==='true';
    openOptimizer(start);
    if(awaitingSearch || ongoing){event.preventDefault();event.stopImmediatePropagation();return;}
    previousJob=searchPanel()?.dataset.job || '';awaitingSearch=true;
    requestStatus.textContent='Starting search…';requestStatus.hidden=false;searchPanel().hidden=true;
    optimizer.scrollTop=0;requestStatus.scrollIntoView({block:'nearest'});updateSearch();
  },true);
  optimizer.addEventListener('close',()=>{if(searchOpener?.isConnected)searchOpener.focus({preventScroll:true});});
  document.addEventListener('datastar-fetch',event=>{
    const {type,el}=event.detail;
    if(type==='finished' && el?.id==='import-scenario')setTimeout(()=>{
      const documentText=document.getElementById('workspace-data')?.dataset.json;
      if(!documentText)return;
      try{
        const scenario=JSON.parse(documentText).scenario;
        const layout=scenario.target.kind==='champion'?'matchup':'legacy';
        if(app.dataset.layout!==layout){const url=new URL('/',location.origin);url.searchParams.set('scenario',documentText);location.assign(url);}
      }catch{}
    },0);
    if(type==='finished' && el?.matches('[data-search-start]'))setTimeout(()=>{
      updateSearch();
      if(awaitingSearch){
        awaitingSearch=false;requestStatus.textContent='The search could not start. Please retry.';
        searchPanel().hidden=false;updateSearch();
      }
    },0);
  });
  new MutationObserver(records=>{
    if(records.some(record=>record.target.closest?.('#search-panel') || [...record.addedNodes].some(node=>node.nodeType===1 && (node.id==='search-panel' || node.querySelector?.('#search-panel')))))updateSearch();
  }).observe(optimizer,{subtree:true,childList:true,attributes:true,attributeFilter:['data-job','data-poll','data-error','data-applied']});

  // Persistence carries Janet's canonical scenario; it does not calculate combat.
  const savesKey = 'powerspike.scenarios.v1';
  const storageStatus = text => { const node = document.getElementById('scenario-storage-status'); if (node) node.textContent = text; };
  function localSaves() {
    const value = JSON.parse(localStorage.getItem(savesKey) || '[]');
    if (!Array.isArray(value) || value.length > 50) throw new Error('Local save collection is invalid.');
    return value;
  }
  function populateSaves() {
    const select = document.getElementById('saved-scenarios');
    if (!select) return;
    const saves = localSaves();
    if (select.options.length === saves.length+1 && saves.every((entry,index)=>select.options[index+1].value===entry.id && select.options[index+1].text===entry.name)) return;
    const selected = select.value;
    const first = new Option('Choose a local save', '');
    select.replaceChildren(first);
    for (const entry of saves) select.add(new Option(entry.name, entry.id));
    select.value = selected;
  }
  function canonicalDocument() {
    if(app.dataset.stale==='true')throw new Error('Run the matchup before saving or sharing the changed configuration.');
    if (document.getElementById('results')?.dataset.evaluationError === 'true' ||
        !document.getElementById('scenario')?.checkValidity()) {
      throw new Error('Fix the scenario and wait for an updated result before saving or sharing.');
    }
    const text = document.getElementById('workspace-data')?.dataset.json;
    if (!text || text.length > 65536) throw new Error('No completed scenario is available to save.');
    return text;
  }
  function importText(text) {
    if (new TextEncoder().encode(text).length > 65536) throw new Error('Scenario JSON must fit within 64 KB.');
    const input = document.getElementById('scenario-json');
    input.value = text;
    input.dispatchEvent(new Event('input', {bubbles:true}));
  }
  document.addEventListener('click', async event => {
    const button = event.target.closest('[data-scenario-action]');
    if (!button || button.disabled) return;
    try {
      const action = button.dataset.scenarioAction;
      if (action === 'save') {
        const saves = localSaves();
        if (saves.length >= 50) throw new Error('Fifty local saves retained; export or remove an older save first.');
        const documentText = canonicalDocument();
        const scenario = JSON.parse(documentText).scenario;
        const name = document.getElementById('scenario-name').value.trim().slice(0,80) || `${scenario.player.champion} · ${scenario.patch}`;
        saves.unshift({id:crypto.randomUUID(), name, document:documentText});
        const bytes = JSON.stringify(saves);
        if (new TextEncoder().encode(bytes).length > 2*1024*1024) throw new Error('Local save allowance reached. Export or remove an older save.');
        localStorage.setItem(savesKey, bytes);
        populateSaves(); storageStatus('Saved in this browser.');
      } else if (action === 'export') {
        const href = URL.createObjectURL(new Blob([canonicalDocument()], {type:'application/json'}));
        const anchor = document.createElement('a');
        anchor.href = href; anchor.download = 'powerspike-scenario.json'; anchor.click();
        setTimeout(()=>URL.revokeObjectURL(href),1000); storageStatus('Scenario exported.');
      } else if (action === 'share') {
        const url = new URL('/', location.origin); url.searchParams.set('scenario', canonicalDocument());
        if (url.href.length > 16000) throw new Error('This scenario exceeds the share-link allowance. Export JSON instead.');
        document.getElementById('scenario-link').value = url.href;
        storageStatus('Share link ready. Select and copy the link above.');
      } else if (action === 'load' || action === 'remove') {
        const id = document.getElementById('saved-scenarios').value;
        const saves = localSaves(), entry = saves.find(value=>value.id===id);
        if (!entry) throw new Error('Choose a local save.');
        if (action === 'remove') {
          localStorage.setItem(savesKey, JSON.stringify(saves.filter(value=>value.id!==id)));
          populateSaves(); storageStatus('Local save removed.');
        } else {
          importText(entry.document);
          requestAnimationFrame(()=>document.getElementById('import-scenario').click());
        }
      }
    } catch (error) { storageStatus(error.message); }
  });
  document.addEventListener('change', async event => {
    if (event.target.id !== 'scenario-file') return;
    try {
      const file = event.target.files?.[0];
      if (!file) return;
      if (file.size > 65536) throw new Error('Scenario JSON must fit within 64 KB.');
      importText(await file.text()); storageStatus('JSON loaded. Select Load scenario to apply it.');
    } catch (error) { storageStatus(error.message); }
  });
  try { populateSaves(); } catch (error) { storageStatus(error.message); }
  new MutationObserver(records=>{
    if (records.some(record=>record.target.closest?.('#scenario-tools') || Array.from(record.addedNodes).some(node=>node.nodeType===1 && (node.id==='scenario-tools' || node.querySelector?.('#saved-scenarios'))))) {
      try { populateSaves(); } catch(error) { storageStatus(error.message); }
    }
  }).observe(app,{subtree:true,childList:true});

  // Graph geometry and linked inspection live in hud.js. Catalog filtering and
  // canonical scenario persistence above remain independent of those interactions.
})();
