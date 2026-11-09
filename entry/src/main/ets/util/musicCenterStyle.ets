import { plainBackdropBlur, plainGlassFill } from './overlayMaterial';
import { hdsVisualEffect } from './hdsPointLight';
import { MusicCoverColors, musicCoverColors, musicTrackKey, trackKeyOf } from './musicTrackModel';
import { MusicTrack } from './musicTrackModel';

// 音乐中心的几处共用样式（2026-09-18，设计稿「Music Player」）。
//
// 设计稿自带一套深/浅两版调色表；这里**不照抄那份表**，而是映射到仓库既有的颜色资源与
// 玻璃工具上——那套表是写死的色值，跟不了用户的强调色、深浅模式与材质厚度设置。
// 结构（毛玻璃胶囊、封面渐变、背景光晕）照设计稿，用色跟着应用走。

// 【为什么是 plain* 而不是 overlay*】overlayGlassFill 在"设备自报材质可用"时返回
// **透明**、overlayBackdropBlur 同时把模糊归 0——它俩的前提是底下还有一层系统材质
// 在画。而系统早就把**组件级**的 systemMaterial 收回了（只剩 HDS 导航级的栏还有），
// 于是这些面既没有材质、也没有自己的玻璃，看上去就是全透明
//（用户 2026-09-18：「音乐上面的所有抽屉都是透明的」，和 ScrollFab 那个空心圈同一个根因）。
// plain* 这一对不看材质在不在，无条件自绘：半透明底 + backdropBlur，两半必须一起上。
// 光感另走 hdsEffect 的 visualEffect 通道，不受那次收回影响。
export function musicGlassFill(): ResourceColor {
  return plainGlassFill($r('app.color.surface'));
}

export function musicGlassBlur(): number {
  return plainBackdropBlur('card');
}

// 底部浮层与搜索层这种整块的面：底色同上，模糊走更厚的一档。
export function musicSheetBlur(): number {
  return plainBackdropBlur('bar');
}

// 点光源。'card' 档只给光、不给按压形变——整块面板跟着手指变形很怪。
export function musicGlassEffect(): VisualEffect {
  return hdsVisualEffect('card');
}

// 封面：曲目键散列出的一对颜色，斜向渐变。没有曲目时给一块中性灰，不留空洞。
export function musicCoverGradient(track: MusicTrack | null): LinearGradient {
  const colors: MusicCoverColors = track !== null
    ? musicCoverColors(trackKeyOf(track))
    : { from: '#9aa3b2', to: '#4c5566' };
  return { angle: 135, colors: [[colors.from, 0.0], [colors.to, 1.0]] } as LinearGradient;
}

// 背景光晕用的两团颜色，取自同一对封面色——设计稿里背景就是封面色的延伸。
export function musicGlowColors(track: MusicTrack | null): MusicCoverColors {
  return track !== null
    ? musicCoverColors(trackKeyOf(track))
    : { from: '#9aa3b2', to: '#4c5566' };
}

// 合集封面是「最多四格」的马赛克，每格就是一首歌的封面色；格子不够时用玻璃色填。
// 传的是曲目键而不是曲目：合集里存的本来就是键（见 musicCollectionModel）。
export function musicKeyGradient(trackKey: string): LinearGradient {
  const colors: MusicCoverColors = musicCoverColors(trackKey);
  return { angle: 135, colors: [[colors.from, 0.0], [colors.to, 1.0]] } as LinearGradient;
}

// 空格子：一块半透明玻璃，不画渐变。
export function musicEmptyTileFill(): ResourceColor {
  return plainGlassFill($r('app.color.surface_alt'));
}
