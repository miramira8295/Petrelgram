import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire(import.meta.url);
const modulePath=process.env.TYPESCRIPT_MODULE || 'typescript';
const ts=require(modulePath.startsWith('file:')?fileURLToPath(modulePath):modulePath);
const context=vm.createContext({exports:{}});
for(const name of ['androidSmallAlbumGeometry','packAlbumRows','albumGeometryCache']){
  const source=fs.readFileSync(`entry/src/main/ets/util/${name}.ets`,'utf8').replace(/^import .*;$/mg,'').replace(/\bexport /g,'');
  vm.runInContext(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context);
}
const pack=vm.runInContext('packAndroidAlbumRows',context);
const legacy=vm.runInContext('packAlbumRows',context);
const cache=vm.runInContext('new AlbumGeometryCache()',context);
// Independent exhaustive Android general-branch reference: enumerate all
// compositions, filter by row limits, sum slices (no production prefix sums).
function reference(ratios,width){
  const avg=(1+ratios.reduce((a,b)=>a+b,0))/ratios.length;
  const crop=ratios.map(r=>Math.max(.66667,Math.min(1.7,avg>1.1?Math.max(1,r):Math.min(1,r))));
  let best,score=Infinity;
  for(let count=2;count<=4;count++){
    function visit(parts,remaining){
      if(parts.length===count){
        if(remaining!==0)return;
        let offset=0;
        const heights=parts.map(n=>{const h=width/crop.slice(offset,offset+n).reduce((a,b)=>a+b,0);offset+=n;return h;});
        let diff=Math.abs(heights.reduce((a,b)=>a+b,0)-width*4/3);
        if(parts.some((v,i)=>i>0&&parts[i-1]>v))diff*=1.2;
        if(Math.min(...heights)<120)diff*=1.5;
        if(diff<score-1e-9){score=diff;best=parts;}
        return;
      }
      const max=count===3&&parts.length===1&&avg<.85?4:3;
      for(let n=1;n<=max&&n<=remaining;n++)visit([...parts,n],remaining-n);
    }
    visit([],ratios.length);
  }
  return {best,crop};
}
let seed=1789;
const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/2**32;};
for(let n=5;n<=10;n++)for(let sample=0;sample<500;sample++){
  const ratios=Array.from({length:n},()=>.2+random()*3.8),width=80+random()*700;
  const rows=pack(ratios,width),ref=reference(ratios,width);
  assert.deepEqual(Array.from(rows,r=>r.length),ref.best);
  assert.deepEqual(Array.from(rows.flat(),c=>c.idx),Array.from({length:n},(_,i)=>i));
  for(const row of rows){
    assert.ok(Math.abs(row.reduce((sum,c)=>sum+c.width,0)+2*(row.length-1)-width)<1e-8);
    for(const cell of row){assert.ok(cell.width>0&&cell.height>0);assert.equal(cell.height,row[0].height);
      assert.ok(Math.abs(cell.width/cell.height-ref.crop[cell.idx])<1e-8);}
  }
}
for(let n=0;n<=1;n++)assert.equal(JSON.stringify(pack(Array(n).fill(1),320)),JSON.stringify(legacy(Array(n).fill(1),320)));
const ratios=Array(6).fill(1),a=cache.prepare(ratios,320,true);
assert.equal(cache.prepare([...ratios],320,true),a);
assert.notEqual(cache.prepare(ratios,320),a,'legacy and Android geometry must have separate cache keys');
for(let i=0;i<1000;i++)cache.prepare(ratios,100+i,true);
assert.ok(cache.entries.size<=64);assert.ok(cache.cells<=512);
for(const bad of [NaN,Infinity,-1,0])for(const row of pack([bad,1,1,1,1],320))for(const c of row)assert.ok(Number.isFinite(c.width)&&c.width>0);
console.log('Android album general geometry: 3000 reference cases, bounds/order/cache PASS');

// Golden branch fixtures derived from the Android special-case formulas,
// with our documented 2vp gutters/allocated-width normalization.
let tiles=pack([1,1],320).flat();
assert.equal(tiles[0].width,159);assert.equal(tiles[0].height,159);assert.equal(tiles[1].x,161);
tiles=pack([1.5,1.5],320).flat();
assert.equal(tiles[0].width,320);assert.equal(tiles[1].y,tiles[0].height+2);
tiles=pack([.6,1,1],320).flat();
assert.equal(tiles[0].height,325.6);assert.equal(tiles[0].width,159);
assert.equal(tiles[1].x,161);assert.equal(tiles[2].x,161);
assert.equal(tiles[2].y+tiles[2].height,tiles[0].height);
tiles=pack([1,1,1,1],320).flat();
assert.equal(tiles[0].height,325.6);assert.equal(tiles[0].width,198);
assert.equal(tiles[1].x,200);assert.equal(tiles[2].x,200);assert.equal(tiles[3].x,200);
assert.ok(Math.abs(tiles[3].y+tiles[3].height-tiles[0].height)<1e-8);
tiles=pack([1.4,1,1,1],320).flat();assert.equal(tiles[0].width,320);
assert.equal(tiles[1].y,tiles[2].y);assert.equal(tiles[2].y,tiles[3].y);
// Wide panoramas must bypass special layouts, even for 2..4 members.
for(let n=2;n<=4;n++)assert.ok(pack([3,...Array(n-1).fill(1)],320).flat().every(c=>c.x===undefined));
for(let n=2;n<=4;n++)for(let sample=0;sample<1000;sample++){
  const ratios=Array.from({length:n},()=>.01+random()*1.99),width=7+random()*1000;
  const cells=pack(ratios,width).flat();assert.equal(cells.length,n);
  for(let i=0;i<n;i++){
    const c=cells[i];assert.equal(c.idx,i);assert.ok(c.x>=0&&c.y>=0&&c.width>0&&c.height>0);
    assert.ok(c.x+c.width<=width+1e-8);
    for(let j=0;j<i;j++){
      const b=cells[j];
      const overlapX=Math.min(c.x+c.width,b.x+b.width)-Math.max(c.x,b.x);
      const overlapY=Math.min(c.y+c.height,b.y+b.height)-Math.max(c.y,b.y);
      assert.ok(overlapX<=1e-8||overlapY<=1e-8,'no overlapping media/hit rectangles');
    }
  }
}
console.log('Android small albums: branch fixtures, 3000 narrow/wide layouts, panorama dispatch PASS');
