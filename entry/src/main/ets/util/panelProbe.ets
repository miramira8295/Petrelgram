// 面板/气泡挂载计数器 —— **已停用**（2026-09-11，用户要求砍掉热路径探针）。
//
// 原实现：每次 probeHit 累加计数，一个 1s 的 setInterval 把计数用 logE 打成
// `[probe] 1001ms message.mount=… message.plain.reuse=…`。它是常驻的：每秒一次
// 字符串拼接 + 写诊断缓冲，即使用户什么都不做。上一份设备日志里 2986 行。
// 保留两个导出的函数签名让 4 个调用方（TgsStickerView / WebmStickerView /
// ReusableMessageBubble / LightweightPlainTextBubble）不用改；需要时再把
// git 里的实现接回来。
export function probeHit(_name: string, _times: number = 1): void {
}

export function probeEvent(_name: string, _detail: string): void {
}
