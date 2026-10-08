const fs = require('fs'), vm = require('vm'), assert = require('assert');
const source = fs.readFileSync(__dirname + '/../Resources/reels.js','utf8');
let queries = 0, plays = 0, mutation, scheduled;
const video = {dataset:{},getClientRects:() => [1],play:() => { plays++; return Promise.resolve(); }};
const context = {
  location:{protocol:'https:',hostname:'www.instagram.com',pathname:'/reels/'},
  addEventListener:()=>{}, innerHeight:640, window:{}, document:{documentElement:{},querySelectorAll:() => { queries++; return [video]; }},
  setTimeout:fn=>{scheduled=fn;return 1;},clearTimeout:()=>{},
  MutationObserver:class { constructor(fn) { mutation=fn; } observe() {} }
};
assert.equal(vm.runInNewContext(source,context),'ready');
assert.equal(plays,1); assert.equal(video.muted,true); assert.equal(video.playsInline,true);
assert.equal(vm.runInNewContext(source,context),'ready'); assert.equal(plays,1);
const login = {...context,window:{},location:{...context.location,pathname:'/accounts/login/'}};
const before = queries;
assert.equal(vm.runInNewContext(source,login),'login'); assert.equal(queries,before);
const unrelated = {...context,window:{},location:{...context.location,hostname:'example.com'}};
assert.equal(vm.runInNewContext(source,unrelated),'skip'); assert.equal(queries,before);
video.getBoundingClientRect=()=>({top:0,bottom:640});video.pause=()=>{};
context.window.__rwgMuted=false;context.window.__rwgResume();assert.equal(video.muted,false);assert.equal(plays,2);
context.window.__rwgSuspended=true;context.window.__rwgResume();assert.equal(plays,2);
context.window.__rwgSuspended=false;context.window.__rwgMuted=true;context.window.__rwgResume();assert.equal(video.muted,true);assert.equal(plays,3);
mutation();scheduled();assert.equal(plays,4,'recycled video resumes after a feed update');
console.log('PASS: 16 Reels autoplay, resume, mute and login isolation assertions');
