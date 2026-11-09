#!/bin/bash
# 聊天详情页滚动性能采集 —— 一条命令从抓 trace 到出对账表。
#
#   bash scripts/trace-chat-scroll.sh -l cached6
#   bash scripts/trace-chat-scroll.sh -l cached8 -d 15 -t <device-sn>
#
# 为什么存在：P6 要对 cachedCount 做 4/6/8 三档 A/B，每一档都要重复
# 「抓 → 拉回 → 转库 → 跑同一组 SQL」。手工跑这四步的问题不是慢，是**错了
# 不报错**——今天废掉的六七轮采样全都"成功"了，只是数字全是 0。
#
# ── 今天踩到的三个坑，都在这个脚本里被固化掉 ──────────────────────────
#
# 【坑 1】hitrace 必须在**真正的后台任务**里跑。
#   写成 `(hdc shell hitrace ...) &` 塞在同一条命令里，抓到的 trace 里压根
#   没有应用进程。本脚本干脆**不后台**：hitrace -t N 本身就阻塞 N 秒，脚本
#   在前台等它，操作者在这 N 秒里滑动。少一个并发就少一类失败。
#
# 【坑 2】装机后应用回到**会话列表**，不是原来那个会话。
#   "装完直接滑"测的是列表，不是详情页——而列表和详情页是两套完全不同的
#   渲染路径。脚本在开录前会明确要求确认「当前屏幕是聊天详情页」，录完还会
#   用 BuildItem [ReusableMessageBubble] 的条数反向验证这件事。
#
# 【坑 3】应用日志**不进 hilog**。
#   logE 写的是沙箱里的 petrelgram-log.txt，而且攒够 300 行才落盘。所以
#   `hdc shell hilog` 里看不到应用侧的任何打点，别指望用它来判断这一轮有没有
#   录到东西——判断依据只有下面的自检 SQL。
#
# 输出：<outdir>/<label>.ftrace、<label>.db、<label>.txt（对账表）。

set -u

DURATION=10
LABEL="run"
DEVICE=""
OUTDIR=""

usage() {
  cat <<'EOF'
用法: trace-chat-scroll.sh [-l label] [-d seconds] [-t device] [-o outdir]
  -l  本轮标签，进文件名（例：cached4 / cached6 / cached8）。默认 run
  -d  录制秒数。默认 10
  -t  hdc 设备号。只接了一台设备时可以不给
  -o  输出目录。默认 dist/trace
环境变量: HDC、TRACE_STREAMER 可覆盖工具路径
EOF
}

while getopts "l:d:t:o:h" opt; do
  case "$opt" in
    l) LABEL="$OPTARG" ;;
    d) DURATION="$OPTARG" ;;
    t) DEVICE="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="${OUTDIR:-$ROOT/dist/trace}"
mkdir -p "$OUTDIR"

# ── 工具定位 ──────────────────────────────────────────────────────────
HDC="${HDC:-}"
if [ -z "$HDC" ]; then
  # SDK 版本号会随 DevEco 升级变化，取版本号最大的那个。
  HDC="$(ls -d "$HOME"/Library/OpenHarmony/Sdk/*/toolchains/hdc 2>/dev/null | sort -V | tail -1)"
fi
TRACE_STREAMER="${TRACE_STREAMER:-/Applications/DevEco-Studio.app/Contents/tools/profiler/dic_server/trace_streamer}"

die() { echo "" ; echo "✗ $*" >&2 ; exit 1 ; }

[ -n "$HDC" ] && [ -x "$HDC" ] || die "找不到 hdc。用 HDC=<路径> 指定。"
[ -x "$TRACE_STREAMER" ] || die "找不到 trace_streamer：$TRACE_STREAMER"
command -v sqlite3 >/dev/null 2>&1 || die "找不到 sqlite3"

HDC_ARGS=()
[ -n "$DEVICE" ] && HDC_ARGS=(-t "$DEVICE")
hdcsh() { "$HDC" "${HDC_ARGS[@]}" "$@"; }

# 设备在不在。hdc list targets 在没有设备时也返回 0，所以看输出而不是退出码。
TARGETS="$(hdcsh list targets 2>/dev/null | tr -d '\r' | grep -v '^\[Empty\]$' | grep -v '^$')"
[ -n "$TARGETS" ] || die "没有连接的设备（hdc list targets 为空）"

REMOTE="/data/local/tmp/petrel-${LABEL}.ftrace"
FTRACE="$OUTDIR/$LABEL.ftrace"
DB="$OUTDIR/$LABEL.db"
REPORT="$OUTDIR/$LABEL.txt"

# ── 开录前的人工确认（坑 2） ──────────────────────────────────────────
cat <<EOF

━━ 开录前请确认 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1. 屏幕上是**聊天详情页**，不是会话列表。
     刚装完包的应用停在会话列表——在那儿滑，测的是列表。
  2. 目标会话历史足够长（至少能连续快速滑 ${DURATION} 秒不到顶）。
  3. 屏幕常亮，勿扰模式开着（通知横幅会污染帧数据）。
  4. 档位已切到本轮要测的值（设置 → 日志与诊断 → 列表 cachedCount 档位），
     并且**切完之后重新进过一次会话**——切换本身是即时生效的，重进只是为了
     让首屏也在同一档下发生。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

回车开始录制 ${DURATION} 秒，回车后立刻开始连续快速上下滑动。
EOF
read -r _

echo "▶ 录制中（${DURATION}s）—— 现在滑动"
# 前台阻塞执行，见文件头【坑 1】。--overwrite 让缓冲区满了之后覆盖最旧的，
# 于是拿到的永远是**末尾** DURATION 秒里能装下的部分；下面的自检会检查
# 实际跨度对不对得上。
hdcsh shell "hitrace -b 65536 -t ${DURATION} --overwrite ace app ark graphic ohos -o ${REMOTE}" \
  || die "hitrace 执行失败"
echo "▶ 录制结束"

hdcsh file recv "$REMOTE" "$FTRACE" >/dev/null || die "拉取 trace 失败"
hdcsh shell "rm -f ${REMOTE}" >/dev/null 2>&1
[ -s "$FTRACE" ] || die "拉回来的 trace 是空文件"

# 小于 1MB 基本可以断定 hitrace 没抓到东西（65536KB 缓冲跑满 10 秒通常几十 MB）。
SIZE=$(wc -c < "$FTRACE" | tr -d ' ')
[ "$SIZE" -ge 1048576 ] || die "trace 只有 ${SIZE} 字节，太小 —— 这一轮作废。常见原因：hitrace 没真正跑起来，或者设备上有另一个 hitrace 占着。"

rm -f "$DB"
"$TRACE_STREAMER" "$FTRACE" -e "$DB" >/dev/null 2>&1
[ -s "$DB" ] || die "trace_streamer 没有产出数据库 —— 这一轮作废"

q() { sqlite3 "$DB" "$1" 2>/dev/null; }

# ── 自检：先证明这一轮有效，再谈数字 ──────────────────────────────────
#
# 这一段是整个脚本存在的主要理由。下面每一条不通过的情形，今天都真的发生过，
# 而且**不报错、只是数字全 0**，非常容易被误读成"没有复用"。
echo ""
echo "━━ trace 有效性自检 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PROC_N="$(q "select count(*) from process where name like '%petrel%';")"
PROC_N="${PROC_N:-0}"
echo "  应用进程条数           : $PROC_N"
[ "$PROC_N" -gt 0 ] || die "trace 里没有应用进程 —— 这一轮作废。
   今天废掉的采样全是这个形态。可能原因：
     · hitrace 被塞进后台子 shell 里跑（见文件头【坑 1】）；
     · 录制窗口里应用其实在后台（锁屏 / 切到别的应用）；
     · 应用刚被装机重启，录制开始时进程还没起来。
   注意它**不会报错**，只会让下面所有数字都是 0。"

IPID="$(q "select ipid from process where name like '%petrel%' limit 1;")"

STACK_N="$(q "select count(*) from callstack;")"
STACK_N="${STACK_N:-0}"
echo "  callstack 总条数       : $STACK_N"
[ "$STACK_N" -gt 0 ] || die "转库后没有任何 callstack 切片 —— 这一轮作废（tag 集合不对，或 trace 损坏）"

FRAME_N="$(q "select count(*) from frame_slice where ipid=$IPID;")"
FRAME_N="${FRAME_N:-0}"
echo "  应用帧数               : $FRAME_N"
[ "$FRAME_N" -gt 0 ] || die "应用没有任何帧 —— 这一轮作废。录制窗口里页面没有重绘（没滑动，或应用在后台）。"

# 实际跨度。--overwrite 下缓冲区被打满会把开头挤掉，跨度会明显短于 -t 的值。
SPAN_MS="$(q "select cast((max(ts)-min(ts))/1e6 as int) from callstack;")"
SPAN_MS="${SPAN_MS:-0}"
echo "  trace 实际跨度         : ${SPAN_MS} ms（请求 $((DURATION * 1000)) ms）"
MIN_SPAN=$((DURATION * 1000 / 2))
[ "$SPAN_MS" -ge "$MIN_SPAN" ] || echo "  ⚠ 跨度不足请求的一半：缓冲区被打满、开头被覆盖。三档要互相比较的话，这一轮建议重录（或把 -b 调大）。"

# 详情页确认（坑 2）。列表页不会产生这个组件的任何切片。
BUILD_ITEM_BUBBLE="$(q "select count(*) from callstack where name like 'H:CustomNode:BuildItem [ReusableMessageBubble]%';")"
BUILD_ITEM_BUBBLE="${BUILD_ITEM_BUBBLE:-0}"
BUILD_RECYCLE="$(q "select count(*) from callstack where name like '%BuildRecycle [ReusableMessageBubble]%';")"
BUILD_RECYCLE="${BUILD_RECYCLE:-0}"
if [ "$BUILD_ITEM_BUBBLE" -eq 0 ] && [ "$BUILD_RECYCLE" -eq 0 ]; then
  die "整段 trace 里没有一条 ReusableMessageBubble 的切片 —— 这一轮作废。
   最可能的原因是**录的是会话列表而不是聊天详情页**（见文件头【坑 2】）。
   也可能是这一轮压根没有新建也没有回收任何行（滑动幅度太小）。"
fi
echo "  消息行切片             : 新建 $BUILD_ITEM_BUBBLE / 回收 $BUILD_RECYCLE"
echo "  ✓ 自检通过"

# ── 对账表 ────────────────────────────────────────────────────────────
{
  echo "=== $LABEL @ $(date '+%F %T') ==="
  echo "trace: $FTRACE"
  echo "录制 ${DURATION}s，实际跨度 ${SPAN_MS} ms，应用帧 ${FRAME_N}"
  echo ""

  echo "-- 1. 消息行外壳：复用 vs 新建 -------------------------------"
  echo "BuildRecycle [ReusableMessageBubble] : $BUILD_RECYCLE"
  echo "BuildItem    [ReusableMessageBubble] : $BUILD_ITEM_BUBBLE"
  if [ "$BUILD_ITEM_BUBBLE" -gt 0 ]; then
    # 用 awk 而不是 bc：bc 不是每台机器都有，缺了只会静默输出空串。
    echo "复用比 (recycle:build)               : $(awk "BEGIN{printf \"%.2f\", $BUILD_RECYCLE/$BUILD_ITEM_BUBBLE}"):1"
  else
    echo "复用比 (recycle:build)               : ∞（本轮没有新建任何行）"
  fi
  echo ""

  echo "-- 2. 叶子 BuildItem 总数与分布（越小越好）-------------------"
  sqlite3 -header "$DB" "
    select count(*) as build_item_total
    from callstack where name like 'H:CustomNode:BuildItem%';"
  echo ""
  sqlite3 -header "$DB" "
    select substr(name, instr(name,'[')+1, instr(name,']')-instr(name,'[')-1) as component,
           count(*) as n,
           round(sum(dur)/1e6, 1) as total_ms
    from callstack
    where name like 'H:CustomNode:BuildItem%'
    group by component order by n desc limit 15;"
  echo ""

  echo "-- 3. 预加载/预测渲染（P6 要治的那一项）----------------------"
  echo "   P2 之后的基线：predict 510 次 / 1759 ms。"
  echo "   LazyForEach 与 Repeat 的打点名不同，所以这里按 predict/preload/"
  echo "   Prediction 三种拼法一起匹配，看到哪个非零就是当前实现在用的那个。"
  sqlite3 -header "$DB" "
    select substr(name, 1, 60) as marker,
           count(*) as n,
           round(sum(dur)/1e6, 1) as total_ms,
           round(avg(dur)/1e6, 2) as avg_ms
    from callstack
    where name like '%predict%' or name like '%Predict%'
       or name like '%preload%' or name like '%Preload%'
       or name like '%Prediction%'
    group by marker order by total_ms desc limit 15;"
  echo ""

  echo "-- 4. Measure[List] ------------------------------------------"
  sqlite3 -header "$DB" "
    select count(*) as n, round(sum(dur)/1e6,1) as total_ms, round(max(dur)/1e6,2) as max_ms
    from callstack where name like '%Measure[List]%';"
  echo ""

  echo "-- 5. 帧质量（对照 P0/P2 的卡顿帧占比）-----------------------"
  sqlite3 -header "$DB" "
    select flag, count(*) as n, round(avg(dur)/1e6,2) as avg_ms, round(max(dur)/1e6,2) as max_ms
    from frame_slice where type=0 and ipid=$IPID group by flag;"
  echo "   flag: 0=正常, 1=超时(卡顿帧), 3=不需要绘制"
} | tee "$REPORT"

echo ""
echo "✓ 报告：$REPORT"
echo "✓ 数据库：$DB（可继续用 sqlite3 自行查询）"
