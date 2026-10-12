# Task 1 Report — Mod 1: Single photometric pass

Status: **DONE** (semua step lolos; TANPA commit sesuai ledger)

## Step 5 (Determinisme) — PASS

Run ulang label sama (shell `sh_12ba27f6a001r3cC02pHIJ0xC1`, WALL 00:00:43):
depth ter-skip via skip-if-exists (0,017 mnt), fusion jalan ulang di atas maps identik.

| Run | Titik fused | Hash SHA256 `fused_singlepass.ply` |
|---|---|---|
| 1 | 840.899 | `3A521217…09841F` |
| 2 | 840.806 | `4DE34804…8D456B7` |

Selisih 93 titik = **0,011% ≤ ±0,1%** → LOLOS. Hash beda (ekspektasi: fusion
multithread order-nondeterministik, konsisten dengan datum plan 819.227 vs 819.366).

## Step 4 (Ablasi `singlepass`) — PASS (lolos kriteria plan)

Run: `run-ablate.ps1 -Label singlepass -ExtraArgs '--PatchMatchStereo.single_pass 1' -FusionInputType photometric`
(shell `sh_12b98d482001m3rqBVwEjOxGrt`, WALL TOTAL 00:10:20).

| Metrik | Baseline 2-pass | Single-pass | Delta |
|---|---|---|---|
| Waktu depth | ~20,3 mnt (dari 20,9 depth+fusion) | **9,679 mnt** | **−52%** (≈½, sesuai harapan) |
| Waktu fusion | ~0,35 mnt | 0,602 mnt | +0,25 mnt (lebih banyak titik difusi) |
| Titik fused | 819.366 | **840.899** | **+21.533 (+2,6%) — densitas NAIK, tak runtuh** |
| VRAM peak | ~133MB | **139MB** (avg 113) | +6MB, jauh di bawah 1,5GB; 0 OOM |
| Views | 117/117 | 117/117, semua `Writing photometric output` | 0 gugur |

Log memuat per-view `geom_consistency: 0, filter: 1, single_pass: 1` (cabang baru
terbukti aktif); 0× `Ignoring reference image`, 0 ERROR/Failed di patch+fusion log.
Hash run-1 `fused_singlepass.ply` (SHA256): `3A521217…09841F` (penuh di log harness).
Keputusan: **LOLOS** — waktu turun >50% tanpa lubang baru, densitas naik. Tanpa revert.

## Step 0 (RED) — PASS, tercatat

Biner lama (`colmap.exe` pra-build, dijalankan dari dir-nya + `cuda-env/bin` di PATH):

```
./colmap.exe patch_match_stereo --PatchMatchStereo.single_pass 1
EXIT=1
E20261011 22:28:11.241048  3192 base_option_manager.cc:265] Failed to parse options - unrecognised option '--PatchMatchStereo.single_pass'.
```

Catatan jebakan: tanpa `E:\dev\tools\cuda-env\bin` di PATH (atau cwd di luar dir exe),
biner matiUUID 0xC0000135 (STATUS_DLL_NOT_FOUND) tanpa output — bahkan untuk `--help`.
Itu masalah env, bukan flag. RED sah di atas memakai env harness.

## Step 1+2 — Diff (4 file, sesuai brief; prior dirty `max_triangulation_angle` tak tersentuh)

- `colmap/src/colmap/mvs/patch_match_options.h`: `+bool single_pass = false;`
  setelah `filter`, komentar why satu baris.
- `colmap/src/colmap/mvs/patch_match_options.cc`: `+PrintOption(single_pass);`
  setelah `PrintOption(filter)`; tanpa Check baru (sesuai brief).
- `colmap/src/colmap/controllers/option_manager.cc` (+2 baris, setelah blok
  `geom_consistency` ~:1020-1021):
  `AddDefaultOption("PatchMatchStereo.single_pass", &patch_match_stereo->single_pass);`
- `colmap/src/colmap/mvs/patch_match.cc` (`PatchMatchController::Run`):
  guard loop-1 menjadi `if (options_.geom_consistency && !options_.single_pass)`;
  loop-2 memakai salinan `output_options` (bila `single_pass`: `geom_consistency=false,
  filter=true`, tulis maps `photometric`); komentar why satu baris (hemat ~50% waktu depth).
- Harness `run-ablate.ps1`: param baru `[string]$FusionInputType = 'geometric'`
  + fusion `--input_type $FusionInputType` (default tak berubah; RED menuntut override ini).

Default `false` → perilaku upstream tak berubah (single_pass+geom=false identik upstream).

## Step 3 (Build) — PASS

`build-mx150.ps1` → `BUILD_EXIT=0`, `colmap.exe` baru ter-link (13/13 target).
Hanya warning pre-existing (glog/C4244/C4267); nol error.
Verifikasi GREEN parse: `--help` memuat `--PatchMatchStereo.single_pass arg (=0)`;
run dengan flag gagal di `--workspace_path required`, bukan unknown-option.

## Prasyarat ablasi

- Backup: 234 `.bin` depth + 234 `.bin` normal dipindah ke
  `E:/dev/Lewoleba-15agustus/maps_backup_base/{depth_maps,normal_maps}/`
  (stereo/* kosong; restore = pindah balik). Tanpa ini run batal (skip-if-exists).
- Viewpoint oracle: SKIP — tak ada python/numpy/matplotlib (`python3`/`python`
  dua-duanya missing) dan tak ada renderer headless (sesuai catatan Task 0:
  render deferred). Pengganti: jumlah titik + log fusion per-view.
- Baseline pin (dari brief + log 22:25): depth+fusion 20,9 mnt / 819.366 pts /
  VRAM ~133MB. Datum tambahan: re-fusion maps sama → 819.227 pts (bukti
  nondeterminisme order fusion upstream; toleransi ±0,1%).

## Step 4 (Ablasi `singlepass`) — lolos, angka di tabel Status

## Step 5 (Determinisme) — RE-RUNNING

Run ulang label sama (shell `sh_12ba27f6a001r3cC02pHIJ0xC1`); depth di-skip via
skip-if-exists, fusion jalan ulang di atas maps identik; titik dalam ±0,1%.
Bit-identik TIDAK dituntut. Hasil: MENYUSUL. TANPA commit (ledger).

## Risiko / tak dicek

- Kombinasi `geom=false,filter=true` belum pernah diuji upstreamintest —
  validitasnya dibuktikan ablasi ini, bukan inspeksi kernel.
- Screenshot viewpoint vs base di-skip (tak ada renderer/Python di box ini).
- Tak rebuild/tak run lain selama ablasi (1 GPU, Windows lock).
