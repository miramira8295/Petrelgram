// 宿主 WebGL2 编译并运行产品 GLES3 shader；不代替 HarmonyOS 真机合成/帧耗时验证。
// 先用 shatter_geometry_test.cpp 生成 fixture；PLAYWRIGHT_MODULE 可指定已有的 playwright 模块。
import fs from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const shaderFile = fs.readFileSync(new URL('../entry/src/main/cpp/shatter_shaders.h', import.meta.url), 'utf8');
const shaders = [...shaderFile.matchAll(/R"GLSL\(([\s\S]*?)\)GLSL"/g)].map(m => m[1]);
const browser = await chromium.launch({ headless: true,
  executablePath: process.env.SHATTER_CHROME || undefined,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
try {
  const page = await browser.newPage();
  const results = await page.evaluate(({ g, shaders, images }) => {
    const { width, height, surfaceWidth: sw, surfaceHeight: sh, top, tiles } = g;
    const canvas = document.createElement('canvas');
    canvas.width = sw; canvas.height = sh;
    const gl = canvas.getContext('webgl2', { antialias: false, premultipliedAlpha: true });
    if (!gl) throw Error('WebGL2 unavailable');
    const program = gl.createProgram();
    for (let i = 0; i < 2; i++) {
      const shader = gl.createShader(i === 0 ? gl.VERTEX_SHADER : gl.FRAGMENT_SHADER);
      gl.shaderSource(shader, shaders[i]); gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw Error(gl.getShaderInfoLog(shader));
      gl.attachShader(program, shader);
    }
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw Error(gl.getProgramInfoLog(program));
    gl.useProgram(program);
    const texture = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, texture);
    const original = document.createElement('canvas'); original.width = width; original.height = height;
    const sourceCtx = original.getContext('2d');
    const source = sourceCtx.createImageData(width, height);
    const rgba = new Uint8Array(width * height * 4);
    // 不对称的彩色/透明图案，捕获翻转、颜色通道、预乘和静止区域接缝问题。
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
      const offset = (y * width + x) * 4;
      const a = x < 42 ? 0 : x < 90 ? 128 : 255;
      const color = [(x * 13) % 256, (y * 17) % 256, ((x + y) * 3) % 256, a];
      source.data.set(color, offset);
      rgba.set([Math.round(color[0] * a / 255), Math.round(color[1] * a / 255),
        Math.round(color[2] * a / 255), a], offset);
    }
    sourceCtx.putImageData(source, 0, 0);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, rgba);
    for (const param of [gl.TEXTURE_MIN_FILTER, gl.TEXTURE_MAG_FILTER]) gl.texParameteri(gl.TEXTURE_2D, param, gl.LINEAR);
    for (const param of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, param, gl.CLAMP_TO_EDGE);
    const buffer = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(tiles.flat()), gl.STATIC_DRAW);
    for (let i = 0; i < 2; i++) {
      gl.enableVertexAttribArray(i); gl.vertexAttribPointer(i, 4, gl.FLOAT, false, 32, i * 16);
      gl.vertexAttribDivisor(i, 1);
    }
    gl.uniform1i(gl.getUniformLocation(program, 'snapshot'), 0);
    gl.uniform2f(gl.getUniformLocation(program, 'viewportSize'), sw, sh);
    gl.uniform2f(gl.getUniformLocation(program, 'imageSize'), width, height);
    gl.uniform1f(gl.getUniformLocation(program, 'topPadding'), top);
    gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA); gl.disable(gl.DITHER);
    const reference = document.createElement('canvas'); reference.width = sw; reference.height = sh;
    const ctx = reference.getContext('2d');
    const result = [];
    for (const progress of [0, 0.1, 0.3, 0.52, 0.75, 0.95, 1]) {
      gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
      gl.uniform1f(gl.getUniformLocation(program, 'progress'), progress);
      for (const moving of [0, 1]) {
        gl.uniform1i(gl.getUniformLocation(program, 'moving'), moving);
        gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, tiles.length);
      }
      const actual = new Uint8Array(sw * sh * 4);
      gl.readPixels(0, 0, sw, sh, gl.RGBA, gl.UNSIGNED_BYTE, actual);
      if (gl.getError() !== gl.NO_ERROR) throw Error('GL error');
      // 独立重放原 Canvas 路径，用同一组 native 碎片比较视觉偏差。
      ctx.resetTransform(); ctx.clearRect(0, 0, sw, sh); ctx.globalAlpha = 1;
      ctx.save(); ctx.beginPath();
      for (const [x, y, w, h, , , delay] of tiles) if (progress <= delay) ctx.rect(x, top + y, w, h);
      ctx.clip(); ctx.drawImage(original, 0, top); ctx.restore();
      // Chrome 对轴对齐 drawImage 走无边缘 AA 的快路径；极小剪切启用 Skia quad AA，
      // 对应原组件 RenderingContextSettings(true)。位移 < 0.001px，不改变运动判据。
      ctx.transform(1, 0.000001, -0.000001, 1, 0, 0);
      for (const [x, y, w, h, drift, rise, delay, fade] of tiles) {
        if (progress <= delay) break;
        const t = Math.min(1, (progress - delay) / (1 - delay));
        if (t >= 1) continue;
        const scale = 1 - 0.45 * t;
        const motion = 0.35 * t + 0.65 * t * t;
        ctx.globalAlpha = (1 - t) ** fade;
        ctx.drawImage(original, x, y, w, h, x + w * (1 - scale) / 2 + drift * motion,
          top + y + h * (1 - scale) / 2 - rise * motion, w * scale, h * scale);
      }
      const expected = ctx.getImageData(0, 0, sw, sh).data;
      let maxDelta = 0, sumDelta = 0, actualAlpha = 0, expectedAlpha = 0, activePixels = 0;
      let exactInitial = true;
      const channelDeltas = [0, 0, 0, 0];
      for (let y = 0; y < sh; y++) for (let x = 0; x < sw; x++) {
        const a = ((sh - 1 - y) * sw + x) * 4, b = (y * sw + x) * 4;
        if (actual[a + 3] || expected[b + 3]) activePixels++;
        actualAlpha += actual[a + 3]; expectedAlpha += expected[b + 3];
        for (let c = 0; c < 4; c++) {
          const e = c === 3 ? expected[b + c] : Math.round(expected[b + c] * expected[b + 3] / 255);
          const delta = Math.abs(actual[a + c] - e);
          maxDelta = Math.max(maxDelta, delta); sumDelta += delta; channelDeltas[c] += delta;
          if (progress === 0) {
            const direct = y >= top && y < top + height && x < width ? rgba[((y - top) * width + x) * 4 + c] : 0;
            if (Math.abs(actual[a + c] - direct) > 1) exactInitial = false;
          }
        }
      }
      result.push({ progress, maxDelta, meanActiveDelta: sumDelta / Math.max(1, activePixels * 4),
        actualAlpha, expectedAlpha, exactInitial, channelDeltas: channelDeltas.map(n => n / Math.max(1, activePixels)),
        gpu: images && progress === 0.52 ? canvas.toDataURL() : undefined,
        reference: images && progress === 0.52 ? reference.toDataURL() : undefined });
    }
    return result;
  }, { g: fixture, shaders, images: Boolean(process.env.SHATTER_IMAGE_DIR) });
  for (const row of results) {
    if (row.gpu) fs.writeFileSync(`${process.env.SHATTER_IMAGE_DIR}/shatter-gpu.png`, Buffer.from(row.gpu.split(',')[1], 'base64'));
    if (row.reference) fs.writeFileSync(`${process.env.SHATTER_IMAGE_DIR}/shatter-canvas.png`, Buffer.from(row.reference.split(',')[1], 'base64'));
    delete row.gpu; delete row.reference;
  }
  console.log(JSON.stringify(results, null, 2));
  for (const row of results) {
    assert(row.exactInitial, 'Initial frame must reconstruct the full premultiplied snapshot without seams');
    if (row.progress === 1) assert.equal(row.actualAlpha, 0, 'Final frame must be transparent');
    // Canvas 边缘覆盖/采样与 GLES 解析抗锯齿允许小差异；整体位置、颜色、透明度需接近。
    assert(row.meanActiveDelta < 3, `Excessive image deviation at progress ${row.progress}: ${row.meanActiveDelta}`);
    if (row.expectedAlpha) assert(Math.abs(row.actualAlpha / row.expectedAlpha - 1) < .03,
      `Alpha coverage changed at progress ${row.progress}`);
  }
  console.log('Shatter shaders: compiled and 7 frames verified');
} finally { await browser.close(); }
