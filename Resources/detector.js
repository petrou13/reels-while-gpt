(() => {
  if (location.protocol !== 'https:' || !['chatgpt.com','chat.openai.com'].includes(location.hostname)) return 'unknown';
  const visible = e => !!e && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden';
  const buttons = [...document.querySelectorAll('button,[role="button"]')].filter(visible);
  const label = e => [e.getAttribute('aria-label'),e.getAttribute('data-testid'),e.getAttribute('title')].filter(Boolean).join(' ').toLowerCase();
  const stop = /stop generating|stop generation|stop streaming|остановить генерацию|прекратить генерацию|остановить ответ|stop-button/;
  if (buttons.some(e => stop.test(label(e)))) return 'busy';
  const composer = document.querySelector('#prompt-textarea');
  const ready = buttons.some(e => /send-button|send prompt|send message|отправить|voice|голос|dictate|диктов/.test(label(e)));
  return visible(composer) && ready ? 'idle' : 'unknown';
})()
