#!/usr/bin/env python3
"""Compile the actual native snapshot preparation against the platform metadata contract."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = (root / 'entry/src/main/cpp/shatter_renderer.cpp').read_text()
start = source.index('void PreparePixelsImpl(void *data) {')
end = source.index('\nvoid PreparePixels(napi_env', start)
with tempfile.TemporaryDirectory(prefix='petrelgram-shatter-pixels-') as directory:
    output = Path(directory)
    (output / 'shatter_pixels_impl.inc').write_text(source[start:end])
    binary = output / 'test'
    subprocess.run([os.environ.get('CXX', 'clang++'), '-std=c++17', '-O2', '-fsanitize=address,undefined',
                    '-I', str(root / 'entry/src/main/cpp'), '-I', directory,
                    str(root / 'entry/src/test/native/shatter_pixels_test.cpp'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
