export type TdObject = Record<string, Object>;

export interface TdRequest extends Record<string, Object> {
  '@type': string;
}

export class TdError extends Error {
  code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

export interface TdBridge {
  init: (onReceive: (json: string) => void) => void;
  // 桥把请求交给 native。直连桥收 JSON 字符串（testNapi.tdSend 的入参就是
  // 字符串），所以序列化只能发生在调用方。
  send: (json: string) => void;
  // 可选：桥自己负责序列化。实现它的桥（worker）收到的是一份请求对象，
  // stringify 发生在它那一侧；TdClient 只在没有这个能力时才自己序列化。
  //
  // 【为什么不是把 send() 直接改成收对象】直连桥背后是 testNapi.tdSend(string)，
  // 那条路最终仍要字符串；统一成对象只会把 stringify 从 TdClient 挪到直连桥，
  // 而所有测试替身都得跟着改。用可选能力表达"谁来干这件事"更窄。
  sendObject?: (request: TdObject) => void;
  // 可选：桥自己负责销毁 native 运行时。
  //
  // 【为什么销毁也要归桥】td* 一旦被某个线程独占（worker 路径），销毁就必须
  // 回到那条队列上排队：UI 线程直接 tdDestroy 会 join 接收线程、清 g_clientId，
  // 而 worker 里可能正有 tdSend/tdInit 在跑（napi_init.cpp 的 g_created 检查与
  // g_clientId 使用之间没有同步）。没有这个能力的桥 = 直连，由调用方同步销毁。
  destroy?: () => void;
}
