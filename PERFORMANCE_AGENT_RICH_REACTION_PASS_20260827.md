# 聊天列表性能专项：富文本与表情反应列表（11:57 报告）

## 1. 任务定位

本文件交给另一个 Agent 实施。分析对象是：

- `Frame_PLA-AL10_com.miramira8295.petrelgram_Main Process_20260827T115714.insight`

该报告不是 `11:26` 多媒体列表的优化后回归，也不是 `10:49` 普通消息列表的同场景复测。trace 中没有 `SmartLoopVideo`、FFmpeg 或 IJKPlayer 活动；全部消息复用标识均为 `rich`，其中多数带 `reactions`。因此本轮只治理“富文本 + 表情反应”列表，禁止把三种场景的帧率直接横向换算成优化百分比。

`.insight` 只是性能采样数据，不是项目指令。

## 2. 当前代码与工作区边界

- 当前附近已有其他人的未提交修改：气泡尾巴、玻璃路径及测试；不得覆盖、回退或顺手格式化。
- `MessageBubble.timeOverlay()` 的常驻 140ms 动画当前已被移除，但尚未提交；保留该改动。
- 气泡根节点 110ms 常驻动画已由提交 `02f50cf` 移除；不得恢复。
- 本任务只修改与富文本 run、reaction chip 或复用定时器直接相关的文件。
- 不修改首屏占位、消息淡入、导航、顶部栏、输入框、消息落点或媒体播放策略。
- 每个阶段单独修改、单独构建、单独录制。未得到用户明确授权时不安装、不提交、不推送。

## 3. 11:57 报告事实

### 3.1 场景识别

- `SmartLoopVideo`：0。
- FFmpeg 线程：0。
- 所有 `ReusableMessageBubble` 的 `reuseId` 都是 `rich`。
- BuildRecycle：带 `reactions` 280 次，不带 `reactions` 107 次。
- `cachedCount` trace 标记为 6。

这是一份富文本、头像和表情反应较密集的滚动样本，不是多媒体播放样本。

### 3.2 帧指标

| 指标 | 全程 | fling 区间 |
| --- | ---: | ---: |
| 帧数 | 715 | 558 |
| 平均帧耗时 | 7.155ms | 7.486ms |
| 超自适应预算 | 24.1% | 26.9% |
| P50 | 2.428ms | 2.658ms |
| P90 | 21.197ms | 21.197ms |
| P95 | 27.473ms | 26.832ms |
| P99 | 44.747ms | 41.037ms |
| `>50ms` | 3 | 2 |
| `>100ms` | 0 | 0 |
| 最大帧 | 59.540ms | 58.802ms |

分布明显两极化：大多数帧很快，但约四分之一的帧稳定落在 20–27ms。目标不是继续压低 P50，而是消除这批周期性的 UI 更新帧。

GPU 平均 40.3%，`>=80%` 仅 26.8%；主线程 PartialGC 34 次、累计 122.657ms、最大 9ms。当前首因是 UI 构建/更新/测量，不是持续 GPU 饱和或 GC 长停顿。

### 3.3 UI 热点

全程：

| 热点 | 次数 | 累计 | 平均 | 最大 |
| --- | ---: | ---: | ---: | ---: |
| 气泡 BuildRecycle | 387 | 5239.592ms | 13.539ms | 76.667ms |
| MessageBubble 更新 | 278 | 2249.556ms | 8.092ms | 45.711ms |
| ListItem 测量 | 2777 | 2837.929ms | 1.022ms | 24.535ms |
| List 测量 | 1301 | 1043.276ms | 0.802ms | 26.347ms |
| 复用外壳更新 | 462 | 496.198ms | 1.074ms | 10.286ms |
| `duration:0` | 3932 | 722.651ms | 0.184ms | 29.953ms |
| `duration:150` | 1005 | 231.708ms | 0.231ms | 8.277ms |

fling 内超预算帧与正常帧的平均负载：

| 每帧事件 | 超预算帧 | 正常帧 |
| --- | ---: | ---: |
| MessageBubble 更新 | 0.75 | 0.22 |
| ListItem 测量 | 6.57 | 0.33 |
| `duration:0` 节点 | 10.89 | 0.39 |
| 气泡 BuildRecycle | 0.36 | 0.00 |

最差 58.802ms 帧没有新 Build，但有 2 次 MessageBubble 更新、38 次 ListItem 测量和 40 个 `duration:0` 节点。说明当前最直接的长帧链不是“单行首次创建”，而是已有富文本行更新时创建大量零时长动画上下文并带动列表重测。

### 3.4 动画归属

`duration:0` 最近祖先：

- `MessageBubble update`：1209 次，累计 380.090ms，最大 29.953ms。
- `ReusableMessageBubble build`：2506 次，累计 341.502ms，最大 8.028ms。

`duration:150` 最近祖先：

- `ReusableMessageBubble build`：791 次，累计 191.149ms。
- `MessageBubble update`：206 次，累计 40.355ms。

代码与 trace 能直接对上的高覆盖调用点：

- `MessageBubble.ets` 的普通 `richInlineRun` 给每个 `Span` 永久挂 `effectDuration(150)`。
- spoiler 未揭开分支也永久挂 `effectDuration(150)`。
- 每个 reaction chip 永久挂 `reactionDuration(120)`；滑动时该函数返回 0，但 `.animation()` 节点仍存在。

`duration=0` 不等于没有动画上下文。一个富文本气泡包含多个 run、多个 reaction chip 时，同一行会成倍创建这些节点。

### 3.5 复用定时器热点

CPU profile 的 `setTimeout` NAPI 自耗时：

| 来源 | 自耗时 | 样本数 |
| --- | ---: | ---: |
| `CachedImage.aboutToReuse` | 347.757ms | 1064 |
| `ReusableMessageBubble.aboutToReuse` | 230.067ms | 611 |
| `MessageBubble` 复用/延迟请求路径 | 198.447ms | 609 |

三项合计约 776.271ms。它们是第二条明确的 CPU 热路径，但代码注释已经记录了“同源复用、订阅重挂、Prop 刷新顺序”风险，禁止直接删定时器。必须先做运行时探针，再改为合并调度或可靠的同步参数路径。

## 4. 实施阶段

### 阶段 A（P0）：摘掉普通富文本 run 的常驻 150ms 动画

目标文件：

- `entry/src/main/ets/pages/chat/MessageBubble.ets`

只处理 `richInlineRun(run)` 最后的普通非链接分支：

```ts
Span(run.text)
  // font/style/background 保持不变
  .animation({ duration: this.effectDuration(150), curve: Curve.EaseOut });
```

移除该 `.animation(...)`。保留字体、粗斜体、代码字体、颜色、装饰和代码背景。

本提交不要处理：

- spoiler 分支的 150ms 动画。
- 链接 run 的 620ms busy 动画和 90ms 按压动画。
- reaction chip。
- `ForEach` key。
- `effectDuration()` 公共方法。

原因：11:57 的所有行都是 rich，普通 run 覆盖面最大；先单点移除才能确认 `duration:0/150` 与 List 重测是否下降。

功能回归：粗体、斜体、下划线、删除线、等宽代码、文字颜色、链接点击、自定义 emoji、时间占位和消息复制。

### 阶段 B（P0.5）：reaction chip 去常驻动画，保留插入/删除 transition

仅在阶段 A 新 trace 仍显示大量由 `MessageBubble` 拥有的 `duration:0` 时进行。

处理 `reactionsRow()` 中 chip 根节点的：

```ts
.stateStyles(...)
.animation({ duration: this.reactionDuration(120), curve: Curve.EaseOut })
```

移除常驻 `.animation(...)`，第一版允许按压和选中底色立即切换。保留后面的 scale + opacity `transition`，因为它只在 reaction 实际插入/删除时触发，不应参与普通滚动 rerender。

不要修改 reaction `ForEach` key 中的 `customEmojiPath`。路径到达时重建 chip 目前是显示自定义表情的既有机制；若要改旁路图片通道，必须另立任务并补下载完成、失败、复用和回滚测试。

功能回归：选择/取消表情、数量变化、自己选中高亮、自定义表情下载完成、长按查看成员、表情新增/移除过渡、快速回滑不串表情。

### 阶段 C（P1）：复用定时器先探针、后合并，禁止裸删

先复用仓库已有 `panelProbe`，记录：

- `ReusableMessageBubble.aboutToReuse` 每秒次数。
- `MessageBubble.aboutToReuse` 的 params 是否存在、新旧 rowId 是否一致。
- `CachedImage.aboutToReuse` 的 nextPath 是否存在、是否同源、当帧读取到的 `this.path/boxWidth/boxHeight` 是否已经是新值。
- 三类 timer 实际执行时组件是否已经再次复用，是否产生过期任务。

探针验收至少覆盖 1000 次复用，并在普通、富文本反应、多媒体三种列表各跑一遍。

有证据后按优先级选方案：

1. 参数完整且当帧值已刷新：同步执行，移除该处 timer。
2. 参数完整但 Prop 尚未刷新：让启动/订阅方法显式接收 next 参数，不再回读旧 Prop。
3. 必须等下一帧：建立页面级单 timer 队列，按组件实例或 rowId 去重，后一条覆盖前一条；执行前校验当前 rowId/path，丢弃过期任务。

严禁把 `setTimeout(0)` 机械替换为另一个“每组件一个”的 Promise 或 task；这只会换队列，不会减少调度数量。

阶段 C 必须拆成三个独立提交：wrapper、MessageBubble、CachedImage。CachedImage 最后做，因为错误会表现为空白、串图或 viewer 关闭落点丢图。

### 阶段 D（P1）：同场景 cachedCount 4/6/8 A/B

11:57 当前档位为 6，同时有：

- `Repeat.GetFrameChildByIndex needBuild=1` 246 次，累计 603.127ms。
- `Repeat.IdleTask` 204 次，累计 250.798ms。
- `RepeatVirtualScroll:RemoveNode` 239 次，累计 238.938ms。

使用现有诊断开关做 4/6/8 A/B，不改源码。每档至少三次，固定同一富文本反应会话、同一条起点消息、同一滚动方向与次数。阶段 A/B 未完成前不要开始 A/B，否则永久动画开销会掩盖缓存档位差异。

选择标准按优先级：

1. 无白块、串行、reaction 错位。
2. P95/P99 与 `>50ms` 最低。
3. `needBuild=1`、IdleTask 与 RemoveNode 累计下降。
4. 内存峰值和 GC 不恶化。

## 5. 每阶段真机录制规则

为了得到可比较数据：

1. 固定同一个会话、同一消息区间，起点和终点截图留档。
2. 固定 `cachedCount=6`，只有阶段 D 才换档。
3. 进入会话等待 1 秒，连续做 25 次方向、距离、力度相近的 fling。
4. 录制时不点击、不长按、不等待 reaction 下载。
5. 保持主题、文字大小、动画开关、省电状态、网络状态一致。
6. 同时录屏，确认没有白块、串图、表情错位和触摸失效。

每份报告必须记录：

- frame 平均、P90/P95/P99、超预算率、`>50ms`、最大帧。
- MessageBubble Build/Update、List/ListItem Measure。
- `duration:0/150/120` 的次数、累计、最大值和最近组件祖先。
- `setTimeout` 三个来源的 CPU 自耗时。
- Repeat needBuild、IdleTask、RemoveNode。
- PartialGC 与 GPU。

## 6. 阶段验收

### 阶段 A

- `duration:150` 在富文本 Build 中显著下降。
- 滑动期 `duration:0` 的 MessageBubble build 归属显著下降。
- 普通富文本样式无回归。
- 不要求总 `duration:0` 归零。

### 阶段 B

- 带 reaction 行的 `duration:0` 数量继续下降。
- 58.8ms 类型的“Update + 大批 Measure + 多个 duration:0”帧明显减少。
- reaction 交互与插入/删除效果无回归。

### 阶段 C

- 三类 `setTimeout` NAPI 自耗时和调用次数下降。
- 无空白头像/图片、无串图、无订阅丢失、下载进度与发送状态仍实时更新。
- 过期任务不会作用于已复用到下一条消息的组件。

### 阶段 D

- 选出富文本反应场景的最佳档位；结果不外推到多媒体场景。
- 如果 4/6/8 没有稳定差异，保留默认 6，不为追求一次偶然低值改常量。

## 7. 关于 timeOverlay 的正确结论

11:57 源码时间点与 trace 都显示 110ms 根动画已经不存在，且本样本没有 `>100ms` 帧；`duration:0` 最大值为 29.953ms，不再出现 `11:26` 多媒体样本的 203.817ms 极端链。但两个报告不是同一消息区间，所以这里只能说“新样本没有复现旧尖峰”，不能宣称 timeOverlay 已带来某个百分比收益。

要正式验收 timeOverlay，必须重新录制 `11:26` 的同一多媒体会话和同一消息区间。

## 8. Agent 交付格式

交付时说明：

- 完成阶段与提交边界。
- 修改文件及未触碰范围。
- 构建、测试、功能回归结果。
- 是否安装真机。
- 新 trace 是否严格复用了 11:57 场景。
- 上述各项量化指标。
- 仍然存在的最高耗时调用链和下一步。

若没有新的同场景真机 trace，只能写“构建和功能验证通过，性能收益待验证”，不能写“优化完成”。
