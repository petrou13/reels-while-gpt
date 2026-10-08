const vm = require('node:vm'), fs = require('node:fs'), assert = require('node:assert/strict');
const script = fs.readFileSync(__dirname+'/../Resources/swipe.js','utf8');
let checks = 0;
function fixture({login=false,dialog=false,next=true,scrollable=true,offset=0}={}) {
  const calls=[], notices=[], handlers={}, timers=[];
  let height=640, currentOffset=offset, now=1000, mutation;
  const scroller={style:{},scrollHeight:scrollable?2000:640,get clientHeight(){return height},parentElement:null,contains:()=>true,
    getBoundingClientRect:()=>({top:0}),scrollBy:x=>calls.push(x)};
  const card={style:{},parentElement:scroller,getBoundingClientRect:()=>({top:currentOffset,height}),querySelectorAll:()=>[video],querySelector:()=>video};
  const otherCard={style:{},parentElement:scroller,getBoundingClientRect:()=>({top:currentOffset+height,height}),querySelectorAll:()=>[other],querySelector:()=>other};
  const video={style:{},isConnected:true,parentElement:card,getBoundingClientRect:()=>({left:0,top:currentOffset,bottom:currentOffset+height,width:360,height})};
  const other={style:{},isConnected:true,parentElement:otherCard,getBoundingClientRect:()=>({left:0,top:currentOffset+height,bottom:currentOffset+height*2,width:360,height})};
  const ctx={location:{protocol:'https:',hostname:'www.instagram.com',pathname:login?'/accounts/login/':'/reels/'},innerHeight:640,innerWidth:360,
    document:{querySelector:()=>dialog?{}:null,querySelectorAll:()=>next?[video,other]:[video],scrollingElement:scroller,documentElement:{}},
    getComputedStyle:e=>({overflowY:e===scroller?'auto':'visible'}),MutationObserver:class{constructor(fn){mutation=fn;}observe(){}},
    addEventListener:(key,fn)=>handlers[key]=fn,setTimeout:fn=>{timers.push(fn);return timers.length},clearTimeout:()=>{},Date:{now:()=>now},
    window:{webkit:{messageHandlers:{reelPaging:{postMessage:x=>notices.push(x)}}}}};
  vm.runInNewContext(script,ctx);
  calls.length = 0;
  return {ctx,calls,notices,card,otherCard,video,scroller,handlers,timers,
    loadMore:()=>{next=true;mutation();},resize:h=>{height=h;ctx.innerHeight=h;handlers.resize();timers.at(-1)()},advance:()=>now+=1000,offset:x=>currentOffset=x};
}
let f=fixture(); assert.equal(f.ctx.window.__rwgStepReel(1),true); assert.equal(f.calls[0].top,640);checks++;
f=fixture({next:false});assert.equal(f.ctx.window.__rwgStepReel(1),false);assert.equal(f.calls.length,0);assert.equal(f.ctx.window.__rwgScrollReel(1),true);assert.equal(f.calls[0].top,640);checks++;
f=fixture({next:false});assert.equal(f.ctx.window.__rwgStepReel(-1),false);f.ctx.window.__rwgScrollReel(-1);assert.equal(f.calls[0].top,-640);checks++;
f=fixture({login:true});assert.equal(f.ctx.window.__rwgStepReel(1),false);assert.equal(f.notices[0].ready,false);checks++;
f=fixture({dialog:true});assert.equal(f.ctx.window.__rwgStepReel(1),false);assert.equal(f.calls.length,0);checks++;
f=fixture({next:false,scrollable:false});assert.equal(f.ctx.window.__rwgStepReel(1),false);checks++;
f=fixture();assert.equal(f.ctx.window.__rwgStepReel(7),false);checks++;
f=fixture({offset:-130});f.resize(480);assert.equal(f.card.style.height,'480px');assert.equal(f.otherCard.style.height,'480px');assert.equal(f.calls.at(-1).top,-130);checks++;
assert.equal(f.video.style.height,'480px');assert.equal(f.video.style.objectFit,'cover');checks++;
f.ctx.window.__rwgStepReel(1);assert.equal(f.calls.at(-1).top,350,'target aligns the next card, not an accumulated video offset');checks++;
const count=f.calls.length;assert.equal(f.ctx.window.__rwgStepReel(1),false);assert.equal(f.calls.length,count);checks++;
f=fixture();f.resize(800);assert.equal(f.card.style.height,'800px');assert.equal(f.calls.at(-1).behavior,'instant');checks++;
f=fixture({dialog:true});f.resize(480);assert.equal(f.calls.length,0);assert.equal(f.card.style.height,undefined);checks++;
f=fixture({next:false});assert.equal(f.ctx.window.__rwgStepReel(1),false);f.ctx.window.__rwgScrollReel(1);f.loadMore();f.advance();assert.equal(f.ctx.window.__rwgStepReel(1),true);assert.equal(f.calls.at(-1).top,640);checks++;
f=fixture({next:false,scrollable:false});assert.equal(f.notices.at(-1).ready,false,'non-scrollable feed leaves gestures to Instagram');checks++;
f=fixture({next:false,scrollable:false});assert.equal(f.video.style.objectFit,'cover','video fills its container even before feed scrolling is available');assert.equal(f.video.style.width,'100%');checks++;
f=fixture({login:true});assert.equal(f.video.style.objectFit,undefined,'sign-in page is untouched');checks++;
console.log(`PASS: ${checks} Reel paging and resize checks`);
