#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_lfuzzer_ld.py — Lfuzzer(structure_aware, hetero 기본 ON) 로 단일시드 prac.elf 를
변이 → ld.so 로 실행 → '생성된 모든' 변이 ELF 를 '마운트 폴더에 직접' 연번저장.

핵심(설계 의도):
  - run_nofeedback.py(연구 repo)는 크래시만 저장하고 SAVE_ALL 이 없다. 그래서 여기선
    뮤테이터(StructureAwareMutator)만 import 해 '전량저장 루프'를 이 키트가 직접 돈다.
  - 생성한 mutant 를 곧바로 OUT/NNNNNNNNN.so 로 쓴다(수집기·스테이징·압축 없음).
  - OUT 은 마운트 볼륨(Docker=/output) → 컨테이너 밖에 그대로 남는다.
  - 크래시 여부는 OUT/_crashes.csv 에 (seq,rc) 로 기록(파일은 전량저장본에 이미 포함).

사용: python3 run_lfuzzer_ld.py <seed_elf> <out_dir> <seconds> [rng_seed]
환경: PYTHONPATH=<lfuzzer repo>, LFUZZER_HETERO=1 등 뮤테이터 env 그대로 사용.
      LDSO=/lib64/ld-linux-x86-64.so.2, LFUZZER_TIMEOUT=3(초)
"""
from __future__ import annotations
import os
import sys
import time
import subprocess

from lfuzzer.mutators import structure_aware as SA

SEED_PATH = os.path.expanduser(sys.argv[1])
OUT       = os.path.expanduser(sys.argv[2])
SECS      = float(sys.argv[3])
RSEED     = int(sys.argv[4]) if len(sys.argv) > 4 else 0
LOADER    = os.environ.get("LDSO", "/lib64/ld-linux-x86-64.so.2")
TIMEOUT   = float(os.environ.get("LFUZZER_TIMEOUT", "3"))


def is_crash(rc: int) -> bool:
    """음수 rc(시그널 사망) 또는 124(timeout) = 크래시. (run_nofeedback 규약과 동치)"""
    return rc < 0 or rc == 124


def run_loader(path: str):
    """[ld.so, mutant] 직접 실행. 반환코드(또는 timeout=124, 실패=None)."""
    try:
        r = subprocess.run([LOADER, path], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=TIMEOUT)
        return r.returncode
    except subprocess.TimeoutExpired:
        return 124
    except Exception:
        return None


def main():
    with open(SEED_PATH, "rb") as f:
        seed = bytearray(f.read())
    os.makedirs(OUT, exist_ok=True)
    crash_log = open(os.path.join(OUT, "_crashes.csv"), "a", buffering=1)

    mut = SA.StructureAwareMutator(seed=RSEED)      # 결정론적 시드(인스턴스별 RSEED 로 발산)
    n = 0
    crashes = 0
    t0 = time.time()
    deadline = t0 + SECS
    print("[lfuzzer] seed=%s out=%s secs=%.0f rng_seed=%d hetero=%s → 전량 직접저장"
          % (SEED_PATH, OUT, SECS, RSEED, os.environ.get("LFUZZER_HETERO", "1")), flush=True)

    while time.time() < deadline:
        mutant = mut.fuzz(bytes(seed), None, max(len(seed) * 2, 4096))
        n += 1
        # ★ 마운트 폴더에 '직접' 연번 저장(수집기·압축·스테이징 없음).
        path = os.path.join(OUT, "%09d.so" % n)
        with open(path, "wb") as f:
            f.write(bytes(mutant))
        # 저장된 파일을 그대로 ld.so 로 실행 → 크래시 판정(파일은 어차피 보존).
        rc = run_loader(path)
        if rc is not None and is_crash(rc):
            crashes += 1
            crash_log.write("%09d,%d\n" % (n, rc))
        if n % 500 == 0:
            el = time.time() - t0
            print("  execs=%d crash=%d rate=%.1f/s elapsed=%.0fs"
                  % (n, crashes, n / max(el, 1e-9), el), flush=True)

    crash_log.close()
    print("[lfuzzer] done execs=%d crash=%d elapsed=%.0fs → %s"
          % (n, crashes, time.time() - t0, OUT), flush=True)
    print("LFUZZER_DONE", flush=True)


if __name__ == "__main__":
    main()
