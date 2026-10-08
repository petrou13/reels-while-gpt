(() => {
  if (location.protocol !== 'https:' || !['chatgpt.com','chat.openai.com'].includes(location.hostname)) return 'unknown';
  const visible = e => !!e && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden';
  const buttons = [...document.querySelectorAll('button,[role="button"]')].filter(visible);
  const label = e => [e.getAttribute('aria-label'),e.getAttribute('data-testid'),e.getAttribute('title')].filter(Boolean).join(' ').toLowerCase();
  const stop = e => {
    if (e.disabled || e.getAttribute('aria-disabled') === 'true') return false;
    const labels = [e.getAttribute('aria-label'),e.getAttribute('data-testid'),e.getAttribute('title')].filter(Boolean).map(s=>s.toLowerCase().replace(/[_-]/g,' ').trim());
    const s = labels.join(' ');
    if (/stop recording|stop dictat|остановить запись|остановить диктов/.test(s)) return false;
    return labels.some(s => /stop generating|stop generation|stop streaming|stop response|stop turn|stop button|cancel response|cancel generation|остановить|прекратить генерацию|прекратить ответ|interrupt|прервать/.test(s)
      || /^(stop|прекратить)(?:$| \(| \[| esc$)/.test(s));
  };
  if (buttons.some(stop)) return 'busy';
  const composer = document.querySelector('#prompt-textarea');
  const ready = buttons.some(e => /send-button|send prompt|send message|отправить|voice|голос|dictate|диктов/.test(label(e)));
  return visible(composer) && ready ? 'idle' : 'unknown';
})()
