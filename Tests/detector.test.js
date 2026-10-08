const fs = require('fs'), vm = require('vm'), assert = require('assert');
const source = fs.readFileSync(__dirname + '/../Resources/detector.js','utf8');
function button(label,testID='',visible=true) {
  return {textContent:'',getAttribute:k => ({'aria-label':label,'data-testid':testID}[k] || null),getClientRects:() => visible ? [1] : []};
}
function detect(buttons=[],composer=true,host='chatgpt.com',protocol='https:') {
  return vm.runInNewContext(source,{
    location:{hostname:host,protocol}, getComputedStyle:() => ({visibility:'visible'}),
    document:{querySelectorAll:() => buttons,querySelector:() => composer ? {getClientRects:() => [1]} : null}
  });
}
const cases = [
  [detect([button('Stop streaming')]),'busy'],
  [detect([button('Stop')]),'busy'],
  [detect([{...button('Stop'),getAttribute:k=>['aria-label','title'].includes(k)?'Stop':null}]),'busy'],
  [detect([{...button('Stop'),getAttribute:k=>k==='aria-label'?'Stop':k==='title'?'Stop recording':null},button('Send prompt')]),'idle'],
  [detect([button('Остановить')]),'busy'],
  [detect([button('Stop response')]),'busy'],
  [detect([button('Interrupt')]),'busy'],
  [detect([button('Stop recording'),button('Send prompt')]),'idle'],
  [detect([button('Остановить диктовку'),button('Send prompt')]),'idle'],
  [detect([Object.assign(button('Stop'),{disabled:true}),button('Send prompt')]),'idle'],
  [detect([{...button('Stop'),getAttribute:k=>k==='aria-disabled'?'true':k==='aria-label'?'Stop':null},button('Send prompt')]),'idle'],
  [detect([button('','stop-button')]),'busy'],
  [detect([button('Остановить генерацию')]),'busy'],
  [detect([button('Send prompt','send-button')]),'idle'],
  [detect([button('Start voice mode')]),'idle'],
  [detect([button('Отправить сообщение')]),'idle'],
  [detect([button('Send prompt'),button('Stop streaming')]),'busy'],
  [detect([button('Stop streaming','',false),button('Send prompt')]),'idle'],
  [detect([],true),'unknown'],
  [detect([button('Send prompt')],false),'unknown'],
  [detect([button('Send prompt')],true,'chatgpt.com.evil.test'),'unknown'],
  [detect([button('Send prompt')],true,'chatgpt.com','http:'),'unknown'],
];
for (const [actual,expected] of cases) assert.equal(actual,expected);
const guarded=button('Send prompt');
Object.defineProperty(guarded,'textContent',{get(){throw new Error('conversation text must not be requested');}});
assert.equal(detect([guarded]),'idle');
cases.push(['idle','idle']);
console.log(`PASS: ${cases.length} DOM detector cases`);
