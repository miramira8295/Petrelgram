import assert from 'node:assert/strict';
import {ctx,load,compiled} from './test-drawn-text-row.mjs';
ctx.ImageFit={Cover:0,Contain:1};
load(compiled+'util/cachedImageSpec.ts',['CachedImageSpecCache']);
for(const name of ['GameBubble','GiftBubble','GiveawayBubble','MusicBubble','DrawnContactMessage']) load(compiled+`pages/chat/${name}.ts`,[name]);
const cases=[
 ['GameBubble','coverSpec','coverSpecs',{chatId:1,messageId:2,photoFileId:3,photoPath:'/a',richMessage:null,prepared:null,fitAvailableWidth:true,maxWidth:260}],
 ['GiftBubble','photoSpec','photoSpecs',{chatId:1,messageId:2,photoFileId:3,photoPath:'/a'}],
 ['GiveawayBubble','photoSpec','photoSpecs',{chatId:1,messageId:2,boostedChatId:3,photoPath:'/a'}],
 ['MusicBubble','coverSpec','coverSpecs',{chatId:1,msgId:2,audioFileId:3,coverPath:'/a',coverMini:'mini'}],
 ['DrawnContactMessage','avatarSpec','avatarSpecs',{chatId:1,msg:{rowId:2,contactUserId:3,contactAvatarPath:'/a'}}]
];
for(const [name,getter,cache,props] of cases){
 const instance=Object.assign(Object.create(ctx[name].prototype),props,{[cache]:new ctx.CachedImageSpecCache()});
 if(name==='DrawnContactMessage')Object.defineProperty(instance,'layout',{value:{avatarSize:48}});
 const first=instance[getter]; assert.equal(first.drawOnCanvas,true,name);assert.equal(first.path,'/a');
 for(let i=0;i<1000;i++){instance.photoProgress=i%100;instance.downloadProgress=i%100;assert.equal(instance[getter],first,`${name}: byte progress cannot change image input`);}
 instance.chatId=4;const anotherChat=instance[getter];assert.notEqual(anotherChat.sourceKey,first.sourceKey,`${name}: chat-scoped message IDs cannot retain an unrelated image`);
 if(name==='DrawnContactMessage')instance.msg={...instance.msg,contactAvatarPath:'/b'};else if(name==='MusicBubble')instance.coverPath='/b';else instance.photoPath='/b';
 const changed=instance[getter];assert.notEqual(changed,anotherChat);assert.equal(changed.path,'/b');
}
console.log('PASS: compiled card/avatar artwork uses canvas receivers, 1000 progress updates retain decode specs, chat-scoped owners and real path updates invalidate correctly.');
