#!/bin/bash
# status_6.sh — 6컨테이너 상태를 한 표로: 실행상태 · CPU핀 · 생성파일수 · 최근 로그.
#   사용: bash status_6.sh        (한 번 스냅샷)
#         watch -n5 bash status_6.sh   (5초마다 갱신)
set -u
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT="$ROOT/output"
printf "%-15s %-9s %-7s %-9s %s\n" 컨테이너 상태 CPU핀 파일수 "최근로그"
printf "%-15s %-9s %-7s %-9s %s\n" --------- ---- ----- ----- --------
for sn in melkor1 melkor2 melkor3 lfuzzer1 lfuzzer2 lfuzzer3; do
  name="fuzz_$sn"
  state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo none)
  cpu=$(docker inspect -f '{{.HostConfig.CpusetCpus}}' "$name" 2>/dev/null)
  files=$(ls "$OUT/$sn"/*.so 2>/dev/null | wc -l)
  log=$(docker logs --tail 1 "$name" 2>&1 | tr -d '\r' | tail -c 42)
  printf "%-15s %-9s %-7s %-9s %s\n" "$name" "${state:-none}" "${cpu:--}" "$files" "$log"
done
echo "--- CPU/RAM 순간 사용량 ---"
docker stats --no-stream --format '{{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}}' 2>/dev/null | grep fuzz_ || echo "(실행중인 컨테이너 없음)"
