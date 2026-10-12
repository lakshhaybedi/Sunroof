#!/bin/bash
# Measures how much GPU time macOS's compositor (WindowServer) spends with the shelf closed vs open.
# Run it from Terminal with other apps idle (minimise anything that animates, e.g. a chat streaming a reply).
# Usage: scripts/gpu-check.sh
set -u
export LC_ALL=C # ioreg's output isn't all valid UTF-8; awk must treat it as bytes

ws() { # WindowServer's accumulated GPU time, in nanoseconds
  ioreg -l -w0 2>/dev/null | awk '/"IOUserClientCreator"/{c=($0 ~ /WindowServer/)}
    c && /"accumulatedGPUTime"/{match($0,/"accumulatedGPUTime"=[0-9]+/); t+=substr($0,RSTART+21,RLENGTH-21)}
    END{printf "%.0f", t}'
}
measure() { # ms of GPU per second over 5 s
  local a b s e
  a=$(ws); s=$(date +%s); sleep 5; b=$(ws); e=$(date +%s)
  if [ "${a:-0}" = 0 ] || [ "${b:-0}" = 0 ]; then echo "?"; return; fi
  echo $(( (b - a) / 1000000 / (e - s) ))
}

echo "Keep the shelf CLOSED. Measuring for 5 s…"
closed=$(measure)
echo "Now OPEN the shelf and don't touch anything. Starting in 3 s…"
sleep 3
opened=$(measure)
echo
echo "WindowServer GPU time — shelf closed: ${closed} ms/s, shelf open: ${opened} ms/s"
echo "(1000 ms/s would be the GPU busy all the time.)"
