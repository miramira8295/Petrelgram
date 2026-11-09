// 实况照片（鸿蒙「动态照片」/ MovingPhoto）在 Telegram 协议里的落地约定。
//
// 【为什么需要一个约定】TDLib 的消息类型只有 photo / video / animation /
// document，**没有任何「静图 + 动态」配对的类型**。官方 iOS 客户端发实况时也是
// 二选一。所以想做到「PG 发的在 PG 里是实况、别人收到是普通视频」，只能：
//
//   发送：把实况的动态部分（带音轨的 mp4）按 inputMessageVideo 发出去，
//         文件名打上标记；
//   接收：其他客户端看到的就是一段有声短视频，正常播放，什么都不用懂；
//         PG 认出文件名标记，渲染成实况（长按播放、带声音、可存回图库）。
//
// 【为什么标记放在文件名】Telegram 的视频本来就带 DocumentAttributeFilename，
// 这是协议里唯一一个「我们能写、别人不会显示、也不影响任何观感」的字段。备选
// 都更差：caption 打标对所有人可见；相册配对会让别的客户端看到两条；
// 按时长/尺寸猜则必然误判。
//
// 而且接收侧的管道**已经是通的**：formatMsgContent 早就把 video.file_name 取成
// MsgContent.videoFileName 并一路带到 MessageEntry，所以认标记是一个纯判定，
// 不需要新增任何字段。
//
// 【一个尚未验证的前提】TDLib 对 inputFileLocal 是否把本地文件的 basename 原样
// 作为 file_name 传上去——**本机无从验证，必须上机确认**。做法：用本约定发一条，
// 在接收端读 MessageEntry.videoFileName，看标记还在不在。若不在，这条路走不通，
// 得回头考虑别的载体（届时改这一个文件即可，判定与调用点都不用动）。

// 文件名前缀。取得像相机命名，别人看到不会觉得奇怪。
const LIVE_PHOTO_MARK: string = 'PGLIVE';

// 时长上限（秒）。鸿蒙的实况视频通常 1.5~3s，存回图库时系统本身也只接受 ≤10s。
// 判定里带上它有两个作用：挡住「别人恰好把一段长视频命名成 PGLIVE_ 」的误判；
// 也保证我们不会对一段十分钟的视频摆出"长按即播"的实况交互。
export const LIVE_PHOTO_MAX_SECONDS: number = 10;

// 发送侧：给导出的动态部分起名。unique 由调用方保证唯一（序号 + 时间戳即可），
// 不在这里取时间——纯函数才测得了。
export function livePhotoFileName(unique: string): string {
  return `${LIVE_PHOTO_MARK}_${unique}.mp4`;
}

// 从完整路径里取出基名（发送侧起完名要落盘，接收侧拿到的可能带路径）。
function baseNameOf(nameOrPath: string): string {
  const slash: number = Math.max(nameOrPath.lastIndexOf('/'), nameOrPath.lastIndexOf('\\'));
  return slash >= 0 ? nameOrPath.substring(slash + 1) : nameOrPath;
}

// 接收侧：这条视频是不是 PG 发的实况。
//
// 两个条件都要满足——文件名带标记，且时长在实况的量级内。durationSec 传 0
// （TDLib 还没探到时长）也算通过：时长是**用来排除长视频**的，不是必要证据。
export function isLivePhotoVideo(fileName: string, durationSec: number): boolean {
  if (durationSec > LIVE_PHOTO_MAX_SECONDS || durationSec < 0) {
    return false;
  }
  const base: string = baseNameOf(fileName).toUpperCase();
  // 必须是 `PGLIVE_` 开头：只写 PGLIVE 而没有下划线的（比如用户自己有个叫
  // pglive.mp4 的文件）不算，免得把普通视频认成实况。
  return base.startsWith(`${LIVE_PHOTO_MARK}_`) && base.endsWith('.MP4');
}
