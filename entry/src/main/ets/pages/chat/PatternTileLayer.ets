import {
  BLUR_OVERSCAN_SCALE, NO_BLUR_RADIUS, PatternTileGrid, patternTileGrid, tileIndices
} from '../../util/chatBackgroundRaster';

// 图案背景的平铺层——实时绘制那一路专用。
//
// 内容和 chatBackgroundRaster 里的 patternTileGridLayer 一模一样，存在的理由
// 只有一个：**那个是全局 @Builder，而全局 @Builder 带多个参数时不刷新**。官方
// 《自定义构建函数》说得很明确——按引用传递只在"传入一个参数且直接传对象
// 字面量"时生效，多参数不支持 @Builder 函数内 UI 组件刷新。
//
// 它咬到的是真实场景：initSettings 是 fire-and-forget 的，KEY_BG_BLUR 排在几十
// 个 await 之后才落进 AppStorage。页面赶在那之前挂载时，图案层用默认值 8 建好，
// 用户真正的模糊度到货后 @Watch 照常触发、syncRaster 照常重跑，那棵子树却纹丝
// 不动——于是"进会话有概率整屏全模糊，像是配置没读到"。图案浓度滑杆对已经打
// 开的会话不生效，也是同一个 latch。
//
// 改成 @Component 后 @Prop 天然响应，值到货就跟着重画。离屏光栅那一路仍用原来
// 的 @Builder：那是一次性快照，建完就截图，不存在"之后再变"。
@Component
export struct PatternTileLayer {
  @Prop path: string;
  // 不能叫 opacity：会和 CustomComponent 基类的同名通用属性撞名。
  @Prop tileOpacity: number;
  @Prop blurRadius: number;
  @Prop screenW: number;
  @Prop screenH: number;

  private grid(): PatternTileGrid {
    return patternTileGrid(this.screenW, this.screenH);
  }

  // 模糊只施加一次、施加在拼好的整张网格上，绝不逐块施加：逐块模糊会让每块
  // 自己的边缘各糊各的，相邻块的边接不回连续的母题，缝会显出一条淡淡的模糊
  // 线。整层一起模糊则把缝当成同一张图的内部像素，邻块互相糊进去，和源图的
  // 表现一致；只有整张网格的外边界需要过扫，而那个已经由外层的 clip 兜住了。
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
    .scale(this.blurRadius > NO_BLUR_RADIUS
      ? { x: BLUR_OVERSCAN_SCALE, y: BLUR_OVERSCAN_SCALE } : { x: 1, y: 1 })
    .blur(this.blurRadius)
    .renderGroup(true);
  }
}
