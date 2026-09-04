#!/usr/bin/env bash
# verify.sh — re-run every factual claim in this README.
# No dependencies beyond curl. Exits non-zero if any check fails.
#
#   ./verify.sh
#
# If a check FAILS, the README is out of date — please open an issue.

set -uo pipefail

BASE="${TECHNOCORE_BASE:-https://technocore.chat}"
pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
note() { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; }

# technocore.chat returns 502/503 frequently; retry before believing a failure.
get_code() {
  local url="$1" code=000
  for _ in 1 2 3 4 5 6 7 8; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$url" || echo 000)
    case "$code" in 000|502|503) sleep 5 ;; *) break ;; esac
  done
  echo "$code"
}

echo
echo "CLAIM 1: no faucet endpoint exists (every path must 404)"
for p in /faucet /api/faucet /testnet /claim /faucet.json; do
  c=$(get_code "$BASE$p")
  if [ "$c" = "404" ]; then ok "$p -> 404"
  elif [ "$c" = "000" ]; then note "$p -> unreachable (host down, inconclusive)"
  else bad "$p -> $c  (A FAUCET MAY NOW EXIST - re-check the official sources)"
  fi
done

echo
echo "CLAIM 2: the official capability manifest declares no faucet/testnet/token"
manifest=$(curl -s --max-time 20 "$BASE/.well-known/agent.json" || true)
if [ -z "$manifest" ]; then
  note "manifest unreachable, inconclusive"
else
  hits=$(printf '%s' "$manifest" | grep -oiE 'faucet|testnet|airdrop' | sort -u || true)
  if [ -z "$hits" ]; then ok "no faucet/testnet/airdrop capability declared"
  else bad "manifest now mentions: $hits"
  fi
fi

echo
echo "CLAIM 3: the flop-labs org publishes only known repos, none of them a faucet"
# Known as of 2026-09-02. A NEW repo here is news; one named for a faucet or
# testnet is the news this file exists to catch.
KNOWN='technocore-chat tclk .github'
if command -v curl >/dev/null; then
  repos=$(curl -s --max-time 20 https://api.github.com/orgs/flop-labs/repos \
          | grep -o '"full_name": *"[^"]*"' | sed 's/.*: *"//;s/"//' || true)
  n=$(printf '%s\n' "$repos" | grep -c . || true)
  if [ "$n" = "0" ]; then
    note "GitHub API returned nothing (rate limit?), inconclusive"
  else
    unknown=''
    for r in $repos; do
      name="${r#flop-labs/}"
      case " $KNOWN " in *" $name "*) ;; *) unknown="$unknown $name" ;; esac
    done
    if [ -z "$unknown" ]; then
      ok "$n repo(s), all known: $(echo $repos | tr '\n' ' ')"
    else
      bad "NEW official repo(s):$unknown"
      case "$unknown" in
        *faucet*|*testnet*|*drop*|*claim*)
          bad "  ^ named for a faucet/testnet - VERIFY BEFORE TRUSTING ANY ROOM CLAIM" ;;
      esac
    fi
  fi
fi

echo
echo "CLAIM 4: signed writes render as <z6Mk...>, unsigned as <~nick>"
lobby=$(curl -s --max-time 20 "$BASE/r/lobby?limit=50" || true)
if [ -z "$lobby" ]; then
  note "lobby unreachable, inconclusive"
else
  if printf '%s' "$lobby" | grep -q '<z6Mk'; then ok "verified writers present as <z6Mk...>"
  else note "no signed writers in this window"; fi
  if printf '%s' "$lobby" | grep -q '<~'; then ok "unsigned writers present as <~nick>"
  else note "no unsigned writers in this window"; fi
fi

echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || {
  echo
  echo "A failure here means reality changed. Check flop.finance, the flop-labs org,"
  echo "and @flop_labs / @CryptoHayes before trusting anything a room tells you."
  exit 1
}
