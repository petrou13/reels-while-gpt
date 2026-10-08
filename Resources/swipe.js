(() => {
  if (location.protocol !== 'https:' || !['instagram.com','www.instagram.com'].includes(location.hostname)) return;
  if (window.__rwgPaging) return;
  window.__rwgPaging = true;
  let selected = null, resizing = false, timer, lockedUntil = 0;
  const blocked = () => /\/accounts\//.test(location.pathname) ||
    !!document.querySelector('[role="dialog"], input:focus, textarea:focus, [contenteditable="true"]:focus');
  const videos = () => [...document.querySelectorAll('video')].filter(v => {
    const r = v.getBoundingClientRect(); return r.width > 100 && r.height > 150;
  });
  const active = () => videos().filter(v => {
    const r = v.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight;
  }).sort((a,b) => {
    const visible = v => { const r = v.getBoundingClientRect(); return Math.min(r.bottom,innerHeight)-Math.max(r.top,0); };
    return visible(b)-visible(a);
  })[0];
  const scrollParent = video => {
    let node = video.parentElement;
    while (node && !(node.scrollHeight > node.clientHeight+1 && /auto|scroll/.test(getComputedStyle(node).overflowY))) node = node.parentElement;
    return node || document.scrollingElement;
  };
  const cardFor = (video, scroller) => {
    let card = video.parentElement, last = card;
    while (card && card !== scroller) {
      // Do not resize an ancestor shared by several reels.
      if (card.querySelectorAll('video').length > 1) break;
      last = card;
      if (card.getBoundingClientRect().height >= scroller.clientHeight*0.75) return card;
      card = card.parentElement;
    }
    return last;
  };
  const prepare = video => {
    const scroller = scrollParent(video);
    if (!scroller || scroller.clientHeight < 150 || scroller.scrollHeight <= scroller.clientHeight+50) return null;
    const cards = [...new Set(videos().filter(v => scroller.contains(v)).map(v => cardFor(v,scroller)))];
    if (!cards.length || cards.includes(scroller)) return null;
    scroller.style.scrollSnapType = 'y proximity';
    scroller.style.scrollPaddingTop = '0px';
    scroller.style.overscrollBehaviorY = 'contain';
    scroller.style.overflowAnchor = 'none';
    for (const card of cards) {
      const height = `${scroller.clientHeight}px`;
      Object.assign(card.style,{height,minHeight:height,maxHeight:height,width:'100%',maxWidth:'100%',boxSizing:'border-box',scrollSnapAlign:'start',scrollSnapStop:'always',overflow:'hidden'});
      for (const v of card.querySelectorAll('video')) {
        Object.assign(v.style,{height,maxHeight:height,maxWidth:'100%',width:'100%',objectFit:'cover',objectPosition:'center'});
        for (let wrapper=v.parentElement; wrapper && wrapper!==card; wrapper=wrapper.parentElement) {
          Object.assign(wrapper.style,{height:'100%',maxHeight:'100%',minHeight:'0px',width:'100%',maxWidth:'100%'});
        }
      }
    }
    return {scroller,cards,card:cardFor(video,scroller)};
  };
  const align = () => {
    if (blocked()) return false;
    const video = selected && selected.isConnected ? selected : active();
    if (!video) return false;
    const feed = prepare(video); if (!feed) return false;
    const top = feed.scroller === document.scrollingElement ? 0 : feed.scroller.getBoundingClientRect().top;
    feed.scroller.scrollBy({top:feed.card.getBoundingClientRect().top-top,behavior:'instant'});
    selected = video; notify(); return true;
  };
  const notify = () => {
    const v = blocked() ? null : active(), r = v && v.getBoundingClientRect();
    if (!resizing && Date.now() >= lockedUntil && v) selected = v;
    window.webkit?.messageHandlers?.reelPaging?.postMessage(r ?
      {ready:!!scrollParent(v) && scrollParent(v).scrollHeight > scrollParent(v).clientHeight+1,x:r.left,y:r.top,width:r.width,height:r.height,viewportWidth:innerWidth,viewportHeight:innerHeight} : {ready:false});
  };
  window.__rwgScrollReel = direction => {
    if (blocked() || ![1,-1].includes(direction)) return false;
    const video=active(); if (!video) return false;
    const scroller=scrollParent(video); if (!scroller) return false;
    // Scroll towards unloaded content without changing Instagram's sentinels or fetching private endpoints.
    scroller.style.scrollSnapType='none';
    scroller.scrollBy({top:direction*scroller.clientHeight,behavior:'smooth'});
    return true;
  };
  window.__rwgAlignReel = align;
  window.__rwgStepReel = direction => {
    if (blocked() || ![1,-1].includes(direction) || Date.now() < lockedUntil) return false;
    const video = active(); if (!video) return false;
    const feed = prepare(video); if (!feed) return false;
    const current = feed.card.getBoundingClientRect();
    const candidates = feed.cards.filter(c => c !== feed.card)
      .map(c => ({c,r:c.getBoundingClientRect()}))
      .filter(({r}) => (r.top-current.top)*direction > 50)
      .sort((a,b) => Math.abs(a.r.top-current.top)-Math.abs(b.r.top-current.top));
    const top = feed.scroller === document.scrollingElement ? 0 : feed.scroller.getBoundingClientRect().top;
    // At the loaded edge, yield to Instagram's own scrolling/loading instead of snapping back to the last card.
    if (!candidates.length) return false;
    const target = candidates[0].r.top;
    lockedUntil = Date.now()+450;
    if (candidates.length) selected = candidates[0].c.querySelector('video');
    feed.scroller.scrollBy({top:target-top,behavior:'smooth'});
    setTimeout(() => { const v = active(); if (v) selected = v; notify(); },470);
    return true;
  };
  let initialized = false;
  const fillVideos = () => {
    // Instagram reserves space for its bottom navigation. Contain would letterbox the
    // remaining viewport; cover fills it without stretching or touching the navigation.
    if (blocked()) return;
    for (const v of videos()) {
      Object.assign(v.style,{width:'100%',maxWidth:'100%',objectFit:'cover',objectPosition:'center'});
    }
  };
  const refresh = () => {
    fillVideos();
    if (!initialized && !blocked() && active()) { initialized = true; if (!align()) initialized = false; }
    notify();
  };
  new MutationObserver(refresh).observe(document.documentElement,{childList:true,subtree:true});
  addEventListener('scroll',notify,true);
  addEventListener('resize',() => {
    resizing = true; clearTimeout(timer);
    timer = setTimeout(() => { fillVideos(); align(); resizing = false; notify(); },150);
  });
  addEventListener('focusin',notify); addEventListener('focusout',notify);
  refresh();
})()
