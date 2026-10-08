const fs = require('fs'), vm = require('vm'), assert = require('assert');
const source = fs.readFileSync(__dirname + '/../Resources/pip.js','utf8');
let checks = 0;
const eq = (a,b) => { assert.equal(a,b); checks++; };
function fixture() {
  const elements = new Map();
  const video = {getClientRects:()=>[1],getBoundingClientRect:()=>({height:600}),play:()=>Promise.resolve()};
  const document = {pictureInPictureEnabled:true,querySelectorAll:()=>[video],getElementById:id=>elements.get(id),
    createElement:()=>({style:{},remove(){elements.delete(this.id);}}),body:{appendChild:b=>elements.set(b.id,b)}};
  const context = {location:{protocol:'https:',hostname:'www.instagram.com',pathname:'/reels/'},document,window:{}};
  return {context,document,video,elements};
}
(async () => {
  let f=fixture(), requests=0;
  f.video.requestPictureInPicture=()=>{requests++;f.document.pictureInPictureElement=f.video;return Promise.resolve();};
  eq(vm.runInNewContext(source,f.context),'requesting');
  await Promise.resolve(); await Promise.resolve();
  eq(vm.runInNewContext(source,f.context),'active'); eq(requests,1);
  f=fixture(); f.context.location.pathname='/accounts/login/';
  eq(vm.runInNewContext(source,f.context),'login');
  f=fixture(); f.context.location.hostname='example.com';
  eq(vm.runInNewContext(source,f.context),'wrong-page');
  f=fixture(); f.document.querySelectorAll=()=>[];
  eq(vm.runInNewContext(source,f.context),'loading');
  f=fixture(); eq(vm.runInNewContext(source,f.context),'unsupported');
  f=fixture(); f.video.webkitSupportsPresentationMode=()=>true;
  f.video.webkitSetPresentationMode=mode=>{f.video.webkitPresentationMode=mode;};
  eq(vm.runInNewContext(source,f.context),'active');
  f=fixture(); f.video.requestPictureInPicture=()=>Promise.reject(new Error('gesture required'));
  vm.runInNewContext(source,f.context); await Promise.resolve(); await Promise.resolve();
  eq(f.context.window.__rwgPiPStatus,'gesture');
  eq(f.elements.get('rwg-pip').textContent,'▶ Смотреть поверх ChatGPT');
  f.video.requestPictureInPicture=()=>{f.document.pictureInPictureElement=f.video;return Promise.resolve();};
  f.elements.get('rwg-pip').onclick(); await Promise.resolve(); await Promise.resolve();
  eq(f.context.window.__rwgPiPStatus,'active'); eq(f.elements.has('rwg-pip'),false);
  f=fixture(); f.context.window.__rwgLanguage='en';f.video.requestPictureInPicture=()=>Promise.reject(new Error('gesture'));
  vm.runInNewContext(source,f.context);await Promise.resolve();await Promise.resolve();eq(f.elements.get('rwg-pip').textContent,'▶ Watch over ChatGPT');
  console.log(`PASS: ${checks} PiP, Safari, gesture and login isolation cases`);
})().catch(error=>{console.error(error);process.exit(1);});
