# Report Task 2 (Mod 4) — Coarse-to-fine dengan seed existing-path

Status: **DONE** (code + build, tanpa run — ablasi `pyramid1` diserahkan ke controller).
Tanggal: 2026-10-11. Repo `colmap/` HEAD `bd1fcf6`, tanpa commit (ledger: TANPA commit per task).

## Ringkasan

`--PatchMatchStereo.pyramid_levels` (default 0 = mati; ≥1 = aktif) terimplementasi:
fase A = photometric pass pada `max_image_size/2` (tulis `.photometric.bin` coarse) →
upsample nearest di host ke resolusi fine, tulis ulang path sama →
fase B = loop geometrik penuh yang seed lewat path existing
(`ProcessProblem` → `PatchMatch::Check` → `InitWorkspaceMemory`, tak tersentuh).
`InitWorkspaceMemory` (`patch_match_cuda.cu:1825-1833,1859-1867`) hanya memberi
makan seed bila `geom_consistency=true`, sisanya acak — piramid hanya berguna
untuk pass geometrik (fakta ini menentukan guard di bawah).

## Step 1: API (temuan, verbatim signature)

- `DepthMap`: `Rescale(float)`, `Downsize(size_t,size_t)` (`depth_map.h:51-52`);
  `Rescale` hanya downsample via `DownsampleImage` (`depth_map.cc:66-67`).
- `NormalMap`: `Rescale(float)`, `Downsize(size_t,size_t)` (`normal_map.h:45-46`),
  layout slice-major 3 kanal (`mat.h:107-109`, `normal_map.cc:58-67`).
  Fungsi sepadan: `void UpsampleNearest(size_t width, size_t height);` — sama persis.
- `Mat<float>::Read/Write(const path&)` (`mat.cc:43,61`); path tulis
  `DepthMap::Write` dipakai `ProcessProblem` (`patch_match.cc:547`).
- `ComputeDepthRanges` hanya pakai R/T + titik 3D (`model.cc:178-218`) →
  independen ukuran, dihitung SEKALI dari workspace fine, dipakai ulang fase A.

## Step 1b (RED): bukti gagal dulu

Setelah field `pyramid_levels` + call-site `UpsampleNearest` di `Run()` ditulis
SEBELUM implementasi method, build gagal persis seperti brief:

- `patch_match.cc(97): error C2039: 'UpsampleNearest': is not a member of 'colmap::mvs::DepthMap'`
- `patch_match.cc(105): error C2039: 'UpsampleNearest': is not a member of 'colmap::mvs::NormalMap'`

(0 proses `colmap` berjalan saat build — single GPU, lock Windows aman.)

## Step 2: implementasi `UpsampleNearest`

- `DepthMap::UpsampleNearest` (`depth_map.cc`): nearest murni
  `dst = src[(y*H/h)*W + (x*W/w)]`; 0 = invalid tersalin apa adanya (tak tercampur).
- `NormalMap::UpsampleNearest` (`normal_map.cc`): sama per 3 slice; salinan eksak
  tetap unit-length, nol tetap nol — tanpa renormalisasi, tanpa dependensi baru.
- Keduanya no-op bila ukuran sudah sama (kasus skip-if-exists meninggalkan maps
  ukuran fine). `depth_min/max` tak tersentuh (member dipertahankan).

## Step 3: orkestrasi `Run()` — keputusan + alasan

- **Helper file-local di `patch_match.cc` (tanpa ubah `patch_match.h`, yang tak ada
  di brief):** `CreateWorkspace(...)` (konstruksi workspace pada resolusi eksplisit)
  + `UpsamplePyramidSeeds(...)` (baca coarse `.photometric.bin` → upsample →
  tulis ulang + `THROW_CHECK_EQ` vs dim fine). `ReadWorkspace()` kini memanggil
  `CreateWorkspace` — perilaku non-piramid bit-identik (hanya pindah baris).
- **Pilihan workspace (ruling ledger: mutasi-sementara+restore atau workspace kedua,
  pilih minimal):** rebuild `CachedWorkspace` coarse lalu restore fine via helper
  bersama. Alasan: `options_` controller adalah member `const` (mutasi literal
  tak mungkin) dan dim model dikunci saat konstruksi `Workspace`
  (`workspace.cc:44-48`) — rebuild tak terhindarkan; satu helper = diff terkecil,
  tanpa deklarasi header baru. PMVS import dilewati saat rebuild (sudah dikerjakan
  `ReadWorkspace` awal; path identik).
- **Guard:** `use_pyramid = pyramid_levels>=1 && geom_consistency && !single_pass
  && max_image_size>0`. Alasan tiap syarat:
  - `!single_pass` (temuan desain): di bawah `single_pass`, fase B menulis file
    `.photometric.bin` yang SAMA dengan hasil upsample → `skip-if-exists`
    (`patch_match.cc:427-431`) akan me-no-op-kan seluruh fase B diam-diam
    (output = coarse yang diupsample, disajikan sebagai final). Karena pass
    fotometrik mengabaikan seed total (init acak), kombinasi itu murni rugi/
    salah — maka piramid nonaktif dan perilaku `single_pass` murni dipertahankan.
    Ini bentuk "fase A hormati `single_pass`" dari ruling T1–T2 yang tidak
    merusak output maupun membuang waktu GPU.
  - `geom_consistency`: tanpa itu tak ada konsumen seed.
  - `max_image_size>0`: `(-1)/2 = 0` = tanpa-downsize = komputasi ganda sia-sia.
- **Fase B memakai ulang loop output existing tanpa duplikasi** (cabang
  `single_pass` Task 1 tak tersentuh); bila `use_pyramid`, loop fotometrik fine
  dilewati (`else if`) dan digantikan fase A + upsample.
- **`THROW_CHECK` dim fine vs model** (`UpsamplePyramidSeeds`): dim model == dim
  bitmap kerja (ditegakkan `PatchMatch::Check`, `patch_match.cc:98-102`), yang
  dipakai `CopyToDevice` sebagai pitch baris (`patch_match_cuda.cu:1828-1829`) —
  cek ini menutup risiko corrupt pada review focus plan. (Bitmap undistort di disk
  memang lebih besar; yang relevan adalah bitmap kerja hasil rescale.)
- Komentar why satu baris per lokasi, sesuai ponytail.

## Step 4: BUILD (GREEN)

- `build-mx150.ps1` → `[17/17] Linking CXX executable colmap.exe`, exit 0.
  Warning hanya pre-existing di file tak tersentuh (`patch_match_cuda.cu`,
  `gpu_mat.h`). Biner fresh (`colmap.exe` 31 MB).
- Flag terdaftar: `--PatchMatchStereo.pyramid_levels 1` lolos parse dan mencapai
  `Reading workspace...` baru (`patch_match.cc:321`); kontras
  `--PatchMatchStereo.bogus_flag` → `Failed to parse options - unrecognised
  option`, exit 1. (Catatan: shell subagent butuh `PATH=cuda-env\bin` agar exe
  start — `STATUS_DLL_NOT_FOUND` tanpa itu; bukan masalah biner.)

## Step 5: perintah ablasi `pyramid1` (siap run oleh controller — JANGAN dari subagent)

Prasyarat (ruling harness: `skip-if-exists` membatalkan run bila maps lama ada —
pindahkan SEMUA `.bin`, jangan hapus; fase A tulis photometric, fase B tulis
geometric, keduanya harus fresh):

```powershell
New-Item -ItemType Directory -Force E:\dev\Lewoleba-15agustus\dense700\stereo\backup_pre_pyramid1 | Out-Null
Move-Item E:\dev\Lewoleba-15agustus\dense700\stereo\depth_maps\*.bin E:\dev\Lewoleba-15agustus\dense700\stereo\backup_pre_pyramid1\
Move-Item E:\dev\Lewoleba-15agustus\dense700\stereo\normal_maps\*.bin E:\dev\Lewoleba-15agustus\dense700\stereo\backup_pre_pyramid1\
powershell -NoProfile -ExecutionPolicy Bypass -File E:/dev/Colmap-Kernel/run-ablate.ps1 -Label pyramid1 -ExtraArgs '--PatchMatchStereo.pyramid_levels 1'
```

Fusion default harness (`--input_type geometric`) sudah benar (fase B menulis
geometric maps) — tanpa override seperti singlepass. `undistort` tidak diulang
(`dense700/` dipakai ulang); `patch-match.cfg` ditulis ulang harness
(`__auto__, 8`) tiap run.

Kriteria lolos (plan Task 2 Step 5 + override ledger): waktu depth total <
20,317 mnt (dua-pass baseline); titik ≥ 819.366 (@700px, max_angle 65 default
harness); tanpa lubang baru vs base (proxy: titik + 0-view gugur + per-view
counts log fusion; oracle viewpoint SKIP — tanpa renderer di box); determinisme
= double-run titik ±0,1% (hash hanya informatif). Gagal → revert hunks Task 2
saja (Task 1 tetap); `pyramid_levels` default 0 = perilaku upstream utuh.

## File yang disentuh (hanya brief + warisan kotor sebelumnya)

Milik Task 2: `mvs/depth_map.h/.cc` (+`UpsampleNearest`), `mvs/normal_map.h/.cc`
(+padanan), `mvs/patch_match_options.h/.cc` (+field & Print, tanpa Check baru —
cermin Task 1; negatif berperilaku 0 via guard `>=1`), `controllers/option_manager.cc`
(+registrasi), `mvs/patch_match.cc` (+helper, cabang piramid, refactor
`ReadWorkspace`). `patch_match_cuda.cu` (seeding) TAK tersentuh. Tanpa commit.

## Yang dilewati / risiko (wajib baca)

- TIDAK run (perintah di atas siap; controller luncurkan dari sesinya agar
  notifikasi kembali — pelajaran Task 1).
- Tanpa round-trip test tereksekusi (`ctest` OFF per plan; kebenaran index nearest
  hanya lewat review + build — risiko sisa kecil: off-by-one tepi pada aspek
  non-2:1, akan terlihat sebagai titik anjlok di ablasi).
- Kombinasi `pyramid_levels 1 + single_pass 1` = fallback `single_pass` murni
  (by design, lihat alasan skip-if-exists) — jangan ablasi kombinasi itu.
- `pyramid_levels > 1` diperlakukan = 1 (satu level coarse, sesuai brief).
- Jika `dense700/stereo` masih berisi maps `singlepass` (photometric saja),
  backup-semua-`.bin` di atas tetap prasyarat yang benar.
