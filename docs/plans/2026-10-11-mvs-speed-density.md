# MVS Speed+Density Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port OpenMVS speed+density mechanisms into COLMAP `mvs/` as native C++/CUDA mods, each proven by a full-117 @700px ablation, until time and points approach OpenMVS (2,91 mnt / 4,51jt titik).

**Architecture:** Sequential mods on the existing two-pass orchestration (single-pass fold → pyramid init → view floor → confidence/fusion → overlap → param ablation); each task ends in a runnable `colmap.exe` + measured numbers, revert on regression.

**Tech Stack:** C++17 + CUDA (sm_61), existing COLMAP `mvs/` classes, PowerShell `.ps1` harness (repo rule: never inline `$`; bash has no coreutils).

**Spec:** `<repo>/docs/specs/2026-10-11-colmap-mvs-speed-density-design.md`

## Global Constraints

- Scope kode: `colmap/src/colmap/mvs/` + `colmap/src/colmap/controllers/option_manager.cc` saja.
- Tanpa GPL/AGPL/non-komersial masuk build/eksekusi; OpenMVS hanya ide, tulis ulang native.
- Target MX150 2GB sm_61; VRAM <1,5GB; 0 OOM; fallback deterministik (seed tetap, `fused.ply` bit-identik, double-run diff).
- Baseline ablasi = run adil @700px (`MODS.md` milestone adil); harness freeze sebelum Task 1.
- Jangan rebuild saat biner dipakai run (Windows lock); klaim hanya dari angka.

## Cara kerja tiap task (TDD red-green + ponytail — mengikat)

Iron law yang diadaptasi ke repo ini (tanpa pytest; suite = build penuh):
**TIDAK ADA KODE PRODUKSI TANPA BUKTI GAGAL DULU.** Bentuk RED yang sah di
repo ini: (a) CLI menolak flag baru (exit ≠ 0, pesan flag tak dikenal);
(b) `Check()` menolak nilai buruk; (c) build GAGAL (simbol belum ada)
setelah call-site ditulis duluan; (d) run baseline menunjukkan perilaku
buruk yang harus dibalik (lambat/gugur). Bentuk GREEN: build exit 0 (167
target = regression gate) + run harness + angka + double-run jumlah titik
dalam ±0,1% (bit-identik TIDAK dituntut untuk fusion multithread; bukti:
input identik → 819.227 vs 819.366).
`ctest` tidak dipakai (build kita `TESTS_ENABLED=OFF`; menyalakannya =
rebuild berat — di luar scope, dicatat sebagai skip beralasan).
Ladder ponytail: tangga pertama yang menahan (tak perlu? → helper existing?
→ stdlib? → satu baris? → kode minimal); tiap diff minimal + komentar why
satu baris; tiap skip dicatat di log task. Pelaksana yang menulis kode
sebelum RED: hapus, ulangi dari RED.

## Review Focus

- View dengan 0 tetangga setelah filter → problem dibuang + lubang strip. Harapan: floor ≥2 tetangga + log. Diuji di Task 3 (ablasi 15° vs 65° + hitung problem gugur).
- `geom_consistency=true` tanpa photometric maps → init seed kosong/crash. Harapan: Check() menolak atau fallback acak + warning. Diuji di Task 1 (run tanpa maps).
- Upsample coarse→fine salah ukuran vs bitmap fine → CopyToDevice corrupt. Harapan: THROW_CHECK dimensi + test round-trip. Diuji di Task 2.
- Threading/I-O overlap merusak determinisme atau LRU cache. Harapan: bit-identik double-run. Diuji di Task 5 (atau SKIP bila idle <5%).
- Instance konkuren melebihi VRAM di view besar. Harapan: fallback sekuensial + 0 OOM full-117. Diuji di Task 5.

---

### Task 0: Harness freeze + baseline pin

**Files:**
- Create: `<repo>/run-ablate.ps1`
- Modify: none.

**Interfaces:**
- Consumes: `g3-patch700.ps1` (pola sampler VRAM + CLI flags baseline).
- Produces: `run-ablate.ps1 -Label <nama> [-ExtraArgs <string>]` → menulis `log_patch_<label>.txt`, `log_fusion_<label>.txt`, `vram_<label>.csv`, mencetak titik/waktu/hash; dipakai semua task.

- [ ] **Step 1: Konfirmasi repo git colmap + catat hash**

Run: `git -C <repo>/colmap status --short` dan `git -C <repo>/colmap rev-parse --short HEAD`
Expected: status bersih (atau hanya file mod kita), HEAD tercetak. Bila bukan repo git → tiap task menyimpan backup `.orig` sebelum edit (catat di log task).

- [ ] **Step 2: Tulis `run-ablate.ps1` (parameter Label + ExtraArgs)**

Isi: tiru `g3-patch700.ps1` (undistort SEKALI di luar skrip — `dense700/` dipakai ulang; sampler `nvidia-smi` 5dtk; `patch_match_stereo` flags baseline @700px + `$ExtraArgs`; `stereo_fusion` flags baseline; ekor: `Select-String 'Number of fused points|Elapsed time'` + `Get-FileHash fused.ply`).
Pin viewpoint: render 1 nadir + 1 oblik `dense700/fused.ply` vs `openmvs/scene_dense.ply` dari kamera sama, simpan PNG sebagai `view-nadir-base.png` / `view-oblik-base.png` (cara render bebas — catat perintahnya di skrip sebagai komentar).

- [ ] **Step 3: Dry-run tanpa kode berubah**

Run: `run-ablate.ps1 -Label base`
Expected: angka ≈ baseline (819.366 pts / 20,90 mnt / VRAM ~133MB). Beda >5% → investigasi sebelum Task 1.

### Task 1 (Mod 1): Single photometric pass

**Files:**
- Modify: `colmap/src/colmap/mvs/patch_match_options.h` (+`bool single_pass = false;`), `colmap/src/colmap/mvs/patch_match_options.cc` (+PrintOption, tanpa Check baru), `colmap/src/colmap/controllers/option_manager.cc` (+`AddDefaultOption("PatchMatchStereo.single_pass", &patch_match_stereo->single_pass);` setelah baris 1020), `colmap/src/colmap/mvs/patch_match.cc` (`PatchMatchController::Run()`, :170-207).

**Interfaces:**
- Consumes: `PatchMatchOptions::geom_consistency/filter` semantics (`patch_match.cc:183-197`).
- Produces: `--PatchMatchStereo.single_pass` (true = satu loop `geom_consistency=false, filter=true`, tulis `photometric` maps; loop geometrik dilewati).

- [ ] **Step 0 (RED): Buktikan flag belum ada**

Run (biner lama, tanpa argumen workspace penuh — cukup sampai parse gagal): `colmap.exe patch_match_stereo --PatchMatchStereo.single_pass 1`
Expected: exit ≠ 0 dengan pesan flag tak dikenal. Catat pesan persis di log task. Dilarang lanjut sebelum ini tercatat.

- [ ] **Step 1: Tambah flag mengikuti pola Mod 1**

Deklarasi + Print + AddDefaultOption persis pola `max_triangulation_angle` (`option_manager.cc:1014-1015`). Default `false` (perilaku upstream tidak berubah).

- [ ] **Step 2: Cabang di `Run()`**

Bila `options_.single_pass`: photometric loop seperti :184-197 tetapi `photometric_options.filter = true`; lewati loop kedua (:199-204). Komentar satu baris: kenapa (hemat ~50% waktu depth).

- [ ] **Step 3: Build**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<repo>/build-mx150.ps1"`
Expected: exit 0, `colmap/build-mx150/src/colmap/exe/colmap.exe` baru. Style: samakan sekitarnya (c++.sh bila tersedia).

- [ ] **Step 4: Ablasi full-117**

Run: `run-ablate.ps1 -Label singlepass -ExtraArgs '--PatchMatchStereo.single_pass 1'` (+ fusion `--input_type photometric` — didukung `exe/mvs.cc:313`).
Expected: waktu depth ≈ setengah baseline; titik + screenshot viewpoint vs base. Lolos bila waktu turun tanpa lubang baru; bila densitas runtuh → REVERT + catat, lanjut Task 2 di atas baseline dua-pass.

- [ ] **Step 5: Determinisme + commit**

Run ulang label sama sekali lagi; `Get-FileHash` kedua `fused.ply` harus identik. Commit di repo colmap (`git add src/colmap/mvs/patch_match* src/colmap/controllers/option_manager.cc`, pesan `mvs: single photometric pass option`) atau backup `.orig` bila tanpa git.

### Task 2 (Mod 4): Coarse-to-fine dengan seed existing-path

**Files:**
- Modify: `colmap/src/colmap/mvs/depth_map.h/.cc` (+`void UpsampleNearest(size_t w, size_t h);` — nearest agar depth valid/tidak-valid tidak tercampur; `Rescale` existing hanya downsample via `DownsampleImage`), `colmap/src/colmap/mvs/normal_map.h/.cc` (+fungsi sepadan; Step 1 periksa API-nya), `colmap/src/colmap/mvs/patch_match_options.h/.cc` (+`int pyramid_levels = 0;`), `colmap/src/colmap/controllers/option_manager.cc`, `colmap/src/colmap/mvs/patch_match.cc` (`Run()`).

**Interfaces:**
- Consumes: Task 1 (`single_pass` dipakai untuk pass coarse maupun fine bila aktif); seeding `InitWorkspaceMemory` (`patch_match_cuda.cu:1825-1833,1859-1867`) — TIDAK DIUBAH, hanya diberi makan.
- Produces: `--PatchMatchStereo.pyramid_levels` (0 = mati; 1 = coarse `max_image_size/2` → upsample host → fine geom pass).

- [ ] **Step 1: Periksa API NormalMap + Mat read/write**

Baca `normal_map.h`, `mat.h` (`Read`/`Write`), konfirmasi `DepthMap::Write` path dipakai `ProcessProblem` (:538). Catat signature persis untuk Step 3.

- [ ] **Step 1b (RED): Tulis call-site dulu, saksikan build gagal**

Tambahkan pemakaian `UpsampleNearest` di `Run()` + field `pyramid_levels` di options SEBELUM implementasinya, lalu build.
Expected: GAGAL (undeclared identifier). Catat error persis. Baru lanjut Step 2.

- [ ] **Step 2: Implementasi `UpsampleNearest` (+ padanan NormalMap)**

Nearest-neighbor murni, preservasi 0 = invalid. Tanpa dependensi baru.

- [ ] **Step 3: Orkestrasi piramid di `Run()`**

Bila `pyramid_levels >= 1`: fase A = loop photometric dengan `max_image_size/2` (tulis photometric `.bin` coarse); lalu per problem baca coarse `.bin` → `UpsampleNearest` ke ukuran fine → tulis ulang path sama; fase B = loop geometrik penuh (seed lewat path existing). THROW_CHECK dimensi fine vs bitmap sebelum fase B. Komentar: alur + kenapa nearest.

- [ ] **Step 4: Build** (perintah Task 1 Step 3). Expected: exit 0.

- [ ] **Step 5: Ablasi `pyramid_levels 1` full-117 + determinisme + commit**

Expected: waktu total < baseline dua-pass; titik ≥ baseline; screenshot viewpoint tanpa lubang baru; double-run hash identik. Gagal → revert Task 2 saja (Task 1 tetap).

### Task 3: View floor + ablasi sudut (tanpa per-piksel kernel)

**Files:**
- Modify: `colmap/src/colmap/mvs/patch_match.cc` (`ReadProblems` cabang `__auto__`, :312-361) — floor: tiap view pertahankan ≥2 tetangga terlemah menurut shared-points walau lolos sudut; hitung + LOG jumlah view yang kena floor.
- Modify: harness saja untuk ablasi (tanpa kode): `max_triangulation_angle` 15 vs 65.

**Interfaces:**
- Consumes: Mod 1 Mod1 filter (:340-342), clamp `filter_min_num_consistent` (:466-468).
- Produces: tidak ada flag baru (floor selalu aktif — perilaku upstream berubah hanya pada kasus yang dulu gugur total).

- [ ] **Step 0 (RED): Reproduksi gugur di biner lama**

Run `run-ablate.ps1 -Label tri15-red -ExtraArgs '--PatchMatchStereo.max_triangulation_angle 15'` (biner SEKARANG, tanpa floor).
Expected: log memuat `Ignoring reference image` (view gugur total) — ini bug yang harus dibalik. Catat jumlahnya.

- [ ] **Step 1: Implementasi floor + LOG**

Edit minimal di :336-361. Satu baris komentar: floor anti-lubang strip.

- [ ] **Step 2: Build** (perintah Task 1 Step 3). Expected: exit 0.

- [ ] **Step 3: Ablasi 15° vs 65° @700px + hitung gugur**

Dua run `run-ablate.ps1 -Label tri15/tri65`. Bandingkan titik, waktu, jumlah "Ignoring reference image" di log, screenshot viewpoint tepi strip. Putuskan nilai default (§keputusan di bawah) dari angka, bukan tebakan. Per-piksel ≤4 ala OpenMVS eksplisit DITUNDA (butuh ubah kernel dalam — di luar scope plan ini).

- [ ] **Step 4: Determinisme + commit.**

### Task 4: Confidence floor + bobot prior fusion (CPU saja)

**Files:**
- Modify: `colmap/src/colmap/mvs/patch_match_cuda.cu` (filter sweep-terakhir, :1209-1276 — baca dulu regionnya) + opsi baru `filter_min_confidence` (default 0 = mati); `colmap/src/colmap/mvs/fusion.h/.cc` (+`fuse_prior_weight`, default 0 = mati) + registrasi di `option_manager.cc` (cari `AddStereoFusionOptions`, pola sama).

**Interfaces:**
- Consumes: `sel_prob_map_` (skor [0,1] existing) sebagai confidence; `StereoFusion::Fuse` traversal (`fusion.cc:369-559` — baca sebelum implementasi).
- Produces: titik fotometrik lemah-tapi-konsisten lolos via lantai (bukan tolak-biner); dukungan virtual fraksional untuk permukaan koheren miskin view.

- [ ] **Step 0 (RED): Flag ditolak + angka baseline sebagai rekor gagal**

CLI `filter_min_confidence` / `fuse_prior_weight` di biner lama → exit ≠ 0. Angka `tri65`/baseline (titik + area datar berlubang di screenshot) = rekor perilaku buruk yang harus dibalik. Catat keduanya.

- [ ] **Step 1: Baca region filter + Fuse, catat invariannya**

Tulis di log task: kondisi tolak persis + di mana titik gugur. Tanpa ini dilarang lanjut (anti false-positive).

- [ ] **Step 2: Implementasi minimal di balik default-mati**

Satu opsi per sisi (depth + fusion), masing-masing ≤20 baris inti + komentar. Dilarang ubah threshold existing.

- [ ] **Step 3: Build.** Expected: exit 0.

- [ ] **Step 4: Ablasi bertahap (satu opsi sekali) + oracle viewpoint**

Mulai `filter_min_confidence` kecil; hanya bila titik naik tanpa noise → coba `fuse_prior_weight`. Tiap kenaikan noise visual di atap/vegetasi = revert opsi itu. Screenshot wajib.

- [ ] **Step 5: Determinisme + commit.**

### Task 5: Overlap I/O-komputasi (ukur dulu, SKIP bila <5%)

**Files:** Kemungkinan `patch_match.cc` (`workspace_mutex_` :472, `thread_pool_` :177) — hanya bila Step 1 membuktikan idle ≥5%.

- [ ] **Step 1: Kuantifikasi idle dari log TANPA kode**

Dari `log_patch_base.txt`: selisih timestamp "Reading inputs..."→sweep pertama vs total per view × 117. Idle <5% dari 20,3 mnt → SKIP task (catat keputusan + angka), selesai.

- [ ] **Step 2 (bila lanjut): overlap + fallback sekuensial**

Prefetch input view-berikut di `io_thread_pool_` selagi sweep berjalan; VRAM budget check sebelum tambah worker; 0 OOM full-117; double-run bit-identik. (Detail implementasi diserahkan pelaksana — region kecil, pola existing.)

- [ ] **Step 3: Build + ablasi + commit.**

### Task 6: Ablasi `window_step=2` (nol kode)

- [ ] **Step 1: Run `run-ablate.ps1 -Label ws2 -ExtraArgs '--PatchMatchStereo.window_step 2'`** (didukung `Check()`, `patch_match_options.cc:83`).

Expected: waktu sweep ≈ ¼; nilai NCC vs `ws1` dari titik + screenshot. Menang → jadikan default harness; kalah → catat dan buang.

### Task 7: Validasi Secondary + laporan (prasyarat: SfM Secondary)

- [ ] **Step 1: Pastikan `sparse` Secondary 51 foto ada** (fase openmvs-t2; bila belum → STOP, catat sebagai blocker, bukan failure plan ini).
- [ ] **Step 2: Run konfigurasi pemenang full Secondary**, catat waktu/titik/VRAM + screenshot viewpoint.
- [ ] **Step 3: Tabel akhir Primary vs OpenMVS + keputusan default tiap flag** → `MODS.md` + revisi plan goal.
