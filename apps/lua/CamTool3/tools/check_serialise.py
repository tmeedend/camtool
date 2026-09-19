"""Check that what core/serialise.lua writes is JSON, and is the same document.

The Lua suite can assert on the text core/serialise produces, but it has no
JSON parser to read it back with -- parsing is CSP's job in game. So the
round trip is checked here instead: Lua writes a real camera file out, Python
parses it, and the result is compared field by field against the original.

Only the differences migration is supposed to make are allowed: the version
and interpolation_mode that core/data adds, and camera_fov, which the file
stores as 1/(fov+15) and a version 1 document holds in degrees.

Run it after touching the serialiser, from apps/lua/CamTool3:
    python tools/check_serialise.py
"""
import json
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
SOURCE = os.path.join(
    APP, '..', '..', 'python', 'CamTool_2', 'data',
    'ks_red_bull_ring_layout_gp-init.json')
FIXTURE = 'tests/fixtures/camera_file_lap'

LUAJIT = os.path.expandvars(r'%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe')

SCRIPT = """
package.path = './?.lua;' .. package.path
local data = require('core/data')
local serialise = require('core/serialise')
local doc = data.load(require('%s'))
local out = assert(io.open([[%s]], 'wb'))
out:write(serialise.toJson(doc))
out:close()
"""


def decode_fov(stored):
    """1/(fov+15) back to degrees, the way core/fov does it."""
    if stored == 0:
        return 0.00001
    return (1 - 15 * stored) / stored


def compare(original, written, path=''):
    """Walk both and report every difference migration does not explain."""
    problems = []

    if isinstance(original, dict):
        if not isinstance(written, dict):
            return ['%s: object became %s' % (path, type(written).__name__)]
        for key in original:
            here = '%s.%s' % (path, key)
            if key not in written:
                # A null in the source is a key with no value; the writer
                # leaves those out, exactly as CamTool 2 does on save.
                if original[key] is None:
                    continue
                problems.append('%s: missing' % here)
                continue
            problems += compare(original[key], written[key], here)
        for key in written:
            if key not in original and key not in ('version', 'interpolation_mode'):
                problems.append('%s.%s: appeared from nowhere' % (path, key))
        return problems

    if isinstance(original, list):
        if not isinstance(written, list):
            return ['%s: list became %s' % (path, type(written).__name__)]
        if len(original) != len(written):
            return ['%s: %d entries became %d'
                    % (path, len(original), len(written))]
        for i, (a, b) in enumerate(zip(original, written)):
            problems += compare(a, b, '%s[%d]' % (path, i))
        return problems

    if isinstance(original, (int, float)) and not isinstance(original, bool):
        expected = original
        if path.endswith('.camera_fov'):
            expected = decode_fov(original)
        if not isinstance(written, (int, float)):
            return ['%s: number became %r' % (path, written)]
        if expected == 0 or written == 0:
            same = abs(expected - written) < 1e-12
        else:
            same = abs(expected - written) / abs(expected) < 1e-12
        if not same:
            return ['%s: %r became %r' % (path, expected, written)]
        return []

    if original != written:
        return ['%s: %r became %r' % (path, original, written)]
    return []


def main():
    out_path = os.path.join(tempfile.gettempdir(), 'camtool3_serialise.json')
    script = SCRIPT % (FIXTURE, out_path.replace('\\', '/'))

    result = subprocess.run([LUAJIT, '-e', script], cwd=APP,
                            capture_output=True, text=True)
    if result.returncode != 0:
        print('luajit failed:\n' + result.stderr)
        return 1

    with open(out_path, encoding='utf-8') as handle:
        try:
            written = json.load(handle)
        except ValueError as error:
            print('what Lua wrote is not JSON: %s' % error)
            return 1

    with open(SOURCE, encoding='utf-8') as handle:
        original = json.load(handle)

    problems = compare(original, written)
    if problems:
        print('%d differences:' % len(problems))
        for line in problems[:40]:
            print('  ' + line)
        return 1

    print('round trip clean: %s parses, and matches the source'
          % os.path.basename(out_path))
    print('  %d cameras, %d bytes'
          % (len(written.get('pos') or []), os.path.getsize(out_path)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
