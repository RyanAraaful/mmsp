# MMSP mods — drone dense engine (MX150 2GB sm_61)

Basis: COLMAP `bd1fcf6` (`<repo>/colmap`, snapshot pristine = commit pertama).
Dataset acuan: primary site (117 foto DJI nadir) + secondary site (51 foto).

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
- Prebuilt `<openmvs-prebuilt>` (v2.4.0) GAGAL dipakai: `DensifyPointCloud`
  mati saat init CUDA (`UtilCUDADevice.h:54`, code 500, named symbol
  not found) — biner tak kompatibel driver/MX150. Lanjut build sumber.
  Data sampingan valid: pairing OpenMVS 2–8 view/ref (mendukung
  `__auto__` 6 kita).
- Patch kompat-build (BUKAN custom perilaku): fork poselib OpenMVS
 (`cdcseacave/PoseLib ccdd2f6`) kena penyakit deduksi Eigen 5 + MSVC
  yang sama → patch forwarding-identik di
  `buildtrees/.../jacobian_accumulator.h` (backup di
  `<cuda-toolkit>\poselib-eigen5-fix\`), numerik tak berubah. Sumber
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

### Protokol benchmark (MX150 2GB; primer: Primary 15-AGUSTUS 117 foto,
sekunder/pembanding: Secondary  51 foto @~80m + subset strip
Primary ±30 foto untuk iterasi cepat)

Metrik: waktu depth, waktu fusion, jumlah titik, peak VRAM
(`nvidia-smi`), lubang visual di atap/jalan. Lawan: COLMAP stok 3.13
(2106 dtk @1000px, `fused.ply` 29KB), config ini, OpenMVS
(menyusul), Metashape High (menyusul). Menang = waktu ≤ OpenMVS
dengan titik ≥ dan lubang ≤.

## Build (MX150, Windows, MSVC 19.34 + CUDA 12.4 conda, no-admin)

Toolchain: `<cuda-toolkit>\cuda-env` (micromamba, channel `nvidia/label/cuda-12.4.1`)
+ curand fallback dari wheel PyPI (`curand.lib` di-generate via `dumpbin`+`lib.exe`).
`sm_61` compile-and-run teruji `SM61_OK`. Skrip: `configure-mx150.ps1`, `build-mx150.ps1`.
vcpkg di `<vcpkg>` (bootstrap selesai).

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

### Milestone 2026-10-11: HEAD-TO-HEAD Primary (jujur, operating point beda)

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
117 JPG Primary → `sparse/0` (116/117, CPU SIFT) → undistort
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

### Milestone 2026-10-12: VONIS AKHIR optimasi (Tugas 0–6 + Secondary)

Konfig pemenang (`iter1`, default baru): ws2 + num_iterations 1, yaitu
pyramid_levels 1 + filter_min_confidence 0.2 + window_step 2 +
fuse_prior_weight 1.0 + floor ≥2 + max_tri 65 + auto 8. Flag baru (semua
default-mati = upstream utuh): `single_pass`, `pyramid_levels`,
`filter_min_confidence`, `fuse_prior_weight`.

Tangga ablasi Primary @700px (117 view):

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

Secondary 51 foto (site kedua, alt ~80m): SfM 50–51/51 (extract 5,45 +
match 3,18 + mapper 0,72 mnt). Head-to-head @700px:

| | COLMAP iter1 | OpenMVS develop |
|---|---|---|
| Waktu | 1,39 mnt (depth 1,16 + fusion 0,24) | 0,75 mnt (40 dtk) |
| Titik | 1.453.518 (1,04J/mnt; +2,1% vs ws2, TAHAN) | 1.890.956 (~2,5J/mnt, 13,1M→15%) |
| Gap | — | +30% titik, 1,86x waktu |

Metrik numerik (`metrics.cpp`, STL-only, tanpa dependensi): okupansi 0,5m,
outlier NN-8 (median+3MAD), C2C dua arah 50rb sampel, asumsi eksplisit
OpenMVS ≈ acuan. Primary: coverage kita atas acuan 0,995 (onlyB=2 sel),
C2C A→B median 4,4cm/p90 11cm, outlier 7,6% vs 2,9%. Secondary: coverage 0,998,
C2C 4,2cm, outlier 5,5% vs 4,6%. Vonis lubang: TERPENUHI di kedua site.
Temuan jujur: halo = harga rescue (baseline pra-mod bersih 2,9% tapi
berlubang 23%; pemenang 0% lubang tapi 7,6% outlier + ekor ekstrem).
PGM nadir per pasangan di `nadir_{A,B}.bmp`; cek visual manusia DICORET
atas perintah pemilik ("lupakan") — oracle = numerik penuh.

Vonis vs kriteria goal (titik/mnt ≥ DAN lubang ≤): lubang TERPENUHI di
kedua site; titik/mnt BELUM tapi dekat — Primary 902rb vs 1,55J (1,7x;
waktu 1,11x = paritas waktu tercapai), Secondary 1,04J vs 2,5J (2,4x; waktu
1,86x). Determinisme iter1/iter2: −0,011% (Secondary menyusul). Tuas logis
tersisa: NCC adaptif. PopSIFT tetap pending (sparse sudah cukup, tak
pengaruhi kriteria).

### Milestone 2026-10-12 Ronde-3 CUDA (kernel, gerbang: tanpa kehilangan titik)

Perubahan kernel (`mvs/` saja, matematika NCC utuh): `SWEEP_THREADS_PER_BLOCK`
64 untuk kernel sweep 1D (`patch_match_cuda.cu`, elem-wise tetap 32 —
64×64 langgar maks 1024 thread/blok) + buffer ping-pong `Rotate()`
(7 spare per view, pangkas ~8.400 malloc/free per run). nsys: Sweep 82%
waktu GPU, transfer 3,8 dtk (bukan bottleneck); ncu GAGAL di WDDM
(detach 2x) → vonis empiris via ablasi + rerun.

| Varian | Primary depth / titik | Secondary depth / titik | Vonis |
|---|---|---|---|
| b32 (RED) | 1,975 / 3.356.045 | 1,157 / 1.453.518 | baseline |
| b64 | 1,916 (−3,0%) / +0,03% | 1,126 (−2,7%) / −0,05% | MENANG UMUM |
| b128 | 1,893 (−4,2%) / +0,14% | 1,220 (+5,4%) / +0,06% | CORET (regresi r5) |
| reuse (+b64) | 1,932 rerata / aman | — | NETRAL, dipertahankan (VRAM) |
| launch_bounds | 1,984 (+4,3%) | — | DIBUANG + revert |

Metrik (`metrics.exe`, pemenang kini): Primary reuse2 coverage 0,997
(onlyB=1 sel), C2C A→B med 4,1cm/p90 10cm, outlier 7,4% vs 3,2%.
Secondary b64 coverage 0,998 (onlyB=1), C2C 4,3cm, outlier 5,4% vs 4,8%.
Throughput kini: Primary 1,37J/mnt vs 1,55J (0,88x), Secondary 1,10J vs
2,52J (0,44x). Micro-CUDA DINYATAKAN HABIS (r7/r3 NCC, block, reuse,
launch_bounds semua divonis angka); sisa gap hanya via tuas algoritmik
(red-black/densifikasi, keluar gerbang titik-sama) atau sisi densitas.

### Milestone 2026-10-12 Ronde-D densitas (parametrik, tanpa kode)

D1 `min_num_pixels` 3→2 (fusion-only): 25,54Jt pts (+660%) tapi SAMPAH —
bbox ±36km, in_shared 0,73, outlier 13,3%, C2C med 7,3cm p90 61,6cm.
DITOLAK (throughput 6,3x semu).
D2 `max_depth_error` 0,05→0,1: Primary 3.563.973 (+6,1%, fusion 0,511)
outlier 8,98% C2C 4,29cm onlyB=0; Secondary 1.489.288 (+2,4%) outlier 5,75%
C2C 4,36cm onlyB=1. LOLOS umum.
Secondary-r3 (flag r3 penuh + D2, pertama kali diuji di Secondary): depth 0,806
(−28%!) / 1.721.491 (+15,6%), outlier 7,16% C2C 4,28cm onlyB=1. JUARA
BARU Secondary (0,68x, dari 0,44x). r3 generalisasi sempurna.
D3 `max_reproj_error` 4→6: titik TURUN 5% di kedua site (relaksasi
menggabung track) dengan kualitas datar (Primary out 9,21% C2C 4,27cm;
Secondary out 7,31% C2C 4,26cm). DITOLAK umum.
Juara bertahan: Primary `fused_d2.ply` 3.563.973 (1,476J/mnt = 0,95x),
Secondary `fused_secondary_r3.ply` 1.721.491 (1,713J/mnt = 0,68x). Lubang
terpenuhi (onlyB ≤1) di kedua site. kernel-t3 DITUTUP di angka ini
(re-verifikasi segar 2026-10-12 identik ledger); sisa gap = riset
algoritmik berikutnya (red-black/densifikasi, butuh gate baru).

### Milestone 2026-10-14 duel OpenSfM (pembanding eksternal, pin `c1fcfcec` 2026-10-08, BSD-2-Clause; tak masuk tree/notices)

Duel tercatat Secondary 51 foto (file 4000x3000 sama, `single_camera`, 51/51 teregistrasi kedua sisi):

| metrik | hibrida kita (COLMAP SIFT) | OpenSfM (HAHOG default) | sumber |
|---|---|---|---|
| resolusi proses | 3200 (default SIFT) | 2048 (`feature_process_size`) | `extractor.cc:138`, `config.py:41` |
| fitur/foto aktual | mean 12.665 (9.637–16.008) | mean 4.973 (4.706–5.384) | `database.db`, `stats.json` |
| pasangan match | 243 (sequential overlap 10) | 862 (GPS distance 150) | `database.db`, `log_match_features.txt` |
| extract | 275 dtk (GPU) | 101,8 dtk | log duel |
| match | 187 dtk (CPU) | 49,2 dtk | log duel |
| total SfM | 503 dtk | 203,4 dtk | log + `profile.log` |
| points | 19.833 | 19.962 | mapper / `stats.json` |
| track | 5,008 | 3,858 (5,331 over-two; definisi beda) | model_analyzer / `stats.json` |
| reproj | 0,912px | 0,765px | model_analyzer / `stats.json` |

VONIS: OpenSfM MENANG wall (2,5x) di duel tercatat; kualitas campur (points ±0,6% sama, reproj mereka lebih baik, track kita lebih panjang).

**Duel ulang FAIR (2026-10-14, project `Midai-14agustus-fair`, hasil lama tak ditimpa):**
COLMAP `--FeatureExtraction.max_image_size 2048 --SiftExtraction.max_num_features 5000`;
OpenSfM `config.yaml` HAHOG/2048/4000 (= default, perilaku tak berubah).

| metrik | COLMAP fair | OpenSfM fair | sumber |
|---|---|---|---|
| fitur/foto aktual | mean 7.192 (5.920–9.280; flag 5000 = soft target, tak hard-cap) | mean 4.973 (4.706–5.384) | `database.db`, `stats.json` |
| pasangan match | 243 (sequential overlap 10) | 862 (GPS distance 150) | `database.db`, `log_match_features.txt` |
| extract | 121,7 dtk (CPU) | 95,4 dtk | `log_extract.txt` / `profile.log` |
| match | 84,3 dtk (CPU) | 48,5 dtk | `log_match.txt` / `profile.log` |
| mapper/reconstruct | 27,1 dtk | 43,7 dtk | `log_mapper.txt` / `profile.log` |
| total SfM | ~233 dtk | ~209 dtk | jumlah stage |
| reg | 51/51 | 51/51 | model_analyzer / `stats.json` |
| points | 12.686 | 19.992 | model_analyzer / `stats.json` |
| track | 4,966 | 3,860 | model_analyzer / `stats.json` |
| reproj | 1,015px | 0,767px | model_analyzer / `stats.json` |

VONIS FAIR: wall hampir setera (OpenSfM 1,1x — gap 2,5x tertutup setelah resolusi disamakan);
kualitas OpenSfM menang (points +58%, reproj lebih baik; track kita lebih panjang).
Sisa beda jujur: budget fitur 1,4x (7,2rb vs 5rb — flag COLMAP soft) + pasangan 243 vs 862
+ SIFT vs HAHOG (itu yang diadu).

**Optimasi 1 SELESAI (2026-10-14, project `Midai-14agustus-fairgpu`):**
extract pakai SIFT-GPU native (`--SiftExtraction.use_gpu_native 1`, match tetap CPU).
Verifikasi jalur: log TAK ada baris `sift.cc:779` CPU (kode native memang tanpa LOG) +
fitur mean 7.194 vs 7.192 CPU (paritas bit, sesuai desain).
Hasil: extract 113,3 (vs 121,7 CPU, −7%) + match 82,9 + mapper 27,4 = ~224 dtk
(vs 233 CPU, −4%); 51/51, 12.737 pts, track 4,957, reproj 1,016px.
VONIS: valid tapi kecil — OpenSfM tetap 1,07x + kualitas menang. Gain GPU menyusut
di 2048px (dulu −26% di 3200px); overhead alokasi-per-Extract mendominasi di MX150.

**Optimasi 2 NO-OP karena desain salah (2026-10-14, project `Midai-14agustus-fairo7`):**
overlap 10→7 hasilkan pasangan IDENTIK (243 = 243) karena `quadratic_overlap=true`
(default, `pairing.h:92`): spacing eksponensial 1,2,4,8,16,32 — untuk 51 foto,
overlap 7 dan 10 valid di spacing yang sama. Hasil: 51/51, 12.678 pts
(vs 12.686 = noise), match 83,5 vs 84,3 dtk. Bukan gagal eksekusi (semua exit 0),
tapi knob tak berfungsi di rentang ini. Syaratretry: overlap ≤5 atau
`--SequentialMatching.quadratic_overlap 0`.

**Optimasi 3 SELESAI (2026-10-14, project `Midai-14agustus-fair8000`):**
`max_num_features` 5000→8000 + extract GPU-native, match CPU, overlap 10.
Aktual fitur mean 11.875 (flag soft lagi); extract 110,2 + match 177,8 +
mapper 42,2 = ~330 dtk; 51/51, 19.532 pts, track 4,977, reproj 0,927px.
Tukaran: +6.800 pts (+54%) untuk +106 dtk (+47%) vs fair-GPU.
VONIS: paritas points hampir tertutup (19.532 vs 19.992 = 97,7%) tapi wall
1,58x OpenSfM (330 vs 209); reproj tetap kalah (0,927 vs 0,767px).
Pelajaran: OpenSfM capai 20rb points dari 5rb fitur + 862 pasangan, kita butuh
11,9rb fitur + 243 pasangan — strategi pilih pasangan lebih menentukan
daripada budget fitur mentah. Match CPU skala ~kuadratik (84→178 dtk),
jadi jalan keluar wall = matcher lebih cepat atau pasangan lebih pintar,
bukan fitur lebih banyak.

### Root cause mapper crash (0xc0000409 @52 frame, deterministik 2x)

Tersangka terkonfirmasi: `SPARSE_SCHUR+EIGEN_SPARSE` (kombinasi baru:
Ceres tanpa SuiteSparse + Eigen 5.0.1). Bukti: paksa `DENSE_SCHUR`
(`max dense 1e6/sparse 1e6+1` di `bundle_adjustment_ceres.cc`,
`CERES_NO_SUITESPARSE` only) → mapper lolos penuh 116/117.
Kebijakan kernel: proyek drone (≤ ratusan foto) selalu DENSE_SCHUR;
SPARSE praktis mati sampai ada SuiteSparse non-GPL atau fix upstream.
Revisit bila proyek >500 foto.
`build-mx150/src/colmap/exe/colmap.exe` jalan (`-h` OK).
Skrip SfM: `sfm-primary.ps1` (CPU SIFT `use_gpu 0`, single_camera,
sequential overlap 10) → `<primary-dataset>\`.

### Rencana profiling GPU + SfM-GPU native (putusbawan pemilik 2026-10-12)

PopSIFT DITOLAK (MPL-2.0 di luar pengecualian Eigen+CUDA yang tercatat;
 diverifikasi via docs AliceVision — paten SIFT sendiri kedaluwarsa 2020
 sehingga paten bukan masalah, lisensinya yang ditolak). Pengganti: tulis
 SIFT-GPU native Apache-2.0 di tree ini (tanpa dependensi baru), ronde
 pertama = ekstraksi + matching sekaligus. Pembanding = install OpenSfM
 (BSD-3.0) + duel adil Secondary 51 foto: kecepatan (mnt extract+match)
 dan kualitas (reg rate, track length, reproj error).
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
| gklib, metis, openimageio | `Apache-2.0` | aman |
| ceres | `BSD-3-Clause` (terverifikasi dari file copyright vcpkg — BUKAN Apache; baris lama salah) | aman |
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

### Lisensi final (2026-10-12, disetujui pemilik)

Apache-2.0 untuk karya orisinal (`LICENSE`, Copyright 2026 RyanAraaful).
`THIRD_PARTY_NOTICES.md` ditulis dari sumber primer (teks penuh BSD/MIT
terverifikasi, pointer MPL-2.0/BSL-2.0/EULA). Koreksi: Ceres = BSD-3
(file copyright vcpkg), bukan Apache seperti baris audit lama.

### D1 end-to-end baseline (2026-10-24, MX150)

Sumber: run-summary D1 terbaru yang tersedia lokal; 117 JPG, 117 terdaftar,
`dense/fused.ply` 3.521.155 titik, 859,562 dtk (14m 19,562 dtk), peak VRAM
203 MB dari 555 sampel, input tidak berubah, status `success`, tanpa OOM.
Timing tahap: feature extraction 272,506 dtk (31,7%), sequential matching
291,773 dtk (34,0%), mapping 97,296 dtk (11,3%), undistortion 49,285 dtk
(5,7%), PatchMatch 99,821 dtk (11,6%), fusion 42,250 dtk (4,9%). Model
analysis 0,341 dtk; snapshot input 2,567 dtk; integrity check 3,159 dtk.

Keputusan F3: sequential matching dan extraction mendominasi (564,279 dtk,
65,6% total); keduanya berada di internals SfM yang di luar scope perubahan
ini. PatchMatch + fusion memakai 142,071 dtk (16,5% total), tanpa bukti
bottleneck kernel yang membenarkan rewrite. Pertahankan konfigurasi D1 untuk
QA final; tidak ada eksperimen optimasi yang dilakukan. Pengukuran
`tools/metrics.exe` terhadap cloud OpenMVS lokal (`scene_dense.ply`), 0,5 m
occupancy dan sampel 50.000 titik: coverage ours-of-reference 0,970899,
C2C ours→reference median 0,070916 m / p90 0,138137 m, outlier ours 8,528%
dan reference 3,236%. Ini pembanding antar-engine pada site yang sama,
bukan akurasi survey-grade; hasil final akan diukur dengan alat dan referensi
yang sama.

### Finalisasi kontrak proses D1 (2026-10-24)

`process-drone.ps1` mempertahankan argumen `-ImagesPath` / `-OutputDir` dan
field summary lama; summary v1 menambah `schemaVersion: 1` serta
`fusedCloudPath: "dense/fused.ply"` relatif terhadap output. Baris stdout
`MMSP_STAGE_EVENT ` berisi JSON per-stage untuk `started`, `completed`, dan
`failed`. `-ColmapExe` menerima binary eksplisit tanpa memuat konfigurasi
developer; bila tidak diberikan, perilaku development lama dipertahankan.
`-GpuIndex` (default 0) dipakai PatchMatch dan sampler VRAM.

Verifikasi: `test-process-drone.ps1` lulus di Windows PowerShell 5.1 dan
PowerShell 7; kedua script lulus `tools/parsecheck.ps1` pada kedua versi.
Fake-COLMAP menguji JSON, event, path, GPU, kegagalan exit 7, executable
hilang, indeks GPU invalid, perlindungan output non-empty, serta validasi
pasca-COLMAP yang gagal. Event `completed` baru dikirim setelah output tahap
lulus validasi; validasi mapper atau PatchMatch yang gagal menghasilkan event
`failed`.

### Status build/runtime RTX 3050 dan jalur lisensi (2026-10-24)

Cache `colmap/build-mx150/CMakeCache.txt` menunjuk ke source checkout lain;
binary dan DLL closure lokal di folder itu bukan bukti build dari branch ini
dan packager kini menolaknya. Audit artefak lama tetap menunjukkan mengapa
triplet dinamis tidak dapat didistribusikan: `libgfortran-5.dll` dan
`libgcc_s_seh-1.dll` berlisensi GPL-3.0 dengan GCC Runtime Library Exception
3.1, `libquadmath-0.dll` LGPL-2.1, dan `libwinpthread-1.dll` MIT-style.
`libwinpthread` bersifat permissive dan bukan blocker tersendiri, tetapi tidak
dibutuhkan oleh profile statis terverifikasi dan memerlukan notice/map bila
kelak dikemas. GCC exception memberi izin tambahan untuk kombinasi tertentu,
tetapi kebijakan permissive-only repo tetap mengecualikan komponen GPL/LGPL.

Audit port vcpkg menunjukkan jalur konfigurasi tanpa perubahan kode Faiss:
triplet `x64-windows-static` memilih CLAPACK (`ports/lapack/vcpkg.json` dan
`portfile.cmake`) sebagai LAPACK, dengan OpenBLAS sebagai BLAS. OpenBLAS
0.3.33 berlisensi BSD-3-Clause dan port mengaktifkan `NOFORTRAN=ON`;
CLAPACK didistribusikan dengan `COPYING` BSD-3-Clause meski field SPDX port
kosong. Faiss menggunakan provider BLAS/LAPACK yang dipasok CMake/vcpkg;
`FAISS_ENABLE_MKL` dimatikan eksplisit agar tidak memilih backend proprietary.
Zstandard 1.5.7 dual-license BSD-3-Clause atau GPL-2.0-only; build memilih
opsi BSD-3-Clause. Build awal mengompilasi seluruh target tetapi gagal link
karena vcpkg `/MT` bertentangan dengan target COLMAP `/MD` (LNK2038
RuntimeLibrary). Percobaan `x64-windows-static-md` tertahan saat fetch metadata
registry tanpa aktivitas CPU atau koneksi; dihentikan sebelum package berubah.
Konfigurasi minimum menyetel `CMAKE_POLICY_DEFAULT_CMP0091=NEW` dan
`CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>` agar target
CMake memakai `/MT` yang cocok dengan triplet. Build ulang tetap memakai
arsitektur `61;86`; belum ada klaim build, runtime, atau package PASS sampai
kompilasi dan audit import PE dari binary tersebut selesai.

### Review internal (2026-10-24)

Dua temuan Major telah diperbaiki dan diverifikasi ulang: event `completed`
ditunda sampai validasi keluaran tahap lulus, dan README kini mengungkap
dependency runtime GPL/LGPL-family pada build Windows yang tersedia. Reviewer
tidak menemukan Critical/Major tersisa. Catatan Minor: harness uji membaca
stdout penuh sebelum stderr; fake executable saat ini menghasilkan output
kecil, jadi tidak memblokir. Prasyarat PowerShell 5.1/7 telah ditambahkan ke
dokumentasi runtime.

### F2/F4 final runtime follow-up (2026-10-24, historical trial)

Profile permissive-only kini dibangun dari source checkout ini: build Windows
Release selesai 396/396 target; setelah optional ONNX dimatikan secara
eksplisit, rebuild selesai 222/222 target. CMake memakai `/MT`, vcpkg
`x64-windows-static`, dan menghasilkan kode CUDA untuk `sm_61` serta `sm_86`
(flag `compute_61`/`sm_61` dan `compute_86`/`sm_86` terverifikasi pada objek
build). Recursive import audit executable menemukan satu DLL app-local,
`cudart64_12.dll`; paket membawa DLL itu dan lisensi CUDA, 110 notice vcpkg,
source header Eigen MPL-2.0, serta notice proyek. `VCOMP140.DLL` disediakan
Microsoft Visual C++ 2015–2022 x64 Redistributable; Windows API dan driver
NVIDIA tetap prasyarat sistem. Tidak ada DLL GPL/LGPL-family di closure paket.
GCC Runtime Library Exception 3.1 dicatat untuk artefak build lama, tetapi
kebijakan permissive-only proyek tetap mengecualikannya. Packager diuji di
PowerShell 5.1; smoke `colmap version` dari paket berhasil dengan CUDA Toolkit
bin dikeluarkan dari `PATH`.

Trial paket awal melalui Windows PowerShell 5.1: 117/117 foto terdaftar,
234 depth maps, 3.522.577 titik di log/JSON/PLY, status `success`, input
unchanged, tanpa OOM, total 874,099 dtk, dan peak VRAM 203 MB. Mean
reprojection error 0,829178 px. Hasil ini **historis dan superseded**: audit
setelahnya menemukan cache FetchContent lama menunjuk ke source dependency
yang tidak terverifikasi terhadap URL hash. Hasil ini bukan bukti QA untuk
runtime pinned final.

Lima skrip PowerShell yang berubah lulus `tools/parsecheck.ps1` di Windows
PowerShell 5.1 dan 7; kontrak runner fake-COLMAP juga lulus di kedua versi.
Build `sm_86` terbukti sampai kompilasi objek saja; runtime RTX 3050 menunggu
perangkat fisik.

### F2/F4 revalidated from pinned sources (2026-10-24)

Configure final menghapus `FETCHCONTENT_SOURCE_DIR_POSELIB` dan
`FETCHCONTENT_SOURCE_DIR_FAISS` dari cache sebelum generate. Source PoseLib
dan Faiss dipopulasi dari URL yang memiliki `URL_HASH` SHA-256. Hash yang
diverifikasi: PoseLib `ee46322581c7901fe24e91434eeec27163f820d481cba5faa43d37651fabc8e8`,
Faiss `4b1ae7e7a0a46385b4084f0e3945623a15fcf99d793bf44d82aae8e24f11e5f5`.
Patch PoseLib MSVC/Eigen 5 hanya meneruskan ekspresi Eigen ke overload
akumulator yang sudah ada; tidak mengubah perhitungan. Build Release penuh
selesai 208/208 action dengan CUDA `sm_61;sm_86`; Faiss dan `feature/index.cc`
tidak diubah.

Packager kini gagal tertutup untuk DLL yang tidak ada dalam map lisensi
eksplisit. Closure terukur berisi satu DLL app-local, `cudart64_12.dll`
(NVIDIA CUDA Toolkit license disertakan), dan komponen Windows/VC Runtime yang
tidak dibundel. Package menyertakan 110 notice vcpkg, header source Eigen
MPL-2.0, license proyek, notice third-party, dan license CUDA. Smoke
`colmap version` pada package yang diaudit berhasil dengan CUDA Toolkit dan
source checkout dikeluarkan dari `PATH`.

QA E2E final dari package yang sama: 117/117 foto, 3.515.801 titik yang cocok
di JSON/log/header `dense/fused.ply`, `status=success`, exit code 0, input
unchanged, 234 depth maps, tanpa OOM, peak VRAM 203 MB dari 621 sampel.
Binary PLY little-endian tervalidasi dengan 27 byte per vertex, header 248
byte, dan koordinat XYZ sampel finite/nonzero. Mean reprojection error
0,829217 px (baseline 0,828526 px; delta +0,000691 px). Total 877,795 dtk
(14m 37,795 dtk), +18,233 dtk (+2,12%) dari baseline 859,562 dtk; selisih
titik −5.354 (−0,152%). Tidak ada klaim akurasi survey-grade.

Timing final per tahap: snapshot input 2,788 dtk; feature extraction 274,334;
sequential matching 287,601; mapper 94,168; model analyzer 0,271;
undistortion 67,886; PatchMatch 95,608; fusion 49,648; integrity check
3,118. Dua E2E pinned sebelumnya berdurasi 1.109,564 dtk dan 1.243,991 dtk
(matching 467,302 dan 485,278 dtk), tetapi perlambatan tersebut tidak
berulang pada matcher-only dari database salinan (274,408 dtk) maupun E2E
final (287,601 dtk matching; 877,795 dtk total). Penyebab variasi dua run
awal belum terukur dan dicatat tanpa atribusi. Final run berada dalam 2,12%
dari baseline; hasil lama tetap tersimpan sebagai observasi, bukan
disembunyikan.

Review independen menemukan Major tentang source override FetchContent dan
missing-input summary; keduanya diperbaiki dan diuji. Review berikutnya
menemukan Major pada allowlist DLL packager; map eksplisit ditambahkan,
package final berhasil dibuat, dan re-review tidak menemukan Critical/Major.
Security regression suite setelah perubahan final lulus 57/57. Gitleaks 8.30.1
dan artifact guard pada staged diff final lulus; scanner memeriksa sekitar
57,22 KB perubahan dan tidak menemukan leak atau artifact terlarang.
Runtime RTX 3050 belum diuji pada hardware fisik; bukti saat ini sampai
kompilasi `sm_86`.

### Eksperimen sparse SIFT CUDA opt-in (2026-10-24, MX150 sm_61)

Eksperimen 117 foto membandingkan baseline CPU D1 dengan extractor CUDA
native COLMAP yang sudah ada; matcher, pair selection sequential
(`overlap=10`, quadratic overlap 1), mapper, geometric verification, dan
dense pipeline tetap sama. Kedua run memakai executable SHA-256
`72C0037AA752590B6324AB560889D9023DFABE779E869FB8BCEBE39E2C8C0A29`, path
dataset dan daftar input 117 foto yang sama. Perbedaan ekstraksi hanya
`SiftExtraction.use_gpu_native=1`; COLMAP GPU mode tetap mati dan matcher
tetap CPU. Database berisi 903.715 keypoint/descriptor rows pada run CUDA
dan 903.709 pada CPU.

| Metrik | CPU D1 | Native CUDA extractor |
|---|---:|---:|
| Extraction | 274,334 dtk | 249,169 dtk (−9,17%) |
| Sequential matching | 287,601 dtk | 432,473 dtk (+50,38%) |
| Mapper | 94,168 dtk | 161,135 dtk (+71,11%) |
| Sparse subtotal (3 tahap) | 656,103 dtk | 842,777 dtk (+28,45%) |
| E2E | 877,795 dtk | 1.083,708 dtk (+23,46%) |
| Verified pairs | 317 | 317 |
| Verified inlier matches | 235.217 | 235.270 (+53; +0,023%) |
| Foto terdaftar | 117/117 | 117/117 |
| Mean reprojection error | 0,829217 px | 0,830204 px (+0,000987 px) |
| Fused points | 3.515.801 | 3.521.307 (+0,157%) |
| Depth maps | 234 | 234 |
| Peak VRAM tersampel | 203 MB | 681 MB |

Tabel `two_view_geometries` memiliki 692 records per run, tetapi 375
berstatus `DEGENERATE` dengan nol inlier. Angka verified pair di atas hanya
menghitung konfigurasi sukses (`config>1`), yaitu 317 per run. Selisih waktu
matching/mapper tidak dapat diatribusikan ke extractor: run berlangsung
beberapa jam terpisah dan clock, temperatur, serta beban CPU tidak dicatat.
Walau ekstraksi CUDA menghemat 25,165 dtk, run ini tidak menunjukkan
percepatan sparse atau E2E. Karena itu CUDA tetap opt-in eksperimen dan CPU
tetap backend produksi.

Perbandingan diagnostik cloud dengan sampling fixed-stride 50.000 titik
menunjukkan 98,875% massa titik CUDA dan 99,382% massa titik CPU berada pada
sel okupansi 0,5 m yang sama; occupancy Jaccard 0,436964. Rasio outlier 8-NN
masing-masing 8,764% dan 8,854%. C2C mentah dua arah memiliki median 0,074062
dan 0,071931 m. Cloud belum disejajarkan dengan Sim3/ICP dan bounding box
berbeda besar, terutama pada sumbu Z; angka ini diagnostik saja dan bukan
bukti parity atau akurasi cloud. Eksperimen ini tidak membandingkan
points/minute dengan OpenMVS atau mengukur no-hole coverage lintas benchmark,
jadi tidak menghasilkan klaim terhadap success metric proyek.

MMSP build yang dipakai untuk eksperimen mengandung target `sm_61` dan
`sm_86`; runtime dilakukan pada MX150 (`sm_61`). Tidak ada RTX 3050 di
lingkungan, jadi MMSP runtime `sm_86` belum diuji. Hasil dataset ini menguji
extractor CUDA native MMSP; matcher CUDA MMSP belum diimplementasikan.

CudaSift diaudit dan dibangun hanya di OS temp dari commit
`ed5ef54c67354959e3d5fa829d30de5b278b4d62` pada branch `AdaLovelace`.
Build library terpisah berhasil untuk `sm_61` dan `sm_86` dengan NVCC 12.4,
MSVC 19.34, dan OpenCV 4.14.0. CMake kandidat mengunci `sm_89`; nilai target
di-override hanya pada checkout temporary untuk setiap build. Build Windows
juga memerlukan `-DWIN32`, karena header menggunakan `#ifdef WIN32` sementara
MSVC otomatis mendefinisikan `_WIN32`. Dependency prototype dipatok lewat
vcpkg baseline `e456309491fd875487bf02b8a0dca76c1b1b00cc`, OpenCV tanpa
default features, zlib 1.3.2, serta helper build vcpkg. Notice OpenCV yang
terpasang menyertakan Apache-2.0 dan notice zlib memakai lisensi Zlib; CMake
kandidat sendiri tidak mematok versi OpenCV dan manifest OpenCV tidak
mendeklarasikan SPDX license, sehingga ini bukan audit dependency yang dapat
dipakai untuk menyatakan produk lolos.

Smoke test terpisah berjalan pada MX150 `sm_61` memakai citra sintetis
256×256: ekstraksi menghasilkan 1.401 fitur, descriptor berisi 128 float
dengan norm pertama 1, dan matcher API kandidat mengembalikan 1.401 pasangan
pada citra yang sama. Ini sanity check runtime, bukan benchmark atau bukti
kompatibilitas matcher COLMAP. API CudaSift memakai `float[128]`, sedangkan
database COLMAP menyimpan SIFT 128-D sebagai `uint8`; adapter dan parity
harus diuji sebelum interface COLMAP dapat menggunakannya. `sm_86` library
terkompilasi, tetapi belum runtime-tested karena perangkat RTX 3050 tidak
tersedia.

Audit lisensi CudaSift tetap **INDETERMINATE / belum lulus**: branch memiliki
MIT LICENSE dengan copyright Mårten Björkman, tetapi provenance serta cakupan
perubahan branch belum dapat dipastikan dan salinan dokumentasi lama menyebut
penggunaan non-komersial. Reviewer lisensi dan reviewer teknis sama-sama
merekomendasikan menutup gate sampai pemegang hak mengklarifikasi lisensi
serta seluruh provenance. Source CudaSift tidak dimasukkan ke MMSP, tidak
diintegrasikan, dan tidak dipakai dalam benchmark dataset 117 foto.

### Sparse CUDA matching/mapping screening — NO-GO (2026-10-24, MX150 sm_61)

Sebuah prototype sementara untuk exact top-two L2 pada descriptor SIFT
128-D byte dibangun pada Windows Release (`/MT`) dengan CUDA Toolkit
12.4.131 dan target `sm_61;sm_86`. Perangkat runtime adalah Intel Core
i5-8250U dengan GeForce MX150 2 GB, driver 582.28, power plan Balanced.
Source kernel ditulis untuk percobaan ini dengan lisensi
Apache-2.0; tidak mengambil source CudaSift, PopSift, SiftGPU, Faiss, atau
kode vendor CUDA. Prototype dan test sementara dihapus setelah hasil gagal
gate; tidak ada source matcher baru atau dependensi yang tertinggal di tree.

Screening memakai database CPU-extraction 117 foto yang sama untuk kedua
matcher. SHA-256 daftar input adalah
`4C4B85761C1AAB40C7685CC9C0C6FE348BA785EF1FC9D2C354E5AA8EB61C67FB`, dan
SHA-256 database extraction-only adalah
`EB0E9C5CF6C4F049928DC5FF2601A851C9BD847783B8FFBDBB0C0CE84C253640`.
Kedua run memakai executable Release SHA-256
`9E01396A60C29A2125E9349C4D9B5FD9814DC7ABD4B43AE142F4D76446F7891D`, opsi
sequential `overlap=10`, quadratic overlap 1, cross-check/ratio/geometric
verification default yang sama, dan input database hasil clone identik.
CPU Faiss menghasilkan 245.138 raw matches, 316 verified pairs, dan 235.221
inliers dalam 310,397 dtk. Native CUDA exact search menghasilkan 249.682 raw
matches, 317 verified pairs, dan 240.200 inliers dalam 1.303,495 dtk.
Per run ini raw-match Jaccard 0,967671 (common 243.345); inlier Jaccard
0,969636 (common 234.046). Inlier bertambah 2,117% dan waktu matching menjadi
4,20 kali lebih lama (+319,94%). Hasil tidak identik karena CPU memakai Faiss
IVF dengan pencarian approximate, sedangkan prototype memeriksa semua
descriptor. Prototype gagal toleransi yang ditetapkan sebelum screening
(raw agreement >=99,99%, perubahan inlier <=0,1%); tidak ada klaim parity.
Verdict prototype matching adalah **NO-GO**. Unit test atau regression test
otomatis untuk prototype tidak dijalankan; screening dataset satu kali ini
bukan pengganti suite test.

Angka waktu tersebut adalah satu screening penuh per backend, bukan median
benchmark tiga pengulangan. Pengulangan dan E2E matcher CUDA dihentikan setelah
gate correctness gagal dan run penuh menunjukkan perlambatan besar. Karena itu
tidak ada klaim foto terdaftar, reprojection error, sparse/E2E total, atau
point-cloud parity untuk matcher CUDA. Warm-up CPU E2E terpisah berhasil
117/117 foto, 234 depth maps, dan 3.531.284 fused points, tetapi bukan
pembanding E2E terhadap CUDA matcher. Artifak log/database disimpan pada
direktori eksperimen eksternal dan tidak dilacak Git.

Pada screening CUDA, telemetry `nvidia-smi` satu detik mencatat maksimum
utilisasi GPU 100%, suhu 78 C, clock SM dalam rentang 1.328–1.670 MHz, dan
maksimum VRAM tersampel 87 MB; ini adalah sampling driver, bukan peak
allocation kernel. Pengambilan daya tidak tersedia. `typeperf` pada window
yang sama mencatat CPU sistem rata-rata 16,4%, maksimum 56,2%, dan available
RAM minimum 12.344 MB. Sensor suhu/clock CPU tidak tersedia.
Tidak terjadi OOM. Runtime hanya diuji pada GeForce MX150 (`sm_61`); RTX 3050
tidak tersedia. Build menghasilkan target `sm_86`, tetapi tidak ada klaim
runtime RTX 3050.

GPU mapping **belum dievaluasi**: tidak ada prototype atau benchmark mapping
CUDA. Build memakai Ceres 2.2.0 dengan komponen LAPACK dan Schur
specialization tanpa dukungan CUDA; jalur CUDA sparse/CUDSS tidak tersedia,
jadi eksperimen mapping dihentikan pada pemeriksaan kelayakan ini. Profil CPU
sebelumnya mencatat local/global BA 81,1 detik dalam mapper 99,6 detik dan E2E
932,2 detik. Angka itu bukan hasil pengujian GPU mapping. CPU
SIFT/matching/mapping tetap backend produksi; tidak ada CUDA matching atau
mapping yang aktif.
