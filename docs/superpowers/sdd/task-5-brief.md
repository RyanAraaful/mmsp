# Brief Task 5 — Overlap I/O-komputasi (ukur dulu, SKIP bila <5%)

(Sumber: plan `docs/superpowers/plans/2026-10-11-mvs-speed-density.md`, Task 5 verbatim + adaptasi SDD di bawah.)

**Files:** Kemungkinan `colmap/src/colmap/mvs/patch_match.cc` (`workspace_mutex_` :472, `thread_pool_` :177) — hanya bila Step 1 membuktikan idle ≥5%.

- [ ] **Step 1: Kuantifikasi idle dari log TANPA kode (ini deliverable utama bila SKIP)**

Dari `log_patch_tri65.txt` (atau run terbaru): selisih timestamp "Reading inputs..."→sweep pertama ("Iteration 1" / "Sweep 1") per view × 117 vs total depth. Idle <5% dari total depth → SKIP task (tulis angka + keputusan di report, selesai, tanpa kode). Idle ≥5% → lanjut Step 2.

- [ ] **Step 2 (bila lanjut): overlap + fallback sekuensial**

Prefetch input view-berikut di `io_thread_pool_` selagi sweep berjalan; VRAM budget check sebelum tambah worker (puncak terukur ~135MB, budget <1,5GB); 0 OOM full-117; double-run titik ±0,1% (bit-identik TIDAK dituntut). RED dulu: tunjukkan di kode bahwa I/O terkunci mutex global selama compute + ukur idle dari log. Komentar why satu baris.

- [ ] **Step 3: Build + serah run (JANGAN launch run; controller yang run).**

## Adaptasi SDD untuk task ini (mengikat)

- Aturan kerja pemilik: (1) TDD — RED (kode + angka idle) dulu; (2) ponytail — bila ukur <5%, TIDAK ADA KODE adalah jawaban yang benar; (3) context7 — WAJIB bila menyentuh API CUDA (stream/event/pinned memory): resolve + query docs dulu, jangan andalkan ingatan.
- JANGAN commit. JANGAN dispatch subagent. JANGAN rebuild saat run aktif (cek proses colmap dulu; ablasi conf02 mungkin masih jalan — bila ragu NEEDS_CONTEXT).
- Report: `E:/dev/Colmap-Kernel/docs/superpowers/sdd/task-5-report.md`, balas SINGKAT (<15 baris): Status + angka idle + keputusan SKIP/lanjut + path report.
