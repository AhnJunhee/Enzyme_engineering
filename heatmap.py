import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

# 1. 데이터 로드
try:
    rmsd_matrix = np.load("chain_b_rmsd.npy")
    with open("run_names.txt", "r") as f:
        run_names = [line.strip() for line in f.readlines()]
except FileNotFoundError:
    print("❌ 데이터 파일을 찾을 수 없습니다.")
    exit()

# 2. 히트맵 그리기 (Publication Quality)
plt.figure(figsize=(12, 10))
sns.set_theme(style="white")

# 컬러 맵을 진한 파란색(낮은 RMSD) 위주로 설정
ax = sns.heatmap(rmsd_matrix, 
                 xticklabels=run_names, 
                 yticklabels=run_names,
                 annot=True, fmt=".2f", # 칸 안에 RMSD 수치 표시
                 annot_kws={"size": 8},
                 cmap="YlGnBu_r", 
                 linewidths=.5,
                 cbar_kws={'label': 'RMSD (Å)'})

plt.title(f"Boltz-2 Ensemble Convergence (Avg RMSD: {np.mean(rmsd_matrix[rmsd_matrix>0]):.4f} Å)", 
          fontsize=16, pad=20)
plt.xticks(rotation=45, ha='right')
plt.tight_layout()

# 3. 이미지 저장
plt.savefig("boltz2_rmsd_heatmap.png", dpi=300)
print("✅ 'boltz2_rmsd_heatmap.png'가 성공적으로 생성되었습니다!")