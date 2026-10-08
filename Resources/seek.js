(() => {
  if (location.protocol !== 'https:' || !['instagram.com','www.instagram.com'].includes(location.hostname)) return;
  if (window.__rwgSeek) return;
  window.__rwgSeek = true;
  const ids = new WeakMap(); let nextID=1;
  const id = v => { if (!ids.has(v)) ids.set(v,nextID++); return ids.get(v); };
  const area = v => { const r=v.getBoundingClientRect(); return Math.max(0,Math.min(r.bottom,innerHeight)-Math.max(r.top,0))*Math.max(0,Math.min(r.right,innerWidth)-Math.max(r.left,0)); };
  const active = () => [...document.querySelectorAll('video')].filter(v => v.isConnected && v.getClientRects().length).sort((a,b) => area(b)-area(a))[0];
  const valid = v => v && area(v)>0 && Number.isFinite(v.duration) && v.duration>0 && !/\/accounts\//.test(location.pathname) && !window.__rwgSuspended && !document.querySelector('[role="dialog"]');
  const update = () => {
    const v=active();
    window.webkit?.messageHandlers?.reelPaging?.postMessage(valid(v) ?
      {kind:'seek',ready:true,token:id(v),time:v.currentTime,duration:v.duration} : {kind:'seek',ready:false});
  };
  window.__rwgSeekTo = (token,time) => {
    const v=active();
    if (!valid(v) || id(v)!==token || !Number.isFinite(time)) return false;
    time=Math.max(0,Math.min(time,Math.max(0,v.duration-0.01)));
    if (v.seekable && v.seekable.length) {
      let closest=null;
      for (let i=0;i<v.seekable.length;i++) {
        const clamped=Math.max(v.seekable.start(i),Math.min(time,v.seekable.end(i)));
        if (closest===null || Math.abs(clamped-time)<Math.abs(closest-time)) closest=clamped;
      }
      time=closest;
    }
    try { v.currentTime=time; update(); return true; } catch (_) { return false; }
  };
  window.__rwgSeekUpdate=update;
  setInterval(update,250); update();
})();
