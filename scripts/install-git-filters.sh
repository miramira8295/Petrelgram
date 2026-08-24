#!/usr/bin/env bash
# 安装 git clean filter，让 module.json5 里的 client_id **物理上提交不进去**。
#
#   bash scripts/install-git-filters.sh
#
# ---------------------------------------------------------------------------
# 为什么需要它
#
# 华为 Push Kit 要求 client_id 配在 entry/src/main/module.json5 的 module 级
# metadata 里，官方文档还特意写了「请注意不要使用其他方式设置 value 值」——
# 没有运行时口子。而这个文件必须被版本库跟踪（里面全是 abilities、权限、路由），
# 不能像 ApiCredentials.ets 那样"真文件 gitignore、模板进仓库"。
#
# 「记得提交前手动清掉」不是方案：迟早有一次忘记。clean filter 是 git 在**写入
# 对象库之前**跑的钩子，工作区里放真值照常构建，git 存下来的永远是抹掉的版本。
# 不靠自觉，靠机制。
#
# filter 的定义在 .git/config（不进版本库），所以每台开发机要跑一次本脚本。
# 别人 clone 下来没装 filter，拿到的就是空值——那正是想要的结果。
#
# ---------------------------------------------------------------------------
# 注意
#
# · 装了 filter 之后，`git diff` 看到的是**抹掉后**的内容，所以本地填了真值也
#   不会显示成"已修改"。这是设计如此，但第一次遇到会以为改动丢了。
# · 要临时看真值：直接打开文件，或 `git config --unset filter.clientid.clean`
#   之后再 `git diff`。
# · smudge 方向刻意不做（checkout 时不注入）：那需要把真值另存一份在本地，
#   多一个存放点就多一个泄露面。填一次的成本远低于此。
set -euo pipefail

cd "$(dirname "$0")/.."

# clean：写进 git 对象库之前跑。把 client_id 那条 metadata 的 value 抹成空串。
#
# 只匹配紧跟在 "name": "client_id" 之后的那个 value，不用全局替换——module.json5
# 里还有别的 metadata（backup_config 等），无差别替换会把它们一起弄坏。
git config filter.clientid.clean \
  'sed -E "/\"name\"[[:space:]]*:[[:space:]]*\"client_id\"/{n;s/(\"value\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\1\2/;}"'

# smudge 设成 cat = 不改动。checkout 出来就是空值，本地要自己填。
git config filter.clientid.smudge cat

echo "已安装 clean filter：entry/src/main/module.json5 的 client_id 不会进版本库"
echo
echo "自检："
if git check-attr filter -- entry/src/main/module.json5 | grep -q "filter: clientid"; then
  echo "  .gitattributes 生效 ✓"
else
  echo "  !! .gitattributes 没生效，检查它是否存在且已提交"
  exit 1
fi

# 用一段假数据走一遍 clean，确认替换规则真的有效——只声明不验证等于没做。
probe=$(printf '%s\n' \
  '    "metadata": [' \
  '      {' \
  '        "name": "client_id",' \
  '        "value": "1234567890"' \
  '      },' \
  '      {' \
  '        "name": "ohos.extension.backup",' \
  '        "resource": "$profile:backup_config"' \
  '      }' \
  '    ],' | eval "$(git config filter.clientid.clean)")
if printf '%s' "$probe" | grep -q '"value": ""' && printf '%s' "$probe" | grep -q 'backup_config'; then
  echo "  替换规则自检通过 ✓（client_id 被抹空，其它 metadata 未受影响）"
else
  echo "  !! 替换规则自检失败，输出如下："
  printf '%s\n' "$probe"
  exit 1
fi
