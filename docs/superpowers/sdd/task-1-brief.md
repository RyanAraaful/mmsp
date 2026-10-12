# Brief Task 1 (Mod 1) — Single photometric pass

(Sumber: plan `docs/superpowers/plans/2026-10-11-mvs-speed-density.md`, Task 1 verbatim + adaptasi SDD di bawah.)

**Files:**
- Modify: `colmap/src/colmap/mvs/patch_match_options.h` (+`bool single_pass = false;`), `colmap/src/colmap/mvs/patch_match_options.cc` (+PrintOption, tanpa Check baru), `colmap/src/colmap/controllers/option_manager.cc` (+`AddDefaultOption("PatchMatchStereo.single_pass", &patch_match_stereo->single_pass);` setelah baris 1020), `colmap/src/colmap/mvs/patch_match.cc` (`PatchMatchController::Run()`, :170-207).
- Harness: tambah 1 baris/param override fusion `--input_type` di `run-ablate.ps1` (RED menuntut; default tetap `geometric`).

**Interfaces:**
- Consumes: `PatchMatchOptions::geom_consistency/filter` semantics (`patch_match.cc:183-197`).
- Produces: `--PatchMatchStereo.single_pass` (true = satu loop `geom_consistency=false, filter=true`, tulis `photometric` maps; loop geometrik dilewati).

- [ ] **Step 0 (RED): Buktikan flag belum ada**

Run (biner lama): `colmap.exe patch_match_stereo --PatchMatchStereo.single_pass 1`
Expected: exit ≠ 0 dengan pesan flag tak dikenal. Catat pesan persis di log task. Dilarang lanjut sebelum ini tercatat.

- [ ] **Step 1: Tambah flag mengikuti pola Mod 1**

Deklarasi + Print + AddDefaultOption persis pola `max_triangulation_angle` (`option_manager.cc:1014-1015`). Default `false` (perilaku upstream tidak berubah).

- [ ] **Step 2: Cabang di `Run()`**

Bila `options_.single_pass`: photometric loop seperti :184-197 tetapi `photometric_options.filter = true`; lewati loop kedua (:199-204). Komentar satu baris: kenapa (hemat ~50% waktu depth).

- [ ] **Step 3: Build**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:/dev/Colmap-Kernel/build-mx150.ps1"`
Expected: exit 0, `colmap/build-mx150/src/colmap/exe/colmap.exe` baru. Style: samakan sekitarnya (c++.sh bila tersedia).

- [ ] **Step 4: Ablasi full-117**

Run: `run-ablate.ps1 -Label singlepass -ExtraArgs '--PatchMatchStereo.single_pass 1'` (+ fusion `--input_type photometric` — didukung `exe/mvs.cc:313`).
Expected: waktu depth ≈ setengah baseline; titik + screenshot viewpoint vs base. Lolos bila waktu turun tanpa lubang baru; bila densitas runtuh → REVERT + catat, lanjut Task 2 di atas baseline dua-pass.

- [ ] **Step 5: Determinisme + selesai (TANPA commit — lihat adaptasi)**

Run ulang label sama sekali lagi; jumlah titik kedua run dalam ±0,1% (bit-identik TIDAK dituntut — fusion upstream order-nondeterministik, bukti: 819.227 vs 819.366 dari input sama).

## Adaptasi SDD untuk task ini (mengikat)

- Aturan kerja pemilik: (1) TDD — Step 0 RED dulu, kode dihapus-diulangi bila ditulis sebelum RED; (2) ponytail — diff minimal, komentar why satu baris, tanpa file/opsi baru di luar brief; (3) context7 — hanya bila menyentuh API eksternal (tidak diperkirakan).
- PRASYARAT ABLASI (harness gap dari Task 0): `ProcessProblem` skip-if-exists (`patch_match.cc:418-422`) — SEBELUM run, PINDAHKAN `dense700/stereo/depth_maps/*.bin` + `dense700/stereo/normal_maps/*.bin` ke direktori backup (JANGAN hapus; reproducible ±21 mnt). Tanpa ini run batal (terbukti: dry-run base depth 0,66 dtk, 117/117 skip).
- JANGAN commit (lihat ledger). JANGAN dispatch subagent. JANGAN rebuild saat run aktif (1 GPU, Windows lock) — build dan run strictly sequential.
- Viewpoint oracle: cek `python3 -c "import numpy, matplotlib"` dulu; bila ada, render okupansi top-down+oblik `fused_singlepass.ply` vs `fused_base.ply` (+ `scene_dense.ply` bila murah); bila tidak ada, catat skip + alasan (keputusan tool di tangan controller).
- Run ±11 mnt (single pass) melebihi jendela tanpa pengawasan. ATURAN: PINDAHKAN maps ke backup, luncurkan run via background shell, catat shell ID di report, lalu kembalikan NEEDS_CONTEXT dengan shell ID + kriteria lolos; controller verifikasi saat notifikasi tiba. JANGAN tinggalkan run tanpa jejak.
- Report: tulis LENGKAP ke `E:/dev/Colmap-Kernel/docs/superpowers/sdd/task-1-report.md`, balas SINGKAT (<15 baris): Status + angka (waktu depth, titik, VRAM peak, delta vs baseline, hasil determinisme) + path report.
