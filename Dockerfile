# ldso-fuzz-6h-saveall — Lfuzzer vs Melkor · ld.so 6h 전량저장 재현환경
#   Ubuntu 24.04 = glibc 2.39 (ld.so = /lib64/ld-linux-x86-64.so.2, distro -O2)
# build: docker build -t ldso-fuzz-6h-saveall .
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc git python3 binutils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

# 1) Lfuzzer 뮤테이터 (hetero 기본 ON 브랜치). 레포는 public → 토큰 불필요.
RUN git clone --depth 1 -b feat/coverage-guided-upgrade \
        https://github.com/Longarden/lfuzzer.git /root/lfuzzer
ENV LFUZZER=/root/lfuzzer

# 2) Melkor 빌드 (public)
#    GCC 10+ 는 -fno-common 이 기본 → Melkor(옛 코드)의 헤더 전역변수(PAGESIZE 등)가
#    'multiple definition' 링크에러를 낸다. CC="gcc -fcommon" 로 옛 동작 복원.
#    melkor 타깃만 빌드(templ/envtools 테스트도구는 불필요).
RUN git clone --depth 1 https://github.com/IOActive/Melkor_ELF_Fuzzer.git \
        /root/melkor_repro/Melkor_ELF_Fuzzer \
    && make -C /root/melkor_repro/Melkor_ELF_Fuzzer melkor CC="gcc -fcommon"
ENV MELKOR_BIN=/root/melkor_repro/Melkor_ELF_Fuzzer/melkor

# 3) 이 키트 스크립트(전량저장 러너 + 오케스트레이터)
COPY run_saveall_6h.sh run_lfuzzer_ld.py run_melkor_ld.py /root/kit/
ENV KIT=/root/kit
RUN chmod +x /root/kit/run_saveall_6h.sh

# 4) 단일시드 prac.elf — 레포에 커밋된 확정본(두 퍼저 공통, 동일 시드)
COPY seeds/prac.elf /root/seed_6h/prac.elf
ENV SEED=/root/seed_6h/prac.elf
RUN { /lib64/ld-linux-x86-64.so.2 /root/seed_6h/prac.elf; rc=$?; \
      echo "baseline rc=$rc"; \
      [ "$rc" -lt 128 ] || { echo "ERROR: prac.elf 이 시그널로 크래시(rc=$rc)"; exit 1; }; }

# 5) 전량저장 결과 = /output 볼륨(마운트)에 낱개·연번(NNNNNNNNN.so) 직접 저장.
#    컨테이너 밖(호스트의 -v 대상)에 그대로 남는다. 압축 없음, 수집기 없음.
ENV OUTDIR=/output
RUN mkdir -p /output

CMD ["/bin/bash"]
