#!/bin/bash
#SBATCH --job-name=AJH_BZ            # 작업 이름
#SBATCH --output=boltz_%j.out        # 정상 출력 로그
#SBATCH --error=boltz_%j.err         # 에러 발생 시 로그
#SBATCH --nodes=1                    # 노드 1개 사용
#SBATCH --ntasks=1                   # 태스크 1개
#SBATCH --cpus-per-task=8            # CPU 코어 8개
#SBATCH --gres=gpu:1                 # GPU 1장 요청
#SBATCH --partition=gpus             # GPU 파티션
#SBATCH --nodelist=gpu04             # 지정 노드 ##자리 비는 곳에 투입##

# ----------------------------------------------------------------
# [사용자별 경로 설정] - $USER 변수가 실행한 사람의 아이디로 자동 치환됩니다.
# 본인의 가상환경 이름이 boltz2로 되어있는지 확인해야 합니다.
# ----------------------------------------------------------------
USER_HOME="/data01/genbiolab/$USER"
BOLTZ_CACHE="$USER_HOME/.boltz"
HF_CACHE="$USER_HOME/.cache/huggingface"
TMPDIR="$USER_HOME/tmp"
OUTPUT="$USER_HOME/outputs"

# 1. 아나콘다 모듈 로드 (공용 모듈)
module load anaconda3/2024.10

# 2. 필수 라이브러리 경로 및 가상환경 활성화
export LD_LIBRARY_PATH=/data01/genbiolab/modules/anaconda3/2024.10/lib:$LD_LIBRARY_PATH
conda activate boltz2

# 3. 용량 부족 방지를 위한 경로 강제 지정 (사용자별 폴더 활용)
export BOLTZ_CACHE_DIR=$BOLTZ_CACHE      
export BOLTZ_CACHE_PATH=$BOLTZ_CACHE     
export HF_HOME=$HF_CACHE                 
export TMPDIR=$TMPDIR

# 필요한 폴더가 없으면 자동으로 생성
mkdir -p $BOLTZ_CACHE_PATH
mkdir -p $TMPDIR
mkdir -p $OUTPUT

# 4. 모델 실행 경로 설정 (.local/bin 등 사용자 개별 경로 포함)
export PATH=$PATH:$USER_HOME/.local/bin

echo "User: $USER"
echo "Running Boltz on Node: $(hostname)"
echo "Base Output Directory: $OUTPUT"

# ----------------------------------------------------------------
# 5. [추가 및 수정된 부분] 다중 실행(Loop) 및 Seed 제어
# ----------------------------------------------------------------

# 반복할 횟수를 여기에 적어주세요. 
# (예: 기초 테스트는 3, 표준 논문용은 10, 동역학/앙상블 분석용은 30~50)
NUM_RUNS=1

# 1. 오늘 날짜 확인 (00시 기준 자동 갱신)
NOW=$(date +"%Y%m%d")

# 2. 기존 폴더들을 검색해서 당일 가장 높은 번호(X) 찾기
MAX_NUM=0
for dir in ${OUTPUT}/${NOW}_*; do
    if [ -d "$dir" ]; then
        # 폴더명에서 제일 마지막 '_' 뒤의 숫자만 추출
        NUM=${dir##*_}
        # 추출한 값이 숫자인지 확인하고 MAX값 갱신
        if [[ "$NUM" =~ ^[0-9]+$ ]] && [ "$NUM" -gt "$MAX_NUM" ]; then
            MAX_NUM=$NUM
        fi
    fi
done

# 3. 다음 번호 할당 및 최상위 폴더 생성 (예: 20260319_1, 20260319_2 ...)
NEXT_NUM=$((MAX_NUM + 1))
DATE_DIR="${OUTPUT}/${NOW}_${NEXT_NUM}"
mkdir -p "$DATE_DIR"

echo "Starting $NUM_RUNS independent Boltz predictions in $DATE_DIR..."

for i in $(seq 1 $NUM_RUNS); do
    RUN_ID=$(printf "%02d" $i)
    RANDOM_SEED=$RANDOM
    
    CURRENT_OUTPUT="${DATE_DIR}/run_${RUN_ID}"
    mkdir -p "$CURRENT_OUTPUT"

    echo "=========================================================="
    echo "[Run $RUN_ID/$NUM_RUNS] Running with SEED: $RANDOM_SEED"
    echo "Saving to: $CURRENT_OUTPUT"
    echo "=========================================================="

    # 4. Boltz 실행
    boltz predict input.yaml \
        --out_dir "$CURRENT_OUTPUT" \
        --use_msa_server \
        --seed $RANDOM_SEED
    
    # 5. 실행이 정상적으로 끝났는지 확인 ($?는 직전 명령어의 성공 여부를 뜻함, 0이면 성공)
    if [ $? -eq 0 ]; then
        # 시드 정보 저장
        echo "SEED=$RANDOM_SEED" > "${CURRENT_OUTPUT}/seed_info.txt"

        # 6. [핵심] 안전한 이중 폴더 해체 (파일 증발 방지)
        # boltz_results_ 로 시작하는 폴더를 정확히 찾아서 변수에 저장
        BOLTZ_SUBDIR=$(find "$CURRENT_OUTPUT" -mindepth 1 -maxdepth 1 -type d -name "boltz_results_*" | head -n 1)
        
        if [ -n "$BOLTZ_SUBDIR" ] && [ -d "$BOLTZ_SUBDIR" ]; then
            # 안의 내용물을 안전하게 바깥(run_01 등)으로 꺼냄
            mv "$BOLTZ_SUBDIR"/* "$CURRENT_OUTPUT"/ 2>/dev/null
            # 내용물이 비워진 껍데기 폴더만 강제 삭제
            rm -rf "$BOLTZ_SUBDIR"
            echo "[Run $RUN_ID] Cleanup successful."
        else
            echo "[Run $RUN_ID] Warning: 'boltz_results_' directory not found, cleanup skipped."
        fi
    else
        echo "❌ [Run $RUN_ID] Boltz execution failed! Skipping cleanup to preserve error logs."
    fi
done

echo "All predictions nicely organized in ${DATE_DIR}."