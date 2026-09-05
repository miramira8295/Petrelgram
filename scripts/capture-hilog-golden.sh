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
# 【四】手动走的样本**不可复现**，所以有 --auto。
#   黄金样本的全部用途是 diff：这一轮和上一轮比，多出来/少掉/顺序变了的打点
#   就是回归的线索。可手动操作做不到两轮一致——每次滑动的幅度、停顿的时长、
#   进的是哪个会话都不一样，diff 出来全是噪声，真正的回归反而被淹掉。
#   更糟的是聊天列表**一直在重排**（这个账号里的群几秒就换序），按坐标点会
#   进错会话——写这个脚本时就点错过一次。
#   --auto 用两样东西把这件事变确定：
#     · 进会话一律走深链接 `tg://openmessage?channel_id=..&msg_id=..`
#       （应用注册了 tg:// scheme，见 module.json5 与 util/deepLink.ets），
#       每轮进的都是同一个会话的同一条消息，且**完全不碰聊天列表**；
#     · 步骤 3 的"引用跳转"也用深链接跳到指定消息——它走的是与点引用气泡
#       完全相同的那条路（jumpToMessageId → 锚点 → 高亮闪烁），但不需要在
#       消息内容上盲点，避免误触链接/媒体/长按菜单。
#   全程只有一次坐标点击（右下角 ↓ 回底按钮，位置固定），其余全是深链接、
#   固定像素的滑动、以及 HOME/返回键。
#
# 输出：docs/hilog-golden/<label>/NN-<step>.log + <label>/meta.txt
# 这些是诊断产物、不是源码，默认落在 gitignore 的 docs/ 下面。

set -u

LABEL=""
DEVICE=""
OUTROOT="docs/hilog-golden"
AUTO=0
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
      手动模式：走一整轮场景，每步提示你在手机上操作。
  capture-hilog-golden.sh -l <label> --auto [-t <device>]
      自动模式：用 uinput/深链接自己驱动，**推荐**。理由见文件头【四】。
      需要 <outdir>/targets.env（本机私有，不进仓库；格式见该文件注释）。
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
    --auto) AUTO=1; shift;;
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

# ── 自动模式：目标配置与动作原语 ──────────────────────────────────────
TARGETS="$OUTROOT/targets.env"
if [ "$AUTO" -eq 1 ]; then
  if [ ! -f "$TARGETS" ]; then
    echo "自动模式需要 $TARGETS，但它不存在。"
    echo "它放的是本机账号里的会话 id / 消息 id（隐私，不进仓库），"
    echo "首次使用要自己填一份——需要的字段与取法见 --help 或脚本注释。"
    exit 1
  fi
  # shellcheck disable=SC1090
  . "$TARGETS"
  for V in CHAT_MAIN MSG_OLD MSG_NEW CHAT_UNREAD FAB_X FAB_Y; do
    eval "VAL=\${$V:-}"
    if [ -z "$VAL" ]; then echo "targets.env 缺字段：$V"; exit 1; fi
  done
fi

# 等待。sleep 在个别 shell 下不可用，退回 ping 计时。
nap() {
  sleep "$1" 2>/dev/null || ping -n "$(( $1 + 1 ))" 127.0.0.1 >/dev/null 2>&1
}

# 深链接进会话。msg_id 传 0 表示只开会话、不跳消息（走未读分割线那条路）。
open_chat() {
  local channel="$1" msg="$2"
  if [ "$msg" = "0" ]; then
    HDC shell "aa start -U 'tg://openmessage?channel_id=$channel'" >/dev/null 2>&1
  else
    HDC shell "aa start -U 'tg://openmessage?channel_id=$channel&msg_id=$msg'" >/dev/null 2>&1
  fi
}

# 往回翻一屏（手指从上往下拖 = 看更早的消息）。固定像素，保证每轮一致。
swipe_older() {
  HDC shell "uinput -T -m 660 900 660 2300 600" >/dev/null 2>&1
}

tap() { HDC shell "uinput -T -c $1 $2" >/dev/null 2>&1; }
key_home() { HDC shell "uinput -K -d 1 -u 1" >/dev/null 2>&1; }
key_back() { HDC shell "uinput -K -d 2 -u 2" >/dev/null 2>&1; }

# ── 组合动作 ──────────────────────────────────────────────────────────
# 冷进 = **真的冷启动**：先把应用整个停掉再深链接进去。
#
# 走过的两条弯路，都留在这儿免得再来一遍：
#  · 直接深链接到"当前已经打开的那个会话"是无操作，一行日志都没有；
#  · 改成"先按返回键退回列表再深链接"也不行——返回键并不总能把 ChatPage
#    弹掉（会被置顶条之类先吃掉），于是深链接落到还活着的页面上，被当成
#    **页内跳转**处理，raw.log 里看到的是 [Jump80] jumpToMessageId 而不是
#    [InitialPage]。这一步要测的恰恰是首屏那条路，页内跳转不算数。
# force-stop 之后 pid 会变，所以 PID 是在这一步跑完之后才解析的（见主流程）。
do_cold_enter() { HDC shell "aa force-stop $PKG" >/dev/null 2>&1; nap 3; open_chat "$CHAT_MAIN" "$MSG_OLD"; }
# 往回翻五屏。
do_scroll5() { swipe_older; nap 1; swipe_older; nap 1; swipe_older; nap 1; swipe_older; nap 1; swipe_older; }
# 切后台放 30 秒再回来。原方案写的是 3 分钟，缩短到 30 秒——超过缓冲上限的风险
# 比多等两分半更实在，而"切后台再恢复"这条路径 30 秒已经足够走完。
do_background() { key_home; nap 30; open_chat "$CHAT_MAIN" 0; }

# ── 自动模式的采集骨架：全程只清一次、只 dump 一次，事后按时间戳切段 ──────
#
# 【为什么不是「每步清空 → 动作 → 等 → dump」】
# 第一版就是那么写的，结果六步里总有两三步是空的或缺关键打点。原因是结构性的：
# 应用处理深链接、跳转、翻页都是异步的，快一点慢一点，打点就落到**下一步**的
# 窗口里去了——而且两个文件看起来都「有内容」，不逐条查根本发现不了。实测见过
# 步骤 3 的 [Jump80] 出现在 04-jump-to-latest.log 的第一行。
#
# 改成：开跑前清一次缓冲，每步只记下**动作开始前的设备时刻**，六步跑完整段
# dump 一次，再按这些时刻把行切进各自的文件。迟到的日志按它自己的时间戳落回
# 正确的格子，这个失败模式整个消失。代价只是多存一份原始 dump（raw.log），
# 那反而有用：切段切错了还能回去看。

BOUNDS=""   # "名字|设备时刻" 每步一行

dev_now() { HDC shell "date '+%m-%d %H:%M:%S.%3N'" 2>/dev/null | tr -d ''; }

# 记边界 → 跑动作 → 等它稳定。不 dump。
astep() {
  local n="$1" name="$2" settle="$3"; shift 3
  local t; t="$(dev_now)"
  BOUNDS="$BOUNDS$(printf '%02d' "$n")-$name|$t
"
  echo "第 $n 步：$name（$t 起）"
  "$@"
  nap "$settle"
}

# 六步跑完之后：整段 dump，按边界切段，每段各自核对该有的打点。
finish_auto() {
  local raw="$OUT/raw.log"
  HDC shell "hilog -x -P $PID -e '$TAGS'" 2>/dev/null | tr -d '' > "$raw"
  echo
  echo "整段 dump：$raw（$(wc -l <"$raw" | tr -d ' ') 行）"
  echo "按时刻切段："
  local prev_name="" prev_t=""
  while IFS='|' read -r nm t; do
    [ -z "$nm" ] && continue
    if [ -n "$prev_name" ]; then split_one "$prev_name" "$prev_t" "$t"; fi
    prev_name="$nm"; prev_t="$t"
  done <<EOF
$BOUNDS
EOF
  [ -n "$prev_name" ] && split_one "$prev_name" "$prev_t" "99-99 99:99:99.999"
}

# 把 raw.log 里时间戳落在 [from, to) 的行抽进这一步的文件。hilog 的时间戳是
# "MM-DD HH:MM:SS.mmm"，同一天内按字符串比大小就是按时间比。
split_one() {
  local nm="$1" from="$2" to="$3"
  local f="$OUT/$nm.log"
  awk -v a="$from" -v b="$to" '{ ts = substr($0,1,18); if (ts >= a && ts < b) print }' \
    "$OUT/raw.log" > "$f"
  local lines; lines="$(wc -l <"$f" | tr -d ' ')"
  local want=""
  case "$nm" in
    *cold-enter*)  want="InitialPage";;
    *scroll-up*)   want="Anchor|NewerFire";;
    *reply-jump*)  want="Jump80";;
    *jump-to-latest*) want="JumpLatest|Bottom62|Jump80";;
    *enter-unread*) want="InitialPage";;
    *background*)  want="InitialPage|Anchor|NewerFire|Follow62";;
  esac
  if [ "$lines" -eq 0 ]; then
    echo "  $nm: 0 行 ⚠ 这一步没触发任何打点"
  elif [ -n "$want" ] && ! grep -qE "$want" "$f"; then
    echo "  $nm: $lines 行 ⚠ 没有该有的 \"$want\"——动作可能没生效"
  else
    echo "  $nm: $lines 行"
  fi
}
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

if [ "$AUTO" -eq 1 ]; then
  cat <<EOF

自动采集黄金样本：$LABEL
输出目录：$OUT
目标：会话 $CHAT_MAIN（锚点 $MSG_OLD，跳转 $MSG_NEW）、未读会话 $CHAT_UNREAD

全程约 60 秒，不需要你动手。除了右下角 ↓ 按钮那一次点击，其余全是深链接、
固定像素滑动和 HOME 键——不碰聊天列表、不点消息内容。
EOF
  # 全程只清这一次。之后六步只记边界、不 dump。
  HDC shell "hilog -r" >/dev/null 2>&1
  astep 1 cold-enter-large-chat 12 do_cold_enter
  # 第 1 步做的是 force-stop + 冷启动，pid 变了，重新解析一次；后面所有步骤
  # 与最终 dump 都用这个新 pid。第 1 步自己的日志也是这个进程打的，不会漏。
  PID="$(HDC shell "pidof $PKG" 2>/dev/null | tr -d '' | awk '{print $1}')"
  if [ -z "$PID" ]; then echo "冷启动后应用没起来，采集中止。"; exit 1; fi
  echo "  （冷启动后新 pid: $PID）"
  astep 2 scroll-up-3-pages      8 do_scroll5
  astep 3 reply-jump            12 open_chat "$CHAT_MAIN" "$MSG_NEW"
  astep 4 jump-to-latest         8 tap "$FAB_X" "$FAB_Y"
  astep 5 enter-unread-chat     12 open_chat "$CHAT_UNREAD" 0
  astep 6 background-resume     10 do_background
  finish_auto
  echo
  echo "────────────────────────────────────────────────────────────"
  echo "采完了：$OUT"
  ls -1 "$OUT" | sed 's/^/  /'
  echo
  echo "下一步：改完某一批之后 -l after-xxx 重录，再 --diff $LABEL after-xxx。"
  exit 0
fi
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
