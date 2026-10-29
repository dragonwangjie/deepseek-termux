#!/usr/bin/env node
/**
 * dsh-patch — 统一的 dsh Android 适配入口（取代旧 patches/*.patch 文本 diff）
 *
 * 为什么重写：旧 5 个 .patch 按行锚点匹配，实测在 dsh 0.2.2-alpha.2 上 5/5 失配，
 * 其中 2 个目标包（dsh-host-apiproxy / dsh-client-runtime）已被上游重构掉。
 * 新机制沿用 patch-dsh-android-link.js 已验证的做法：marker 锚点 + 幂等 + 版本门，
 * 锚点失配时只报告不写盘、不猜。
 *
 * 用法：node dsh-patch.mjs --root <@deepseek-ai 目录> [--list] [--check] [--only <id>] [--verbose]
 * 退出码：0 全部成功/已就位 | 2 有补丁需人工重建锚点 | 1 真失败
 */
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const args = process.argv.slice(2);
const get = (f) => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : undefined; };
const has = (f) => args.includes(f);
const VERBOSE = has('--verbose');
const scriptDir = import.meta.dirname ?? path.dirname(new URL(import.meta.url).pathname);

/** 兼容仓库布局（v2/ 与 patches/ 同级）与扁平部署布局（全部同目录） */
function findRel(rel) {
  const base = path.basename(rel);
  const cands = [
    path.join(scriptDir, rel),
    path.join(scriptDir, '..', rel),
    path.join(scriptDir, 'patches', base),
    path.join(scriptDir, '..', 'patches', base),
    path.join(scriptDir, base),
  ];
  return cands.find((p) => fs.existsSync(p)) ?? null;
}

function resolveRoot() {
  const given = get('--root');
  if (given) return given;
  const out = spawnSync('npm', ['root', '-g'], { encoding: 'utf8' }).stdout?.trim();
  const cand = [out && path.join(out, '@deepseek-ai'),
    '/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai'].filter(Boolean);
  return cand.find((d) => fs.existsSync(d)) ?? null;
}

/** 从 @deepseek-ai 目录向上找到安装根（顶层 node_modules 所在处） */
function installRoot(scopeRoot) {
  let d = scopeRoot;
  while (d && d !== '/') {
    if (fs.existsSync(path.join(d, 'node-addon-require-builtin'))) return d;
    const parent = path.dirname(d);
    if (parent === d) break;
    d = parent;
    if (path.basename(d) === 'node_modules') return d;
  }
  return path.dirname(scopeRoot);
}

function dshVersion(root) {
  for (const p of [path.join(root, 'dsh/package.json'), path.join(root, '..', 'dsh/package.json')]) {
    try { return JSON.parse(fs.readFileSync(p, 'utf8')).version; } catch { /* next */ }
  }
  return null;
}

/** major.minor 区间门 */
function inRange(version, range) {
  if (!version || !range) return true;
  const key = (v) => { const m = /^(\d+)\.(\d+)/.exec(v); return m ? Number(m[1]) * 100 + Number(m[2]) : NaN; };
  const v = key(version), a = key(range[0]), b = key(range[1]);
  return Number.isNaN(v) ? true : (v >= a && v <= b);
}

const c = (n, s) => `\x1b[${n}m${s}\x1b[0m`;
const info = (s) => console.log(c('1;34', '==>'), s);
const okLn = (s) => console.log(c('1;32', '[ok]  '), s);
const skipLn = (s) => console.log(c('1;33', '[skip]'), s);
const fixLn = (s) => console.log(c('1;36', '[fix] '), s);
const badLn = (s) => console.log(c('1;31', '[FAIL]'), s);
const naLn = (s) => console.log(c('1;35', '[n/a] '), s);

const PATCHES = [
  {
    id: '10-android-link',
    title: 'link() -> rename()（SELinux 禁硬链接：会话/附件/write 新建文件）',
    run: (ctx) => {
      const script = findRel(path.join('patches', 'patch-dsh-android-link.js'));
      if (!script) return { status: 'fail', msg: '找不到 patch-dsh-android-link.js' };
      const r = spawnSync(process.execPath, [script, '--root', ctx.root], { encoding: 'utf8' });
      const out = `${r.stdout ?? ''}${r.stderr ?? ''}`;
      if (r.status !== 0) return { status: 'fail', msg: out.split('\n').slice(0, 3).join(' / ') };
      const n = (out.match(/\[PATCHED\s*\]/g) || []).length;
      if (n > 0) return { status: 'patched', msg: `${n} 处已修补（重启 dsh 生效）` };
      const first = (out.match(/\[OK\s*\][^\n]*/) || ['已是目标态'])[0].trim();
      return { status: 'skip', msg: first };
    },
  },
  {
    id: '15-link-residue',
    title: '清算 0.2.x 的 link() 残余（简写属性 + 异名调用点，旧脚本盖不到）',
    run: (ctx) => {
      const script = findRel('15-link-residue.mjs');
      if (!script) return { status: 'fail', msg: '找不到 15-link-residue.mjs' };
      const r = spawnSync(process.execPath, [script, '--root', ctx.root], { encoding: 'utf8' });
      const out = `${r.stdout ?? ''}${r.stderr ?? ''}`;
      if (r.status !== 0) return { status: 'fail', msg: out.split('\n').slice(0, 3).join(' / ') };
      const n = (out.match(/\[PATCHED\s*\]/g) || []).length;
      if (n > 0) return { status: 'patched', msg: `${n} 个文件的 link 残余已清算` };
      return { status: 'skip', msg: (out.match(/\[OK\s*\][^\n]*/) || ['无残余'])[0].trim() };
    },
  },
  {
    id: '20-narb-android',
    title: 'node-addon-require-builtin 本地构建（0.2.x 硬依赖，官方无 android 预编译）',
    range: ['0.2.0', '0.99.99'],
    run: (ctx) => {
      const narbDir = path.join(ctx.installRoot, 'node-addon-require-builtin');
      if (!fs.existsSync(narbDir)) return { status: 'skip', msg: '此版本不依赖 narb' };
      const probe = spawnSync(process.execPath, ['-e',
        `try{const n=require(${JSON.stringify(narbDir)});process.stdout.write(n.getBindingInfo().bindingSource)}catch(e){process.exit(1)}`,
      ], { encoding: 'utf8', cwd: ctx.installRoot });
      if (probe.status === 0 && probe.stdout.trim() === 'local-build') {
        return { status: 'skip', msg: 'binding 已可用（local-build）' };
      }
      if (ctx.check) {
        const why = `probe rc=${probe.status} out=${JSON.stringify((probe.stdout || '').trim())} err=${JSON.stringify(String(probe.stderr || '').split('\n')[0].slice(0, 90))}`;
        return { status: 'na', msg: `binding 未就绪，需 setup-narb-android.sh | ${why}` };
      }
      const script = findRel('setup-narb-android.sh');
      if (!script) return { status: 'fail', msg: '找不到 setup-narb-android.sh' };
      const r = spawnSync('bash', [script, '--root', ctx.root], { stdio: 'inherit' });
      return r.status === 0
        ? { status: 'patched', msg: 'narb 已本地构建并自检通过' }
        : { status: 'fail', msg: `setup-narb-android.sh 退出码 ${r.status}` };
    },
  },
  {
    id: '30-static-cache-immutable',
    title: '静态资产 immutable 缓存头（原 patches/04 的新载体，待量化收益）',
    run: (ctx) => {
      const f = path.join(ctx.root, 'dsh-host-frontend-static/lib/index.js');
      if (!fs.existsSync(f)) return { status: 'na', msg: 'dsh-host-frontend-static 不存在' };
      const s = fs.readFileSync(f, 'utf8');
      if (s.includes('dsh-android:immutable-cache')) return { status: 'skip', msg: '已应用' };
      const m = /"cache-control":\s*"no-cache"/.exec(s);
      if (!m) return { status: 'na', msg: '锚点（cache-control: no-cache）已不存在，需人工重建' };
      const ln = s.slice(0, m.index).split('\n').length;
      if (VERBOSE) info(`  锚点 ${f}:${ln}`);
      return { status: 'na', msg: `锚点在 :${ln}，但 dist 无内容哈希资产，改 immutable 会缓存过期——先确认上游是否已够快` };
    },
  },
  {
    id: '40-subprocess-android',
    title: 'subprocess 终端检测把 android 视同 linux',
    run: (ctx) => {
      const dir = path.join(ctx.root, 'dsh-subprocess-local/lib');
      if (!fs.existsSync(dir)) return { status: 'na', msg: 'dsh-subprocess-local 不存在' };
      const hits = [];
      for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.js'))) {
        const s = fs.readFileSync(path.join(dir, f), 'utf8');
        s.split('\n').forEach((l, i) => {
          if (/===\s*["']linux["']/.test(l)) hits.push(`${f}:${i + 1}`);
        });
      }
      if (!hits.length) return { status: 'na', msg: '未找到 platform === "linux" 判定，可能已内置' };
      if (ctx.check) return { status: 'na', msg: `${hits.length} 处候选（${hits.slice(0, 3).join(', ')}），语义各不同，需逐个核实` };
      let n = 0;
      for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.js'))) {
        const p = path.join(dir, f);
        const s = fs.readFileSync(p, 'utf8');
        if (!/===\s*["']linux["']/.test(s)) continue;
        if (s.includes('dsh-android:platform')) continue;
        if (!ctx.confirmed) {
          return { status: 'na', msg: '未传 --confirm-platform-patch，拒绝盲改影响沙箱判定的代码' };
        }
        const out = s.replace(/===\s*["']linux["']/g, `=== "linux" || process.platform === "android" /* dsh-android:platform */`);
        fs.writeFileSync(p, out);
        n += (out.match(/dsh-android:platform/g) || []).length;
      }
      return { status: 'patched', msg: `${n} 处已改为 android 视同 linux` };
    },
  },
];

const root = resolveRoot();
if (!root) { badLn('未找到 @deepseek-ai 目录，用 --root 指定'); process.exit(1); }
const ver = dshVersion(root);
const CHECK = has('--check');
const only = get('--only');
const ctx = { root, installRoot: installRoot(root), check: CHECK, confirmed: has('--confirm-platform-patch') };

info(`root: ${root}`);
info(`dsh : ${ver ?? '未知'}`);
if (has('--list')) {
  PATCHES.forEach((p) => console.log(`  ${p.id.padEnd(26)} ${p.title}`));
  process.exit(0);
}

let code = 0, ran = 0;
for (const p of PATCHES) {
  if (only && p.id !== only) continue;
  ran += 1;
  if (p.range && !inRange(ver, p.range)) {
    naLn(`${p.id}: dsh ${ver} 不在支持区间 ${p.range.join('..')}`);
    code = code || 2;
    continue;
  }
  let res;
  try { res = p.run(ctx); }
  catch (e) { res = { status: 'fail', msg: String((e && e.message) || e) }; }
  const line = `${p.id}: ${res.msg}`;
  if (res.status === 'ok' || res.status === 'patched') fixLn(line);
  else if (res.status === 'skip') skipLn(line);
  else if (res.status === 'na') { naLn(line); code = code || 2; }
  else { badLn(line); code = 1; }
}
if (!ran) { badLn(`--only ${only} 不在注册表`); process.exit(1); }
console.log(CHECK ? `[dsh-patch] 检查完成（--check 未写盘）rc=${code}` : `[dsh-patch] 完成 rc=${code}（2=有待人工重建的锚点）`);
process.exit(code);
