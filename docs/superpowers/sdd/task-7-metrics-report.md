# Report Task 7a — Metrik numerik COLMAP vs OpenMVS (Lewoleba)

## Status run
- Tool: `E:/dev/Colmap-Kernel/metrics.cpp` (single file, C++17, STL only) → `E:/dev/Colmap-Kernel/metrics.exe` (cl MSVC 14.34, `/O2`), CLI `metrics.exe <plyA> <plyB>`, exit 0.
- A (ours): `E:/dev/Lewoleba-15agustus/dense700/fused_ws2.ply` — 2.912.986 pts. B (acuan): `E:/dev/Lewoleba-15agustus/openmvs/scene_dense.ply` — 4.514.363 pts.
- RED: sebelum task ini tidak ada metrics.cpp/exe/angka. GREEN: run 2×, total 106 dtk CPU (< 5 mnt). Tidak commit. Proses `colmap.exe` (PID 2560) yang sedang jalan tidak diganggu (hanya baca dua PLY produk-jadi).

## Layout PLY persis (dibaca dari byte header, bukan tebakan)
- A: `binary_little_endian`, `float x y z`, `float nx ny nz`, `uchar red green blue` — stride tetap 27 B (cek: 2912986×27 + 248 header = 78650870 = ukuran file, pas).
- B: `binary_little_endian`, `float32 x y z`, `uint8 r g b`, `float32 nx ny nz`, **`list uint8 uint32 view_indices`, `list uint8 float32 view_weights`** — stride variabel; parser skipping list per-point (sisa byte untuk list ≈ 34,4 B/pt ≈ rerata ~4 view/pt, wajar). Bukti parse benar: kedua cloud berimpit level-cm di inti (lihat C2C); salah skip 1 byte saja sudah mengacak seluruh koordinat B.

## Definisi metrik (parameter tetap di code)
- Okupansi: union bbox kedua cloud, sel 0,5 m; kunci sel 63-bit, sort+unique, op himpunan via two-pointer. `fill_jaccard = both/union`; `coverage_A_of_B = both/|B|` (A menutup acuan); `coverage_B_of_A = both/|A|`. Tambahan: fraksi titik-di-sel-bersama per cloud (membedakan "cakupan luas" vs "halo noise").
- Outlier: sampel 50rb/cloud via stride tetap deterministik (A:58, B:90 — tanpa RNG, "seed tetap" terpenuhi secara konstruksi); voxel-hash 0,25 m; jarak NN ke-8 dalam sampel sendiri (ekspansi shell bila 27 sel kosong; <8 tetangga → INF = outlier); outlier jika `> median + 3*MAD`.
- C2C dua arah: 50rb sampel → NN di cloud lawan PENUH (voxel 0,25 m, mulai 27 sel, ekspansi s/d kubus 9³ ≈ ±1 m; gagal = `missing`, dikeluarkan dari statistik, dilaporkan). median = tengah terurut (n genap: rata-rata dua tengah); p90 = `d[floor(0.9n)]`.

## Angka (run final, identik run pertama kecuali diagnostik bbox)
- bbox_A: min(-986.2, -614.6, 0.2) max(236.1, 353.7, 1691.8) | bbox_B: min(-1.9, -6.3, 1.2) max(2.8, 6.8, 2.5)
- cells_A 8453, cells_B 371, onlyA 8084, onlyB 2, both 369, union 8455 → jaccard 0.0436, coverage_A_of_B 0.9946, coverage_B_of_A 0.0437
- points_A_in_shared 0.9532 | points_B_in_shared 1.0000
- outlier_A: median 0.0942, MAD 0.0251, thr 0.1694, **ratio 0.0759** | outlier_B: median 0.0822, MAD 0.0216, thr 0.1471, **ratio 0.0288**
- c2c_AtoB: found 49507 missing 493, mean 0.0719, **median 0.0444, p90 0.1139** | c2c_BtoA: found 50000 missing 0, mean 0.0411, **median 0.0353, p90 0.0827**

## Asumsi eksplisit: OpenMVS ≈ acuan, bukan kebenaran absolut
Semua "lubang/akurasi" di bawah dibaca relatif terhadap scene_dense.ply.

## Interpretasi
1. Lubang (holes): proksi `onlyB = 2 sel` ≈ 4 titik B (≈0%) — kita praktis tidak melewatkan apa pun yang diliput acuan (coverage_A_of_B 0.995).
2. Jaccard 0.044 JANGAN dibaca "tidak overlap": 95,3% titik A dan ~100% titik B berimpit di 369 sel inti (C2C median 3–4 cm membuktikan satu frame di inti). Jaccard hancur oleh halo A (8084 sel, hanya 4,7% titik A), bukan oleh lubang.
3. Halo A: ~3,7% titik dalam sel-halo tapi ≤1 m dari permukaan B (scatter shell), ~1% benar-benar jauh (missing 493/50000) termasuk pencilan ekstrem pendorong bbox (x −986, z 1691). Outlier-ratio A 7,6% vs B 2,9% konsisten dengan ini.
4. Anomali extent: B seluruhnya dalam kotak ~4,7×13,1×1,2 m; A + inti yang sama + ekor lebar. Penyebab (crop/ROI OpenMVS vs model sparse berbeda vs geometri runtuh) belum dipastikan — butuh tindak lanjut, bukan asumsi.

## Rekomendasi gate
Jangan gate pada Jaccard. Pakai: holes-proxy onlyB/coverage_A_of_B + C2C A→B (median/p90) + outlier-ratio A vs B. Target mod berikutnya: kecilkan halo/outlier A tanpa menaikkan onlyB.

## Yang dilewati / risiko
- Sampel stride atas urutan-file (dianggap campur spasial; bias mungkin jika file terurut spasial).
- Tanpa registrasi/ICP — disengaja (ponytail); valid karena inti sudah segaris cm-level, tetapi C2C di halo tercemar perbedaan frame bila frame ternyata beda skala.

## Fix report — ekspor nadir PGM hole-map (owner decision: semua dataset nadir; oblique views dropped)
- RED: sebelum fix, tidak ada file `nadir_*.pgm` di kedua site (4× Test-Path False).
- Perubahan (`metrics.cpp` saja, tetap STL-only): CLI baru `metrics.exe <plyA> <plyB> --pgm <prefix>`; tanpa `--pgm` perilaku angka-saja tidak berubah (angka Lewoleba rerun identik s/d 6 desimal). Memakai union bbox + sel 0,5 m yang sudah ada: proyeksi top-down (buang z, baris 0 = y max), `<prefix>_A.pgm` + `<prefix>_B.pgm` biner P5 (isi = putih 255, kosong = hitam 0), dimensi identik per pasangan by construction (satu union bbox). Guard dimensi >20000/px atau >250M px → exit 1.
- Run 1 Lewoleba (`--pgm E:/dev/Lewoleba-15agustus/nadir`, 104,5 dtk): `pgm_A .../nadir_A.pgm 2445 1937`, `pgm_B .../nadir_B.pgm 2445 1937` — ukuran file identik 4735982 (= 2445×1937+17 header).
- Run 2 Midai — A=`E:/dev/Midai-14agustus/dense/fused_midai_ws2.ply` (1.465.184 pts), B=`E:/dev/Midai-14agustus/openmvs/scene_dense.ply` (1.890.956 pts), `--pgm E:/dev/Midai-14agustus/nadir` (22,9 dtk): `pgm_A .../nadir_A.pgm 385 483`, `pgm_B .../nadir_B.pgm 385 483` — ukuran identik 185970 (= 385×483+15 header), header P5 terverifikasi. Angka Midai: onlyB 1 sel (holes ≈ 0), coverage_A_of_B 0,9979, outlier A 0,0553 vs B 0,0465, C2C A→B median 0,0423/p90 0,0967 (409 missing), B→A median 0,0356/p90 0,0842 (0 missing) — pola sama seperti Lewoleba (B kotak kecil ~15×6×1,7 m di dalam bbox A ~192×241×324 m).
- Tidak commit; CPU-only; proses lain tak disentuh.
- Tanpa perbandingan warna/normal; tanpa ICP; run GPU lain tak tersentuh.
