# COLMAP-Kernel mods — setara Metashape/OpenMVS di RTX 3050 4GB

Basis: COLMAP 4.2.1 (`E:\Colmap-Kernel\colmap`, shallow clone tag 4.2.1).
Dataset acuan: 80 foto DJI nadir, `E:\Dataset_output\Tes-rerun-full`.

Scope: depth (`patch_match_stereo`) + dense (`stereo_fusion`) SAJA.
Sparse, mesh (poisson/delaunay), tekstur: tidak disentuh.

Konteks: FOTO DRONE saja (DJI nadir, overlap tinggi 70-90%, altitude
puluhan–ratusan meter). BUKAN MVS generik (objek dekat, indoor, unordered).
Semua default + mod dinilai buat drone: baseline pendek & seragam, area
datar luas (atap/sawah/jalan), vegetasi goyang angin, depth range besar
tapi bisa dipangkas dari altitude.

## Mod 1 — DONE: `max_triangulation_angle` di auto view selection

Masalah: `__auto__` hanya buang baseline SEMPIT (`min_triangulation_angle`),
baseline LEBAR lolos semua. NCC jebol di baseline lebar → depth noise →
fusion buang (kasus `fused.ply` 29KB vs `.vis` 92MB). Metashape pilih
tetangga overlap disiplin dua arah.

Ubah (4 file, vertical slice penuh):

- `src/colmap/mvs/patch_match_options.h` — field baru
  `double max_triangulation_angle = -1.0f` (-1 = mati, default off,
  perilaku upstream tidak berubah).
- `src/colmap/mvs/patch_match_options.cc` — `PrintOption` + `Check`
  (0–180, harus >= min bila aktif).
- `src/colmap/controllers/option_manager.cc` —
  `AddDefaultOption("PatchMatchStereo.max_triangulation_angle", ...)`
  sehingga flag CLI `--PatchMatchStereo.max_triangulation_angle` hidup.
- `src/colmap/mvs/patch_match.cc` — loop `__auto__` tolak src image yang
  persentil sudutnya > batas (radian, konsisten dgn `DegToRad` existing).

Rekomendasi drone nadir: `--PatchMatchStereo.max_triangulation_angle 15`
(lihat `drone-rtx3050.ini`).

## Mod 2 — PLANNED: NCC window adaptif (`patch_match_cuda.cu`)

`window_radius` global = generik. Atap/sawah datar butuh jendela besar,
tepi gedung butuh kecil. Lokasi: `PhotoConsistencyCostComputer`
(~baris 451), `ComputeNCCProb` (~735), sweep `SweepFromTopToBottom` (~938).
Rencana: baca varians lokal dari ref image, pilih radius 5/7/11 per piksel.
Belum implement — butuh uji kualitas vs waktu di 80 foto dulu.

## Mod 3 — PLANNED: tiling sadar-VRAM (`patch_match.cc` + `cache_size`)

Metashape tidak pernah spill di 4GB karena tile dihitung dari VRAM bebas.
COLMAP `cache_size` statis (default 32GB!). `drone-rtx3050.ini` set 16
sebagai mitigasi tanpa compile. Rencana kernel: query `cudaMemGetInfo`
saat setup, turunkan batch otomatis bila bebas < 1GB.

### Kriteria robust Mod 3/F8 di MX150 2GB (ditambah 2026-10-11, temuan G1)

G1 mengukur: ±8 dtk/view @1400px, VRAM cuma ±245MB, occupancy ±10%
(sweep = 1 thread/kolom ≈ 1400 thread). Headroom → konkurensi:
`cuda_instances` 2–3 problem konkuren ala OpenMVS
`nPatchMatchCUDAInstances` (≈750MB, aman). Target: SM ≥50% sustain
fase compute (ukur CUPTI), VRAM <1500MB selalu, 0 OOM di 117 view,
fallback deterministik ke sekuensial bila alokasi gagal, I/O overlap
(prefetch view berikut saat sweep) agar idle antar-view <10%.
Bukan target: pelebaran sweep per-piksel (risiko CUDA dalam, tunda).

## Lewati OpenMVS — gap + rencana

OpenMVS `DensifyPointCloud` tidak ada di mesin ini (no binary), jadi
perbandingan level desain + benchmark menyusul. Keunggulan OpenMVS yang
harus dikejar/dilewati di scene drone nadir:

| # | OpenMVS | COLMAP 4.2.1 stok | Status kita |
|---|---|---|---|
| 1 | Piramid coarse-to-fine (`resolution-level`): init depth dari skala kasar → iterasi sedikit, area datar terisi | Satu skala (`max_image_size`), 5 iterasi buta | Mod 4 PLANNED |
| 2 | Filter view by sudut/skala/oklusi (`number-views`, fuse) | `__auto__` by shared-points + batas bawah saja | Mod 1 DONE (batas atas; setara filter sudut) |
| 3 | NCC + sub-pixel refine (`sub-precision`, `optimize`) | NCC window global, tanpa refine adaptif | Mod 2 PLANNED |
| 4 | Fusion visibility + deviasi normal | Threshold kaku (`max_depth_error 0.01` bunuh hasil drone) | Config DONE (longgar dulu), weighting PLANNED |
| 5 | Tiling per-view hemat VRAM | `cache_size` statis 32GB | Mod 3 PLANNED (`cache_size 16` sementara) |

### Resep build OpenMVS eksternal (Ryzen 7 + RTX 3050) — hasil portable ke MX150

Jalankan di mesin RTX (VS2022 + CUDA 12.x + vcpkg + git + Ninja ada):

```
git clone https://github.com/cdcseacave/openMVS.git
cd openMVS && git checkout a3b6d0d
cmake -B build-rtx -G Ninja -DCMAKE_TOOLCHAIN_FILE=<vcpkg>/scripts/buildsystems/vcpkg.cmake -DOpenMVS_USE_CUDA=ON -DOpenMVS_USE_SIFTGPU=OFF -DOpenMVS_BUILD_VIEWER=OFF -DOpenMVS_USE_PYTHON=OFF -DOpenMVS_ENABLE_TESTS=OFF -DOpenMVS_ENABLE_IPO=OFF -DOpenMVS_USE_BREAKPAD=OFF -DCMAKE_CUDA_ARCHITECTURES="61;86" -DCMAKE_BUILD_TYPE=Release
cmake --build build-rtx --config Release --target DensifyPointCloud InterfaceCOLMAP
```

Lalu zip: `build-rtx/bin/*DensifyPointCloud*` + `*InterfaceCOLMAP*` +
semua DLL dari `vcpkg_installed/x64-windows/bin` + `cudart64_12.dll`,
`cublas64_12.dll` (dari CUDA toolkit mesin itu). Kirim folder ke sini,
run `DensifyPointCloud -i scene.mvs` di MX150 untuk verifikasi
(`Ref image paired` + tanpa CUDA error = lolos).
Syarat: JANGAN `-march=native`; sumber harus commit SAMA (a3b6d0d).

### Jeda aman 2026-10-11 (laptop istirahat, build OpenMVS dihentikan di opencv4)
Resume: jalankan `configure-openmvs.ps1` lagi — vcpkg lanjut otomatis
(opencv build ulang dari nol ±40–70 mnt, sisanya cache). Jangan hapus
`build-mx150/`, `vcpkg_installed/`, `buildtrees/`, `downloads/`.

### Catatan build OpenMVS (benchmark internal saja, tidak didistribusikan)

- Fitur `cuda` di `vcpkg.json` OpenMVS menarik `siftgpu[cuda]` TANPA
  menghiraukan `OpenMVS_USE_SIFTGPU=OFF`. Diterima apa adanya: SiftGPU
  ter-build tapi tidak dieksekusi (DensifyPointCloud + InterfaceCOLMAP
  tidak menyentuh jalur SIFT). Alternatif (patch manifest mereka)
  ditunda kecuali build gagal.
- `ceres[suitesparse]` milik OpenMVS dibiarkan (GPL hanya mengikat bila
  binary OpenMVS didistribusikan; pemakaian benchmark internal aman).
- Gagal unduh `suitesparse-config` (curl 56) = transien → retry configure.
- Prinsip: **OpenMVS stok** (sumber tak disentuh); yang custom hanya COLMAP.
  Flag OFF (SIFTGPU/viewer/python/tests) terverifikasi tak mengubah
  numerik DensifyPointCloud: 0 referensi SiftGPU di `libs/MVS`,
  `apps/DensifyPointCloud`, `apps/InterfaceCOLMAP` (grep 2026-10-11).
- Prebuilt `C:\OpenMVS` (v2.4.0) GAGAL dipakai: `DensifyPointCloud`
  mati saat init CUDA (`UtilCUDADevice.h:54`, code 500, named symbol
  not found) — biner tak kompatibel driver/MX150. Lanjut build sumber.
  Data sampingan valid: pairing OpenMVS 2–8 view/ref (mendukung
  `__auto__` 6 kita).
- Patch kompat-build (BUKAN custom perilaku): fork poselib OpenMVS
  (`cdcseacave/PoseLib ccdd2f6`) kena penyakit deduksi Eigen 5 + MSVC
  yang sama → patch forwarding-identik di
  `buildtrees/.../jacobian_accumulator.h` (backup di
  `E:\dev\tools\poselib-eigen5-fix\`), numerik tak berubah. Sumber
  OpenMVS sendiri tetap stok.
- Blokir configure: genex `SuiteSparse::SuiteSparseConfig` gagal di
  generate meski target ada (paradoks vcpkg SuiteSparse 7.14, root
  cause tak ketemu setelah audit penuh). Solusi: link SuiteSparse
  dimatikan di `libs/Math` (fallback Eigen — jalur opsional resmi
  upstream); DensifyPointCloud tak menyentuh kode SuiteSparse.
  Ceres (SHARED) tak mempropagasi genex tsb. Sumber perilaku dense
  tetap stok.

### Prioritas khusus drone (bukan generik)

1. Mod 4 coarse-to-fine — atap/sawah datar = kasus drone paling umum.
2. Mod 1 DONE + `__auto__ 8` — overlap drone tinggi, tetangga wajib
   sedikit & disiplin (baseline seragam, buang sudut >15°).
3. Fusion longgar-dulu — `max_depth_error 0.01` stok bunuh scene
   altitude puluhan meter; 0.05 titik kembali.
4. Mod 2/3 menyusul setelah angka dasar ada.

### Mod 4 — PLANNED: init coarse-to-fine tanpa sentuh CUDA

Dua tahap orkestrasi (bisa skrip dulu, kernel belakangan):
tahap 1 `max_image_size 500`, `num_iterations 5` → depth kasar;
tahap 2 `max_image_size 2000` pakai depth tahap 1 sebagai init,
`num_iterations 2`, `window_radius 7`. Target: waktu < 1 tahap penuh
2000 + lubang tekstur tertutup. Kernel: dukung baca init maps existing
di `patch_match.cc` bila belum ada.

### Protokol benchmark (MX150 2GB; primer: Lewoleba 15-AGUSTUS 117 foto,
sekunder/pembanding: Midai 14-Agustus-2025 51 foto @~80m + subset strip
Lewoleba ±30 foto untuk iterasi cepat)

Metrik: waktu depth, waktu fusion, jumlah titik, peak VRAM
(`nvidia-smi`), lubang visual di atap/jalan. Lawan: COLMAP stok 3.13
(2106 dtk @1000px, `fused.ply` 29KB), config ini, OpenMVS
(menyusul), Metashape High (menyusul). Menang = waktu ≤ OpenMVS
dengan titik ≥ dan lubang ≤.

## Build (MX150, Windows, MSVC 19.34 + CUDA 12.4 conda, no-admin)

Toolchain: `E:\dev\tools\cuda-env` (micromamba, channel `nvidia/label/cuda-12.4.1`)
+ curand fallback dari wheel PyPI (`curand.lib` di-generate via `dumpbin`+`lib.exe`).
`sm_61` compile-and-run teruji `SM61_OK`. Skrip: `configure-mx150.ps1`, `build-mx150.ps1`.
vcpkg di `E:\dev\vcpkg` (bootstrap selesai).

### Patch build-tree `_deps` (terdokumentasi, re-apply bila `build-mx150/_deps` dihapus)

PoseLib FetchContent pin upstream `1bb8881` + Eigen 5.0.1 + MSVC: deduksi
template `NormalAccumulator::add_jacobian(res, J, w)` gagal (C2672,
`ParamsDim` ambigu) untuk `Matrix<double,2,9>` di
`_deps/poselib-src/PoseLib/robust/optim/monodepth_relpose.h:710,749`
(refiner monodepth-varying-focal, tidak dipakai pipeline drone).
Patch: `acc.add_jacobian(res, J, weights[i])` → `acc.add_jacobian<2, 9>(...)`
di kedua situs + komentar alasan. Setara upstream, tanpa ubah perilaku.
Patch lanjutan (round 2, pola sama — MSVC+Eigen 5 gagal deduksi dari tipe
fixed-size): `recalibrator.h:58` `add_residual(res)` → `add_residual<2>(res)`,
`:88` `add_jacobian(res, J)` → `add_jacobian<2, Eigen::Dynamic>(res, J)`;
`monodepth_relpose.h:607,615` `add_residual(res, w)` → `add_residual<2>(...)`.
Semua setara perilaku (argumen template = tipe aktual argumen).
Patch round 3: `monodepth_relpose.h:470,508` → `add_jacobian<2, 8>(...)`;
`:372,380` → `add_residual<2>(...)` (shared-focal).
Patch round 4 (final): `:237,277` → `add_jacobian<2, Eigen::Dynamic>(...)`
(fixed-focal); lalu patch sentral di `jacobian_accumulator.h`:
overload forwarding `MatrixBase` → argumen eksplisit (setara perilaku,
tanpa ambiguitas dengan call `(double,...)` yang sudah jalan).
`bundle.cc` + `recalibrator.cc` lolos setelahnya.

### Milestone 2026-10-11: sparse 15-AGUSTUS JADI (116/117, pts ~5.3MB bin)

Ekstraksi 11 mnt + matching 9.3 mnt + mapper 2 mnt (DENSE_SCHUR).

### Milestone 2026-10-11: HEAD-TO-HEAD Lewoleba (jujur, operating point beda)

| | COLMAP Mod1 + drone-mx150 | OpenMVS develop a3b6d0d default |
|---|---|---|
| Working res | 1400x1050 full | 700x525 (level 1) + sublevels |
| Depth | 41.17 mnt (108 view) | ~2 mnt (117 view, GPU) |
| Fusion | 1.86 mnt → 2.505.833 pts | ~29 dtk → 4.514.363 pts (17% dari 27,1M) |
| Total | 43.03 mnt = **58.226 pts/mnt** | 3.13 mnt = **~1,44J pts/mnt** |
| VRAM peak | 321MB | 405MB |
| RAM peak | — | 1,93GB |

Gap ±25x throughput + 1,8x titik = TUGAS mod F (terutama coarse-to-fine
+ konkurensi). OpenMVS menang karena kerja di 700px + 4 instance
paralel + confidence terintegrasi — semua sudah di rencana F.

PatchMatch 108/108 view @1400px (`__auto__` 6, max_angle 15, depth 15–100):
41.17 mnt. Fusion 1.86 mnt → **`fused.ply` 64.5MB, 2.505.833 titik**.
Total dense 43.03 mnt = **58.226 titik/mnt**, VRAM peak **321MB**.
9 problem gugur filter sudut (investigas F3: floor anti-kosong).

### Milestone 2026-10-11: HEAD-TO-HEAD ADIL @700px (operating point disamakan)

Vonis run sebelumnya (1400 vs 700) dinyatakan TIDAK RELEVAN (beda kelas
kerja). Rerun terkontrol `dense700/` dari garis keturunan yang sama:
117 JPG Lewoleba → `sparse/0` (116/117, CPU SIFT) → undistort
`--max_image_size 700` → PatchMatch 700px. OpenMVS `scene.mvs`
(InterfaceCOLMAP dari data yang sama) estimasi depth di 700x525
(`resolution-level 1`). Jadi resolusi depth SAMA; yang beda tinggal
kernel (itu yang diuji).

| | COLMAP `dense700` (Mod1, stok kernel) | OpenMVS develop a3b6d0d |
|---|---|---|
| Depth res | 700px (undistort 700) | 700x525 (level 1, input 1,40MP/gbr) |
| View policy | `__auto__` 8, min_tri 1°, max_tri 65° | `number-views 8`, fuse 2 (adaptif 2–8/view) |
| Iterasi | num_samples 10, num_iterations 4, window 5/1 | `--iters 4 --geometric-iters 2` (+2 refine ~0,2–1 dtk) |
| Geom/filter | gc 1, reg 0.3, max_cost 3; filter 1, min_ncc 0.15, min_tri 3, min_consistent 2, geom_max_cost 1 | `fusion-filter 2` |
| Fusion | min_pixels 3, reproj 4, depth_err 0.05, normal 20, check 30 | 27.122.787 depths → 4.525.430 (17%) → trim ROI 11.067 |
| Depth | **20,317 mnt** (117/117, ±5,4–5,8 dtk/view) | ∈ total (first pass ±1–3 dtk + refine) |
| Fusion | **0,582 mnt** (34,9 dtk) | ~29 dtk (di dalam total) |
| **Total** | **20,899 mnt → 819.366 pts = ~39,2rb pts/mnt** | **2,909 mnt (2m54,6 dtk) → 4.514.363 pts = ~1,55J pts/mnt** |
| File | `dense700/fused.ply` 22.123.129 B | `scene_dense.ply` 277.076.583 B |
| VRAM | 119–141MB patch (tipikal 133–135, nvidia-smi 5 dtk), 0 saat fusion (CPU) | 405MB (run lama; run ini tak disampel ulang) |
| RAM peak | — (tak diukur run ini) | 1,93GB |

Rasio: titik **5,51x**, waktu **7,18x lebih lama**, throughput **~39,6x**.
Skrip: `undistort700.ps1`, `g3-patch700.ps1` (cfg backup
`patch-match.cfg.full`, `__auto__ 20→8`). Log: `log_patch700.txt`,
`log_fusion700.txt`, `vram_700.csv` (±243 sampel 21:01:30–21:22:23),
`openmvs/DensifyPointCloud-261011204302001811.log`.
Koreksi: klaim "VRAM tidak valid" (chat 2026-10-11) SALAH — 0 di ekor
= fase fusion CPU, bukan sampler mati; 133MB fase patch valid dan
wajar (700px ≈ 1/4 piksel dari 1400px/321MB).
Implikasi: gap riil di titik operasi sama → lanjut Mod 4
(coarse-to-fine) + konkurensi 2–3 instance (F8) sebagai penutup gap
utama.

### Milestone 2026-10-12: VONIS AKHIR optimasi (Tugas 0–6 + Midai)

Konfig pemenang (`iter1`, default baru): ws2 + num_iterations 1, yaitu
pyramid_levels 1 + filter_min_confidence 0.2 + window_step 2 +
fuse_prior_weight 1.0 + floor ≥2 + max_tri 65 + auto 8. Flag baru (semua
default-mati = upstream utuh): `single_pass`, `pyramid_levels`,
`filter_min_confidence`, `fuse_prior_weight`.

Tangga ablasi Lewoleba @700px (117 view):

| Konfig | Depth | Titik | vs baseline |
|---|---|---|---|
| baseline 2-pass | 20,317 mnt | 819.366 | — (39,2rb/mnt) |
| singlepass (T1) | 9,59 (47%) | 840.806 (+2,6%) | 2,1x |
| pyramid1 (T2) | 14,81 (73%) | 886.796 (+8,2%) | 1,35x |
| tri15 (T3) | 10,86 | 452.300 (floor selamatkan 51 view, 0 gugur) | default tetap 65° |
| tri65 (T3) | 14,38 | 886.854 (≈pyramid1) | floor no-op di 65° |
| conf02 (T4) | 13,72 | 1.176.350 (+32,6%) | rescue bekerja |
| prior05 (T4) | — (fusion saja) | 1.176.518 (+0,01%, inert: 2+0,5<3) | — |
| prior10 (T4) | — (fusion saja) | 2.850.098 (+142% vs conf02) | 1,67jt konsistensi-2 |
| **ws2 (T6)** | **7,62** | **2.912.986 (+2,2%)** | **8,19 mnt = 356rb/mnt (9,1x, 3,55x titik)** |
| iter2 (R2) | 4,37 (57% ws2) | 2.949.920 (+1,3% TAHAN) | 4,91 mnt = 600rb/mnt |
| **iter1 (R2)** | **2,65** | **2.922.546 (−0,9% TAHAN)** | **3,24 mnt = 902rb/mnt (23x, 3,57x titik)** |
| OpenMVS | ∈ 2,91 total | 4.514.363 | target (1,55J/mnt) |

T5 (overlap I/O) SKIP by design: idle terukur 3,9% < 5%, compute-bound
91,7%. Determinisme: semua re-run ±0,003–0,02% (< ±0,1%); fusion upstream
order-nondeterministik (bit-identik TIDAK dituntut).

Midai 51 foto (site kedua, alt ~80m): SfM 50–51/51 (extract 5,45 +
match 3,18 + mapper 0,72 mnt). Head-to-head @700px:

| | COLMAP iter1 | OpenMVS develop |
|---|---|---|
| Waktu | 1,39 mnt (depth 1,16 + fusion 0,24) | 0,75 mnt (40 dtk) |
| Titik | 1.453.518 (1,04J/mnt; +2,1% vs ws2, TAHAN) | 1.890.956 (~2,5J/mnt, 13,1M→15%) |
| Gap | — | +30% titik, 1,86x waktu |

Metrik numerik (`metrics.cpp`, STL-only, tanpa dependensi): okupansi 0,5m,
outlier NN-8 (median+3MAD), C2C dua arah 50rb sampel, asumsi eksplisit
OpenMVS ≈ acuan. Lewoleba: coverage kita atas acuan 0,995 (onlyB=2 sel),
C2C A→B median 4,4cm/p90 11cm, outlier 7,6% vs 2,9%. Midai: coverage 0,998,
C2C 4,2cm, outlier 5,5% vs 4,6%. Vonis lubang: TERPENUHI di kedua site.
Temuan jujur: halo = harga rescue (baseline pra-mod bersih 2,9% tapi
berlubang 23%; pemenang 0% lubang tapi 7,6% outlier + ekor ekstrem).
PGM nadir per pasangan di `nadir_{A,B}.bmp`; cek visual manusia DICORET
atas perintah pemilik ("lupakan") — oracle = numerik penuh.

Vonis vs kriteria goal (titik/mnt ≥ DAN lubang ≤): lubang TERPENUHI di
kedua site; titik/mnt BELUM tapi dekat — Lewoleba 902rb vs 1,55J (1,7x;
waktu 1,11x = paritas waktu tercapai), Midai 1,04J vs 2,5J (2,4x; waktu
1,86x). Determinisme iter1/iter2: −0,011% (Midai menyusul). Tuas logis
tersisa: NCC adaptif. PopSIFT tetap pending (sparse sudah cukup, tak
pengaruhi kriteria).

### Milestone 2026-10-12 Ronde-3 CUDA (kernel, gerbang: tanpa kehilangan titik)

Perubahan kernel (`mvs/` saja, matematika NCC utuh): `SWEEP_THREADS_PER_BLOCK`
64 untuk kernel sweep 1D (`patch_match_cuda.cu`, elem-wise tetap 32 —
64×64 langgar maks 1024 thread/blok) + buffer ping-pong `Rotate()`
(7 spare per view, pangkas ~8.400 malloc/free per run). nsys: Sweep 82%
waktu GPU, transfer 3,8 dtk (bukan bottleneck); ncu GAGAL di WDDM
(detach 2x) → vonis empiris via ablasi + rerun.

| Varian | Lewoleba depth / titik | Midai depth / titik | Vonis |
|---|---|---|---|
| b32 (RED) | 1,975 / 3.356.045 | 1,157 / 1.453.518 | baseline |
| b64 | 1,916 (−3,0%) / +0,03% | 1,126 (−2,7%) / −0,05% | MENANG UMUM |
| b128 | 1,893 (−4,2%) / +0,14% | 1,220 (+5,4%) / +0,06% | CORET (regresi r5) |
| reuse (+b64) | 1,932 rerata / aman | — | NETRAL, dipertahankan (VRAM) |
| launch_bounds | 1,984 (+4,3%) | — | DIBUANG + revert |

Metrik (`metrics.exe`, pemenang kini): Lewoleba reuse2 coverage 0,997
(onlyB=1 sel), C2C A→B med 4,1cm/p90 10cm, outlier 7,4% vs 3,2%.
Midai b64 coverage 0,998 (onlyB=1), C2C 4,3cm, outlier 5,4% vs 4,8%.
Throughput kini: Lewoleba 1,37J/mnt vs 1,55J (0,88x), Midai 1,10J vs
2,52J (0,44x). Micro-CUDA DINYATAKAN HABIS (r7/r3 NCC, block, reuse,
launch_bounds semua divonis angka); sisa gap hanya via tuas algoritmik
(red-black/densifikasi, keluar gerbang titik-sama) atau sisi densitas.

### Milestone 2026-10-12 Ronde-D densitas (parametrik, tanpa kode)

D1 `min_num_pixels` 3→2 (fusion-only): 25,54Jt pts (+660%) tapi SAMPAH —
bbox ±36km, in_shared 0,73, outlier 13,3%, C2C med 7,3cm p90 61,6cm.
DITOLAK (throughput 6,3x semu).
D2 `max_depth_error` 0,05→0,1: Lewoleba 3.563.973 (+6,1%, fusion 0,511)
outlier 8,98% C2C 4,29cm onlyB=0; Midai 1.489.288 (+2,4%) outlier 5,75%
C2C 4,36cm onlyB=1. LOLOS umum.
Midai-r3 (flag r3 penuh + D2, pertama kali diuji di Midai): depth 0,806
(−28%!) / 1.721.491 (+15,6%), outlier 7,16% C2C 4,28cm onlyB=1. JUARA
BARU Midai (0,68x, dari 0,44x). r3 generalisasi sempurna.
D3 `max_reproj_error` 4→6: titik TURUN 5% di kedua site (relaksasi
menggabung track) dengan kualitas datar (Lewoleba out 9,21% C2C 4,27cm;
Midai out 7,31% C2C 4,26cm). DITOLAK umum.
Juara bertahan: Lewoleba `fused_d2.ply` 3.563.973 (1,476J/mnt = 0,95x),
Midai `fused_midai_r3.ply` 1.721.491 (1,713J/mnt = 0,68x). Lubang
terpenuhi (onlyB ≤1) di kedua site.

### Root cause mapper crash (0xc0000409 @52 frame, deterministik 2x)

Tersangka terkonfirmasi: `SPARSE_SCHUR+EIGEN_SPARSE` (kombinasi baru:
Ceres tanpa SuiteSparse + Eigen 5.0.1). Bukti: paksa `DENSE_SCHUR`
(`max dense 1e6/sparse 1e6+1` di `bundle_adjustment_ceres.cc`,
`CERES_NO_SUITESPARSE` only) → mapper lolos penuh 116/117.
Kebijakan kernel: proyek drone (≤ ratusan foto) selalu DENSE_SCHUR;
SPARSE praktis mati sampai ada SuiteSparse non-GPL atau fix upstream.
Revisit bila proyek >500 foto.
`build-mx150/src/colmap/exe/colmap.exe` jalan (`-h` OK).
Skrip SfM: `sfm-15agustus.ps1` (CPU SIFT `use_gpu 0`, single_camera,
sequential overlap 10) → `E:\dev\Lewoleba-15agustus\`.

### Rencana profiling GPU + PopSIFT (setelah baseline CPU jadi)
Urutan: baseline CPU selesai → integrasi PopSIFT (MPL-2.0) sebagai ablasi
→ profiling → baru putuskan optimasi.

1. **cuBLAS SGEMM fp32 microbench**: sweep ukuran (512–4096) via `cublasSgemm`,
   ukur GFLOPS vs roofline MX150 (±1.65 TFLOPS fp32 teoritis) — jadi angka
   acuan kapasitas GPU sebelum tuduh kernel lain lambat.
2. **Stage timing PopSIFT**: total ekstraksi, top-2 kernel, konversi
   deskriptor (host), transfer H2D/D2H — instrumentasi CUDA events +
   chrono bila nsys tak tersedia.
3. **Nsight**: `nsight-systems` tidak ada di conda win-64; installer
   resmi butuh admin → CORet. Pengganti: **`cuda-cupti` 12.4 terpasang**
   (`lib/cupti64_2024.1.1.dll` + `cupti.lib` + header; catat: DLL di
   `lib\`, bukan `bin\` — tambah ke PATH saat run profiler) +
   instrumentasi CUDA events manual.
   Target: temukan 1 bagian terlambat, optimasi itu dulu (bukan tebak).

## Kebijakan lisensi — hindari GPL/AGPL & non-komersial (mesin MX150, 2026-10-11)

Audit `src/thirdparty/` + `vcpkg.json` + `cmake/FindDependencies.cmake`.
Aturan: tidak ada kode GPL/AGPL yang ikut build; tidak ada eksekusi kode
non-komersial; OpenMVS (AGPL-3.0) hanya dipakai sebagai pembanding
proses-terpisah, tidak ada salin kode ke tree ini (port fitur = tulis ulang
native, bukan copy).

| Komponen | Lisensi | Status | Tindakan |
|---|---|---|---|
| LSD (`thirdparty/LSD`) | AGPL-3.0 | BAHAYA (copyleft jaringan) | `-DLSD_ENABLED=OFF` saat configure |
| CGAL (vcpkg) | GPL | BAHAYA | `-DCGAL_ENABLED=OFF` (sudah rencana) |
| SuiteSparse via ceres | GPL-2.0+ | BAHAYA (link statis vcpkg) | `suitesparse` DIBUANG dari fitur ceres di `vcpkg.json` (sisakan `lapack`, `schur`); Ceres fallback ke `EIGEN_SPARSE` + `ITERATIVE_SCHUR` — cukup untuk SfM 117 foto |
| CHOLMOD (SuiteSparse) di `optim/` + `FindDependencies` | GPL | BAHAYA (`REQUIRED` + link unconditional) | Dibuat opsional: `find_package(CHOLMOD)` tanpa `REQUIRED`, link + definisi `COLMAP_NO_CHOLMOD` kondisional di `optim/CMakeLists.txt`, `sparse_cholesky.{h,cc}` fallback LDLT-only via `#ifdef` |
| Default sparse-lib Ceres (`SUITE_SPARSE`) | — (runtime fail bila SuiteSparse absen) | WAJIB perbaiki (BA auto bisa fatal) | `CeresBundleAdjustmentOptions()` set `EIGEN_SPARSE` bila `CERES_NO_SUITESPARSE` (`bundle_adjustment_ceres.cc`) |
| Qt (GUI) | LGPL/GPL | hindari | `-DGUI_ENABLED=OFF` (sudah rencana) |
| SiftGPU (`thirdparty/SiftGPU`) | UNC custom: riset/non-profit saja | TERBATAS — ikut ter-link bila CUDA/GL on (`GPU_ENABLED`, tanpa saklar build) | TIDAK DIPAKAI (keputusan 2026-10-11, sempat uji ±3.5 dtk/foto lalu revert): SfM selalu `--FeatureExtraction.use_gpu 0 --FeatureMatching.use_gpu 0` (CPU SIFT via VLFeat/BSD, terukur ±6 dtk/foto wall, 10–18rb fitur/foto). Alternatif GPU yang dievaluasi: ALIKED via ONNX (MIT, tapi butuh cuDNN yang tak tersedia tanpa akun NVIDIA → jatuh ke CPU; juga mengganti tipe fitur) dan OpenCV-SIFT (Apache, tapi tak terhubung ke COLMAP) — keduanya ditolak. Uji GPU dialihkan ke MVS dense (PatchMatch CUDA, kode sendiri, tanpa masalah lisensi) |
| PoissonRecon | MIT | aman, dipakai `colmap_mvs` | — |
| VLFeat, Eigen (MPL-2.0), Boost, glog/gflags, SQLite, Metis (Apache), OpenImageIO, ONNX (MIT), faiss (MIT), PoseLib (BSD), OpenBLAS, curl/OpenSSL | permisif | aman | — |
| Caspar/Symforce | default `CASPAR_ENABLED=OFF` + butuh `sm_75` (kita `sm_61`) | tidak aktif | — |

Flag configure final (bersih GPL): `-DCUDA_ENABLED=ON -DGUI_ENABLED=OFF
-DCGAL_ENABLED=OFF -DLSD_ENABLED=OFF -DTESTS_ENABLED=OFF
-DDOWNLOAD_ENABLED=OFF -DCASPAR_ENABLED=OFF` (+ default lain).

### Audit dependensi vcpkg ter-install (2026-10-11, 28+ paket)

Sumber: field `license` tiap `ports/*/vcpkg.json` + output lisensi vcpkg.
Keputusan: **tolak semua non-permisif; dual-license ambil sisi permisif.**

| Paket | Lisensi terdeklarasi | Putusan |
|---|---|---|
| zstd | `BSD-3-Clause OR GPL-2.0-only` | PAKAI sisi **BSD-3-Clause** (terdokumentasi di sini); sisi GPL tidak diambil |
| sqlite3 | `blessing` (dedikasi public-domain SQLite) | aman |
| jasper (field kosong) | JasPer License 2.0 (MIT-style, permisif) | aman |
| eigen3 | `MPL-2.0` | aman (copyleft level-file; static-link tidak menular) |
| openblas, lapack-reference (`BSD-3-Clause-Open-MPI`) | BSD | aman |
| gklib, metis, openimageio, ceres | `Apache-2.0` | aman |
| tiff (`libtiff`), bzip2 (`bzip2-1.0.6`), libpng (`libpng-2.0`), zlib/zstd-runtime/minizip-ng (`Zlib`), liblzma (`0BSD`) | permisif | aman |
| glew (field kosong) | BSD/MIT upstream | aman |
| opengl port + egl/opengl-registry | system lib / Apache-2.0 | aman (pengecualian system library) |
| cuda port | tidak install apa-apa (verifikasi saja) | toolchain conda tunduk EULA NVIDIA (redistributable, catat untuk distribusi) |
| suitesparse/cxsparse/cholmod | TIDAK ADA di tree (`vcpkg_installed/.../share` bersih) | terkonfirmasi tersingkir |
| onnxruntime-gpu (FetchContent biner) | MIT | aman, verifikasi saat fetch selesai |

### Audit lisensi putaran-2 (2026-10-12, bukti fisik + context7)

Metode: baca file LICENSE tiap komponen, flag configure aktual, artefak
build, strings + link-line `build.ninja` pada `colmap.exe`, docs Eigen
(MPL-2.0 terkonfirmasi). Temuan load-bearing: `colmap_sift_gpu.lib`
TERBUKTI ter-link statis ke biner (UNC: riset/non-profit saja) —
"tak pernah dieksekusi" tidak menolong distribusi. Perbaikan (sudah
dieksekusi + terverifikasi): hapus `src/thirdparty/SiftGPU/` dan
`src/thirdparty/LSD/` (AGPL) dari tree; `SIFTGPU_ENABLED` default-OFF
+ gerbang `COLMAP_SIFTGPU_ENABLED` di `sift.cc` (factory use_gpu→nullptr,
cermin upstream non-GPU); default `LSD_ENABLED`→OFF; export/link yatim
(`colmap_sift_gpu` di root + `feature/CMakeLists`) digerbang sama.
Verifikasi: rebuild sukses, `colmap_sift_gpu.lib` hilang, strings
SiftGPU tinggal 1 (teks warning), LSD nol objek (dari awal), smoke
CPU-SIFT 3/3 foto lolos (exit 0). Pengecualian tercatat (tanpa alternatif
realistis): Eigen MPL-2.0 header-only tak-dimodifikasi (karya besar boleh
permisif, notice dipertahankan) + toolchain CUDA proprietary (redistributable,
notice NVIDIA wajib pada distribusi biner).
