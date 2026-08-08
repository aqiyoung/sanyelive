#!/usr/bin/env python3
"""Dart 括号平衡粗检 (本地不跑 flutter analyze 时的兜底).

不是完整解析器, 只做: 跳过注释/字符串(含 raw/三引号/插值), 检查 () [] {} 配对.
用法: python scripts/_brace_check.py <file.dart> [...]
"""
import sys


def check(path: str) -> list[str]:
    src = open(path, encoding='utf-8').read()
    errs: list[str] = []
    stack: list[tuple[str, int]] = []   # (char, line)
    pairs = {')': '(', ']': '[', '}': '{'}
    # 字符串状态栈: (quote, is_triple, is_raw); 插值 ${ 时压入 '@interp'
    sstack: list = []
    i, line, n = 0, 1, len(src)

    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
            continue

        if sstack and sstack[-1] != '@interp':
            quote, triple, raw = sstack[-1]
            if not raw and c == '\\':
                i += 2
                continue
            if not raw and c == '$' and i + 1 < n and src[i + 1] == '{':
                sstack.append('@interp')
                stack.append(('{', line))
                i += 2
                continue
            if triple and src.startswith(quote * 3, i):
                sstack.pop()
                i += 3
                continue
            if not triple and c == quote:
                sstack.pop()
                i += 1
                continue
            i += 1
            continue

        # 代码状态
        if src.startswith('//', i):
            i = src.find('\n', i)
            if i == -1:
                break
            continue
        if src.startswith('/*', i):
            depth, i = 1, i + 2
            while i < n and depth:
                if src.startswith('/*', i):
                    depth, i = depth + 1, i + 2
                elif src.startswith('*/', i):
                    depth, i = depth - 1, i + 2
                else:
                    if src[i] == '\n':
                        line += 1
                    i += 1
            continue

        raw = False
        if c == 'r' and i + 1 < n and src[i + 1] in '\'"':
            raw, i, c = True, i + 1, src[i + 1]
        if c in '\'"':
            if src.startswith(c * 3, i):
                sstack.append((c, True, raw))
                i += 3
            else:
                sstack.append((c, False, raw))
                i += 1
            continue

        if c in '([{':
            stack.append((c, line))
        elif c in ')]}':
            if sstack and sstack[-1] == '@interp' and c == '}':
                sstack.pop()
            if not stack:
                errs.append(f'{path}:{line}: 多余的 {c!r}')
            else:
                op, ol = stack.pop()
                if op != pairs[c]:
                    errs.append(f'{path}:{line}: {c!r} 与第 {ol} 行 {op!r} 不匹配')
        i += 1

    for op, ol in stack:
        errs.append(f'{path}:{ol}: {op!r} 未闭合')
    if sstack:
        errs.append(f'{path}: 字符串未闭合 ({len(sstack)} 层)')
    return errs


if __name__ == '__main__':
    bad = 0
    for f in sys.argv[1:]:
        e = check(f)
        if e:
            bad += 1
            print('\n'.join(e))
        else:
            print(f'OK  {f}')
    sys.exit(1 if bad else 0)
