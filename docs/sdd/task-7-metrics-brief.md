# Brief Task 7a — Skrip metrik numerik (okupansi + outlier + cloud-to-cloud)

(Sumber: keputusan pemilik 2026-10-12 — gate numerik per mod + oracle laporan.)

**Files:**
- Create: `<repo>/metrics.cpp` (single file, C++17, tanpa dependensi baru — hanya STL), compile via `cl.exe` MSVC BuildTools (pola env `vcvars64` di `build-mx150.ps1:3-7`).
- Read-only: `<primary-dataset>/dense700/fused_ws2.ply` (2,9jt titik, hasil kita) dan `<primary-dataset>/openmvs/scene_dense.ply` (4,5jt titik, acuan).

**Interfaces:** CLI: `metrics.exe <plyA> <plyB>` → stdout angka + exit 0. JANGAN commit. JANGAN ganggu proses `colmap` yang mungkin jalan (GPU milik run lain).

- [ ] **Step 1: Inspeksi header PLY kedua file** (ascii header: format binary_little_endian + daftar properti). Catat layout persis (x y z nx ny nz r g b?) + tipe. Dilarang menebak layout — baca byte header dulu.
- [ ] **Step 2 (RED): program belum ada** — catat bahwa metrik belum terukur (angka target di bawah = rekor yang harus diisi). Lanjut implementasi.
- [ ] **Step 3: Implementasi minimal:**
  - Okupansi: bbox union kedua cloud, sel 0,5 m; laporkan sel terisi A, B, hanya-A, hanya-B (proksi lubang), fill-rate.
  - Outlier-ratio: sampel 50rb titik/cloud (stride tetap, seed tetap), voxel-hash, jarak NN ke-8; outlier = > median + 3*MAD; laporkan rasio per cloud.
  - Cloud-to-cloud dua arah: sampel 50rb dari A ke B dan sebaliknya (voxel 0,25 m, 27 sel); laporkan mean/median/p90 tiap arah.
- [ ] **Step 4: Compile + run pasangan Primary** (biner di `<repo>/metrics.exe`). Expected: angka keempat metrik tercetak < 5 mnt CPU.
- [ ] **Step 5: Report** ke `<repo>/docs/sdd/task-7-metrics-report.md` (angka + definisi + asumsi "OpenMVS ≈ acuan"), balas SINGKAT (<15 baris).

## Adaptasi SDD (mengikat)

- TDD: definisi metrik di atas = spesifikasi; RED = angka belum ada. Ponytail: satu file, tanpa lib baru; sampling secukupnya agar run < 5 mnt. context7: tidak perlu (STL + format PLY dari header).
- JANGAN commit. JANGAN dispatch subagent. JANGAN sentuh/lock file yang sedang ditulis run lain (baca saja; bila ragu NEEDS_CONTEXT).
