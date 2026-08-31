#!/bin/bash
# stop_all_6.sh — run_all_6.sh 로 띄운 6컨테이너 중지·제거(출력 파일은 마운트라 남는다).
set -u
for n in fuzz_melkor1 fuzz_melkor2 fuzz_melkor3 fuzz_lfuzzer1 fuzz_lfuzzer2 fuzz_lfuzzer3; do
  docker rm -f "$n" >/dev/null 2>&1 && echo "제거: $n" || true
done
echo "출력 폴더(output/*)의 .so 파일은 그대로 남아있음(마운트 영속)."
