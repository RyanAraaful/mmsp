# SfM-GPU Native Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native CUDA SIFT extractor + matcher (Apache-2.0, zero new dependencies) behind a default-off flag, each stage proven by build + 3-foto smoke + timing vs CPU VLFeat.

**Architecture:** New `NativeGpuSiftExtractor : FeatureExtractor` in `feature/sift_gpu_native.h/.cu`, branched from `CreateSiftFeatureExtractor` on a new `use_gpu_native` flag (existing `use_gpu` path stays purged/nullptr). GPU matcher as second class in the same `.cu`, branched from `CreateSiftFeatureMatcher`. Drone-first scope: upright nadir stills, fixed octave budget, CPU fallback on any CUDA failure.

**Tech Stack:** C++17 + CUDA sm_61, existing `feature/` classes, PowerShell `.ps1` harness.

**Spec:** `MODS.md` §Rencana profiling GPU + SfM-GPU native + goal decisions rev 10 (PopSIFT rejected, extract+match, OpenSfM duel in Part B plan).

## Global Constraints

- Scope kode: `colmap/src/colmap/feature/` + `controllers/option_manager.cc` saja.
- Tanpa GPL/AGPL/non-komersial; tanpa dependensi baru (FetchContent dilarang di plan ini).
- Target MX150 2GB sm_61; OOM = fallback CPU + log, bukan crash.
- Default semua flag baru mati = perilaku upstream/CPU tidak berubah.
- Jangan rebuild saat biner dipakai run (Windows lock); klaim hanya dari angka.
- TDD adaptasi repo: RED = CLI tolak flag baru (exit ≠ 0) atau build GAGAL setelah call-site ditulis duluan; GREEN = build exit 0 + smoke angka.

## Review Focus

- Foto 4000x3000 melebihi VRAM 2GB → fallback CPU + log (diuji Task 2, foto full-res Secondary).
- Foto gelap/under-exposed → jumlah fitur tidak nol-crash, laporkan 0 fitur + lanjut (diuji Task 2).
- Determinisme ekstraksi GPU run-to-run → fitur/foto dalam ±1% (diuji Task 2/4).
- Deskriptor GPU tak cocok dengan matcher CPU (skala/norm beda) → smoke ukur inlier-ratio match, bukan cuma hitung fitur (diuji Task 4).
- `use_gpu=true` lama tetap nullptr (purge SiftGPU utuh) → tidak ada regresi jalur purged (diuji Task 1).

---

### Task 1: Flag + factory wiring (tanpa algoritma)

**Files:**
- Modify: `colmap/src/colmap/feature/sift.h` (+`bool use_gpu_native = false;` di `SiftExtractionOptions`, +decl factory), `colmap/src/colmap/feature/sift.cc` (+Print/Check + cabang factory → throw `not implemented`), `colmap/src/colmap/controllers/option_manager.cc` (+`AddDefaultOption("SiftExtraction.use_gpu_native", ...)` dan `"SiftMatching.use_gpu_native"` pola `max_triangulation_angle`), `colmap/src/colmap/feature/CMakeLists.txt` (daftar `sift_gpu_native.cu` bila `CUDA_ENABLED`).
- Create: `colmap/src/colmap/feature/sift_gpu_native.h` (decl `NativeGpuSiftExtractor : public FeatureExtractor`, ctor `(const SiftExtractionOptions&)`, `Extract` → `LOG(FATAL) not implemented`), `colmap/src/colmap/feature/sift_gpu_native.cu` (stub).
- Test: `scripts/measure/smoke-sift-gpu.ps1` (3 foto Secondary, `--SiftExtraction.use_gpu_native 1`, catat exit + fitur/foto + wall).

**Interfaces:**
- Consumes: `FeatureExtractor::Extract(const Bitmap&, FeatureKeypoints*, FeatureDescriptors*)` (`feature/extractor.h:100-105`), `SiftExtractionOptions::Check()` (`feature/sift.cc:71+`).
- Produces: `--SiftExtraction.use_gpu_native`, `--SiftMatching.use_gpu_native` (bool, default false); `CreateNativeGpuSiftExtractor(const SiftExtractionOptions&) -> std::unique_ptr<FeatureExtractor>`.

- [ ] **Step 1 (RED): flag ditolak biner lama**

Run: `colmap.exe feature_extractor --SiftExtraction.use_gpu_native 1` (biner sekarang).
Expected: exit ≠ 0, pesan flag tak dikenal. Catat pesan persis.

- [ ] **Step 2: tambah flag + cabang factory stub**

Decl + Check (tolak kombinasi `use_gpu_native && estimate_affine_shape` dengan pesan) + AddDefaultOption + cabang factory ke stub. Komentar satu baris per cabang.

- [ ] **Step 3: build**

Run: `scripts/setup/build-mx150.ps1`.
Expected: exit 0, `colmap.exe` baru.

- [ ] **Step 4: GREEN smoke (gagal dengan benar)**

Run: `scripts/measure/smoke-sift-gpu.ps1`.
Expected: exit ≠ 0 dengan `not implemented`, 0 artefak tertulis. `use_gpu=true` lama tetap nullptr (cek `sift_test.cc:194` tak tersentuh; TESTS_ENABLED=OFF = skip beralasan, catat).

- [ ] **Step 5: commit**

`git add colmap/src/colmap/feature/sift_gpu_native.* colmap/src/colmap/feature/sift.* colmap/src/colmap/controllers/option_manager.cc colmap/src/colmap/feature/CMakeLists.txt scripts/measure/smoke-sift-gpu.ps1`, pesan `feature: native GPU SIFT flag + factory stub (default-off)`.

### Task 2: CUDA octave + DoG + extrema (deteksi, tanpa orientasi/deskriptor)

**Files:**
- Modify: `colmap/src/colmap/feature/sift_gpu_native.cu` (kernel oktav/downsample, DoG, extrema + respons; fallback CPU bila alokasi gagal), `.h` (param internal, tanpa ubah interface Task 1).
- Test: `smoke-sift-gpu.ps1` Step 4 (mode `--deteksi-saja`, bandingkan hitung keypoint vs VLFeat CPU per 3 foto, toleransi ±15%).

**Interfaces:**
- Consumes: `Bitmap` grayscale float 0..1 (konversi host-side sekali, pola `sift.cc` CPU path).
- Produces: `FeatureKeypoints` (x, y, skala) — orientasi/deskriptor diisi Task 3; `Extract` tetap FATAL sampai Task 3 selesai (cabang internal, bukan interface baru).

- [ ] **Step 1 (RED): smoke deteksi-saja gagal**

Run smoke mode baru di biner Task 1.
Expected: FATAL `not implemented`.

- [ ] **Step 2: implementasi kernel minimal**

Oktav fixed `first_octave=-1, num_octaves=4` (ikut options), DoG 3 level/oktav, extrema 26-neighbor + `peak_threshold`, `edge_threshold`abschluss via Hessian trace/det (rumus Lowe, komentar satu baris). Satu stream CUDA, `cudaMalloc` sekali per `Extract`, `cudaFree` di akhir; gagal alokasi → LOG(WARNING) + return false (caller fallback CPU di Task 4, bukan di sini).

- [ ] **Step 3: build.** Expected: exit 0.

- [ ] **Step 4: ablasi 3 foto**

Run smoke. Lolos bila keypoint/foto dalam ±15% VLFeat CPU + wall tercatat (belum dituntut menang). Foto full-res 4000x3000: lolos bila keluar angka ATAU fallback-log bersih (Review Focus 1).

- [ ] **Step 5: commit.** Pesan `feature: native GPU SIFT detection (octave+DoG+extrema)`.

### Task 3: Orientasi + deskriptor 128D (format cocok CPU)

**Files:**
- Modify: `colmap/src/colmap/feature/sift_gpu_native.cu` (+histogram orientasi 36-bin + `max_num_orientations`, deskriptor 4x4x8 + normalisasi L1_ROOT persis `sift.h:92-98`, kuantisasi uint8 0..255).
- Test: `smoke-sift-gpu.ps1` Step 4 (mode penuh: `Extract` hidup, tulis database 3 foto).

**Interfaces:**
- Consumes: keypoint Task 2.
- Produces: `FeatureDescriptors` uint8 128D L1_ROOT — byte-kompatibel dengan matcher CPU (inlier-ratio Task 4 membuktikan).

- [ ] **Step 1 (RED): deskriptor kosong**

Run smoke penuh di biner Task 2.
Expected: 0 deskriptor / FATAL.

- [ ] **Step 2: implementasi**

Satu kernel orientasi + satu kernel deskriptor; sigma/orientasi konvensi VLFeat (komentar konversi bila beda). Tanpa affine/DSP (ditolak `Check` Task 1).

- [ ] **Step 3: build.** Expected: exit 0.

- [ ] **Step 4: smoke penuh + determinisme**

Run 2x. Lolos bila fitur/foto ±1% antar-run + format database valid (`colmap database_reader` baca tanpa error).

- [ ] **Step 5: commit.** Pesan `feature: native GPU SIFT orientation + 128D descriptors`.

### Task 4: GPU matcher + fallback CPU + duel Secondary-51

**Files:**
- Modify: `colmap/src/colmap/feature/sift_gpu_native.cu` (+`NativeGpuSiftMatcher : FeatureMatcher`, brute-force L2 di GPU, ratio-test + cross-check di host persis default `SiftMatchingOptions`), `sift.cc` (cabang `CreateSiftFeatureMatcher` bila `use_gpu_native`), `smoke-sift-gpu.ps1` (+duel Secondary 51: extract wall/foto, match wall/pasangan, inlier-ratio).
- Test: duel Secondary 51 foto GPU vs CPU (tabel: wall, fitur/foto, pasangan, inlier-ratio, reg rate via mapper DENSE_SCHUR bawaan biner).

**Interfaces:**
- Consumes: `FeatureMatcher::Match` (signature di `feature/matcher.h` — baca sebelum implementasi, catat di log task), `SiftMatchingOptions` (`sift.h:112+`).
- Produces: vonis MENANG/KALAH vs CPU + angka duel (masuk MODS.md + laporan, bukan kode).

- [ ] **Step 1 (RED): matcher flag ditolak / nullptr**

Run match GPU di biner Task 3.
Expected: fallback CPU atau error tercatat (bukan segfault).

- [ ] **Step 2: implementasi matcher**

Matriks L2 per-pasangan di GPU (tiling bila deskriptor > VRAM, fallback CPU + log), ratio `max_ratio` + cross-check di host. Multicore: batch async multi-image via 2 stream (alasan: overlap H2D/compute).

- [ ] **Step 3: build.** Expected: exit 0.

- [ ] **Step 4: duel Secondary 51**

Run duel. Lolos bila extract+match wall < CPU DAN inlier-ratio ≥ CPU −5% DAN reg rate ≥ CPU (52 foto acuan: 50–51/51). SGEMM microbench DICORET (tak ada SGEMM di jalur SIFT; timing per-stage = wall extract/match). Gagal → revert Task 4 saja (Tasks 1–3 tetap).

- [ ] **Step 5: commit + catat MODS.md.** Pesan `feature: native GPU SIFT matcher + Secondary duel`.
