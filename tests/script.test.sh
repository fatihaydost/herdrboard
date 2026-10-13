#!/bin/bash
# Tests for package/contents/scripts/herdboard-sessions. Run: bash tests/script.test.sh
# Uses a stub `herdr` on PATH; never talks to a real herdr server or KWin.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERDBOARD_SCRIPT:-$HERE/../package/contents/scripts/herdboard-sessions}"
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

(( fail == 0 )) && echo "all $n tests passed"
exit $fail
