import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../extension/activity.js',import.meta.url),'utf8');
function activity() {
 const events={},messages=[],document={visibilityState:'visible'};let time=0;
 vm.runInNewContext(source,{document,Date:{now:()=>time},addEventListener:(type,fn)=>{events[type]=fn;},chrome:{runtime:{sendMessage:async message=>{messages.push(JSON.parse(JSON.stringify(message)));}}}});
 return {events,messages,document,advance(ms){time+=ms;}};
}
test('only real visible-document input reports use, with no input contents',()=>{
 const a=activity();a.events.keydown({isTrusted:false,key:'secret'});assert.equal(a.messages.length,0);
 a.document.visibilityState='hidden';a.events.pointermove({isTrusted:true});assert.equal(a.messages.length,0);
 a.document.visibilityState='visible';a.events.keydown({isTrusted:true,key:'secret'});
 assert.deepEqual(a.messages,[{type:'ACTIVITY'}]);
 assert.equal(a.events.focus,undefined);assert.equal(a.events.scroll,undefined,'Programmatic scrolling must not count as user input');
});
test('continuous pointer movement is throttled without stopping later activity reports',()=>{
 const a=activity();for(let i=0;i<100;i++)a.events.pointermove({isTrusted:true});assert.equal(a.messages.length,1);
 a.advance(1000);a.events.wheel({isTrusted:true});assert.equal(a.messages.length,2);
});
