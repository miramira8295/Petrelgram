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
MIN_TESTS="${MIN_TESTS:-2210}"
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
