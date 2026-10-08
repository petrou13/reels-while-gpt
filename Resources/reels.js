(() => {
  if (location.protocol !== 'https:' || !['instagram.com','www.instagram.com'].includes(location.hostname)) return 'skip';
  if (/\/accounts\//.test(location.pathname)) return 'login';
  if (window.__reelsWhileGPTAutoplay) return 'ready';
  window.__reelsWhileGPTAutoplay = true;
  const play = () => { if (window.__rwgSuspended) return; document.querySelectorAll('video').forEach(video => {
    if (!video.getClientRects().length || video.dataset.rwgAutoplay) return;
    video.dataset.rwgAutoplay = '1';
    video.muted = window.__rwgMuted !== false;
    video.playsInline = true;
    const attempt = video.play();
    if (attempt && attempt.catch) attempt.catch(() => {});
  }); };
  window.__rwgResume = () => {
    if (window.__rwgSuspended) return;
    const visible = [...document.querySelectorAll('video')].filter(v => {
      if (!v.getClientRects().length) return false;
      const r = v.getBoundingClientRect(); return r.top < innerHeight && r.bottom > 0;
    }).sort((a,b) => {
      const area = v => { const r=v.getBoundingClientRect(); return Math.min(r.bottom,innerHeight)-Math.max(r.top,0); };
      return area(b)-area(a);
    });
    document.querySelectorAll('video').forEach(v => {
      if (v !== visible[0]) { v.pause(); return; }
      v.muted = window.__rwgMuted !== false;
      v.playsInline = true;
      const attempt = v.play(); if (attempt && attempt.catch) attempt.catch(() => {});
    });
  };
  // Instagram may recycle a video element with a new source. Re-evaluate the visible player after DOM changes.
  let resumeTimer;
  const observer = new MutationObserver(() => { clearTimeout(resumeTimer); resumeTimer=setTimeout(() => window.__rwgResume(),100); });
  observer.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['src']});
  addEventListener('scroll',() => window.__rwgResume(),true);
  play();
  return 'ready';
})()
