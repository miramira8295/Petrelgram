import { fileIo as fs } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { bundleManager } from '@kit.AbilityKit';
import { diagLogText, logE } from './log';
import { DiagEnvironment, diagLogHeader } from './diagLogHeader';
import { str } from './strings';

// 把诊断日志另存为文件。
//
// **为什么需要它**（issue #89）：现在只有"上传给开发者"一条路，而它依赖网络——
// 用户反馈网络不好时反复失败，正好在最需要看日志的时候用不了。导出成文件之后
// 用户可以自己用任何方式（IM、邮件、网盘）把它发出来。
//
// 内容取自 diagLogText()：那里已经把**内存缓冲和磁盘上两份轮转文件**合在一起
// 了，直接读磁盘文件会漏掉还没落盘的那一段（攒够 300 行才 flush），而出问题的
// 往往正是最后那几十行。
//
// 文件名带时间戳：用户可能导出多次，同名会让他们分不清哪份是哪次。时间戳由
// 调用方传入而不是这里取 —— 保持这个模块可测、不依赖时钟。
export function diagLogFileName(stamp: string): string {
  return `petrelgram-log-${stamp}.txt`;
}

// 时间戳格式：YYYYMMDD-HHmmss。避免冒号和空格——有些文件系统和分享目标处理不好。
export function diagLogStamp(now: Date): string {
  const p2 = (n: number): string => `${n}`.padStart(2, '0');
  return `${now.getFullYear()}${p2(now.getMonth() + 1)}${p2(now.getDate())}` +
    `-${p2(now.getHours())}${p2(now.getMinutes())}${p2(now.getSeconds())}`;
}

// 导出到用户选定的位置。日志可能有几 MB，先写进应用缓存再拷贝到目标 URI——
// 与 mediaSaver 保存文件走同一条路，那条路已经在真机上跑过。
// 当前设备与应用版本。**每一项都单独 try**：getBundleInfoForSelfSync 会抛，
// 而抬头缺一行远好过因为取不到版本号就导不出日志。
function currentEnvironment(): DiagEnvironment {
  let appVersion: string = '';
  try {
    appVersion = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
    ).versionName;
  } catch (e) {
    logE(`exportDiagLog getBundleInfo failed: ${e}`);
  }
  return {
    appVersion: appVersion,
    apiVersion: deviceInfo.sdkApiVersion,
    deviceModel: deviceInfo.productModel,
    osFullName: deviceInfo.osFullName
  };
}

export function exportDiagLog(context: common.UIAbilityContext, stamp: string): void {
  const body: string = diagLogText();
  if (body === '') {
    promptAction.showToast({ message: str('diag_export_empty'), duration: 1800 });
    return;
  }
  // 抬头在最前面：用户把日志贴到 issue 里时往往只贴开头几屏。
  const text: string = `${diagLogHeader(currentEnvironment())}${body}`;
  const name: string = diagLogFileName(stamp);
  const tmpPath: string = `${context.cacheDir}/${name}`;
  try {
    const file = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, text);
    fs.closeSync(file);
  } catch (e) {
    logE(`exportDiagLog write temp failed: ${e}`);
    promptAction.showToast({ message: str('diag_export_failed'), duration: 2000 });
    return;
  }
  const docPicker = new picker.DocumentViewPicker(context);
  const opts = new picker.DocumentSaveOptions();
  opts.newFileNames = [name];
  docPicker.save(opts).then((uris: string[]): void => {
    if (uris.length === 0) {
      cleanupTemp(tmpPath);
      return; // 用户取消
    }
    try {
      const src = fs.openSync(tmpPath, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.copyFileSync(src.fd, dst.fd);
      fs.closeSync(src);
      fs.closeSync(dst);
      promptAction.showToast({ message: str('diag_export_done'), duration: 2000 });
    } catch (e) {
      logE(`exportDiagLog copy failed: ${e}`);
      promptAction.showToast({ message: str('diag_export_failed'), duration: 2000 });
    }
    cleanupTemp(tmpPath);
  }).catch((e: Object): void => {
    logE(`exportDiagLog picker failed: ${JSON.stringify(e)}`);
    promptAction.showToast({ message: str('diag_export_failed'), duration: 2000 });
    cleanupTemp(tmpPath);
  });
}

// 临时文件不留在缓存里：日志含聊天痕迹，能早删就早删。
function cleanupTemp(path: string): void {
  try {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  } catch (e) {
    logE(`exportDiagLog cleanup failed: ${e}`);
  }
}
