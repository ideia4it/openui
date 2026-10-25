#!/usr/bin/env bash
# Compiles a fresh project that depends on openui without phoenix_live_view,
# the way most hosts that only parse or generate prompts will use it. Fails on
# any warning and when LiveView code was compiled in.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cd "$work"
mix new consumer > /dev/null
cd consumer
cat > mix.exs <<MIX
defmodule Consumer.MixProject do
  use Mix.Project
  def project, do: [app: :consumer, version: "0.1.0", elixir: "~> 1.18", deps: [{:openui, path: "$root"}]]
end
MIX

mix deps.get > /dev/null
output="$(mix compile --force 2>&1)"
echo "$output" | tail -5
if echo "$output" | grep -qi "warning"; then
  echo "openui compiled with warnings without phoenix_live_view" >&2
  exit 1
fi

loaded="$(mix run -e 'IO.write(Code.ensure_loaded?(OpenUI.LiveView.Components))')"
if [ "$loaded" != "false" ]; then
  echo "OpenUI.LiveView.Components was compiled without phoenix_live_view" >&2
  exit 1
fi
echo "openui compiles cleanly without phoenix_live_view"
