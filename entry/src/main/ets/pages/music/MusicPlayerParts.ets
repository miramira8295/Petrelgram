import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { musicGlassBlur, musicGlassFill } from '../../util/musicCenterStyle';

// 播放页里两个会随状态变的小件（2026-09-18 从 MusicPlayerView 的 @Builder 拆出来）。
//
// 【为什么必须是组件，不能是 @Builder】带参 @Builder 的参数是**首次挂载那一刻按值
// 捕获的，之后永不更新**——官方 arkts-builder 只在「单个参数且直接传对象字面量」
// 时按引用传递，多参一律不刷新；而本仓 2026-09-11 相册那轮真机实证更狠：单对象参数
// 但调用点传变量时同样降级成按值。builder 体确实会重跑（里面读 this. 是活的），
// 但形参停在旧值。
//
// 落到这里就是用户 2026-09-18 报的那条：「播放器内格式码率等信息，不能立即出来，
// 可能还需要重新进这个页面」。音源探测是异步的（读本地文件头，或向 TDLib 只下前
// 64 KB），结果落在挂载之后；`source` 更新了、build 重跑了，四个格子却还是挂载
// 那一刻的值。切到「我的」页签再切回来能出来，因为那会把整棵子树重建一次。
//
// @Prop 是另一套机制（父→子单向同步，每次变更真的推下来），可靠。
//
// 【边界只传基本类型和 Resource】@Prop 的深拷贝会把闭包丢掉，组件会"什么都不画"
// 而不是报错，所以回调走**不带装饰器**的普通成员。

export const MUSIC_INFO_CELL_RADIUS: number = 12;

// 音源信息格（格式 / 码率 / 采样-位深 / 大小）。值为空时画一道破折号，
// 让四个格子在探测回来之前也是等宽等高的，不会等出来一跳。
@Component
export struct MusicInfoCell {
  @Prop label: Resource;
  @Prop value: string;

  build() {
    Column({ space: 2 }) {
      Text(this.label).fontSize(10).fontColor(COLOR_TEXT_SECONDARY).maxLines(1);
      Text(this.value !== '' ? this.value : '—')
        .fontSize(13).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .layoutWeight(1).padding({ top: 8, bottom: 8, left: 4, right: 4 })
    .borderRadius(MUSIC_INFO_CELL_RADIUS)
    .backgroundColor(musicGlassFill())
    .backdropBlur(musicGlassBlur())
    .border({ width: 0.5, color: $r('app.color.divider') });
  }
}

// 控制区里的圆形次要按钮（播放列表 / 上一首 / 下一首 / 加入合集）。
// enabled 与 icon 都跟状态走：曲目适配进来之后前后曲要亮，加入合集之后图标要变勾。
//
// 成员名避开 `size` / `enabled`：CustomComponent 基类上已有同名的通用属性方法，
// 撞名直接是编译错（10505001 "not assignable to the same property in base type"）。
@Component
export struct MusicRoundButton {
  @Prop icon: Resource;
  @Prop diameter: number;
  @Prop iconSize: number;
  @Prop active: boolean;

  onTap: () => void = (): void => {};

  build() {
    Row() {
      SymbolGlyph(this.icon).fontSize(this.iconSize).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(this.diameter).height(this.diameter).borderRadius(this.diameter / 2)
    .justifyContent(FlexAlign.Center)
    .opacity(this.active ? 1 : 0.3)
    .enabled(this.active)
    .onClick((): void => { this.onTap(); });
  }
}
