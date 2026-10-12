# Task 0 Report — Harness freeze + baseline pin

## Status: NEEDS_CONTEXT (harness frozen + verified statically; 21-min dry-run NOT launched)

## 1. Yang dibuat

**`<repo>/run-ablate.ps1`** (baru, 51 baris, satu-satunya file baru).
Parameter: `-Label <nama>` (wajib), `-ExtraArgs '<flags>'` (opsional, di-splat ke
`patch_match_stereo` tanpa `Invoke-Expression`). Isi meniru `g3-patch700.ps1`:
CUDA env via `<cuda-toolkit>/cuda-env`, sampler `nvidia-smi` 5 dtk → `vram_<label>.csv`,
flags baseline @700px persis, `stereo_fusion` baseline, ekor
`Select-String 'Number of fused points|Elapsed time'` + `Get-FileHash`, plus stopwatch
wall-total. Undistort tidak dijalankan ulang (`dense700/` dipakai ulang).
Per-label: `log_patch_<label>.txt`, `log_fusion_<label>.txt`, `vram_<label>.csv`,
`dense700/fused_<label>.ply` (copy 1 baris; `fused.ply` tetap baseline-compatible).

Dua deviasi mikro dari g3 (disengaja, tercatat):
- Backup `.full` hanya dibuat bila belum ada (g3 menimpanya tiap run — berisiko
  membekukan cfg yang sudah termutasi); replace `__auto__, \d+ → __auto__, 8` idempoten.
- Satu typo saya sendiri (`max_reproi_error` nyasar di baris fusion) ditemukan saat
  verifikasi dan sudah dihapus sebelum selesai.

**Modify: none** (tidak ada file C++ / lain yang diubah).

## 2. Step 1 — repo git colmap + hash

- `git -C <repo>/colmap rev-parse --short HEAD` → **`bd1fcf6`**
 (banner biner `--help` mengonfirmasi `COLMAP 4.2.1 Commit bd1fcf6`).
- `status --short` → dirty oleh **10 file mod goal sebelumnya** (option_manager.cc,
  patch_match.*, bundle_adjustment_ceres.cc, optim/*, cmake/FindDependencies.cmake,
  thirdparty/CMakeLists.txt, vcpkg.json). Tree milik controller; saya tidak menyentuh /
  commit apapun. Catatan: baseline biner `build-mx150/.../colmap.exe` dibangun dari tree
  ini (bukan upstream murni) — dry-run tetap sah sebagai pin harness selama biner tidak
  di-rebuild sebelum Task 1.

## 3. Step 2 — verifikasi harness (bukti, bukan klaim)

- Parse PowerShell (`PSParser::Tokenize`): **0 error**.
- Perbandingan flag-value pair g3 vs run-ablate (setelah normalisasi quote/koma):
  **Compare-Object kosong = 17 flag PatchMatch + 7 flag Fusion + workspace/cfg identik.**
- Biner: `colmap.exe patch_match_stereo --help` exit 0 **hanya bila** `cuda-env\bin`
  di PATH (tanpa itu exit `0xC0000135` DLL-not-found) — harness men-set ini, terbukti perlu.
- `dense700/stereo/patch-match.cfg` sudah `__auto__, 8`; `openmvs/scene_dense.ply` ada
 (277 MB) sebagai pembanding viewpoint.

## 4. Step 3 — dry-run: TIDAK dijalankan (butuh controller)

RED task ini = dry-run menyimpang >5% dari baseline (819.366 pts / 20,90 mnt / ~133 MB).
Run ±21 menit + GPU tunggal (Windows lock, tidak bisa rebuild/paralel) melebihi jendela
aman tanpa pengawasan — sesuai brief, saya tidak meluncurkannya. Perintah persis:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<repo>/run-ablate.ps1" -Label base
```

(dijalankan dari sesi foreground yang ditunggui; tidak bersamaan dengan build.)
Kriteria lolos: `Number of fused points ≈ 819.366 ±5%`, wall ≈ 20,9 mnt ±5%,
puncak `vram_base.csv` ≈ 133 MB. Beda >5% = RED → investigasi sebelum Task 1.

## 5. Temuan / keraguan (concerns)

1. **Viewpoint PNG belum dirender** (`view-nadir-base.png` / `view-oblik-base.png`):
   tidak ada renderer headless di box ini (tanpa build GUI `model_viewer`, tanpa
   CloudCompare/Meshlab CLI). Kandidat perintah dicatat sebagai komentar di skrip
  (baris 45–50). Perlu controller putuskan tool render sebelum Task 1 butuh screenshot.
2. **Task 1 butuh override fusion `--input_type photometric`** (plan Task 1 Step 4)
   yang belum ada di harness (brief Task 0 hanya Label+ExtraArgs untuk patch).
   Sengaja tidak ditambahkan (ponytail: bukan untuk nanti) —executor Task 1 menambah
   1 baris saat RED-nya menuntut.
3. context7 tidak dipakai (tidak ada API eksternal yang disentuh). Tanpa dependensi baru.
