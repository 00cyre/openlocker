import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const settle = () => new Promise(resolve => setImmediate(resolve));
async function page(script, state) {
  const elements = {}, events = {}, calls = [];
  const $ = id => elements[id] ??= {hidden:true,disabled:false,textContent:'',addEventListener(type,fn){events[id+':'+type]=fn;}};
  const source=readFileSync(new URL(`../extension/${script}`,import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
  vm.runInNewContext(source,{$,request:async type=>{calls.push(type);return state;},notice:()=>{},document:{visibilityState:'visible',addEventListener(type,fn){events[type]=fn;}},addEventListener:(type,fn)=>{events[type]=fn;},setInterval:()=>{},chrome:{runtime:{getManifest:()=>({version:'1.0.1'})}}});
  await settle(); return {elements,events,calls};
}
test('a local reload notice explains the running version and opens extension settings',async()=>{
  const p=await page('reload-notice.js',{reloadRequired:true,installedVersion:'1.0.2',runningVersion:'1.0.1'});
  assert.equal(p.elements['#reload-notice'].hidden,false);
  assert.match(p.elements['#reload-description'].textContent,/1\.0\.2.*1\.0\.1/);
  p.events['#extension-settings:click']();await settle();
  assert.equal(p.calls.at(-1),'OPEN_EXTENSION_SETTINGS');
  assert.ok(!p.calls.includes('UNLOCK'));
});
test('a current extension keeps the reload notice hidden',async()=>{
  const p=await page('reload-notice.js',{reloadRequired:false});
  assert.equal(p.elements['#reload-notice'].hidden,true);
});
test('an already installed update opens Chrome settings instead of downloading it again',async()=>{
  const p=await page('update-ui.js',{reloadRequired:true,version:'1.0.2',installed:'1.0.1',available:false});
  assert.match(p.elements['#update-status'].textContent,/reload needed/);
  await p.events['#update:click']();
  assert.equal(p.calls.at(-1),'OPEN_EXTENSION_SETTINGS');
  assert.ok(!p.calls.includes('INSTALL_UPDATE'));
});
