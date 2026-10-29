#!/usr/bin/env node
/**
 * 15-link-residue — 清算 dsh 0.2.x 上 link() 的残余引用
 *
 * 2026-10-29 真机实测发现：旧 patch-dsh-android-link.js 只改两个固定调用点
 * 并从 import 删 link，但 0.2.x 还有它看不到的引用：
 *   A) 对象字面量简写 `link,`（session-persistence-jsonl:1615 defaultFileSystem）
 *      import 被删后就是未定义变量，模块 import 即 ReferenceError: link is not defined
 *   B) 参数名不同的调用点 `await link(source, target)` / `await link(staged.path, target)`
 *      （attachment-local:494/555），旧脚本锚点不匹配，Android 上照旧 EACCES
 *
 * 原则：只新增、只改调用，**绝不从 import 删 link**——多余导入无害，缺导入致命。
 * 幂等：带 marker，可重复执行。
 */
import fs from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
const ri = argv.indexOf('--root');
const ROOT = ri >= 0 ? argv[ri + 1] : null;
if (!ROOT) { console.error('[FAIL] 需要 --root <@deepseek-ai 目录>'); process.exit(64); }

const MARKER = 'dsh-android-link-residue';
let patched = 0;

const load = (rel) => {
  const f = path.join(ROOT, rel);
  return fs.existsSync(f) ? { f, rel, src: fs.readFileSync(f, 'utf8') } : null;
};
const save = (t, src, what) => { fs.writeFileSync(t.f, src); patched++; console.log(`[PATCHED ] ${t.rel}: ${what}`); };
const skip = (t, what) => console.log(`[OK      ] ${t.rel}: ${what}`);

/** 确保 fs/promises 导入里有 rename（只增不删） */
function ensureRename(src) {
  const m = /^(import \{)([^}]*)(\} from "node:fs\/promises";)$/m.exec(src);
  if (!m) return src;
  const names = m[2].split(',').map((s) => s.trim()).filter(Boolean);
  if (names.includes('rename')) return src;
  names.splice(1, 0, 'rename');
  return src.replace(m[0], `${m[1]} ${names.join(', ')} ${m[3]}`);
}

/** A 类：简写 link, -> link: (…) => rename(…) */
function fixShorthand(rel) {
  const t = load(rel);
  if (!t) return console.log(`[MISSING ] ${rel}`);
  if (t.src.includes(MARKER)) return skip(t, '简写已展开');
  const re = /(^[ \t]*)link,[ \t]*$/m;
  if (!re.test(t.src)) return skip(t, '无简写 link 属性');
  let src = t.src.replace(re, `$1link: (source, target) => rename(source, target), /* ${MARKER} A */`);
  src = ensureRename(src);
  return save(t, src, '简写 link -> rename（保留属性名）');
}

/** B 类：任意参数名的 await link(a, b) */
function fixCallSites(rel) {
  const t = load(rel);
  if (!t) return console.log(`[MISSING ] ${rel}`);
  if (t.src.includes(MARKER)) return skip(t, '调用点已改');
  const re = /await link\(([^(),\n]+),\s*([^(),\n]+)\);/g;
  const hits = [...t.src.matchAll(re)];
  if (!hits.length) return skip(t, '无残余 await link() 调用');
  let src = t.src.replace(re, (_w, a, b) => `/* ${MARKER} B */ await rename(${a}, ${b});`);
  src = ensureRename(src);
  return save(t, src, `${hits.length} 处 link() -> rename`);
}

fixShorthand('dsh-session-persistence-jsonl/lib/index.js');
fixCallSites('dsh-attachment-local/lib/index.js');
console.log(`[residue ] 本次修补 ${patched} 个文件`);
