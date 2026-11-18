import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';

const g=group('');
Object.assign(g.head,{contentType:'contact',contactFirstName:'Ada',contactLastName:'Lovelace',contactPhone:'+123',contactVcard:'card',contactUserId:42,contactAvatarPath:''});
const engine=new ctx.DrawnTextLayouts(),p=engine.prepare(ui,g,data,style);
assert.ok(p);assert.equal(p.caption.widgets[0].widget.kind,'message-contact');
const before=layoutCounters();
for(let i=0;i<1000;i++) {
 const next={...g,head:{...g.head,contactAvatarPath:i%2?'/new-avatar':'',sendState:i%2?'sending':'sent'}};
 assert.equal(engine.prepare(ui,next,data,style),p,'avatar/status arrival must not rebuild paragraphs');
}
assert.deepEqual(layoutCounters(),before);
for(const width of [160,240,400]) {
 const plan=engine.prepare(ui,g,{...data,contentWidth:width},style),slot=plan.caption.widgets[0];
 assert.ok(slot.width>0 && slot.width<=plan.caption.widthVp+.01);
}
const caption={...g,head:{...g.head,text:'contact caption',textEntities:[]}};
const next=engine.prepare(ui,caption,data,style);
assert.notEqual(next,p);assert.equal(next.caption.source.blocks[1].source.content,'contact caption');
assert.equal(p.caption.source.blocks.length,1,'published source remains immutable');
load(compiled+'pages/chat/DrawnContactMessage.ts',['DrawnContactMessage']);
const calls=[];
const local=Object.assign(Object.create(ctx.DrawnContactMessage.prototype),{msg:g.head,onClaim:()=>false,
 actions:{onContactOpen:(...args)=>calls.push(args),onPhoneOpen:phone=>calls.push(phone)}});
local.openContact();local.callContact();assert.equal(calls.length,0,'selection/long press consumes activation');
local.onClaim=()=>true;local.openContact();assert.deepEqual(calls.pop(),[42,'+123','card']);
local.msg={...g.head,contactUserId:43,contactPhone:'+456',contactVcard:'new'};
local.openContact();assert.deepEqual(calls.pop(),[43,'+456','new'],'reused handler targets current contact');
local.callContact();assert.equal(calls.pop(),'+456');
local.msg={...local.msg,contactPhone:'   '};local.callContact();assert.equal(calls.length,0);
console.log('PASS: contact slot/caption/narrow geometry, 1000 avatar/status updates without layout, immutable source, selection guards and reused action identity.');

const card='BEGIN:VCARD\r\nVERSION:3.0\r\nTEL;TYPE=CELL:tel:+111\r\nitem1.TEL:+111\r\nEMAIL:a@example.org\r\nORG:Example;Lab\r\nNOTE:ignored\r\nPHOTO;ENCODING=b:abcdef\r\n ghijk\r\nEND:VCARD';
const summary=ctx.contactVcardSummary(card,'+222');
assert.deepEqual([...summary.phones],['+222','+111']);
assert.deepEqual([...summary.lines],['+222','+111','a@example.org','Example Lab']);
const folded=ctx.contactVcardSummary('EMAIL:long@\n example.org\nORG;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=E4=B8=AD=\n=E6=96=87','');
assert.deepEqual([...folded.lines],['long@example.org','中文']);
const long=ctx.contactVcardSummary('EMAIL:a'+('\n b'.repeat(10000)),'');assert.equal(long.lines[0].length,10001);
local.msg={...g.head,contactPhone:'',contactVcard:'BEGIN:VCARD\nTEL:+999\nEND:VCARD'};local.callContact();assert.equal(calls.pop(),'+999','vCard-only number remains callable');
const originalWidget=p.caption.widgets[0].widget;
const detailed={...g,head:{...g.head,contactVcard:'BEGIN:VCARD\n'+Array.from({length:30},(_,i)=>`EMAIL:a${i}@example.org`).join('\n')+'\nEND:VCARD'}};
const expanded=engine.prepare(ui,detailed,data,style);
assert.ok(expanded.caption.widgets[0].height>p.caption.widgets[0].height,'first prepare contains full vCard height');
const other=engine.prepare(ui,{...g,head:{...g.head,rowId:999}},data,style);assert.notEqual(other.caption.widgets[0].widget,originalWidget);
console.log('PASS: vCard phones/email/company, grouped keys, deduplication, folded/quoted-printable Unicode and 10000 continuations, vCard-only dial and variable-height ownership.');
// The first parent plan owns final geometry and the exact painted paragraphs.
vm.runInContext('globalThis.contactLayoutFor=contactLayoutFor;globalThis.ContactPainter=DrawnContactTextPainter;globalThis.originalContactSummary=contactVcardSummary;',ctx);
let summaryCalls=0;ctx.countContactSummary=(...args)=>{summaryCalls++;return ctx.originalContactSummary(...args);};
vm.runInContext('contactVcardSummary=countContactSummary',ctx);
const fresh=new ctx.DrawnTextLayouts();
const first=fresh.prepare(ui,detailed,data,style),firstSlot=first.caption.widgets[0],cardPlan=ctx.contactLayoutFor(firstSlot.widget);
assert.equal(cardPlan.height,firstSlot.height);assert.equal(cardPlan.width,firstSlot.width);
assert.ok(cardPlan.detailsY+cardPlan.details.getHeight()/cardPlan.density<=cardPlan.height);
assert.ok(cardPlan.avatarY+cardPlan.avatarSize<=cardPlan.height);assert.ok(cardPlan.actionX+cardPlan.actionSize<=cardPlan.width);
const firstCalls=summaryCalls,firstCounters=layoutCounters();
for(let i=0;i<1000;i++)assert.equal(fresh.prepare(ui,{...detailed,head:{...detailed.head,contactAvatarPath:`/avatar${i}`,sendState:i%2?'sent':'sending'}},data,style),first);
assert.equal(summaryCalls,firstCalls);assert.deepEqual(layoutCounters(),firstCounters);
assert.equal(fresh.prepare(ui,detailed,data,{...style,mathRevision:999}),first,'no metrics revision is needed for native size feedback');
const small=fresh.prepare(ui,detailed,{...data,contentWidth:160},style),smallLayout=ctx.contactLayoutFor(small.caption.widgets[0].widget);
assert.equal(summaryCalls,firstCalls,'width changes reuse parsed vCard');assert.ok(smallLayout.height>=cardPlan.height);
const largeFontUi={...ui,fp2px:size=>ui.fp2px(size)*1.8};
const large=fresh.prepare(largeFontUi,detailed,data,{...style,environment:'larger-font'});
assert.ok(large.caption.widgets[0].height>firstSlot.height);assert.equal(summaryCalls,firstCalls);
const painter=new ctx.ContactPainter(),paintCalls=[];
cardPlan.title.paragraph.paint=(_canvas,x,y)=>paintCalls.push(['title',x,y]);
cardPlan.details.paint=(_canvas,x,y)=>paintCalls.push(['details',x,y]);
painter.bind(cardPlan);const paintCounters=layoutCounters();painter.drawBehind({canvas:{}});assert.deepEqual(layoutCounters(),paintCounters);
assert.deepEqual(paintCalls,[['title',cardPlan.textX*cardPlan.density,cardPlan.titleY*cardPlan.density],['details',cardPlan.textX*cardPlan.density,cardPlan.detailsY*cardPlan.density]]);
const nativeSource=fs.readFileSync(root+'pages/chat/DrawnContactMessage.ets','utf8');
assert.doesNotMatch(nativeSource,/onAreaChange|setPollWidgetHeight|onMetricsChanged/);
console.log('PASS: first contact plan has final geometry, 1000 updates never parse/measure, width/font changes reuse vCard, measured paragraphs paint unchanged with no layout callback.');

const crossChat=fresh.prepare(ui,detailed,{...data,chatId:data.chatId+1},style);
assert.notEqual(crossChat.caption.widgets[0].widget,firstSlot.widget,'same numeric row across chats has a different widget owner');
assert.ok(cardPlan.accessibilityLabel.includes('a0@example.org'),'Canvas summary remains available to screen readers');
