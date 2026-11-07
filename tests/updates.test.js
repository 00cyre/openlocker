import test from 'node:test';
import assert from 'node:assert/strict';
import { isNewer, releaseVersion } from '../extension/updates.js';
const release = () => ({ tag_name:'v0.1.2', draft:false, prerelease:false, assets:[{name:'OpenLocker-0.1.2-macOS.dmg',size:1234,browser_download_url:'https://github.com/00cyre/openlocker/releases/download/v0.1.2/OpenLocker-0.1.2-macOS.dmg'}] });
test('updates compare numeric versions and reject downgrades or malformed versions', () => {
  assert.equal(isNewer('1.0.10','1.0.9'),true);
  for (const v of ['0.1.2','0.1.1','01.2.3','1.2.3-beta','1.2','https://evil.test']) assert.equal(isNewer(v,'0.1.2'),false,v);
});
test('only the stable release and its exact official asset are accepted', () => {
  assert.equal(releaseVersion(release()),'0.1.2');
  for (const mutate of [r=>r.draft=true,r=>r.prerelease=true,r=>r.tag_name='v../../oops',r=>r.assets[0].browser_download_url='https://evil.test/update.dmg',r=>r.assets[0].size=100_000_001]) {
    const value=release();mutate(value);assert.throws(()=>releaseVersion(value));
  }
});
