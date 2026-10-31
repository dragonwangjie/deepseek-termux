#!/data/data/com.termux/files/usr/bin/sh
# verify-deploy.sh - functional post-deploy checks for dsh on Android/Termux.
# Exercises real behaviour (http round-trip, real link() syscall). It does NOT
# grep source files, so it cannot be fooled by a patched-but-broken install.
# Run inside Termux:  sh verify-deploy.sh   (exit 0 == all required checks pass)
# SIDE EFFECT: check 4 calls durl, which is self-healing and will (re)start the
# service if it is down. That is intentional; do not run it just to "peek".
H=${HOME:-/data/data/com.termux/files/home}
U=/data/data/com.termux/files/usr
DSHDIR=${DSHDIR:-$H/dsh022/node_modules/@deepseek-ai/dsh}
fails=0
warns=0
ok(){ printf "OK   %s\n" "$1"; }
bad(){ printf "FAIL %s\n" "$1"; fails=$((fails+1)); }
wrn(){ printf "WARN %s\n" "$1"; warns=$((warns+1)); }

# 1 node must actually execute and meet the dsh engines floor
NV=$($U/bin/node -p "process.versions.node" 2>/dev/null)
if [ -z "$NV" ]; then
  bad "node not runnable"
else
  $U/bin/node -e "const v=process.versions.node.split(\".\").map(Number),f=[24,9,0];for(let i=0;i<3;i++){if(v[i]>f[i])process.exit(0);if(v[i]<f[i])process.exit(1)}process.exit(0)" 2>/dev/null && ok "node $NV meets engines floor 24.9.0" || bad "node $NV below engines floor 24.9.0"
fi

# 2 dsh package resolves and its entrypoint exists
DV=$($U/bin/node -e "try{process.stdout.write(require(process.argv[1]).version)}catch(e){}" "$DSHDIR/package.json" 2>/dev/null)
if [ -n "$DV" ]; then ok "dsh $DV"; else bad "cannot read dsh version from $DSHDIR/package.json"; fi
[ -f "$DSHDIR/lib/bin.js" ] && ok "lib/bin.js present" || bad "lib/bin.js missing"

# 3 launcher scripts parse
for f in run-dsh.sh supervise.sh; do
  if [ ! -f "$H/$f" ]; then wrn "$H/$f missing (script layout not installed)"; continue; fi
  $U/bin/sh -n "$H/$f" 2>/dev/null && ok "$f syntax" || bad "$f syntax error"
done
[ -x "$U/bin/durl" ] && ok "durl installed in $U/bin" || wrn "durl not installed"

# 4 REAL round-trip: ask durl for a URL, follow token->cookie->200
URL=$($U/bin/durl 2>/dev/null | grep -o "http://[^ ]*token=[^ ]*" | tail -1)
if [ -z "$URL" ]; then
  bad "durl returned no reachable URL (if the screen was off: MIUI freezes com.termux on screen-off -> wake the screen and re-run)"
else
  J=/data/data/com.termux/verify_jar_$$
  R=$(curl -s -c "$J" -b "$J" -L -o /dev/null -m 15 -w "%{http_code} %{num_redirects}" "$URL" 2>/dev/null)
  rm -f "$J"
  set -- $R
  FC="$1"; RC="$2"
  if [ "$FC" = "200" ]; then ok "login round-trip final=200 redirects=$RC"; else bad "login round-trip final=${FC:-none} redirects=${RC:-none} (want 200)"; fi
fi

# 5 REAL link() probe: is hardlink blocked by SELinux on this ROM?
TD=$(mktemp -d "$H/.verify_link.XXXXXX" 2>/dev/null)
if [ -z "$TD" ]; then
  wrn "mktemp under $H failed; link() probe skipped"
else
  printf x > "$TD/a"
  if ln "$TD/a" "$TD/b" 2>/dev/null; then
    ok "link() permitted (rename() fallback patch optional)"
  else
    wrn "link() blocked by SELinux -> apply patches/patch-dsh-android-link.js so sessions/attachments persist"
  fi
  rm -rf "$TD"
fi

# 6 process census. NOTE: pgrep -f double-counts one supervisor because the
# in-script watchdog subshell inherits the same argv (proved: 1 logical
# supervisor -> 2 pids, ppid chain x->x). So keep only top-level supervisors,
# i.e. those whose parent is NOT itself a supervise.sh process.
topsup=0
for p in $(pgrep -f supervise.sh 2>/dev/null); do
  pp=$(cut -d " " -f4 /proc/$p/stat 2>/dev/null)
  pm=0
  if [ -n "$pp" ] && [ -r "/proc/$pp/cmdline" ]; then pm=$(tr "\\0" " " < "/proc/$pp/cmdline" 2>/dev/null | grep -c supervise.sh); else pm=0; fi
  [ "${pm:-0}" -eq 0 ] 2>/dev/null && topsup=$((topsup+1))
done
topnode=0
for p in $(pgrep -f "dsh/lib/bin.js" 2>/dev/null); do
  pp=$(cut -d " " -f4 /proc/$p/stat 2>/dev/null)
  pm=0
  if [ -n "$pp" ] && [ -r "/proc/$pp/cmdline" ]; then pm=$(tr "\\0" " " < "/proc/$pp/cmdline" 2>/dev/null | grep -c dsh/lib/bin.js); else pm=0; fi
  [ "${pm:-0}" -eq 0 ] 2>/dev/null && topnode=$((topnode+1))
done
case "$topsup" in
  0) wrn "no supervisor running (service is unsupervised)" ;;
  1) ok "one supervisor" ;;
  *) bad "$topsup independent supervisors (expected 1)" ;;
esac
case "$topnode" in
  1) ok "one dsh node process" ;;
  0) wrn "no dsh node process alive" ;;
  *) bad "$topnode node processes (expected 1)" ;;
esac

printf "\n== fails=%d warns=%d\n" "$fails" "$warns"
[ "$fails" -eq 0 ] || exit 1
exit 0
