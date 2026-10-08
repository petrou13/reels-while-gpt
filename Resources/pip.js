(() => {
  if (location.protocol !== 'https:' || !['instagram.com','www.instagram.com'].includes(location.hostname)) return 'wrong-page';
  if (/\/accounts\//.test(location.pathname)) return 'login';
  const visible = v => v.getClientRects().length > 0;
  const videos = [...document.querySelectorAll('video')].filter(visible);
  const video = videos.sort((a,b) => b.getBoundingClientRect().height-a.getBoundingClientRect().height)[0];
  if (!video) return 'loading';
  if (document.pictureInPictureElement || video.webkitPresentationMode === 'picture-in-picture') return 'active';
  if (window.__rwgPiPRequested === video) return window.__rwgPiPStatus || 'requesting';
  window.__rwgPiPRequested = video;
  video.muted = true; video.playsInline = true;
  video.play().catch(() => {});
  const button = () => {
    if (document.getElementById('rwg-pip')) return;
    const b = document.createElement('button'); b.id = 'rwg-pip';
    b.textContent = window.__rwgLanguage === 'en' ? '▶ Watch over ChatGPT' : '▶ Смотреть поверх ChatGPT';
    b.style.cssText = 'position:fixed;bottom:28px;left:12px;right:12px;z-index:2147483647;padding:16px;border:0;border-radius:14px;background:#743cff;color:white;font:600 16px system-ui;cursor:pointer';
    b.onclick = () => { window.__rwgPiPRequested = null; window.__rwgPiPStatus = null; window.__rwgPiPEnter(); };
    document.body.appendChild(b);
  };
  const failure = () => { window.__rwgPiPStatus = 'gesture'; button(); };
  window.__rwgPiPEnter = () => {
    try {
      if (video.requestPictureInPicture && document.pictureInPictureEnabled) {
        window.__rwgPiPStatus = 'requesting';
        video.requestPictureInPicture().then(() => { window.__rwgPiPStatus = 'active'; document.getElementById('rwg-pip')?.remove(); }).catch(failure);
      } else if (video.webkitSupportsPresentationMode && video.webkitSupportsPresentationMode('picture-in-picture')) {
        video.webkitSetPresentationMode('picture-in-picture');
        window.__rwgPiPStatus = video.webkitPresentationMode === 'picture-in-picture' ? 'active' : 'gesture';
        if (window.__rwgPiPStatus !== 'active') button();
      } else { window.__rwgPiPStatus = 'unsupported'; }
    } catch (_) { failure(); }
  };
  window.__rwgPiPEnter();
  return window.__rwgPiPStatus || 'requesting';
})()
