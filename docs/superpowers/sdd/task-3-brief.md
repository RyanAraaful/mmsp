# Brief Task 3 — View floor + ablasi sudut (tanpa per-piksel kernel)

(Sumber: plan `docs/superpowers/plans/2026-10-11-mvs-speed-density.md`, Task 3 verbatim + adaptasi SDD di bawah.)

**Files:**
- Modify: `colmap/src/colmap/mvs/patch_match.cc` (`ReadProblems` cabang `__auto__`, :336-361) — floor: tiap view pertahankan ≥2 tetangga terlemah menurut shared-points walau lolos sudut; hitung + LOG jumlah view yang kena floor.
- Harness: ablasi 15° vs 65° (tanpa kode).

**Interfaces:**
- Consumes: filter Mod1 (:340-342), clamp `filter_min_num_consistent` (:466-468).
- Produces: tidak ada flag baru (floor selalu aktif — perilaku upstream berubah hanya pada kasus yang dulu gugur total).

- [ ] **Step 0 (RED): Reproduksi gugur di biner lama**

(NOTE controller: biner saat ini SUDAH berisi floor bila task ini selesai — RED ini untukmu sebelum implementasi, memakai biner sekarang yang belum punya floor.) Runlapangan kecil? TIDAK — RED = tunjukkan di kode bahwa `src_images` kosong → problem dibuang (:369-376) + bukti historis 9 view gugur @1400px/15° (MODS.md). Bila ragu, tanya controller. Dilarang lanjut tanpa RED tercatat.

- [ ] **Step 1: Implementasi floor + LOG**

Edit minimal di :336-361: setelah filter sudut, bila `src_images.size() < 2` dan ada kandidat overlap (sebelum filter), tambahkan yang terlemah sampai 2 (abaikan batas sudut, tetap hormati min bawah? — putuskan minimal: ambil top shared-points tanpa filter atas; catat pilihan di report). LOG (INFO, satu baris per run): jumlah view kena floor. Satu baris komentar why: floor anti-lubang strip.

- [ ] **Step 2: Build** (`build-mx150.ps1`). Expected: exit 0. Sebelum build pastikan tidak ada proses `colmap` (GPU lock).

- [ ] **Step 3: Selesai tanpa run (controller yang run)**

JANGAN luncurkan ablasi. Serahkan: konfirmasi tidak ada flag baru + perintah run-ablate untuk `tri15`/`tri65` bila diperlukan (controller yang putuskan/jalankan). Per-piksel ≤4 ala OpenMVS eksplisit DITUNDA.

- [ ] **Step 4: Selesai tanpa commit (ledger).**

## Adaptasi SDD untuk task ini (mengikat)

- Aturan kerja pemilik: (1) TDD — RED dulu; (2) ponytail — diff minimal; (3) context7 — hanya API eksternal.
- JANGAN commit. JANGAN dispatch subagent. JANGAN rebuild saat run aktif.
- Determinisme operasional ±0,1% (tidak dituntut bit-identik). Viewpoint oracle SKIP (tanpa renderer).
- Report: `E:/dev/Colmap-Kernel/docs/superpowers/sdd/task-3-report.md`, balas SINGKAT (<15 baris): Status + RED/BUILD evidence + path report.
