import { mirrorChatEnvKey } from './chatEnvMirror';

// 材质档位变更纪元（2026-09-15 从 util/overlayMaterial 拆出来，那边原样再导出）。
//
// overlayMaterial 的 getter 是普通函数，util 订阅不了 AppStorage，所以"改了设置要重绘"只能由调用方订阅——
// 和语言切换的 LANGUAGE_EPOCH 是同一套办法。用一个纪元而不是让每个组件分别订阅几个键：调用方只关心"材质变了"。
//
// 单独成文件，是为了让 store/AppSettings 在省电翻面时也能 bump 它，而不和 overlayMaterial 互相 import
// （overlayMaterial 要读 AppSettings 的键）。这个文件除了 chatEnvMirror（无依赖）什么都不引。
export const MATERIAL_EPOCH: string = 'materialEpoch';

// V2 组件订阅不到 AppStorage：@StorageProp / @StorageLink 在 @ComponentV2 里是
// 编译错误（装饰器归属表：V1 装饰器不能在 V2 组件里用），所以材质承载组件
// （NativeGlassHost 等）原先只在「恰好被别的状态重建」时才换新材质——用户
// 改完厚度/光感停在那页，浮层就还是旧档。
//
// 这里再挂一个 @ObservedV2 单例：V2 组件在 build 里读一次 source.epoch 就按
// @Trace 依赖机制登记，bump 时立刻重绘。AppStorage 那条老路保留给 V1 组件
// （@StorageProp(MATERIAL_EPOCH)）。
@ObservedV2
export class MaterialEpochSource {
  @Trace epoch: number = 0;
}

export const materialEpochSource: MaterialEpochSource = new MaterialEpochSource();

export function bumpMaterialEpoch(): void {
  const next: number = (AppStorage.get<number>(MATERIAL_EPOCH) ?? 0) + 1;
  AppStorage.setOrCreate(MATERIAL_EPOCH, next);
  materialEpochSource.epoch = next;
  mirrorChatEnvKey(MATERIAL_EPOCH, next);
}
