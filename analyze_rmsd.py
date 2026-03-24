import os
import numpy as np
import pandas as pd
from glob import glob
from Bio.PDB import MMCIFParser
from MDAnalysis.analysis.rms import rmsd

# 1. 파일 검색 및 초기 세팅
cif_files = sorted(glob("outputs/20260319*/**/input_model_0.cif", recursive=True))
if not cif_files:
    raise FileNotFoundError("❌ CIF 파일을 찾을 수 없습니다.")

print(f"🔎 총 {len(cif_files)}개의 구조를 분석합니다...")

parser = MMCIFParser(QUIET=True)
run_names, coords_a, coords_b = [], [], []

# 2. 파일 파싱 및 좌표 즉시 추출 (메모리 최적화)
for f in cif_files:
    run_name = next((p for p in f.split(os.sep) if "run_" in p), "unknown")
    struct = parser.get_structure(run_name, f)[0] # 첫 번째 모델만 로드
    
    # A체인 CA 원자 / B체인 Heavy 원자 좌표만 리스트로 묶어서 곧바로 Numpy 배열 변환
    ca_atoms = [atom.coord for atom in struct['A'].get_atoms() if atom.get_name() == 'CA']
    lig_atoms = [atom.coord for atom in struct['B'].get_atoms() if atom.element != 'H']
    
    run_names.append(run_name)
    coords_a.append(np.array(ca_atoms, dtype=np.float32))
    coords_b.append(np.array(lig_atoms, dtype=np.float32))

# 3. MDAnalysis 기반 초고속 RMSD 행렬 계산
num = len(run_names)
mat_a, mat_b = np.zeros((num, num)), np.zeros((num, num))

for i in range(num):
    for j in range(i + 1, num):
        # superposition=True로 최적의 3D 회전 및 RMSD 오차 즉시 반환
        mat_a[i, j] = mat_a[j, i] = rmsd(coords_a[i], coords_a[j], superposition=True)
        mat_b[i, j] = mat_b[j, i] = rmsd(coords_b[i], coords_b[j], superposition=True)

# 4. Pandas 요약 및 파일 저장
df = pd.DataFrame({
    'Run_Name': run_names,
    'Chain_A_RMSD (Å)': np.mean(mat_a, axis=1),
    'Chain_B_RMSD (Å)': np.mean(mat_b, axis=1)
})

print("\n[ 🏆 최고 수렴 모델 Top 5 ]")
print(df.sort_values('Chain_A_RMSD (Å)').head().to_string(index=False))

np.save("chain_a_rmsd.npy", mat_a)
np.save("chain_b_rmsd.npy", mat_b)
df.to_csv("rmsd_summary.csv", index=False)

print("\n💾 행렬(.npy) 및 요약표(.csv)가 성공적으로 저장되었습니다.")