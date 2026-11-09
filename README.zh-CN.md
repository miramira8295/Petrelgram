# Petrelgram

[English](README.md) · **简体中文** · [Русский](README.ru.md) · [Français](README.fr.md)

[![Telegram](https://img.shields.io/badge/Telegram-加入群组-26A5E4?style=flat&logo=telegram&logoColor=white)](https://t.me/+khkR9mLZyoliODFl)
[![Release](https://img.shields.io/github/v/release/miramira8295/Petrelgram?style=flat)](https://github.com/miramira8295/Petrelgram/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat)](LICENSE)

一个开源的**非官方 HarmonyOS NEXT Telegram 客户端**。使用 ArkTS/ArkUI 编写，
通过原生 N-API 桥接 [TDLib](https://core.telegram.org/tdlib)（Telegram 官方客户端库）。

## 功能

- **账号** —— 手机号登录与两步验证、多账号登录、切换与退出
- **会话列表** —— 文件夹、归档、未读角标、实时连接状态
- **消息** —— 富文本、图片、相册、视频、文件、贴纸（WEBP / TGS / WEBM）、
  自定义表情、回复、转发、表情回应、评论串、置顶消息、定时消息、多选
- **发送** —— 提及与命令自动补全、媒体、文件、语音、音乐、位置、联系人、
  投票、骰子
- **通话** —— 基于 tgcalls 的端到端加密一对一语音/视频
- **群组语音与直播** —— 多人语音、摄像头与屏幕共享、频道直播、应用内悬浮窗
- **话题与故事** —— 论坛话题列表与话题内独立消息流；全屏故事查看器
- **搜索** —— 覆盖 11 个类别的全局搜索
- **资料页** —— 用户、Bot、群组与频道；头像、简介、用户名编辑；二维码名片
- **设置** —— 隐私与安全、通知、存储、设备与会话、聊天文件夹、省电模式、深色模式

## 目录结构

```
AppScope/            应用级配置（包名、图标）
entry/src/main/ets/
  tdkit/             TDLib N-API 桥、客户端、鉴权服务
  store/             不可变 store + 订阅机制（会话、消息、资料等）
  pages/             ArkUI 页面（登录、会话列表、聊天、资料、搜索……）
  services/          媒体流式播放、直播后台任务、语音录制与播放
  util/              解析/格式化工具（富文本、相册、日期……）
entry/src/main/cpp/  原生桥（libentry.so → libtdjson.so / libtgcalls_ohos.so）
entry/src/test/      单元测试（通过 scripts/run-local-tests.sh 运行）
scripts/             TDLib/tgcalls 拉取与编译脚本、本地测试门禁
```

## 构建

### 环境要求

- **DevEco Studio 6.0+**，含自带的 OpenHarmony SDK/NDK
- `curl` 与 `file`（macOS/Linux 自带）

### 1. 原生库

应用以预编译原生库的形式内置 TDLib 和 tgcalls，路径为 `entry/libs/arm64-v8a/`
（合计约 50 MB，未提交到仓库）。`libentry.so` 同时链接这两个库，**缺任何一个都会
让构建停在** ninja 的 `missing and no known rule to make it`。

**方式 A —— 下载预编译产物（推荐）：**

```bash
bash scripts/fetch-libs.sh [tag]   # 两个库一起从本仓库的 GitHub Releases 下载
```

不带参数时脚本会自动解析最新的 Release。不要退回用滚动 tag `tdlib-latest`：
它的 `libtdjson.so` 保持更新，但 `libtgcalls_ohos.so` 落后于各个版本化 Release。

**方式 B —— 从源码编译（较新的 Mac 上约 10-15 分钟）：**

```bash
# 需要 clang（Xcode CLT）、cmake、ninja、gperf、patchelf
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
bash scripts/build-tdlib.sh
bash scripts/build-tgcalls-ohos.sh
```

`build-tdlib.sh` 端到端封装了
[`ErBWs/tdlib-ohos-build`](https://github.com/ErBWs/tdlib-ohos-build)：用 DevEco
NDK 为 arm64-v8a 交叉编译 OpenSSL（静态，`1_1_1w`）与 TDLib（release **1.8.65**），
在宿主机预先生成 TDLib 的 TL-schema 源码（交叉编译时必需），用 `patchelf` 把
SONAME 规范化为 `libtdjson.so` —— 不做这一步，原生桥会**静默**加载失败。脚本是
幂等的，可以放心重复执行。

`build-tgcalls-ohos.sh` 首次运行需下载并编译 WebRTC，耗时较长；版本固定和当前
媒体能力边界见 [`scripts/tgcalls/README.md`](scripts/tgcalls/README.md)。

### 2. Telegram API 凭据

TDLib 需要你自己的 `api_id`/`api_hash` —— 本仓库不提供任何凭据。

1. 在 <https://my.telegram.org/apps> 注册一个应用。
2. 把 `entry/src/main/ets/tdkit/ApiCredentials.template.ets` 复制为同目录下的
   `ApiCredentials.ets`。
3. 生成打包后的常量，并把打印出来的三个值粘贴进去：

   ```bash
   node scripts/gen-creds.mjs <api_id> <api_hash>
   ```

`ApiCredentials.ets` 已被 gitignore —— **切勿提交真实凭据**，一旦泄露请立即吊销
重建。这里的打包只做混淆（并非加密），仅用于提高从安装包中随手提取的门槛。

### 3. 签名

`build-profile.json5` 中的 `signingConfigs` 为空。用 DevEco Studio 打开项目，通过
**File > Project Structure > Signing Configs > Support HarmonyOS Auto-Sign**
（需要华为开发者账号）在本地生成调试证书。任何签名材料都不需要提交或分享。

### 4. 构建与运行

用 DevEco Studio 打开并在 HarmonyOS NEXT 设备/模拟器上运行，或使用命令行：

```bash
hvigorw assembleHap --no-daemon
```

运行测试门禁：

```bash
./scripts/run-local-tests.sh    # 必须输出 "LOCAL TESTS: PASS"
```

该脚本先跑 i18n 检查再跑单测 —— 一秒出结果的静态检查不该排在两分钟的测试构建后面。

## 本地化

界面文案全部在资源文件里。源语言（简体中文）放在
`entry/src/main/resources/base/element/string.json`，译文放在语言限定词目录
（如 `en_US/element/string.json`），复数在 `element/plural.json`。系统按设备语言
自动匹配，匹配不到时回落 `base`。

**`$r()` 还是 `str()`。** 组件渲染的文案一律用 `$r('app.string.x')`：它是一个
`Resource`，ArkUI 在配置变更时会重新解析，所以切语言能当场生效。`str('x')`
返回的是普通字符串，构建时就定死了 —— 只在确实需要 `string` 的地方用：
`string` 类型的 `@State`、模型字段、比较、`.join()`、以及非 UI 代码。
`@Builder` 参数遇到类型冲突时把它放宽成 `ResourceStr`，不要把调用点改回 `str()`。

**模块级 `const` 不能装文案。** 常量在首次 import 时就构建了，那时字符串源还没
装好，语言会被冻在那一刻。改成函数（`fallbackCountries()` 而不是
`FALLBACK_COUNTRIES`）。

**不要拿显示文案当状态匹配。** `label.substring(0, 2)`、`text.includes('重试')`
这类写法在换语言的瞬间就失效，判断要落在结构化字段上。

只进 `console.*` 的诊断字符串不翻译，用 `// i18n-exempt: <理由>` 标注。

```bash
node scripts/i18n-extract.mjs               # 按域统计仍硬编码的中文文案
node scripts/i18n-extract.mjs --domain util # 某个域的明细与 key 建议
node scripts/i18n-lit.mjs <file>            # 列出单个文件的中文字面量与行号
node scripts/i18n-check.mjs                 # 门禁（已并入 run-local-tests.sh）
```

`i18n-check.mjs` 检查五件事：代码引用的 key 在 `base` 中存在；`base` 里的每个 key
都能在代码中找到引用；**资源值里不得残留 `${` 模板源，且各语言的占位符编号集合
必须一致**；语言目录没有 `base` 之外的孤儿 key、各语言缺哪些词条；**已纳入门禁的
目录中不得再出现中文字面量**。

第三条是补上的 —— 门禁、单测、编译器各自能看见一类错误，但谁都看不见
「`file_downloading` 的值是 `${sizeLabel} · 正在下载` 这段模板源本身」，这种错误
只会在设备上显形。

`scripts/i18n-config.mjs` 的 `MIGRATED` 现在覆盖全部源码目录 —— 新建目录要一并
加进去，否则门禁会悄悄跳过它。key 命名 `<域>_<组件>_<语义>`，如
`chat_forward_title`。

## 状态与声明

- 开发中；界面以尽量贴近官方 Android 客户端为目标。
- 这是一个**非官方**客户端。请使用你自己的 API 凭据，并遵守
  [Telegram API 服务条款](https://core.telegram.org/api/terms)。
- 陌生用户搜索遵循 Telegram/TDLib 的服务端可发现性规则，通常只能找到拥有公开
  用户名或已进入服务端搜索范围的用户，不能通过该功能枚举任意手机号。

## 许可证

[Apache License 2.0](LICENSE)
