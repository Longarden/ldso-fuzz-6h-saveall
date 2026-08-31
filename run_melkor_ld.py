#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_melkor_ld.py — Melkor(-a 전메타데이터 치환)로 단일시드 prac.elf 를 변이 →
ld.so 로 실행 → '생성된 모든' 변이 ELF 를 '마운트 폴더에 직접' 연번저장.

핵심(설계 의도):
  - Melkor 바이너리는 시드 하나에서 -n N 개의 orc(변이본)를 한 번에 emit 한다.
    emit 된 orc 를 곧바로 OUT/NNNNNNNNN.so 로 옮긴다(수집기·스테이징·압축 없음).
  - Melkor 는 time/pid 로 자체 난수 → 같은 시드라도 인스턴스마다 자연히 다른 변이.
  - 크래시 여부는 OUT/_crashes.csv 에 (seq,rc) 로 기록(파일은 전량저장본에 이미 포함).
  - 단일코어 컨테이너용 단일 프로세스(워커 분산 없음 → 연번이 곧 전역 생성순서).

사용: python3 run_melkor_ld.py <seed_elf> <out_dir> <seconds> [n_mutants] [likelihood]
환경: MELKOR_BIN=~/melkor_repro/Melkor_ELF_Fuzzer/melkor, LDSO=/lib64/ld-linux-x86-64.so.2
"""
from __future__ import annotations
import os
import sys
import glob
import time
import shutil
import tempfile
import subprocess

SEED_PATH = os.path.expanduser(sys.argv[1])
OUT       = os.path.expanduser(sys.argv[2])
SECS      = float(sys.argv[3])
NMUT      = int(sys.argv[4]) if len(sys.argv) > 4 else 40
LIK       = int(sys.argv[5]) if len(sys.argv) > 5 else 10
MELKOR    = os.path.expanduser(os.environ.get("MELKOR_BIN",
                              "~/melkor_repro/Melkor_ELF_Fuzzer/melkor"))
LOADER    = os.environ.get("LDSO", "/lib64/ld-linux-x86-64.so.2")
TIMEOUT   = float(os.environ.get("LFUZZER_TIMEOUT", "3"))


def is_crash(rc: int) -> bool:
    return rc < 0 or rc == 124


def run_loader(path: str):
    try:
        r = subprocess.run([LOADER, path], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=TIMEOUT)
        return r.returncode
    except subprocess.TimeoutExpired:
        return 124
    except Exception:
        return None


def main():
    if not os.path.isfile(SEED_PATH):
        sys.exit("시드 파일 없음: %s" % SEED_PATH)
    os.makedirs(OUT, exist_ok=True)
    crash_log = open(os.path.join(OUT, "_crashes.csv"), "a", buffering=1)
    base = os.path.basename(SEED_PATH)
    tmp = tempfile.mkdtemp(prefix="melk_")

    n = 0
    crashes = 0
    t0 = time.time()
    deadline = t0 + SECS
    print("[melkor] seed=%s out=%s secs=%.0f -a -n%d -l%d → 전량 직접저장"
          % (SEED_PATH, OUT, SECS, NMUT, LIK), flush=True)

    try:
        while time.time() < deadline:
            # Melkor 로 시드에서 NMUT 개 변이 batch 생성(orcs_<base>/orc_*).
            try:
                subprocess.run([MELKOR, "-a", SEED_PATH, "-n", str(NMUT),
                                "-l", str(LIK), "-q"],
                               cwd=tmp, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=60)
            except Exception:
                continue
            orcs = os.path.join(tmp, "orcs_" + base)
            if not os.path.isdir(orcs):
                continue
            for orc in sorted(glob.glob(os.path.join(orcs, "orc_*"))):
                if time.time() >= deadline:
                    break
                n += 1
                # tmp 에서 크래시 판정(레이스 없음).
                rc = run_loader(orc)
                # ★ 마운트 폴더에 '직접' 연번 저장. 저장 성공 후에만 크래시 로그
                #   (이동 실패 시 연번-로그 desync 방지).
                dest = os.path.join(OUT, "%09d.so" % n)
                try:
                    shutil.move(orc, dest)
                    os.chmod(dest, 0o755)      # 원본 prac.elf 처럼 실행권한(+x) 부여
                except Exception:
                    n -= 1
                    continue
                if rc is not None and is_crash(rc):
                    crashes += 1
                    crash_log.write("%09d,%d\n" % (n, rc))
                if n % 200 == 0:      # 진행로그(살아있음 표시) — lfuzzer 와 동일 패턴
                    el = time.time() - t0
                    print("  execs=%d crash=%d rate=%.1f/s elapsed=%.0fs"
                          % (n, crashes, n / max(el, 1e-9), el), flush=True)
            shutil.rmtree(orcs, ignore_errors=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        crash_log.close()

    print("[melkor] done execs=%d crash=%d elapsed=%.0fs → %s"
          % (n, crashes, time.time() - t0, OUT), flush=True)
    print("MELKOR_DONE", flush=True)


if __name__ == "__main__":
    main()
