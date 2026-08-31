# ldso-fuzz-6h-saveall — Lfuzzer vs Melkor · ld.so 6h 전량저장 재현 키트

glibc 동적 링커 `ld.so` 를 대상으로 **Lfuzzer**(hetero 강도혼합·ELF 메타데이터 4축 변이)와
**Melkor**(규칙기반 메타데이터 치환)를 **동일 조건**(단일코어·단일시드·6시간)으로 돌려
공정 비교하고, **생성된 모든 변이 ELF 를 압축 없이 낱개로, 마운트 폴더에 직접, 생성순서
연번으로 저장**하는 재현 키트.

```
━━ 핵심 설계 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 SUT      /lib64/ld-linux-x86-64.so.2  (Ubuntu 24.04 = glibc 2.39, distro -O2)
 시드     prac.elf 딱 1개 (레포에 커밋, 두 퍼저 공통·동일 시드)
 저장     ★ 압축 없음 · 수집기/스테이징 없음 · 퍼저가 마운트 폴더에 '직접' 씀
          → OUTDIR/NNNNNNNNN.so (000000001.so, 000000002.so …, 생성순서 연번)
          → 크래시뿐 아니라 '전량' 저장. 크래시 목록은 OUTDIR/_crashes.csv
 마운트   OUTDIR = 볼륨 마운트 → 컨테이너를 지워도 호스트에 파일이 남는다
 크래시   [ld.so, mutant] 직접 실행 → 시그널(rc<0) 또는 timeout(124)
```

> 방어적 보안 연구용. 링커/로더 견고성 버그를 찾고 도구 간 어긋남을 규명하기 위한 것.

---

## 빠른 시작 (A) — Docker 6컨테이너 (권장)

**Melkor ×3(코어 1/2/3) + Lfuzzer ×3(코어 4/5/6)**, 각 컨테이너는
**단일코어(`cpuset` 핀) · RAM 4GB 상한 · 6시간 · 전량 직접저장 · 별도 출력폴더**.
**모두 동일 설정·동일 단일시드 prac.elf**. 두 퍼저 다 '자체난수'라 3개가 자연 발산한다
(Melkor=바이너리가 time/pid 시드, Lfuzzer=러너가 OS 엔트로피로 시딩, 실제 시드는 로그에 기록).

> ⚠️ **WSL2 사용자: 반드시 WSL 홈(`~/`, ext4)에 클론·실행하라. `/mnt/c`(윈도우 드라이브) 금지.**
> docker.io 가 `/mnt/c` 를 drvfs 로 바인드마운트하면 쓰기가 10배 이상 느려 전량저장이 병목된다
> (실측: 같은 18초에 ext4 3740개 vs /mnt/c 315개). Docker Desktop(윈도우/맥)은 해당 없음.

### (A-1) compose 없이 — `run_all_6.sh` (권장, 어디서나 동작)

우분투 `docker.io` 처럼 **compose 플러그인이 없어도** 되는 plain `docker run` 런처.

```bash
git clone https://github.com/Longarden/ldso-fuzz-6h-saveall.git
cd ldso-fuzz-6h-saveall

bash run_all_6.sh            # 6h 기동 (빌드→6컨테이너 docker run -d)
#   먼저 짧게 시험하려면:  bash run_all_6.sh 60   # 60초

# 상태·자원·로그
docker ps
docker stats                       # 컨테이너별 CPU%·RAM(4GB 대비) 실시간
docker logs -f fuzz_melkor1        # fuzz_melkor1..3 / fuzz_lfuzzer1..3

# 결과(호스트에 바로, 컨테이너 밖) — 낱개·연번 .so (압축 없음)
ls output/lfuzzer1/ | sort | tail  # 000000001.so 000000002.so ...
ls output/melkor1/*.so | wc -l     # 총 생성 개수
cat output/lfuzzer1/_crashes.csv   # 크래시난 연번,rc 목록

bash stop_all_6.sh                 # 전체 중지·제거(출력 파일은 남음)
```

### (A-2) compose 로 (플러그인 있을 때만)

`docker compose` v2 플러그인이 설치돼 있어야 한다(`docker compose version` 으로 확인).
없으면 `sudo apt install docker-compose-v2` 하거나 (A-1)을 쓰라.

```bash
mkdir -p output/melkor1 output/melkor2 output/melkor3 \
         output/lfuzzer1 output/lfuzzer2 output/lfuzzer3
docker compose up --build -d
docker compose ps ; docker stats ; docker compose logs -f melkor1
docker compose down
```

> 각 컨테이너 안에서 퍼저가 `/output`(=호스트 `./output/<name>`)에 **직접** `.so` 를 쓴다.
> 중간 임시폴더·주기적 수집·압축 **없음**. `/output` 은 마운트라 **컨테이너를 지워도 남는다.**

### ⚠️ 자원 요건
- **코어 6개(cpuset 1~6) + RAM 24GB(6×4GB).** 부족하면 `docker-compose.yml` 에서
  서비스 수를 줄이거나 `cpuset`/`mem_limit` 을 조정.
- 전량저장은 컨테이너당 시간당 수 GB → **호스트 디스크 여유(수백 GB) 필수.**

---

## 빠른 시작 (B) — 로컬(WSL2 / Ubuntu 24.04)

```bash
# 0) 요구 패키지
sudo apt update && sudo apt install -y build-essential gcc git python3 binutils

# 1) Lfuzzer 뮤테이터 (public)
git clone -b feat/coverage-guided-upgrade https://github.com/Longarden/lfuzzer.git ~/lfuzzer
export LFUZZER=~/lfuzzer

# 2) Melkor 빌드 (GCC 10+ 는 -fcommon 필요: 옛 코드의 헤더 전역변수 중복정의 링크에러 회피)
git clone https://github.com/IOActive/Melkor_ELF_Fuzzer.git ~/melkor_repro/Melkor_ELF_Fuzzer
make -C ~/melkor_repro/Melkor_ELF_Fuzzer melkor CC="gcc -fcommon"
export MELKOR_BIN=~/melkor_repro/Melkor_ELF_Fuzzer/melkor

# 3) 시드(레포에 포함) 배치 + 이 키트 폴더
export KIT=$(pwd)                       # 이 레포 클론 위치
export SEED=$KIT/seeds/prac.elf         # 단일시드(커밋된 확정본)
/lib64/ld-linux-x86-64.so.2 "$SEED"; echo "baseline rc=$?"   # 128 미만이어야 함

# 4) 6시간 실행 (여유 큰 볼륨! WSL 홈 ext4 권장, /mnt/c 금지)
mkdir -p ~/out_lfuzzer ~/out_melkor
OUTDIR=~/out_lfuzzer setsid nohup bash "$KIT/run_saveall_6h.sh" lfuzzer 21600 >~/lf.log 2>&1 </dev/null &
OUTDIR=~/out_melkor  setsid nohup bash "$KIT/run_saveall_6h.sh" melkor  21600 >~/mk.log 2>&1 </dev/null &
# (시드 미지정 = 자체난수. 재현이 필요하면 끝에 정수 시드: "... lfuzzer 21600 12345")
```

진행 확인:
```bash
ps -ef | grep -E "run_lfuzzer_ld|run_melkor_ld" | grep -v grep
watch -n5 'ls ~/out_lfuzzer/*.so | wc -l; ls ~/out_melkor/*.so | wc -l'
ls ~/out_lfuzzer | sort | tail        # 최신 연번
ls --full-time ~/out_lfuzzer | tail   # 파일별 저장시각(=생성순서)
```

---

## 모니터링 — 확인 방법

### 폴더에 전량 저장되는지
```bash
ls output/lfuzzer1/*.so | wc -l              # 개수 증가 = 전량 저장중
ls output/lfuzzer1 | sort | head             # 000000001.so 부터 연번
ls output/lfuzzer1 | sort | tail             # 최신 연번
cat output/lfuzzer1/_crashes.csv             # 어느 연번이 크래시였나(seq,rc)
```

### CPU 핀 + RAM 4GB 배정 확인
```bash
docker stats --no-stream                     # 컨테이너별 CPU%·MEM USAGE / LIMIT(=4GiB)
for c in fuzz_melkor1 fuzz_melkor2 fuzz_melkor3 fuzz_lfuzzer1 fuzz_lfuzzer2 fuzz_lfuzzer3; do
  echo -n "$c  "; docker inspect -f 'cpuset={{.HostConfig.CpusetCpus}} mem={{.HostConfig.Memory}}' $c
done
# 기대: melkor1=1 … lfuzzer3=6, mem=4294967296 (=4GiB)
```

### 컨테이너 밖에 저장되는지(마운트)
```bash
docker compose down                          # 컨테이너 전부 제거
ls output/lfuzzer1/*.so | wc -l              # 여전히 파일이 남아있음 = 마운트 영속 확인
```

### 타임스탬프/순서
- **파일명 연번 = 생성 순서** (`ls | sort`).
- **mtime = 저장 시각** (`ls --full-time`, `stat -c '%y %n' <파일>`).

---

## 환경변수

| 변수 | 기본 | 설명 |
|---|---|---|
| `OUTDIR` | Docker=`/output`, 로컬=`~/fuzz_out` | 최종 저장 단일폴더(마운트). 낱개·연번 직접저장 |
| `SEED` | `~/seed_6h/prac.elf` | 단일시드 파일 경로 |
| `LFUZZER` | `~/lfuzzer` | Lfuzzer 뮤테이터 저장소 |
| `MELKOR_BIN` | `~/melkor_repro/.../melkor` | Melkor 바이너리 |
| `LDSO` | `/lib64/ld-linux-x86-64.so.2` | SUT 로더 |
| `LFUZZER_TIMEOUT` | `3` | 로더 1회 실행 timeout(초) |

## 시드·난수 설계 (동일 시드 + 무조건 자체난수)
- **ELF 시드는 prac.elf 딱 1개**, 두 퍼저·6개 컨테이너 전부 동일하게 이걸 base 로 변이.
- **RNG 는 둘 다 무조건 자체난수** → 같은 시드·같은 설정이어도 컨테이너 3개가 자연히 다른 변이:
  - Melkor: C 바이너리가 time/pid 로 자체 시드.
  - Lfuzzer: 뮤테이터 `StructureAwareMutator(seed=X)` 는 원래 X로 '결정론적 시딩'이라,
    러너(`run_lfuzzer_ld.py`)가 매 프로세스 **OS 엔트로피(os.urandom)** 로 X를 새로 뽑아
    자체난수화한다. 실제 사용한 X 는 로그(`rng_seed=… (self-random)`)에 기록된다.

## 결과 해석
- 크래시 대부분 = PC가 쓰레기주소로 점프(와일드-PC). 의미있는 신호는 **이름있는 로더함수**
  (`_dl_relocate_object`·`_dl_check_map_versions`·`elf_machine_rela`·`do_lookup_x`·
  `_dl_call_fini` 등) 착지 크래시 → CASR 스택해시로 버킷팅해 비교.
- 예산: 단일코어 × 6시간 = 6 CPU-hours (두 퍼저 동일, 같은 `prac.elf` 단일시드).
