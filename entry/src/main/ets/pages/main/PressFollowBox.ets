// 按住拖动跟手的外壳（用户 2026-11-18：底栏旁边那颗音乐胶囊与展开后的音乐条
// 也要"按住拖动时轻微形变、跟着手指"的反馈）。
//
// **为什么单独抽一个组件**：MainScreen 是整页级 V1 组件，位移量放页面 @State 会
// 让它每帧整页 ExecuteRerender（交接文档实测峰值 14.8ms）。这里只有一颗小组件
// 重建，页面不动。
//
// 算法与聊天页输入栏那套一致：Down 记原点，Move 只算与原点之差（黏住手指，
// 不是每帧从零抖一下），幅度 ×0.18 夹在 ±3vp，Up/Cancel 归零。位移挂在包住
// 内容的 Stack 上，所以玻璃（子节点 NativeGlassHost）会跟着一起动。

@Component
export struct PressFollowBox {
  // 内容由调用方以尾随闭包给出（唯一的 @BuilderParam 才能吃尾随闭包）。
  @BuilderParam content: () => void = this.placeholder;
  // 跟手权重：位移 = 手指位移 × 该系数，再夹到 ±3vp。默认 0.18。
  @Prop followRatio: number = 0.18;
  // 按下时的整体不透明度（只做一点点，用来补足"被按住"的观感）。
  @Prop pressedOpacity: number = 0.9;

  @State private pressed: boolean = false;
  @State private dx: number = 0;
  @State private dy: number = 0;
  private startX: number = 0;
  private startY: number = 0;

  @Builder
  placeholder() {
  }

  private track(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressed = true;
      this.dx = 0;
      this.dy = 0;
      if (event.touches.length > 0) {
        this.startX = event.touches[0].x;
        this.startY = event.touches[0].y;
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (!this.pressed || event.touches.length === 0) {
        return;
      }
      const k: number = this.followRatio;
      const mx: number = (event.touches[0].x - this.startX) * k;
      const my: number = (event.touches[0].y - this.startY) * k;
      this.dx = mx > 3 ? 3 : (mx < -3 ? -3 : mx);
      this.dy = my > 3 ? 3 : (my < -3 ? -3 : my);
      return;
    }
    this.pressed = false;
    this.dx = 0;
    this.dy = 0;
  }

  build() {
    Stack() {
      this.content();
    }
    .width('100%').height('100%')
    .translate({ x: this.dx, y: this.dy })
    .opacity(this.pressed ? this.pressedOpacity : 1)
    .onTouch((event: TouchEvent): void => { this.track(event); });
  }
}
