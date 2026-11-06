import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const script = readFileSync(new URL('../extension/locked.js', import.meta.url), 'utf8').replace(/^import .*;\n/gm, '');
const settle = () => new Promise(resolve => setImmediate(resolve));
async function page({ visible = true, focused = true, domain = 'example.com', cancel = false, idle = false, unlocked = false } = {}) {
  const listeners = {}, elements = {}, requests = [];
  const navigations = [];
  const $ = selector => elements[selector] ??= { disabled:true, addEventListener(event, callback) { listeners[`${selector}:${event}`] = callback; } };
  const document = { visibilityState:visible?'visible':'hidden',hasFocus:()=>focused,addEventListener:(name,fn)=>listeners[name]=fn };
  vm.runInNewContext(script, { $, document, window:{addEventListener:(name,fn)=>listeners[name]=fn}, location:{hash:'#https://example.com/',replace(url){navigations.push(url);}}, chrome:{runtime:{openOptionsPage(){}},idle:{queryState:async()=>idle?'idle':'active',onStateChanged:{addListener:fn=>listeners.idle=fn}}},
    IDLE_SECONDS:300,webURL: v=>new URL(v), request:async type=>{ requests.push(type); if(type==='UNLOCK'&&cancel) throw Error('Cancelled'); return {domain,unlocked}; },
    busy:async (_,task)=>{try{await task();}catch{}}, notice:()=>{} });
  await settle(); return { requests, listeners, document, navigations, input(){idle=false;listeners.idle('active');} };
}
test('a visible locked site prompts once and keeps cancellation retryable', async () => {
  const p=await page({cancel:true});
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1);
  p.listeners.focus();p.listeners.focus();await settle();
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1,'Touch ID focus changes must not loop prompts');
  await p.listeners['#unlock:click']();
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,2);
});
test('an idle timeout waits until the user returns before prompting', async () => {
  const p=await page({idle:true});
  assert.equal(p.requests.includes('UNLOCK'),false);
  p.listeners.focus();await settle();
  assert.equal(p.requests.includes('UNLOCK'),false);
  p.input();await settle();
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1);
  p.input();p.listeners.focus();await settle();
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1);
});
test('an already-unlocked domain resumes from a lock page without Touch ID', async () => {
  const p=await page({unlocked:true});
  assert.equal(p.requests.includes('UNLOCK'),false);
  assert.deepEqual(p.navigations,['https://example.com/']);
});
test('background or unprotected pages do not prompt', async () => {
  for (const options of [{visible:false},{focused:false},{domain:null}]) {
    const p=await page(options);assert.equal(p.requests.includes('UNLOCK'),false);
  }
  const p=await page({visible:false});p.document.visibilityState='visible';p.listeners.visibilitychange();await settle();
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1);
});
