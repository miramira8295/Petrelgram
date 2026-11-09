import { mirrorChatEnvKey } from './chatEnvMirror';

// 材质档位变更纪元（2026-09-15 从 util/overlayMaterial 拆出来，那边原样再导出）。
//
// overlayMaterial 的 getter 是普通函数，util 订阅不了 AppStorage，所以"改了设置要重绘"只能由调用方订阅——
// 和语言切换的 LANGUAGE_EPOCH 是同一套办法。用一个纪元而不是让每个组件分别订阅几个键：调用方只关心"材质变了"。
//
// 单独成文件，是为了让 store/AppSettings 在省电翻面时也能 bump 它，而不和 overlayMaterial 互相 import
// （overlayMaterial 要读 AppSettings 的键）。这个文件除了 chatEnvMirror（无依赖）什么都不引。
export const MATERIAL_EPOCH: string = 'materialEpoch';

export function bumpMaterialEpoch(): void {
  const next: number = (AppStorage.get<number>(MATERIAL_EPOCH) ?? 0) + 1;
  AppStorage.setOrCreate(MATERIAL_EPOCH, next);
  mirrorChatEnvKey(MATERIAL_EPOCH, next);
}
