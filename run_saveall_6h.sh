#!/bin/bash
# run_saveall_6h.sh — Lfuzzer(hetero) 또는 Melkor 를 단일코어로 N초 돌리며
# 생성된 '모든' 변이 ELF 를 '마운트 폴더에 직접' 낱개·연번(NNNNNNNNN.so)으로 저장.
#
#   ★ 압축 없음.  ★ 수집기/스테이징 없음(퍼저가 $OUTDIR 에 곧바로 씀).
#   ★ 크래시만이 아니라 전량 저장.  ★ 단일시드 prac.elf 로 두 퍼저 공통.
#
# 사용: bash run_saveall_6h.sh <lfuzzer|melkor> [seconds] [rng_seed]
#   기본 21600초(6h). rng_seed 는 인스턴스별 발산용(기본 0).
# 환경:
#   OUTDIR   최종 저장 폴더(마운트 볼륨). Docker=/output. 미지정 시 ~/fuzz_out.
#   LFUZZER  Lfuzzer 뮤테이터 저장소(~/lfuzzer), KIT 이 스크립트 폴더,
#   SEED     단일시드 파일 경로(기본 ~/seed_6h/prac.elf)
#   MELKOR_BIN, LDSO
set -u
MODE=${1:?usage: run_saveall_6h.sh <lfuzzer|melkor> [seconds] [rng_seed]}
TOTAL=${2:-21600}
RSEED=${3:-${RUN_SEED:-0}}
LFUZZER=${LFUZZER:-$HOME/lfuzzer}
KIT=${KIT:-$(cd "$(dirname "$0")" && pwd)}
SEED=${SEED:-$HOME/seed_6h/prac.elf}
LD=${LDSO:-/lib64/ld-linux-x86-64.so.2}
OUTDIR=${OUTDIR:-$HOME/fuzz_out}

mkdir -p "$OUTDIR"
export PYTHONPATH="$LFUZZER" LDSO="$LD" \
       LFUZZER_HETERO=1 LFUZZER_P_GENTLE=0.5 LFUZZER_P_CLAMP=0.0
unset LFUZZER_AXIS 2>/dev/null || true

if [ ! -f "$SEED" ]; then echo "[6h:$MODE] 시드 없음: $SEED"; exit 1; fi
# 베이스라인: 시드는 크래시 없이 로드되어야 함(시그널이면 부적합).
"$LD" "$SEED" >/dev/null 2>&1; brc=$?
if [ "$brc" -ge 128 ]; then echo "[6h:$MODE] 시드 baseline 크래시(rc=$brc) → 중단"; exit 1; fi

echo "[6h:$MODE] $(date) 단일시드=$SEED rng_seed=$RSEED → 전량·낱개·연번 직접저장 → $OUTDIR"

# 퍼저가 $OUTDIR 에 곧바로 NNNNNNNNN.so 를 쓴다(수집기 없음).
if [ "$MODE" = "lfuzzer" ]; then
  exec python3 "$KIT/run_lfuzzer_ld.py" "$SEED" "$OUTDIR" "$TOTAL" "$RSEED"
else
  exec python3 "$KIT/run_melkor_ld.py" "$SEED" "$OUTDIR" "$TOTAL" 40 10
fi
