#!/bin/bash
# status_6.sh — 6컨테이너 상태를 한 표로: 상태 · CPU핀 · 경과시간 · 생성파일수 · 최근 로그.
#   사용: bash status_6.sh          (한 번 스냅샷)
#         watch -n5 bash status_6.sh   (5초마다 갱신)
set -u
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT="$ROOT/output"

# --- docker 접근 선점검 (안 되면 상태가 전부 none 으로 뜨는 혼란 방지) ---
if ! docker ps >/dev/null 2>&1; then
  echo "⚠️ docker 명령 실패 — daemon 접근 불가(권한/데몬미기동/API버전)."
  echo "   진단:  docker ps    /    docker version"
  echo "   권한이면:  sudo usermod -aG docker \$USER  후 재로그인 (또는 sudo 로 실행)"
  echo "   데몬이면:  sudo systemctl start docker"
  exit 1
fi

now=$(date +%s)
printf "%-15s %-9s %-6s %-10s %-9s %s\n" 컨테이너 상태 CPU핀 "경과(/6h)" 파일수 "최근로그"
printf "%-15s %-9s %-6s %-10s %-9s %s\n" --------- ---- ----- --------- ----- --------
for sn in melkor1 melkor2 melkor3 lfuzzer1 lfuzzer2 lfuzzer3; do
  name="fuzz_$sn"
  state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo none)
  cpu=$(docker inspect -f '{{.HostConfig.CpusetCpus}}' "$name" 2>/dev/null)
  # 경과시간: running 이면 StartedAt 부터 지금까지
  started=$(docker inspect -f '{{.State.StartedAt}}' "$name" 2>/dev/null)
  if [ "$state" = "running" ] && [ -n "$started" ]; then
    se=$(date -d "$started" +%s 2>/dev/null || echo 0)
    if [ "$se" != 0 ]; then
      el=$(( now - se )); elapsed=$(printf '%dh%02dm' $((el/3600)) $(((el%3600)/60)))
    else elapsed="?"; fi
  else elapsed="-"; fi
  # 파일수: 컨테이너의 '실제 /output 마운트 경로'를 docker inspect로 읽어서 거기서 센다.
  #   (스크립트 위치·실행 경로에 의존하지 않게 — 0으로 잘못 세던 문제 수정)
  src=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/output"}}{{.Source}}{{end}}{{end}}' "$name" 2>/dev/null)
  [ -z "$src" ] && src="$OUT/$sn"     # 컨테이너 없으면 기본 경로로 폴백
  files=$(ls "$src"/*.so 2>/dev/null | wc -l)
  # 최근 로그: 마지막 5줄 중 '빈 줄 제외한 마지막 실제 줄'을 잡고 앞 공백 제거(튼튼하게).
  log=$(docker logs --tail 5 "$name" 2>&1 | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -1 | sed 's/^[[:space:]]*//' | tail -c 46)
  printf "%-15s %-9s %-6s %-10s %-9s %s\n" "$name" "${state:-none}" "${cpu:--}" "$elapsed" "$files" "$log"
done
echo "--- CPU/RAM 순간 사용량 ---"
docker stats --no-stream --format '{{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}}' 2>/dev/null | grep fuzz_ || echo "(실행중인 컨테이너 없음)"
