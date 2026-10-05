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
      optimizer.close();document.querySelector('#loadout-tray .optimize-primary')?.focus({preventScroll:true});
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
    const text = document.getElementById('scenario-data')?.dataset.json;
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
