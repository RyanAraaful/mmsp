# Brief Task 0 — Harness freeze + baseline pin

(Sumber: plan `docs/superpowers/plans/2026-10-11-mvs-speed-density.md`, Task 0 verbatim + adaptasi SDD di bawah.)

**Files:**
- Create: `E:/dev/Colmap-Kernel/run-ablate.ps1`
- Modify: none.

**Interfaces:**
- Consumes: `g3-patch700.ps1` (pola sampler VRAM + CLI flags baseline).
- Produces: `run-ablate.ps1 -Label <nama> [-ExtraArgs <string>]` → menulis `log_patch_<label>.txt`, `log_fusion_<label>.txt`, `vram_<label>.csv`, mencetak titik/waktu/hash; dipakai semua task.

- [ ] **Step 1: Konfirmasi repo git colmap + catat hash**

Run: `git -C E:/dev/Colmap-Kernel/colmap status --short` dan `git -C E:/dev/Colmap-Kernel/colmap rev-parse --short HEAD`
Expected: status bersih (atau hanya file mod kita), HEAD tercetak. Bila bukan repo git → tiap task menyimpan backup `.orig` sebelum edit (catat di log task).

- [ ] **Step 2: Tulis `run-ablate.ps1` (parameter Label + ExtraArgs)**

Isi: tiru `g3-patch700.ps1` (undistort SEKALI di luar skrip — `dense700/` dipakai ulang; sampler `nvidia-smi` 5dtk; `patch_match_stereo` flags baseline @700px + `$ExtraArgs`; `stereo_fusion` flags baseline; ekor: `Select-String 'Number of fused points|Elapsed time'` + `Get-FileHash fused.ply`).
Pin viewpoint: render 1 nadir + 1 oblik `dense700/fused.ply` vs `openmvs/scene_dense.ply` dari kamera sama, simpan PNG sebagai `view-nadir-base.png` / `view-oblik-base.png` (cara render bebas — catat perintahnya di skrip sebagai komentar).

- [ ] **Step 3: Dry-run tanpa kode berubah**

Run: `run-ablate.ps1 -Label base`
Expected: angka ≈ baseline (819.366 pts / 20,90 mnt / VRAM ~133MB). Beda >5% → investigasi sebelum Task 1.

## Adaptasi SDD untuk task ini (mengikat, di luar plan)

- Aturan kerja pemilik (wajib): (1) TDD — tidak ada kode sebelum bukti gagal; untuk task skrip ini RED = dry-run harus mereproduksi angka baseline (bila menyimpang >5% = RED, investigasi, bukan lanjut). (2) Ponytail — satu skrip berparameter, bukan kopi per label; tanpa dependensi/fitur baru. (3) context7 — hanya bila menyentuh API eksternal (tidak diperkirakan di task ini).
- JANGAN commit (tree dirty oleh mod goal sebelumnya; snapshot baseline dipegang controller). JANGAN dispatch subagent apapun.
- Flags baseline @700px persis (dari `g3-patch700.ps1` / MODS.md milestone adil): patch `max_image_size 700, gpu_index 0, window_radius 5, window_step 1, num_samples 10, num_iterations 4, min_tri 1.0, max_tri 65.0, geom_consistency 1, regularizer 0.3, max_cost 3.0, filter 1, filter_min_ncc 0.15, filter_min_tri 3.0, filter_min_num_consistent 2, filter_geom_max_cost 1.0, cache_size 4`, cfg `__auto__ 8`; fusion `max_image_size 700, min_num_pixels 3, max_reproj_error 4.0, max_depth_error 0.05, max_normal_error 20.0, check_num_images 30, cache_size 4`, input `geometric`, output `dense700/fused.ply`.
- Repo rule: skrip via file `.ps1` (jangan inline `$`); CUDA env via `E:/dev/tools/cuda-env`; JANGAN rebuild saat run (1 GPU, Windows lock).
- Report: tulis LENGKAP ke `E:/dev/Colmap-Kernel/docs/superpowers/sdd/task-0-report.md` (isi: yang dibuat, hasil run + angka, file diubah, temuan/keraguan), lalu balas SINGKAT (<15 baris): Status DONE/DONE_WITH_CONCERNS/BLOCKED/NEEDS_CONTEXT + ringkasan angka + path report. Step 3 (±21 mnt) bila melebihi jendela kerjamu: siapkan perintah persisnya, JANGAN biarkan run tanpa kepastian — tanyakan controller dulu via NEEDS_CONTEXT lebih aman.
