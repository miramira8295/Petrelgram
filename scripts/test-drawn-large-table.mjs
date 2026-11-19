import assert from 'node:assert/strict';
import vm from 'node:vm';
import {ctx,ui,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.tableAPI={drawnTableGrid,DrawnTableFreeSpace,DrawnTableColumnGeometry,DrawnTableRowGeometry,DrawnStructuredSource,DrawnRichTextLayouts};',ctx);
const {drawnTableGrid,DrawnTableFreeSpace,DrawnTableColumnGeometry,DrawnTableRowGeometry,DrawnStructuredSource,DrawnRichTextLayouts}=ctx.tableAPI;
const cell=(colspan=1,rowspan=1)=>({colspan,rowspan,source:{content:'x',runs:[],links:[],targets:new Set()},header:false,align:'left'});
function reference(rows){const until=[],cells=[];let columns=0;for(let r=0;r<rows.length;r++){let cursor=0;for(const c of rows[r]){const span=Math.max(1,Math.floor(c.colspan)),height=Math.max(1,Math.min(rows.length-r,Math.floor(c.rowspan)));let available=0;while(available<span){if((until[cursor+available]??0)>r){cursor+=available+1;available=0;}else available++;}cells.push({cell:c,row:r,column:cursor,rows:height,columns:span});for(let i=cursor;i<cursor+span;i++)until[i]=r+height;cursor+=span;columns=Math.max(columns,cursor);}}return {cells,columns,rows:rows.length};}
let seed=2026;const random=()=>{seed=(1664525*seed+1013904223)>>>0;return seed/2**32;};
for(let trial=0;trial<500;trial++){
 const rows=Array.from({length:1+Math.floor(random()*20)},()=>Array.from({length:Math.floor(random()*12)},()=>cell(1+Math.floor(random()*5),1+Math.floor(random()*8))));
 const grid=drawnTableGrid(rows),expected=reference(rows);assert.deepEqual(JSON.parse(JSON.stringify(grid)),JSON.parse(JSON.stringify(expected)));
 const columns=new DrawnTableColumnGeometry(grid),widths=Array(grid.columns).fill(48);
 for(const p of grid.cells){const width=48+random()*150;columns.raise(p.column,p.column+p.columns,width);for(let i=p.column;i<p.column+p.columns;i++)widths[i]=Math.max(widths[i],width);}
 columns.finish();const xs=[0];for(const w of widths)xs.push(xs.at(-1)+w);
 for(const p of grid.cells){assert.ok(Math.abs(columns.at(p.column)-xs[p.column])<1e-6);assert.ok(Math.abs(columns.at(p.column+p.columns)-xs[p.column+p.columns])<1e-6);}
 assert.ok(Math.abs(columns.width-xs.at(-1))<1e-6);
}
let finds=0,assigns=0;const oldFind=DrawnTableFreeSpace.prototype.find,oldAssign=DrawnTableFreeSpace.prototype.assign;
DrawnTableFreeSpace.prototype.find=function(...args){finds++;return oldFind.apply(this,args);};DrawnTableFreeSpace.prototype.assign=function(...args){assigns++;return oldAssign.apply(this,args);};
const depth=2000,rows=[Array.from({length:2000},(_,i)=>cell(1,i%2===0?depth:1)),...Array.from({length:depth-1},()=>[cell(2,1)])];
const largeGrid=drawnTableGrid(rows);assert.equal(largeGrid.cells.length,3999);assert.equal(largeGrid.cells.at(-1).column,1999);assert.equal(largeGrid.columns,2001);
assert.ok(finds<depth*80,`placement must not scan every active column: ${finds}`);assert.ok(assigns<2000*100);
const findsBeforePlain=finds,assignsBeforePlain=assigns;
assert.equal(drawnTableGrid(Array.from({length:500},()=>Array.from({length:10},()=>cell()))).cells.length,5000);
assert.equal(finds,findsBeforePlain);assert.equal(assigns,assignsBeforePlain,'ordinary tables allocate no occupancy tree');
let rangeUpdates=0;const originalColumnUpdate=DrawnTableColumnGeometry.prototype.update;
DrawnTableColumnGeometry.prototype.update=function(...args){rangeUpdates++;return originalColumnUpdate.apply(this,args);};
const ordinaryGrid=drawnTableGrid([[cell(),cell(),cell()]]),ordinaryColumns=new DrawnTableColumnGeometry(ordinaryGrid);
for(const p of ordinaryGrid.cells)ordinaryColumns.raise(p.column,p.column+p.columns,60);ordinaryColumns.finish();assert.equal(rangeUpdates,0);assert.equal(ordinaryColumns.width,180);
const huge=drawnTableGrid([[cell(1_000_000_000,2)],[cell(3)]]);assert.equal(huge.cells[1].column,1_000_000_000);
const compressed=new DrawnTableColumnGeometry(huge);for(const p of huge.cells)compressed.raise(p.column,p.column+p.columns,48);compressed.finish();assert.equal(compressed.width,48_000_000_144);assert.ok(compressed.boundaries.length<=5);
for(const bad of [NaN,Infinity,Number.MAX_SAFE_INTEGER+1])assert.equal(drawnTableGrid([[cell(bad)]]),null);
assert.equal(drawnTableGrid([[cell(Number.MAX_SAFE_INTEGER),cell(1)]]),null,'unsafe aggregate span is rejected before allocating native geometry');
console.log('PASS: 500 merged-occupancy/column-coordinate differential tables; 3999-cell adversarial tall spans use logarithmic free-range operations; billion-column spans compress to O(cells) boundaries; unsafe spans rejected.');
const heights=Array.from({length:1500},()=>30+random()*50),naive=heights.slice(),geometry=new DrawnTableRowGeometry(heights);
for(let i=0;i<3000;i++){
 const start=Math.floor(random()*heights.length),end=start+1+Math.floor(random()*(heights.length-start));
 const expected=naive.slice(start,end).reduce((a,b)=>a+b,0);assert.ok(Math.abs(geometry.total(start,end)-expected)<1e-6);
 const extra=random()*5;geometry.grow(start,end,extra);for(let j=start;j<end;j++)naive[j]+=extra;
}
const ys=geometry.coordinates();let sum=0;for(let i=0;i<naive.length;i++){sum+=naive[i];assert.ok(Math.abs(ys[i+1]-sum)<1e-6);}
console.log('PASS: 3000 range-add/range-sum constraints and final row positions match sequential merged-cell distribution without walking every spanned row.');
const plain=text=>({'@type':'richTextPlain',text}),sourceEngine=new DrawnStructuredSource();
const tableRows=Array.from({length:300},(_,r)=>Array.from({length:10},(_,c)=>({text:(r+c)%83===0?{'@type':'richTextUrl',text:plain(`cell ${r}:${c}`),url:`https://table.test/${r}/${c}`}:plain(`cell ${r}:${c}`),colspan:1,rowspan:1})));
const nodes=[{'@type':'pageBlockTable',cells:tableRows,is_bordered:true,is_striped:true}],source=sourceEngine.prepare(nodes);assert.ok(source);assert.equal(source.blocks[0].source.table.rows.length,300);
const engine=new DrawnRichTextLayouts(),spec={source,maxWidthVp:300,minWidthVp:0,fontSize:16,reserve:'',foreground:'black',accent:'blue',environment:'large-table'},plan=engine.prepare(ui,spec);
assert.equal(plan.tables.length,1);const inner=plan.tables[0].layout;assert.equal(inner.paragraph.parts.length,3000);assert.ok(inner.accessibilityText.endsWith('cell 299:9'));assert.ok(inner.hits.some(h=>h.link.url==='https://table.test/249/0'));
const before=layoutCounters();for(let i=0;i<1000;i++){assert.equal(sourceEngine.prepare(nodes),source);assert.equal(engine.prepare(ui,spec),plan);}assert.deepEqual(layoutCounters(),before);
const wideSource=sourceEngine.prepare([{'@type':'pageBlockTable',cells:[Array.from({length:150},(_,i)=>({text:plain(`column ${i}`)}))]}]);assert.ok(wideSource);const wide=engine.prepare(ui,{...spec,source:wideSource});assert.equal(wide.tables[0].layout.paragraph.parts.length,150);assert.ok(wide.tables[0].layout.widthVp>300);
console.log('PASS: 300-row/3000-cell and 150-column structured tables stay drawn, retain final text/links/independent scrolling, and 1000 updates preserve parsed source and every paragraph.');
