#!/bin/bash
# 聊天详情页滚动子系统的 hilog 黄金样本采集 —— 一条命令走完一整轮场景。
#
#   bash scripts/capture-hilog-golden.sh -l baseline
#   bash scripts/capture-hilog-golden.sh -l after-r2b -t 192.168.8.143:12345
#   bash scripts/capture-hilog-golden.sh --diff baseline after-r2b
#
# 【为什么存在】
# 第二轮（滚动子系统专项）里的批次——锚点复位、翻页闸、JumpLatest、首屏分级
# 揭示——全是**帧级时序**。第一轮那套"逐条真破 detector"在这里失效：本地单测
# 没有真实渲染树、没有滚动、没有 VSync，证明不了这些东西。方案 §6 给这些项目
# 的推迟理由原文就是这条，并且点名了前置条件：**先拿到首屏/翻页的 hilog 黄金
# 样本**，改完再录一次做 diff。这个脚本就是那个前置条件。
#
# ── 三件已经踩过、固化在这里的事 ────────────────────────────────────────
#
# 【一】应用日志**确实进 hilog**。
#   scripts/trace-chat-scroll.sh 的注释里写着"应用日志不进 hilog"，那是过时的：
#   util/log.ets 的 logI/logW/logE 除了写沙箱缓冲，还各自转发 console.info/
#   warn/error，而 ArkTS 的 console.* 是进 hilog 的。2026-09-06 在
#   PLA-AL10 / API 26 上实测确认，I 和 W 两级都能从 `hdc shell hilog` 读回来，
#   进程名出现在 tag 段里（A03D00/com.miramira8295.petrelgram/JSAPP）。
#
# 【二】不开并发。
#   trace-chat-scroll.sh 的"坑 1"教训：把采集塞进后台的 hdc 命令里，抓到的东西
#   经常是空的。这里干脆不流式抓——每一步开始前清空缓冲区，做完这一步再整段
#   dump 出来。每一步都是"清空 → 你操作 → dump"，全同步，少一个并发就少一类
#   失败模式，而且天然按步骤切好了段。
#
# 【三】必须服务端过滤，而且 `-e` 的正则**最长 127 字符**。
#   [ReadDiag] 在这个账号上是每秒几十行的量级（未读会话很多），不过滤的话
#   16M 缓冲区几十秒就冲干净了。hilog 支持 `-e <regex>` 按消息内容过滤。
#   但超过 127 字符它会回一句 "Regular expression too long, max length is 127"
#   然后**什么都不输出**——写脚本时第一版把十二个标签连同 \[ \] 转义全列上，
#   198 字符，当场撞上。所以下面这串刻意压短：`Anchor` 一个词就覆盖
#   AnchorRestore/PrependAnchor/AppendAnchor，`Jump` 覆盖 JumpLatest/Jump80。
#   压短之后拿全量缓冲交叉核对过：短式 72 行 = 全量里十二个标签的总行数 72，
#   一条不漏（脚本每次开跑前也会自己再验一次，见下面的自检）。
#
# 输出：docs/hilog-golden/<label>/NN-<step>.log + <label>/meta.txt
# 这些是诊断产物、不是源码，默认落在 gitignore 的 docs/ 下面。

set -u

LABEL=""
DEVICE=""
OUTROOT="docs/hilog-golden"
DIFF_A=""
DIFF_B=""

# 要留的标签。ChatPage 里实际存在的滚动/跳转/首屏打点，2026-09-06 逐个 grep
# 核过（方案 §5 那张清单里的 [InitialStage] 在代码里**不存在**，别照抄）。
# 必须 ≤127 字符，理由见文件头【三】。当前 74。
TAGS='Anchor|Jump|NewerFire|Follow62|Bottom62|InitialPage|FillViewport|ReusePool'
# 自检用：上面那个短式应当与这十二个标签的全量匹配数**完全相等**。
TAGS_FULL='\[(AnchorRestore|PrependAnchor|AppendAnchor|JumpLatest|Anchor|Jump80|NewerFire|Follow62|Bottom62|InitialPage|FillViewport|ReusePool)\]'

usage() {
  cat <<'EOF'
用法:
  capture-hilog-golden.sh -l <label> [-t <device>] [-o <outdir>]
      走一整轮场景，按步骤分段存下黄金样本。
  capture-hilog-golden.sh --diff <labelA> <labelB> [-o <outdir>]
      把两轮样本逐步骤 diff（只比标签行，忽略时间戳与 pid）。

  -l  本轮标签，进目录名。例：baseline / after-r2b / after-r2c
  -t  设备。省略时用 `hdc list targets` 的第一个
  -o  输出根目录，默认 docs/hilog-golden
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -l) LABEL="$2"; shift 2;;
    -t) DEVICE="$2"; shift 2;;
    -o) OUTROOT="$2"; shift 2;;
    --diff) DIFF_A="$2"; DIFF_B="$3"; shift 3;;
    -h|--help) usage; exit 0;;
    *) echo "未知参数: $1"; usage; exit 2;;
  esac
done

# ── hdc 定位。DevEco 的 toolchains 不在 PATH 里是常态。────────────────────
if ! command -v hdc >/dev/null 2>&1; then
  for CAND in "/d/Applications/DevEco Studio/sdk/default/openharmony/toolchains" \
              "$DEVECO_WIN/sdk/default/openharmony/toolchains"; do
    if [ -x "$CAND/hdc.exe" ] || [ -x "$CAND/hdc" ]; then
      PATH="$CAND:$PATH"; export PATH; break
    fi
  done
fi
if ! command -v hdc >/dev/null 2>&1; then
  echo "找不到 hdc。把 DevEco 的 sdk/default/openharmony/toolchains 加进 PATH，或设 DEVECO_WIN。"
  exit 1
fi

# ── --diff 模式：不碰设备，只比两轮样本 ─────────────────────────────────
if [ -n "$DIFF_A" ]; then
  A="$OUTROOT/$DIFF_A"
  B="$OUTROOT/$DIFF_B"
  if [ ! -d "$A" ] || [ ! -d "$B" ]; then
    echo "两轮样本至少缺一个：$A / $B"; exit 1
  fi
  echo "=== 黄金样本 diff: $DIFF_A → $DIFF_B ==="
  echo "（只比标签行的**内容**，时间戳/pid/tid 已剥掉——那三样每次都不一样，"
  echo "  留着会让 diff 全是噪声。真正要看的是打点的顺序与字段值。）"
  echo
  RC=0
  for FA in "$A"/*.log; do
    STEP="$(basename "$FA")"
    FB="$B/$STEP"
    if [ ! -f "$FB" ]; then echo "!! $STEP: 第二轮缺这一步"; RC=1; continue; fi
    # 剥掉行首的 "09-06 04:29:17.469 40717 40717 W A03D00/<pkg>/JSAPP: "
    strip() { sed -E 's/^[0-9]{2}-[0-9]{2} [0-9:.]+ +[0-9]+ +[0-9]+ +[A-Z] +[^:]+: //'; }
    if diff -q <(strip <"$FA") <(strip <"$FB") >/dev/null; then
      echo "== $STEP  一致（$(wc -l <"$FA" | tr -d ' ') 行）"
    else
      echo "!! $STEP  有差异："
      diff <(strip <"$FA") <(strip <"$FB") | sed 's/^/     /' | head -40
      RC=1
    fi
  done
  echo
  if [ "$RC" -eq 0 ]; then echo "全部一致。"; else echo "有差异——逐条确认是预期内的行为变化还是回归。"; fi
  exit $RC
fi

if [ -z "$LABEL" ]; then usage; exit 2; fi

# ── 设备 ────────────────────────────────────────────────────────────────
if [ -z "$DEVICE" ]; then
  DEVICE="$(hdc list targets 2>/dev/null | head -1 | tr -d '\r')"
fi
if [ -z "$DEVICE" ] || [ "$DEVICE" = "[Empty]" ]; then
  echo "没有已连接的设备。WiFi 调试先：hdc tconn <ip>:<port>"
  exit 1
fi
HDC() { hdc -t "$DEVICE" "$@"; }
echo "设备: $DEVICE"

PKG="com.miramira8295.petrelgram"
PID="$(HDC shell "pidof $PKG" 2>/dev/null | tr -d '\r' | awk '{print $1}')"
if [ -z "$PID" ]; then
  echo "应用没在运行。先在设备上打开 Petrelgram，再重跑。"
  exit 1
fi
echo "应用 pid: $PID"

# 缓冲区拉到上限。[ReadDiag] 在未读会话多的账号上很凶，默认大小撑不过一步。
HDC shell "hilog -G 16M" >/dev/null 2>&1

# ── 开跑前自检。宁可在这里失败，也不要等操作者做完六步才发现一行都没抓到。──
if [ "${#TAGS}" -gt 127 ]; then
  echo "自检失败：过滤正则 ${#TAGS} 字符，超过 hilog 的 127 上限——它会静默返回空。"
  exit 1
fi
PROBE_SHORT="$(HDC shell "hilog -x -P $PID -e '$TAGS'" 2>/dev/null | tr -d '\r' | grep -cE "$TAGS_FULL")"
PROBE_FULL="$(HDC shell "hilog -x -P $PID" 2>/dev/null | tr -d '\r' | grep -cE "$TAGS_FULL")"
echo "自检：短式过滤抓到 $PROBE_SHORT 条带标签的行，全量缓冲里有 $PROBE_FULL 条。"
if [ "$PROBE_SHORT" != "$PROBE_FULL" ]; then
  echo "自检失败：两者不等，说明短式漏了标签。把 TAGS 补全（注意 127 上限）再跑。"
  exit 1
fi
if [ "$PROBE_FULL" -eq 0 ]; then
  echo "提示：当前缓冲里一条打点都没有。这不一定是错的（刚清过/刚启动），"
  echo "      但如果六步跑完每一步都是 0 行，那就是 pid 对不上或打点没触发。"
fi

OUT="$OUTROOT/$LABEL"
mkdir -p "$OUT"
{
  echo "label:  $LABEL"
  echo "device: $DEVICE"
  echo "pkg:    $PKG"
  echo "pid:    $PID"
  echo "git:    $(git rev-parse --short HEAD 2>/dev/null)"
  echo "date:   $(date '+%Y-%m-%d %H:%M:%S')"
  echo "tags:   $TAGS"
} > "$OUT/meta.txt"

# ── 一步 = 清空缓冲 → 你操作 → 回车 → dump ───────────────────────────────
step() {
  local n="$1"; shift
  local name="$1"; shift
  local prompt="$1"; shift
  echo
  echo "────────────────────────────────────────────────────────────"
  echo "第 $n 步：$name"
  echo "  $prompt"
  echo
  printf "  准备好了按回车开始（开始后缓冲区会被清空）..."
  read -r _
  HDC shell "hilog -r" >/dev/null 2>&1
  echo "  缓冲区已清空。**现在做上面那件事**，做完再按回车。"
  printf "  做完了按回车..."
  read -r _
  local f="$OUT/$(printf '%02d' "$n")-$name.log"
  HDC shell "hilog -x -P $PID -e '$TAGS'" 2>/dev/null | tr -d '\r' > "$f"
  local lines
  lines="$(wc -l <"$f" | tr -d ' ')"
  echo "  → $f（$lines 行）"
  if [ "$lines" -eq 0 ]; then
    echo "  ⚠ 一行都没抓到。要么这一步没触发任何打点，要么应用重启了 pid 变了。"
    echo "    pid 变没变：hdc -t $DEVICE shell pidof $PKG（当前记录的是 $PID）"
  fi
}

cat <<EOF

采集黄金样本：$LABEL
输出目录：$OUT

一共 6 步，每步都是「按回车清空缓冲 → 你在手机上操作 → 再按回车 dump」。
全程约两分钟。中途想放弃直接 Ctrl-C，已经存下的步骤不受影响。

开始前请确认：手机屏幕亮着、Petrelgram 在前台、当前停在**会话列表**。
EOF

step 1 cold-enter-large-chat \
  "进一个消息很多的会话（500 条以上最好），等它稳定下来（列表不再跳）。"

step 2 scroll-up-3-pages \
  "在这个会话里连续向上翻 3 屏左右，让它触发翻页加载，停下等它稳定。"

step 3 reply-jump \
  "点一条引用消息跳过去，看高亮闪完，再按返回箭头退回原位。"

step 4 jump-to-latest \
  "点右下角的 ↓ 回到最新消息，等它停稳。"

step 5 enter-unread-chat \
  "退回会话列表，进一个**有未读**的会话，等未读分割线落位、列表停稳。"

step 6 background-resume \
  "把应用切到后台放 30 秒（原方案写的是 3 分钟，这里缩短——超过缓冲上限的
  风险比多等两分半更实在），再切回来，等它恢复到原位置。"

echo
echo "────────────────────────────────────────────────────────────"
echo "采完了：$OUT"
ls -1 "$OUT" | sed 's/^/  /'
echo
echo "下一步："
echo "  改完某一批之后重录一轮：bash scripts/capture-hilog-golden.sh -l after-xxx"
echo "  然后对比：bash scripts/capture-hilog-golden.sh --diff $LABEL after-xxx"
