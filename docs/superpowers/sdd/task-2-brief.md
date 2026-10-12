# Brief Task 2 (Mod 4) — Coarse-to-fine dengan seed existing-path

(Sumber: plan `docs/superpowers/plans/2026-10-11-mvs-speed-density.md`, Task 2 verbatim + adaptasi SDD di bawah.)

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

- [ ] **Step 5: Selesai tanpa run (controller yang run)**

JANGAN luncurkan ablasi (notifikasi shell subagent tidak kembali ke controller — pelajaran Task 1). Serahkan: perintah run-ablate persis untuk ablasi `pyramid1` (termasuk prasyarat backup/restore maps yang mana) + kriteria lolos dari plan. Controller meluncurkan + verifikasi.

## Adaptasi SDD untuk task ini (mengikat)

- Aturan kerja pemilik: (1) TDD — Step 1b RED dulu; kode sebelum RED dihapus-diulangi. (2) ponytail — diff minimal, komentar why satu baris, tanpa file/opsi baru di luar brief. (3) context7 — hanya bila menyentuh API eksternal.
- JANGAN commit (ledger). JANGAN dispatch subagent. JANGAN rebuild saat run aktif — tanyakan/cek tidak ada proses `colmap` sebelum build (Windows lock).
- Fase A butuh workspace `max_image_size/2` sementara + restore (lihat ledger, ruling scan): pilih yang minimal, catat pilihan + alasan di report.
- Determinisme operasional = double-run titik ±0,1% (bit-identik TIDAK dituntut).
- Viewpoint oracle: SKIP (tanpa renderer/Python di box) — proxy: titik + 0 view gugur + per-view counts log fusion.
- Report: tulis LENGKAP ke `E:/dev/Colmap-Kernel/docs/superpowers/sdd/task-2-report.md`, balas SINGKAT (<15 baris): Status + RED/BUILD evidence + perintah run siap + path report.
