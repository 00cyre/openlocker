import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const script = readFileSync(new URL('../extension/locked.js', import.meta.url), 'utf8').replace(/^import .*;\n/gm, '');
const settle = () => new Promise(resolve => setImmediate(resolve));
async function page({ visible = true, focused = true, domain = 'example.com', cancel = false, unlocked = false, updating = false, title } = {}) {
  const listeners = {}, elements = {}, requests = [], navigations = [];
  const $ = selector => elements[selector] ??= { disabled:true, addEventListener(event, callback) { listeners[`${selector}:${event}`] = callback; } };
  const document = { title: 'Site locked · OpenLocker', visibilityState:visible?'visible':'hidden',hasFocus:()=>focused,addEventListener:(name,fn)=>listeners[name]=fn };
  vm.runInNewContext(script, { $, document, URL, setTimeout, clearTimeout, window:{addEventListener:(name,fn)=>listeners[name]=fn}, location:{hash:'#https://example.com/private',replace(url){navigations.push(url);}}, chrome:{runtime:{getURL:path=>'chrome-extension://test/'+path,openOptionsPage(){requests.push('SETTINGS');}},idle:{queryState:async()=>'active',onStateChanged:{addListener:fn=>listeners.idle=fn}}},
    IDLE_SECONDS:300,webURL: v=>new URL(v), request:async type=>{ requests.push(type); if(type==='UNLOCK'&&cancel) throw Error('Cancelled'); return {domain,unlocked,updating,title}; },
    busy:async (_,task)=>{try{await task();}catch{}}, notice:()=>{} });
  await settle();
  const fire = async (name, event = {}) => { listeners[name]?.({type:name,isTrusted:true, button:0, target:{closest:()=>null}, preventDefault(){}, ...event}); await settle(); };
  return { requests, listeners, document, elements, navigations, fire, finishUpdate(){updating=false;} };
}
test('loading, focusing, tab switching and system activity never start Touch ID', async () => {
  const p = await page();
  assert.equal(p.requests.includes('UNLOCK'),false);
  await p.fire('focus'); await p.fire('visibilitychange'); await p.fire('idle');
  await p.fire('mousemove'); await p.fire('pointermove');
  assert.equal(p.requests.includes('UNLOCK'),false);
});
test('a deliberate page click, keypress or scroll prompts once', async () => {
  for (const [name, event] of [['pointerdown',{}],['keydown',{key:'a'}],['wheel',{}]]) {
    const p = await page();
    await p.fire(name,event);
    assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1,name);
  }
});
test('browser shortcuts, modifier keys, synthetic events and settings do not prompt', async () => {
  const p=await page();
  for (const key of ['Alt','Meta','Control','Shift','Tab','Escape']) await p.fire('keydown',{key});
  for (const event of [{key:'t',metaKey:true},{key:'Tab',ctrlKey:true},{key:'a',repeat:true},{key:'a',isTrusted:false}]) await p.fire('keydown',event);
  await p.fire('pointerdown',{isTrusted:false});
  await p.fire('pointerdown',{button:2});
  await p.fire('pointerdown',{target:{closest:selector=>selector==='#settings'?{id:'settings'}:null}});
  await p.fire('pointerdown',{target:{closest:selector=>selector==='#reload-notice'?{id:'reload-notice'}:null}});
  await p.fire('#settings:click');
  assert.equal(p.requests.includes('UNLOCK'),false);
  assert.ok(p.requests.includes('SETTINGS'));
});
test('cancelling does not loop on focus; another intentional click can retry', async () => {
  const p=await page({cancel:true});
  await p.fire('pointerdown');
  await p.fire('focus'); await p.fire('visibilitychange');
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1);
  await p.fire('pointerdown');
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,2);
});
test('one scroll burst cannot repeatedly reopen a cancelled Touch ID dialog', async () => {
  const p=await page({cancel:true});
  for(let i=0;i<5;i++) await p.fire('wheel');
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1);
});
test('hidden, unfocused and updating pages do not prompt; finishing update permits input', async () => {
  for(const options of [{visible:false},{focused:false},{updating:true}]) {
    const p=await page(options); await p.fire('pointerdown');
    assert.equal(p.requests.includes('UNLOCK'),false);
  }
  const p=await page({updating:true}); p.finishUpdate(); await p.fire('pointerdown');
  assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1);
});
test('an already-unlocked domain resumes without Touch ID', async () => {
  const p=await page({unlocked:true});
  assert.equal(p.requests.includes('UNLOCK'),false);
  assert.deepEqual(p.navigations,['https://example.com/private']);
});
test('lock page keeps the saved title and uses the original page favicon', async () => {
  const p=await page({title:'My project · Editor'});
  assert.equal(p.document.title,'My project · Editor · Locked');
  const icon = new URL(p.elements['#site-icon'].href);
  assert.equal(icon.protocol,'chrome-extension:');
  assert.equal(icon.hostname,'test');
  assert.equal(icon.pathname,'/_favicon/');
  assert.equal(icon.searchParams.get('pageUrl'),'https://example.com/private');
  const fresh=await page();
  assert.equal(fresh.document.title,'example.com/private · Locked');
});

test('unlock button consumes one click, without a second pointer or keyboard attempt', async () => {
  const target={closest:selector=>selector==='#unlock'?{id:'unlock'}:null};
  for(const [name,event] of [['pointerdown',{}],['keydown',{key:'Enter'}],['keydown',{key:' '}]]) {
    const p=await page({cancel:true});
    await p.fire(name,{target,...event});
    await p.fire('#unlock:click',{target});
    assert.equal(p.requests.filter(r=>r==='UNLOCK').length,1);
  }
});
