/* Presentation only: patch descriptions, graph geometry and linked trace inspection. */
(() => {
  const app=document.getElementById('powerspike');
  const htmlNode=(tag,className,text)=>{
    const node=document.createElement(tag);
    if(className)node.className=className;
    if(text!==undefined)node.textContent=String(text);
    return node;
  };
  function reveal(node) {
    for(let parent=node;parent && parent!==app;parent=parent.parentElement)if(parent instanceof HTMLDetailsElement)parent.open=true;
    node?.scrollIntoView({block:'nearest'});
  }
  document.addEventListener('click',event=>{
    const button=event.target.closest('[data-ui-toggle]');
    if(!button)return;
    const target=document.getElementById(button.dataset.uiToggle);
    if(!target)return;
    if(target.open)target.open=false;else reveal(target);
    button.setAttribute('aria-expanded',String(target.open));
  });

  // Provider markup is text, never executable HTML. Each payload comes from the
  // selected patch package and carries its own availability/coverage statement.
  const popover=document.getElementById('detail-popover');
  const nativePopover=typeof popover.showPopover==='function';
  if(!nativePopover){popover.removeAttribute('popover');popover.hidden=true;}
  let calculationId=0;
  function closeCalculations() {
    popover.querySelectorAll('.tooltip-calculation').forEach(node=>{
      if(nativePopover && node.matches(':popover-open'))node.hidePopover();
      if(!nativePopover)node.hidden=true;
    });
    popover.querySelectorAll('.tooltip-value').forEach(node=>node.setAttribute('aria-expanded','false'));
  }
  function calculatedValue(segment) {
    const term=htmlNode('span','tooltip-term'),value=htmlNode('button','tooltip-value',segment.text);
    const calculation=htmlNode('span','tooltip-calculation',segment.calculation);
    value.type='button';value.setAttribute('aria-label',`${segment.text}: show calculation`);
    calculation.id=`tooltip-calculation-${++calculationId}`;calculation.setAttribute('role','tooltip');
    value.setAttribute('aria-describedby',calculation.id);value.setAttribute('aria-expanded','false');
    if(nativePopover)calculation.setAttribute('popover','manual');else calculation.hidden=true;
    let timer,pinned=false;
    const hide=()=>{clearTimeout(timer);if(nativePopover && calculation.matches(':popover-open'))calculation.hidePopover();if(!nativePopover)calculation.hidden=true;value.setAttribute('aria-expanded','false');};
    const show=()=>{
      clearTimeout(timer);closeCalculations();
      if(nativePopover)calculation.showPopover();else calculation.hidden=false;
      value.setAttribute('aria-expanded','true');
      const rect=value.getBoundingClientRect(),width=calculation.offsetWidth,height=calculation.offsetHeight;
      calculation.style.left=`${Math.max(12,Math.min(innerWidth-width-12,rect.left))}px`;
      calculation.style.top=`${Math.max(12,rect.bottom+8+height<innerHeight-12?rect.bottom+8:rect.top-height-8)}px`;
    };
    value.addEventListener('pointerenter',event=>{if(event.pointerType!=='touch')show();});
    value.addEventListener('pointerleave',()=>{if(!pinned && document.activeElement!==value)timer=setTimeout(hide,180);});
    value.addEventListener('focus',show);
    value.addEventListener('blur',()=>{pinned=false;hide();});
    value.addEventListener('click',()=>{pinned=!pinned;if(pinned)show();else hide();});
    calculation.addEventListener('pointerenter',()=>clearTimeout(timer));
    calculation.addEventListener('pointerleave',()=>{if(!pinned && document.activeElement!==value)timer=setTimeout(hide,180);});
    term.append(value,calculation);return term;
  }
  let detailAnchor=null,detailPinned=false,detailTimer,restoringFocus=false;
  let detailRequest=null;
  const itemDetailsCache=new Map();
  function closeDetails() {
    detailRequest?.abort();detailRequest=null;
    closeCalculations();
    clearTimeout(detailTimer);detailAnchor?.removeAttribute('aria-expanded');detailAnchor?.removeAttribute('aria-controls');
    detailAnchor=null;detailPinned=false;
    if(nativePopover && popover.matches(':popover-open'))popover.hidePopover();
    if(!nativePopover)popover.hidden=true;
  }
  function positionDetails() {
    if(!detailAnchor?.isConnected){closeDetails();return;}
    const anchor=detailAnchor.getBoundingClientRect(),width=popover.offsetWidth,height=popover.offsetHeight;
    let left=anchor.right+12;
    if(left+width>innerWidth-12)left=anchor.left-width-12;
    popover.style.left=`${Math.max(12,Math.min(innerWidth-width-12,left))}px`;
    popover.style.top=`${Math.max(12,Math.min(innerHeight-height-12,anchor.top))}px`;
  }
  function showDetails(trigger,pin=false,payload=null) {
    if(detailPinned && detailAnchor!==trigger && !pin)return;
    clearTimeout(detailTimer);
    if(!payload && pin && detailAnchor===trigger && detailPinned){closeDetails();return;}
    let data;try{data=payload || JSON.parse(trigger.dataset.details);}catch{return;}
    const scenario=document.getElementById('scenario-data')?.dataset.json;
    const who=trigger.closest('#item-picker')?.dataset.who || 'player';
    const cacheKey=trigger.dataset.detailItem && scenario?JSON.stringify([trigger.dataset.detailItem,who,scenario]):null;
    if(!payload && cacheKey && itemDetailsCache.has(cacheKey))data=itemDetailsCache.get(cacheKey);
    detailRequest?.abort();detailRequest=null;
    const host=trigger.closest('dialog[open]') || app;
    if(popover.parentElement!==host){
      if(nativePopover && popover.matches(':popover-open'))popover.hidePopover();
      host.append(popover);
    }
    detailAnchor?.removeAttribute('aria-expanded');detailAnchor=trigger;detailPinned=pin;
    trigger.setAttribute('aria-expanded','true');trigger.setAttribute('aria-controls','detail-popover');
    const header=htmlNode('div','detail-heading');
    if(data.icon){const image=htmlNode('img');image.src=data.icon;image.alt='';header.append(image);}
    const title=htmlNode('div');title.append(htmlNode('h2','',data.name),htmlNode('span','muted',data.subtitle));header.append(title);
    const close=htmlNode('button','detail-close','×');close.type='button';close.setAttribute('aria-label','Close details');close.addEventListener('click',closeDetails);header.append(close);
    const stats=htmlNode('dl','detail-stats');for(const [label,value] of data.stats || [])stats.append(htmlNode('dt','',label),htmlNode('dd','',value));
    closeCalculations();
    const body=htmlNode('div','detail-body');
    if(data['body-rich'])for(const line of data['body-rich']){
      const text=line.map(segment=>segment.text).join(''),paragraph=htmlNode('p',text.length<45 && !text.includes('.')?'detail-effect-label':'');
      for(const segment of line)paragraph.append(segment.calculation?calculatedValue(segment):document.createTextNode(segment.text));
      body.append(paragraph);
    }else for(const line of data.body || [])body.append(htmlNode('p',line.length<45 && !line.includes('.')?'detail-effect-label':'',line));
    popover.replaceChildren(header,stats,body,htmlNode('p','detail-coverage',data.coverage || 'Unvalidated patch description.'));
    if(['champion-picker','item-picker','ability-settings','rune-editor'].includes(data.action)){
      const button=htmlNode('button','detail-action',trigger.classList.contains('catalog-card')?'Choose item':data['action-label']);button.type='button';
      button.addEventListener('click',()=>{const anchor=detailAnchor;closeDetails();if(data.action.endsWith('-picker'))anchor?.click();else reveal(document.getElementById(data.action));});popover.append(button);
    }
    if(nativePopover && !popover.matches(':popover-open'))popover.showPopover();
    if(!nativePopover)popover.hidden=false;
    positionDetails();
    if(!payload && cacheKey && !itemDetailsCache.has(cacheKey)){
      const request=new AbortController();detailRequest=request;
      fetch(`/details/item?id=${encodeURIComponent(trigger.dataset.detailItem)}&who=${who}`,{
        method:'POST',headers:{'Content-Type':'application/json'},body:scenario,signal:request.signal
      }).then(response=>{if(!response.ok)throw new Error('Item details unavailable');return response.json();}).then(details=>{
        if(request.signal.aborted || detailAnchor!==trigger)return;
        if(itemDetailsCache.size>=64)itemDetailsCache.delete(itemDetailsCache.keys().next().value);
        itemDetailsCache.set(cacheKey,details);showDetails(trigger,detailPinned,details);
      }).catch(()=>{});
    }
  }
  document.addEventListener('pointerover',event=>{const trigger=event.target.closest('[data-details]');if(trigger && !trigger.contains(event.relatedTarget) && event.pointerType!=='touch')showDetails(trigger);});
  document.addEventListener('pointerout',event=>{const trigger=event.target.closest('[data-details]');if(trigger && !trigger.contains(event.relatedTarget) && !detailPinned)detailTimer=setTimeout(closeDetails,180);});
  document.addEventListener('focusin',event=>{const trigger=event.target.closest('[data-details]');if(trigger && !restoringFocus)showDetails(trigger);});
  document.addEventListener('focusout',event=>{if(detailAnchor?.contains(event.target) && !popover.contains(event.relatedTarget) && !detailPinned)detailTimer=setTimeout(closeDetails,180);});
  document.addEventListener('click',event=>{const trigger=event.target.closest('[data-details]');if(trigger?.dataset.detailPin==='true')showDetails(trigger,true);else if(!trigger && !popover.contains(event.target))closeDetails();});
  document.addEventListener('close',event=>{if(detailAnchor?.closest('dialog')===event.target){closeDetails();app.append(popover);}},true);
  popover.addEventListener('pointerenter',()=>clearTimeout(detailTimer));
  popover.addEventListener('focusin',()=>clearTimeout(detailTimer));
  popover.addEventListener('focusout',event=>{if(!popover.contains(event.relatedTarget) && !detailPinned)detailTimer=setTimeout(closeDetails,180);});
  popover.addEventListener('pointerleave',()=>{if(!detailPinned)detailTimer=setTimeout(closeDetails,180);});
  window.addEventListener('resize',()=>{closeCalculations();if(detailAnchor)positionDetails();});
  window.addEventListener('scroll',()=>{closeCalculations();if(detailAnchor)positionDetails();},{capture:true,passive:true});

  const ns='http://www.w3.org/2000/svg',format=value=>new Intl.NumberFormat('en-US',{maximumFractionDigits:0}).format(value);
  function element(name,attrs,text) {
    const node=document.createElementNS(ns,name);for(const [key,value] of Object.entries(attrs))node.setAttribute(key,String(value));
    if(text!==undefined)node.textContent=text;return node;
  }
  let events=[],trace=[],plots=[],selected=null,pinned=null,traceIdentity='';
  const signature=event=>JSON.stringify([event.at,event.source,event.actor,event.target,event.damage,event.origin]);
  function highlight(index,pin=false) {
    if(pin)pinned=pinned===index?null:index;
    selected=index;
    const hits=[...document.querySelectorAll('#attack-events [data-event]')];hits.forEach((hit,i)=>hit.setAttribute('aria-pressed',String(i===index)));
    for(const plot of plots)plot.highlight(index);
    const detail=document.getElementById('event-detail');if(!detail)return;
    if(index===null || !events[index]){detail.replaceChildren(htmlNode('span','muted','Hover or select an attack to inspect its damage and state changes.'));detail.classList.remove('has-event');return;}
    const event=events[index],source=event.source==='attack'?'Basic attack':String(event.source),record=trace[event.traceIndex];
    const heading=htmlNode('div','event-heading'),original=hits[index]?.querySelector('img');
    if(original){const image=original.cloneNode();image.alt='';heading.append(image);}
    const label=htmlNode('div');label.append(htmlNode('strong','',event.label || source),htmlNode('span','muted',`${event.type || 'Damage'} · ${event.at.toFixed(2)} s${event.critical?' · critical strike':''}${pinned===index?' · pinned':''}`));heading.append(label);
    const metrics=htmlNode('div','event-values');metrics.append(htmlNode('strong','',`${format(event.damage)} damage`));
    if(Number(event.absorbed)>0)metrics.append(htmlNode('span','muted',`${format(event.absorbed)} absorbed`));
    if(record)for(const [i,actor] of record.participants.entries()){
      const before=record.before?.[i] || actor;
      const health=before.health!==actor.health?`HP ${format(before.health)} → ${format(actor.health)}`:'';
      const resource=before.resource!==actor.resource?`resource ${format(before.resource)} → ${format(actor.resource)}`:'';
      if(health || resource)metrics.append(htmlNode('span','muted',`${actor.id}: ${[health,resource].filter(Boolean).join(' · ')}`));
    }
    const clear=htmlNode('button','quiet-action','×');clear.type='button';clear.setAttribute('aria-label','Clear highlighted attack');clear.addEventListener('click',()=>{pinned=null;highlight(null);});
    detail.classList.add('has-event');detail.replaceChildren(heading,metrics,clear);
  }
  function buildPlot(box,field,duration) {
    const width=Math.max(200,box.clientWidth),height=field==='damage'?210:155,left=48,right=12,top=12,bottom=30;
    const values=field==='damage'?events.map(e=>e.cumulative):trace.flatMap(event=>[...(event.before || []),...event.participants].map(actor=>actor[field] || 0));
    const ceiling=values.reduce((max,value)=>Math.max(max,value),1)*1.12;
    const x=time=>left+time/duration*(width-left-right),y=value=>height-bottom-value/ceiling*(height-top-bottom);
    const svg=element('svg',{viewBox:`0 0 ${width} ${height}`,role:'img','aria-label':box.dataset.label || field,class:field==='damage'?'damage-chart':'state-chart'});
    svg.append(element('title',{},`${box.dataset.label || field}, trial 0. Select attacks in the event list for linked details.`));
    for(const fraction of [0,.5,1]){const value=fraction*ceiling;svg.append(element('line',{x1:left,x2:width-right,y1:y(value),y2:y(value),class:'chart-grid'}),element('text',{x:left-7,y:y(value)+4,'text-anchor':'end'},format(value)));}
    const ticks=width<380?[0,duration/2,duration]:[0,duration/4,duration/2,3*duration/4,duration];
    for(const time of ticks)svg.append(element('text',{x:x(time),y:height-7,'text-anchor':time===0?'start':time===duration?'end':'middle'},`${Number(time.toFixed(2))} s`));
    const series=field==='damage'?1:2;
    for(let actor=0;actor<series;actor++){
      let path;
      if(field==='damage'){path=`M ${x(0)} ${y(0)}`;for(const event of events)path+=` H ${x(event.at)} V ${y(event.cumulative)}`;path+=` H ${x(duration)}`;}
      else{
        const initial=trace[0]?.before?.[actor]?.[field] ?? trace[0]?.participants?.[actor]?.[field] ?? 0;path=`M ${x(0)} ${y(initial)}`;
        for(const event of trace)path+=` L ${x(event.at)} ${y(event.before?.[actor]?.[field] ?? event.participants[actor][field] ?? 0)} V ${y(event.participants[actor][field] ?? 0)}`;
        path+=` H ${x(duration)}`;
      }
      svg.append(element('path',{d:path,class:actor===0?'chart-line':'chart-opponent'}));
    }
    if(field==='damage')for(const event of events)svg.append(element('circle',{cx:x(event.at),cy:y(event.cumulative),r:2.5,class:'chart-point'}));
    const guide=element('line',{y1:top,y2:height-bottom,class:'chart-hover-guide'}),marks=Array.from({length:series},()=>({point:element('circle',{r:4,class:'chart-hover-point'}),step:element('path',{class:'chart-hover-step'})}));svg.append(guide,...marks.flatMap(mark=>[mark.step,mark.point]));
    const overlay=element('rect',{x:left,y:top,width:width-left-right,height:height-top-bottom,class:'chart-hit-area'});svg.append(overlay);
    const nearest=event=>{
      const rect=svg.getBoundingClientRect(),cursor=(event.clientX-rect.left)*width/rect.width;
      let best=0;for(let i=1;i<events.length;i++)if(Math.abs(x(events[i].at)-cursor)<Math.abs(x(events[best].at)-cursor))best=i;
      return events.length?best:null;
    };
    overlay.addEventListener('pointermove',event=>{if(event.pointerType!=='touch')highlight(nearest(event));});overlay.addEventListener('pointerleave',()=>highlight(pinned));overlay.addEventListener('click',event=>highlight(nearest(event),true));box.replaceChildren(svg);
    return {highlight(index){
      const event=events[index],record=event && trace[event.traceIndex],active=index!==null && event && (field==='damage' || record);
      for(const node of [guide,...marks.flatMap(mark=>[mark.point,mark.step])])node.style.display=active?'':'none';if(!active)return;
      guide.setAttribute('x1',x(event.at));guide.setAttribute('x2',x(event.at));
      marks.forEach((mark,actor)=>{
        const before=field==='damage'?event.cumulative-event.damage:record.before?.[actor]?.[field] ?? record.participants[actor][field] ?? 0;
        const after=field==='damage'?event.cumulative:record.participants[actor][field] ?? 0;
        mark.point.setAttribute('cx',x(event.at));mark.point.setAttribute('cy',y(after));mark.step.setAttribute('d',`M ${x(event.at)} ${y(before)} V ${y(after)}`);
      });
    }};
  }
  function draw() {
    const box=document.getElementById('timeline');if(!box)return;
    const traceBox=document.getElementById('combat-trace'),identity=traceBox?.dataset.scenario || box.dataset.events;
    if(identity!==traceIdentity){pinned=null;selected=null;traceIdentity=identity;}
    events=JSON.parse(box.dataset.events);trace=JSON.parse(traceBox?.dataset.trace || '[]');
    const index=new Map();trace.forEach((event,i)=>{if(event.kind!=='damage')return;const key=signature(event);if(!index.has(key))index.set(key,[]);index.get(key).push(i);});
    let cumulative=0;events.forEach((event,i)=>{cumulative+=event.damage;event.cumulative=cumulative;event.traceIndex=index.get(signature(event))?.shift();event.label=document.querySelector(`#attack-events [data-event="${i}"]`)?.dataset.label;});
    const duration=Number(box.dataset.duration);plots=[buildPlot(box,'damage',duration),...[...document.querySelectorAll('[data-state-chart]')].map(node=>buildPlot(node,node.dataset.stateChart,duration))];highlight(selected);
    if(detailAnchor && !detailAnchor.isConnected)closeDetails();
  }
  document.addEventListener('pointerover',event=>{const hit=event.target.closest('[data-event]');if(hit && !hit.contains(event.relatedTarget) && event.pointerType!=='touch')highlight(Number(hit.dataset.event));});
  document.addEventListener('pointerout',event=>{const hit=event.target.closest('[data-event]');if(hit && !hit.contains(event.relatedTarget))highlight(pinned);});
  document.addEventListener('focusin',event=>{const hit=event.target.closest('[data-event]');if(hit)highlight(Number(hit.dataset.event));});
  document.addEventListener('focusout',event=>{if(event.target.closest('[data-event]'))highlight(pinned);});
  document.addEventListener('click',event=>{const hit=event.target.closest('[data-event]');if(hit)highlight(Number(hit.dataset.event),true);});
  document.addEventListener('keydown',event=>{if(event.key==='Escape'){const anchor=detailAnchor;closeDetails();pinned=null;highlight(null);if(anchor && event.target.closest('#detail-popover')){restoringFocus=true;anchor.focus();restoringFocus=false;}}});
  let drawScheduled=false;
  function scheduleDraw(){if(drawScheduled)return;drawScheduled=true;requestAnimationFrame(()=>{drawScheduled=false;draw();});}
  draw();new ResizeObserver(scheduleDraw).observe(app);
  new MutationObserver(records=>{
    if(records.some(record=>record.type==='attributes' || !(record.target.nodeType===1?record.target:record.target.parentElement)?.closest('#timeline,[data-state-chart],#event-detail,#detail-popover,#attack-events')))scheduleDraw();
  }).observe(app,{subtree:true,childList:true,attributes:true,attributeFilter:['data-events','data-duration','data-total','data-label','data-trace','data-scenario']});
})();
