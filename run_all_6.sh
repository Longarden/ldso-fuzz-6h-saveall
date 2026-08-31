#!/bin/bash
# run_all_6.sh — docker compose 없이 plain `docker run` 으로 6컨테이너 기동.
#   (우분투 docker.io 처럼 compose 플러그인이 없는 환경용. compose 있으면 docker-compose.yml 사용 가능)
#
#   Melkor×3(코어 1/2/3) + Lfuzzer×3(코어 4/5/6),
#   각 단일코어(--cpuset-cpus) · RAM 4GB(--memory) · 별도 출력폴더(마운트) · 전량 자체난수 저장.
#
# 사용:  bash run_all_6.sh [seconds]        # 기본 21600 = 6시간
#        bash run_all_6.sh 60               # 60초 스모크
# 확인:  docker ps ; docker stats ; ls output/lfuzzer1/*.so | wc -l
# 중지:  bash stop_all_6.sh
set -u
SECS=${1:-21600}
IMG=ldso-fuzz-6h-saveall
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT="$ROOT/output"

echo "[run_all_6] 이미지 빌드..."
docker build -t "$IMG" "$ROOT" || { echo "빌드 실패"; exit 1; }

launch() {   # short_name  cpu_index  mode
  local sn=$1 cpu=$2 mode=$3
  local name="fuzz_$sn"
  mkdir -p "$OUT/$sn"
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" \
    --cpuset-cpus "$cpu" --memory 4g --memory-swap 4g \
    -v "$OUT/$sn:/output" "$IMG" \
    bash -lc "bash /root/kit/run_saveall_6h.sh $mode $SECS" >/dev/null \
    && echo "  기동: $name (cpu=$cpu, 4GB) → output/$sn"
}

echo "[run_all_6] 6컨테이너 기동 (${SECS}s)..."
launch melkor1 1 melkor
launch melkor2 2 melkor
launch melkor3 3 melkor
launch lfuzzer1 4 lfuzzer
launch lfuzzer2 5 lfuzzer
launch lfuzzer3 6 lfuzzer

echo "[run_all_6] 상태:"
docker ps --filter "name=fuzz_" --format "  {{.Names}}\t{{.Status}}"
echo "출력은 호스트의 $OUT/<name>/ 에 직접 쌓인다(컨테이너 밖 영속)."
