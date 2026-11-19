import {
  PatternTileGrid, patternTileGrid, tileIndices
} from '../../util/chatBackgroundRaster';

// 图案背景的平铺层——实时绘制那一路专用。
//
// 内容和 chatBackgroundRaster 里的 patternTileGridLayer 一模一样，存在的理由
// 只有一个：**那个是全局 @Builder，而全局 @Builder 带多个参数时不刷新**。官方
// 《自定义构建函数》说得很明确——按引用传递只在"传入一个参数且直接传对象
// 字面量"时生效，多参数不支持 @Builder 函数内 UI 组件刷新。
//
// 图案浓度在设置初始化或滑杆变化后仍要更新，不能锁死在首次构建值。
//
// 改成 @Component 后 @Prop 天然响应，值到货就跟着重画。离屏光栅那一路仍用原来
// 的 @Builder：那是一次性快照，建完就截图，不存在"之后再变"。
@Component
export struct PatternTileLayer {
  @Prop path: string;
  // 不能叫 opacity：会和 CustomComponent 基类的同名通用属性撞名。
  @Prop tileOpacity: number;
  @Prop screenW: number;
  @Prop screenH: number;

  private grid(): PatternTileGrid {
    return patternTileGrid(this.screenW, this.screenH);
  }

  build() {
    Column() {
      ForEach(tileIndices(this.grid().rows), (r: number) => {
        Row() {
          ForEach(tileIndices(this.grid().cols), (c: number) => {
            Image(this.path.startsWith('/') ? `file://${this.path}` : this.path).draggable(false)
              .sourceSize({
                width: this.grid().tileWidth * 2,
                height: this.grid().tileHeight * 2
              })
              .width(this.grid().tileWidth).height(this.grid().tileHeight)
              .objectFit(ImageFit.Cover)
              .autoResize(false)
              .interpolation(ImageInterpolation.High);
              // 【这里**不能**抄 syncLoad(true) —— 2026-09-21 真机 trace 定位】
              //
              // chatBackgroundRaster 的两个 builder 都带 syncLoad(true)，理由写在
              // 那边：它们画在**离屏树**里、画完立刻截图，而离屏组件默认在 IO 线程
              // 解码，不同步就会截到"渐变上挖了个洞"。本组件是上屏实时那一路，
              // 没有截图这一步，那个理由不成立——当初连同其它属性一起抄了过来。
              //
              // 代价是它把整块瓦片的解码拽到主线程：瓦片是**整屏高**
              // （patternTileGrid: tileHeight = screenH），sourceSize 又给了 2 倍，
              // 于是一次 CreateImageObj 就是 **34.93ms**——那正是这份 Frame 录制里
              // 最差那一帧（82.5ms）的主要成分，卡在进会话的第一帧上。
              //
              // 去掉之后图案晚一帧出现。可以接受：底下的渐变已经在了，缺的只是
              // 图案纹理；而且第二次进会话走的是离屏光栅那条路，根本到不了这里。
          }, (c: number): string => `${r}_${c}`);
        }
        .width(this.grid().cols * this.grid().tileWidth).height(this.grid().tileHeight);
      }, (r: number): string => `${r}`);
    }
    .width(this.grid().cols * this.grid().tileWidth)
    .height(this.grid().rows * this.grid().tileHeight)
    .opacity(this.tileOpacity)
    .renderGroup(true);
  }
}
