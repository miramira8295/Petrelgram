#!/bin/bash
# Run the entry module's local (host) hypium unit tests and FAIL on any
# assertion failure.
#
# Why this exists: `hvigorw ... test` executes the assertions but reports
# BUILD SUCCESSFUL even when an `expect().assertX()` fails — the failure only
# appears as an `ERROR: Error in <case>, ...` / `AssertException` line in the
# log, not in the exit code. Relying on BUILD SUCCESSFUL alone lets a broken
# test pass silently. This wrapper greps the output for those failure lines and
# exits non-zero if any are present, giving a trustworthy pass/fail signal.
set -u

# ---------------------------------------------------------------------------
# 用例总数棘轮：只许涨，不许跌。
#
# 基线 1981 = 瘦身批 B8 之后（1814 → B1 1842 → B3 1939 → B5 1959 → B6+B7 1974 → B8 1981）。
# 【为什么】只 grep 失败行的闸门抓不住"整批用例根本没跑"：`List.test.ets` 是
# 手工维护的平铺清单（import 一行 + 调用一行，两处都要加），漏登记一个测试文件
# 时它会被静默跳过 —— 编译不报错、hvigor 照样打 BUILD SUCCESSFUL、这里也照样
# 打 PASS。拿总数当下界就把"少跑了"变成一次显式失败。
#
# 2026-09-06 从 2170 降到 2169：S2 批**故意删除**了一条已失效的用例
# （MediaSaveState 的 'viewerEntry() 为 null 时直接返回'——saveMediaEntry 改成
# 收非空 entry 入参之后，控制器里不再有那个分支，判据搬到了 ChatPage）。
# 这是本说明里「确实删了用例」那一档，不是为了让脚本变绿。
#
# 新增测试后请把这个数字调高；**永远不要为了让脚本通过而调低**（真要临时排查，
# 用环境变量覆盖一次，别改这里的默认值）。
# 2026-09-08 从 2378 降到 2377：底部各条状态条统一成"按内容收紧的胶囊"之后，
# `membershipBarUsesCompactSurface`（判断哪一档用紧凑底板）**没有调用方了**，
# 判据本身失效，连同它那条用例一起删。与上面 MediaSaveState 那次同一档：
# 确实删了用例，不是为了让脚本变绿。
# 2026-10-14：补齐现有基线与聊天可见性/相位时钟的 9 项回归用例。
# 2026-10-27：群成员邀请补 12 项，连同现有用例共 4137 项。
# 2026-10-27：搜索结果抽屉补 9 项，基线升至 4146。
# 2026-10-27：相册单格数据边界补 10 项，基线升至 4156。
# 2026-10-28：代理空凭据、认证协商与配置校验补5项。
# 2026-10-28：相册成批减负补14项头像配置、圆角与分段键回归。
# 2026-10-28：代理候选取消与临时路由回收补9项；原生边界次序另有宿主生命周期验证。
# 2026-10-28：配文轻量判定与富文本合并/交互边界补9项回归。
# 2026-10-28：富文本扫描线补8项重叠/优先级/跨块回归。
# 2026-10-28：相册缩略图重复整行通知与兜底补9项。
# 2026-10-28：文字展示快照补6项输入失效与隔离回归。
# 2026-10-28：单段富配文与数字格式器补10项回归。
# 2026-10-28：气泡回收原位重置补4项手势回归。
# 2026-10-30：加联系人错误归类与请求形状（TDLib 1.8.65）补 13 项。
# 2026-10-30：文件夹条收起/展开状态机补 7 项，基线升至 4262。
# 2026-10-30：文件夹条「滑动隐藏」开关补 2 项，基线升至 4264。
# 2026-10-30：菜单「删除」判据（三态 + 缓存/在途去重/失败不缓存）补 10 项，基线升至 4274。
# 2026-10-30 从 4274 降到 4197：**故意删除**本机代理中继层的两个测试文件
# （HttpsProxy.test.ets、HttpsProxyRelay.test.ets，共 77 项）。中继层不复存在，
# 它们测的隧道握手/路由/监听器恢复都没有被测对象了。这是"确实删了用例"那一档，
# 不是为了让脚本变绿——同一批里 ProxyAutoSwitch.test.ets 的 74 项一条没删，
# 靠注入 available=true 继续覆盖自动切换状态机（它在生产里是关的）。
# 2026-10-30：代理健康度表（EWMA / 排序 / usable 边界）补 11 项，基线升至 4208。
# 同一批里 ProxyAutoSwitch.test.ets 有 5 条原来测 pingProxy 并发的用例按 tcping
# 判据重写（不是删除，总数不变），另补 1 条"绕完一圈就停手"的回归：基线 4209。
# 同一批里两个轮转循环从 4 轮缩到 3 轮，是被这条新闸限住的，不是删断言。
# 同一批里聊天背景的氛围光斑整个撤掉（用户：背景有个透明圆来回动），它专用的
# 相位时钟 backdropPhaseClock 连同 3 条用例一并删除：基线 4206。
# 2026-11-02 从 4206 降到 4203：**故意删除**被测对象已经不存在的用例。
#   · ParagraphCache.test.ets（3 条）—— util/paragraphCache 与 pages/chat/
#     DrawnPlainText 是一整座死岛（互相引用、生产零调用），随死代码一起删除。
#   · PlainTextBubbleReuse.test.ets 从 9 条瘦到 7 条——它原先主要覆盖
#     messageBubbleReuseId 那套**生产零调用**的复用键算法，那套已随死代码删除；
#     文件保留，只覆盖仍然生效的 canRenderLightweightPlainTextRow 判据。
# 4203 是删完后实跑的结果（脚本自己的输出），不是推算值。
# 与上面几次同理：这是"确实删了用例"那一档，不是为了让脚本变绿。
# 2026-11-06 从 4203 降到 4154：**故意删除**被测对象已经不存在的用例。
#   · ChatStore.test.ets（整份）—— 验证 V1 的更新处理器：喂 update、断言实体与发布
#     节奏。V1 数据面已删（实体改由 worker 投递），这些用例没有被测对象。
#   · ChatListV2.test.ets —— 测的是 V1/V2 一行开关，开关本身也随 V1 一起删了。
#   · ChatStoreV2.test.ets —— 同上，它靠 setChatListSourceForTest 切换。
# 4154 是删完后实跑的结果，不是推算值。与「为了让脚本变绿而降」是两档。
MIN_TESTS="${MIN_TESTS:-4154}"
# ---------------------------------------------------------------------------

# Defaults are the macOS install. On Windows (git-bash) DevEco lives elsewhere,
# hvigorw is a .js that needs an explicit node, and hvigor shells out to `java`
# for PackageHap — which is only on PATH if we put the bundled JBR there.
#
# The install directory differs per machine, so probe the known locations in
# order and take the first one that actually has an `sdk` subdirectory. An
# externally supplied DEVECO_WIN still wins, and when nothing matches we leave
# it empty so the macOS defaults below stay in charge.
DEVECO_WIN="${DEVECO_WIN:-}"
if [ -z "$DEVECO_WIN" ]; then
  for DEVECO_WIN_CANDIDATE in \
    "/d/Applications/DevEco Studio" \
    "/d/Works/DevEco Studio" \
    "/c/Program Files/Huawei/DevEco Studio"; do
    if [ -d "$DEVECO_WIN_CANDIDATE/sdk" ]; then
      DEVECO_WIN="$DEVECO_WIN_CANDIDATE"
      break
    fi
  done
fi
if [ -n "$DEVECO_WIN" ] && [ -d "$DEVECO_WIN/sdk" ]; then
  # 【为什么工具链的选取不能挂在 DEVECO_SDK_HOME 的空判上】
  # 这三行（node / hvigorw.js / JBR 的 PATH）才是这个脚本在 Windows 上跑得起来
  # 的全部理由。它们曾经和下面那句 DEVECO_SDK_HOME 赋值共用一个
  # `[ -z "${DEVECO_SDK_HOME:-}" ]` 闸——于是文档里写明的那条调用方式
  #     export DEVECO_SDK_HOME=... && bash scripts/run-local-tests.sh
  # （以及 DevEco 自己已经导出该变量的终端）会整块跳过，HVIGORW 落回 macOS
  # 默认路径，报 "No such file or directory" 并打印一句误导性的
  # "LOCAL TESTS: FAIL (build did not succeed)"——看起来像测试挂了，其实是
  # 解释器没找到。所以：只有 DEVECO_SDK_HOME 本身尊重外部传入，工具链照选。
  if [ -z "${DEVECO_SDK_HOME:-}" ]; then
    # hvigor rejects a POSIX path here, so hand it the Windows spelling.
    export DEVECO_SDK_HOME="$(cd "$DEVECO_WIN/sdk" && pwd -W | sed 's|/|\\|g')"
  fi
  export DEVECO_NODE_HOME="${DEVECO_NODE_HOME:-$DEVECO_WIN/tools/node}"
  export PATH="$DEVECO_WIN/jbr/bin:$PATH"
  HVIGOR_JS="$DEVECO_WIN/tools/hvigor/bin/hvigorw.js"
fi

export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
export DEVECO_NODE_HOME="${DEVECO_NODE_HOME:-/Applications/DevEco-Studio.app/Contents/tools/node}"
HVIGORW="${HVIGORW:-/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# i18n gate first: it is a static check that runs in a second, so a broken
# resource reference should not wait behind a two-minute test build.
NODE_BIN="${DEVECO_NODE_HOME}/bin/node"
[ -x "$NODE_BIN" ] || NODE_BIN="${DEVECO_NODE_HOME}/node"
# Windows: the bundled node is node.exe, and bare `node` is usually not on PATH,
# so without this the gate "fails" for want of an interpreter.
[ -x "$NODE_BIN" ] || NODE_BIN="${DEVECO_NODE_HOME}/node.exe"
[ -x "$NODE_BIN" ] || NODE_BIN="node"
if ! "$NODE_BIN" scripts/i18n-check.mjs; then
  echo ""
  echo "LOCAL TESTS: FAIL (i18n check — see above)"
  exit 1
fi
echo ""

if [ -n "${HVIGOR_JS:-}" ] && [ ! -x "$HVIGORW" ]; then
  OUT="$("$NODE_BIN" "$HVIGOR_JS" --mode module -p module=entry@default -p isLocalTest=true test 2>&1)"
else
  OUT="$("$HVIGORW" --mode module -p module=entry@default -p isLocalTest=true test 2>&1)"
fi
echo "$OUT"

echo "$OUT" | grep -qiE "BUILD SUCCESSFUL" || {
  echo ""
  echo "LOCAL TESTS: FAIL (build did not succeed)"
  exit 1
}

FAILS="$(echo "$OUT" | grep -icE "ERROR: Error in|AssertException")"
if [ "$FAILS" -ne 0 ]; then
  echo ""
  echo "LOCAL TESTS: FAIL ($FAILS assertion-failure line(s) — see 'ERROR: Error in ...' above)"
  exit 1
fi

# Case-count gate. The runner writes its own tally here; the last `Tests run:`
# line is the authoritative one.
RESULT_FILE="entry/.test/default/intermediates/test/coverage_data/test_result.txt"
if [ ! -f "$RESULT_FILE" ]; then
  echo ""
  echo "LOCAL TESTS: FAIL (no $RESULT_FILE — this run most likely never executed a single case)"
  exit 1
fi

# The runner writes CRLF on Windows, so strip CR before parsing — otherwise
# every captured number carries a trailing carriage return and the numeric
# comparisons below blow up instead of comparing.
SUMMARY_LINE="$(tr -d '\r' < "$RESULT_FILE" | grep -E "^Tests run:" | tail -n 1)"
TESTS_RUN="$(echo "$SUMMARY_LINE" | sed -n 's/.*Tests run:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
TESTS_FAILURE="$(echo "$SUMMARY_LINE" | sed -n 's/.*Failure:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
TESTS_ERROR="$(echo "$SUMMARY_LINE" | sed -n 's/.*Error:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
TESTS_PASS="$(echo "$SUMMARY_LINE" | sed -n 's/.*Pass:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"

if [ -z "$TESTS_RUN" ] || [ -z "$TESTS_FAILURE" ] || [ -z "$TESTS_ERROR" ]; then
  echo ""
  echo "LOCAL TESTS: FAIL (could not parse 'Tests run: N, Failure: F, Error: E' out of $RESULT_FILE)"
  echo "  last matching line was: ${SUMMARY_LINE:-<none>}"
  echo "  this run most likely never executed a single case"
  exit 1
fi

if [ "$TESTS_FAILURE" -gt 0 ] || [ "$TESTS_ERROR" -gt 0 ]; then
  echo ""
  echo "LOCAL TESTS: FAIL (Tests run: $TESTS_RUN, Failure: $TESTS_FAILURE, Error: $TESTS_ERROR)"
  exit 1
fi

if [ "$TESTS_RUN" -lt "$MIN_TESTS" ]; then
  echo ""
  echo "LOCAL TESTS: FAIL (only $TESTS_RUN cases ran, ratchet MIN_TESTS is $MIN_TESTS)"
  echo "  a test file that is not registered in entry/src/test/List.test.ets is skipped silently —"
  echo "  check that BOTH the 'import xxxTest from \"./Xxx.test\";' line and the 'xxxTest();' call are there."
  echo "  If cases were deliberately removed, lower MIN_TESTS in this script — never lower it just to go green."
  exit 1
fi

echo ""
echo "LOCAL TESTS: PASS (build succeeded, 0 assertion failures, Tests run: $TESTS_RUN, Pass: ${TESTS_PASS:-?}, ratchet MIN_TESTS: $MIN_TESTS)"
