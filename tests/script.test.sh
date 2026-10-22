#!/bin/bash
# Tests for package/contents/scripts/herdrboard-sessions. Run: bash tests/script.test.sh
# Uses a stub `herdr` on PATH; never talks to a real herdr server or KWin.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERDRBOARD_SCRIPT:-$HERE/../package/contents/scripts/herdrboard-sessions}"
n=0
fail=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
bad() { n=$((n + 1)); fail=1; echo "not ok $n - $1"; }

tmp=$(mktemp)
# ------------------------------------------------ session_in_args (sourced)
(
  set +e
  # shellcheck source=/dev/null
  source "$SCRIPT"
  check() { # args expect-session expect-target  (expect "-" = not a client)
    if session_in_args "$1"; then got="$found_session|$found_target"; else got="-"; fi
    if [[ $got == "$2" ]]; then echo "PASS"; else echo "FAIL [$1] got=$got want=$2"; fi
  }
  check "herdr" "default|"
  check "/home/u/.local/bin/herdr --session proj" "proj|"
  check "herdr --session=proj" "proj|"
  check "herdr --remote box --session=proj" "proj|box"
  check "herdr --remote=user@box:2222" "default|user@box:2222"
  check "herdr --remote -Fevil" "-"
  check "/home/u/.local/bin/herdr server" "-"
  check "herdr api snapshot" "-"
  check "man herdr" "-"
  check "cargo install herdr" "-"
  check "vim /tmp/herdr" "-"
  check "ssh box herdr" "-"
  check "konsole --separate -e bash -c a=(herdr)" "-"
  check "herdr --session a;b" "-"
  valid_machine_target "-oProxyCommand=x" && echo "FAIL target -o accepted" || echo PASS
  valid_machine_target "ssh://me@host.example:22" && echo PASS || echo "FAIL ssh url refused"
) > "$tmp" 2>&1
if grep -q FAIL "$tmp"; then
  bad "session_in_args / target fence"; grep FAIL "$tmp"
else
  ok "session_in_args: only argv0 herdr is a client; --x=y forms; target fence ($(grep -c PASS "$tmp") cases)"
fi
rm -f "$tmp"

# ------------------------------------------- one bad snapshot (stub herdr)
stub=$(mktemp -d)
trap 'rm -rf -- "$stub"' EXIT
cat > "$stub/herdr" <<'EOF'
#!/bin/bash
case "$*" in
  "session list --json")
    echo '{"sessions":[{"name":"default","default":true,"running":true,"session_dir":"/x"},{"name":"good","running":true,"session_dir":"/x/g"},{"name":"broken","running":true,"session_dir":"/x/b"}]}' ;;
  "api snapshot")
    echo '{"result":{"snapshot":{"version":"0.9.1","agents":[{"agent_status":"blocked","pane_id":"w1:p1","terminal_title":"a","workspace_id":"w1","tab_id":"w1:t1"}],"workspaces":[{"workspace_id":"w1","label":"api"}],"tabs":[]}}}' ;;
  "--session good api snapshot")
    echo '{"result":{"snapshot":{"version":"0.9.1","agents":[{"agent_status":"working","pane_id":"w1:p1","terminal_title":"b","workspace_id":"w1","tab_id":"w1:t1"}],"workspaces":[],"tabs":[]}}}' ;;
  "--session broken api snapshot")
    echo '{"result": {"snapsh' ;;
  "machine list --json") echo '[]' ;;
  "--version") echo 'herdr 0.9.1' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stub/herdr"
out=$(PATH="$stub:$PATH" XDG_CACHE_HOME="$stub/cache" bash "$SCRIPT" list --no-windows < /dev/null)
if [[ $(jq -c '[.blocked, .working, .running, ([.sessions[] | select(.name == "broken") | .error][0])]' <<<"$out") == '[1,1,3,"no answer from this server"]' ]]; then
  ok "a broken snapshot marks its own row; the others still count"
else
  bad "broken snapshot isolation: $(jq -c '{blocked,working,running,s:[.sessions[]|{name,error,agents}]}' <<<"$out")"
fi

# --------------------------------------------------- a wedged local herdr
cat > "$stub/herdr" <<'EOF'
#!/bin/bash
sleep 30
EOF
start=$(date +%s)
out=$(PATH="$stub:$PATH" XDG_CACHE_HOME="$stub/cache" bash "$SCRIPT" list --no-windows < /dev/null)
took=$(( $(date +%s) - start ))
if (( took <= 8 )) && [[ $(jq -r .ok <<<"$out") == false ]]; then
  ok "a wedged herdr times out (${took}s) instead of hanging the poll"
else
  bad "wedged herdr: took ${took}s, output $out"
fi

# --------------------------------------------- terminal choice and argv
# A separate kdeglobals in a temp XDG_CONFIG_HOME; stub terminals on a PATH
# that holds nothing else, so the real machine's terminals cannot answer.
term=$(mktemp -d)
mkdir -p "$term/bin" "$term/config" "$term/data/applications"
for t in kitty konsole wezterm gnome-terminal foot ghostty alacritty myterm xdg-terminal-exec; do
  printf '#!/bin/sh\n' > "$term/bin/$t"; chmod +x "$term/bin/$t"
done
for t in kreadconfig6 sed head dirname id; do ln -s "$(command -v $t)" "$term/bin/$t"; done
printf '[Desktop Entry]\nName=Ghost\nExec=ghostty --gtk-single-instance=false %%U\n' > "$term/data/applications/com.mitchellh.ghostty.desktop"
printf '[Desktop Entry]\nExec="weird" %%U\n' > "$term/data/applications/quoted.desktop"
argv_for() { # TerminalApplication TerminalService [drop-from-path...]
  : > "$term/config/kdeglobals"
  { echo "[General]"; [[ -n $1 ]] && echo "TerminalApplication=$1"; [[ -n $2 ]] && echo "TerminalService=$2"; } > "$term/config/kdeglobals"
  local drop
  for drop in "${@:3}"; do mv "$term/bin/$drop" "$term/bin/$drop.off"; done
  ( export PATH="$term/bin" XDG_CONFIG_HOME="$term/config" XDG_DATA_HOME="$term/data" XDG_DATA_DIRS="$term/none"
    source "$SCRIPT"; set +e
    launch=(); launch_argv /p/herdrboard-attach && printf '%s|' "${launch[@]}" )
  for drop in "${@:3}"; do mv "$term/bin/$drop.off" "$term/bin/$drop"; done
}
expect_argv() { # want got label
  if [[ $2 == "$1" ]]; then ok "terminal: $3"; else bad "terminal: $3: got [$2] want [$1]"; fi
}
expect_argv "kitty|--single-instance|bash|/p/herdrboard-attach|" "$(argv_for 'kitty --single-instance' '')" "TerminalApplication with arguments, kitty runs the program directly"
expect_argv "konsole|--separate|-e|bash|/p/herdrboard-attach|" "$(argv_for 'konsole' '')" "konsole gets --separate and -e"
expect_argv "wezterm|start|--|bash|/p/herdrboard-attach|" "$(argv_for 'wezterm' '')" "wezterm start --"
expect_argv "gnome-terminal|--|bash|/p/herdrboard-attach|" "$(argv_for 'gnome-terminal' '')" "gnome-terminal --"
expect_argv "foot|bash|/p/herdrboard-attach|" "$(argv_for 'foot' '')" "foot direct"
expect_argv "myterm|-e|bash|/p/herdrboard-attach|" "$(argv_for 'myterm' '')" "unknown terminal gets -e"
expect_argv "ghostty|--gtk-single-instance=false|-e|bash|/p/herdrboard-attach|" "$(argv_for '' 'com.mitchellh.ghostty.desktop')" "TerminalService: Exec without field codes, ghostty -e"
expect_argv "xdg-terminal-exec|bash|/p/herdrboard-attach|" "$(argv_for 'notinstalled -x' 'quoted.desktop')" "missing app and quoted Exec fall through to xdg-terminal-exec"
expect_argv "konsole|--separate|-e|bash|/p/herdrboard-attach|" "$(argv_for '' '' xdg-terminal-exec)" "nothing set, no xdg-terminal-exec: konsole"
expect_argv "" "$(argv_for '' '' xdg-terminal-exec konsole)" "no terminal at all: launch_argv fails"
expect_argv "xdg-terminal-exec|bash|/p/herdrboard-attach|" "$(argv_for 'kitty; touch /tmp/pwned' '')" "a shell metacharacter stays in the word: \"kitty;\" is no command, nothing evaluated"
rm -rf -- "$term"

# ------------------------------------------------ kill / delete (stub ss)
# A fake herdr server is a real process (comm "herdr", argv "server") and a
# stub `ss` points the session's socket at it, so the /proc checks run for
# real. Each is started in a subshell that exits, so nothing here keeps it as
# a zombie that `kill -0` would still see.
kd=$(mktemp -d)
cat > "$kd/herdr" <<'EOF2'
#!/bin/bash
case "$1 ${2-}" in
  "server ") [[ -n ${HB_IGNORE_TERM-} ]] && trap '' TERM; while :; do sleep 0.05; done ;;
  "session list")
    printf '{"sessions":[{"name":"proj","running":true,"socket_path":"%s"},{"name":"old","running":false},{"name":"bad","running":false}]}\n' "$HB_SOCK" ;;
  "session delete") [[ $3 == bad ]] && exit 1; echo "$3" >> "$HB_LOG" ;;
  *) exit 1 ;;
esac
EOF2
cat > "$kd/ss" <<'EOF2'
#!/bin/bash
printf 'u_str LISTEN 0 4096 %s 1 * 0 users:(("herdr",pid=%s,fd=3))\n' "$HB_SOCK" "$(cat "$HB_PIDFILE")"
EOF2
chmod +x "$kd/herdr" "$kd/ss"
export HB_SOCK="$kd/proj.sock" HB_PIDFILE="$kd/pid" HB_LOG="$kd/deleted"
hb() { PATH="$kd:$PATH" XDG_CACHE_HOME="$kd/cache" bash "$SCRIPT" "$@" < /dev/null; }
spawn() { ( "$@" > /dev/null 2>&1 & echo $! > "$HB_PIDFILE" ); }
gone() { local i; for ((i = 0; i < 20; i++)); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.05; done; return 1; }

spawn "$kd/herdr" server; pid=$(cat "$HB_PIDFILE")
if [[ $(hb kill proj | jq -r .ok) == true ]] && gone "$pid"; then
  ok "kill: TERM ends the session's server"
else bad "kill: server $pid still alive"; kill -KILL "$pid" 2>/dev/null; fi

spawn env HB_IGNORE_TERM=1 "$kd/herdr" server; pid=$(cat "$HB_PIDFILE")
if [[ $(hb kill proj | jq -r .ok) == true ]] && gone "$pid"; then
  ok "kill: a server that ignores TERM gets KILL"
else bad "kill: TERM-ignoring server $pid still alive"; kill -KILL "$pid" 2>/dev/null; fi

spawn sleep 30; pid=$(cat "$HB_PIDFILE")
out=$(hb kill proj)
if [[ $(jq -r .ok <<<"$out") == false ]] && kill -0 "$pid" 2>/dev/null; then
  ok "kill: a socket owned by something that is not a herdr server is left alone"
else bad "kill: non-herdr pid: $out"; fi
kill -KILL "$pid" 2>/dev/null

if [[ $(hb kill nosuch | jq -r .ok) == false && $(hb kill "a;b" | jq -r .ok) == false ]]; then
  ok "kill: unknown or malformed session refused"
else bad "kill: unknown session accepted"; fi

: > "$HB_LOG"
r_run=$(hb delete proj | jq -r .ok); r_old=$(hb delete old | jq -r .ok)
r_bad=$(hb delete bad | jq -r .ok); r_def=$(hb delete default | jq -r .ok)
if [[ "$r_run $r_old $r_bad $r_def" == "false true false false" && $(cat "$HB_LOG") == old ]]; then
  ok "delete: running and default refused, herdr's own refusal reported, stopped one deleted"
else bad "delete: running=$r_run old=$r_old bad=$r_bad default=$r_def log=[$(cat "$HB_LOG")]"; fi
rm -rf -- "$kd"

(( fail == 0 )) && echo "all $n tests passed"
exit $fail
