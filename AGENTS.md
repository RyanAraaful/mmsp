# Colmap-Kernel — wajib dibaca agen tiap sesi

Sumber kebenaran: `MODS.md` (rencana, keputusan, metrik) + `drone-mx150.ini`
(config aktif). Baca `MODS.md` di awal sesi dan selalu baca ulang setelah
compaction/ringkasan konteks — chat boleh hilang, file ini tidak.

- Scope: MVS dense SAJA (`src/colmap/mvs/` + registrasi flag). Jangan sentuh
  sparse, mesh, texture, GUI.
- Target: MX150 2GB sm_61; primer Lewoleba-15AGUSTUS (117 foto), pembanding
  Midai 14-Agustus-2025 (51 foto) + subset strip ±30 foto untuk iterasi.
- Lisensi: tanpa GPL/AGPL/non-komersial (seksi lisensi di `MODS.md`).
  SiftGPU tidak pernah dieksekusi; SfM selalu CPU SIFT (`use_gpu 0`).
- Ukuran keberhasilan: titik/menit ≥ OpenMVS dengan lubang ≤ OpenMVS,
  di kedua site. Klaim hanya dari angka benchmark, bukan tebakan.
- Jangan rebuild saat binary dipakai run (Windows lock). Jangan ubah
  ekstraktor di tengah baseline (merusak komparabilitas).
