# Brief Task 4 — Confidence floor + bobot prior fusion (CPU saja)

(Sumber: plan `docs/superpowers/plans/2026-10-11-mvs-speed-density.md`, Task 4 verbatim + adaptasi SDD di bawah.)

**Files:**
- Modify: `colmap/src/colmap/mvs/patch_match_cuda.cu` (filter sweep-terakhir, :1209-1276 — baca dulu regionnya) + opsi baru `filter_min_confidence` (default 0 = mati); `colmap/src/colmap/mvs/fusion.h/.cc` (+`fuse_prior_weight`, default 0 = mati) + registrasi di `option_manager.cc` (temukan blok opsi StereoFusion — bila namanya bukan `AddStereoFusionOptions`, ikuti pola `AddPatchMatchStereoOptions`, catat nama aktual di report).

**Interfaces:**
- Consumes: `sel_prob_map_` (skor [0,1] existing) sebagai confidence; `StereoFusion::Fuse` traversal (`fusion.cc:369-559` — baca sebelum implementasi).
- Produces: titik fotometrik lemah-tapi-konsisten lolos via lantai (bukan tolak-biner); dukungan virtual fraksional untuk permukaan koheren miskin view.

- [ ] **Step 0 (RED): Flag ditolak + angka baseline sebagai rekor gagal**

CLI `filter_min_confidence` / `fuse_prior_weight` di biner lama → exit ≠ 0 (catat pesan). Angka baseline (819.366; area datar berlubang) = rekor perilaku buruk yang harus dibalik.

- [ ] **Step 1: Baca region filter + Fuse, catat invariannya**

Tulis di report: kondisi tolak persis + di mana titik gugur. Tanpa ini dilarang lanjut (anti false-positive).

- [ ] **Step 2: Implementasi minimal di balik default-mati**

Satu opsi per sisi (depth + fusion), masing-masing ≤20 baris inti + komentar. Dilarang ubah threshold existing.

- [ ] **Step 3: Build** (`build-mx150.ps1`, pastikan tanpa proses colmap). Expected: exit 0.

- [ ] **Step 4: Selesai tanpa run (controller yang run)**

JANGAN luncurkan ablasi. Serahkan perintah run-ablate siap + kriteria (satu opsi sekali; mulai confidence kecil; noise visual = revert opsi itu).

- [ ] **Step 5: Selesai tanpa commit (ledger).**

## Adaptasi SDD untuk task ini (mengikat)

- Aturan kerja pemilik: (1) TDD — RED dulu; (2) ponytail — diff minimal; (3) context7 — hanya API eksternal.
- JANGAN commit. JANGAN dispatch subagent. JANGAN rebuild saat run aktif (cek proses dulu — ablasi tri15/tri65 mungkin masih jalan; bila ragu, tanya controller via NEEDS_CONTEXT).
- Determinisme operasional ±0,1%. Viewpoint oracle SKIP (tanpa renderer).
- Report: `E:/dev/Colmap-Kernel/docs/superpowers/sdd/task-4-report.md`, balas SINGKAT (<15 baris): Status + RED/BUILD evidence + perintah run siap + path report.
