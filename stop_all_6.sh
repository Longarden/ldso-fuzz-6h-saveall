#!/bin/bash
# stop_all_6.sh — run_all_6.sh 로 띄운 6컨테이너를 '중지'만 한다(삭제 안 함).
#   ★ 컨테이너는 삭제하지 않는다(docker stop). 삭제하려면 사용자가 직접 docker rm.
#   출력 파일은 마운트라 어차피 호스트에 그대로 남는다.
set -u
for n in fuzz_melkor1 fuzz_melkor2 fuzz_melkor3 fuzz_lfuzzer1 fuzz_lfuzzer2 fuzz_lfuzzer3; do
  docker stop "$n" >/dev/null 2>&1 && echo "중지(삭제 안함): $n" || true
done
echo "컨테이너는 남아있고(Exited), 출력 폴더(output/*)의 .so 파일도 그대로다(마운트 영속)."
echo "정말 삭제하려면 직접:  docker rm fuzz_melkor1 ...  (자동 삭제 안 함)"
