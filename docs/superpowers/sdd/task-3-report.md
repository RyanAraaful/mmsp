# Task 3 Report — View floor anti-empty (tanpa per-piksel kernel)

Status: DONE (build GREEN; tanpa GPU run — controller yang run ablasi)

## Step 0 (RED, sebelum kode produksi — tercatat dulu)

Bukti kode (biner lama / HEAD bd1fcf6 + Task 1/2): di
`colmap/src/colmap/mvs/patch_match.cc`, cabang `__auto__` memfilter kandidat
overlap lewat sudut (:441-448), lalu bila `src_image_idxs` kosong problem
DIBUANG dengan warning (:472-479):

```
"Ignoring reference image %s, because it has no source images."
```

+ `problems_.push_back` tidak dipanggil → view hilang total → lubang strip.

Bukti historis: `MODS.md:210-213` — run @1400px `__auto__ 6, max_angle 15`
menggugurkan **9 problem** oleh filter sudut ("investigas F3: floor
anti-kosong"). RED terpenuhi tanpa run baru (brief adaptasi SDD: tunjuk kode
+ bukti historis; dilarang run GPU oleh subagent).

## Step 1 (Implementasi floor + LOG)

Diff hanya di `ReadProblems` cabang `__auto__` (`patch_match.cc`):

- Counter `num_floor_views = 0` sebelum loop `problem_configs`.
- Setelah filter sudut, bila `src_images.size() < 2` DAN masih ada kandidat
  overlap yang belum kepilih: urutkan semua kandidat overlap by shared-points
  desc (`std::sort`), tambahkan yang terkuat sampai 2.
- Keputusan (sesuai opsi minimal di brief): **hormati batas bawah
  (`min_triangulation_angle`, default 1.0°), abaikan batas atas (`max`) khusus
  floor.** Rasional: floor hanya merelaksasi filter Mod1 yang menyebabkan 9
  gugur; guard narrow-baseline upstream tetap utuh.
- Counter naik hanya bila floor benar-benar menambah ≥1 tetangga (jujur:
  "kena floor" = terbantu, bukan sekadar trigger).
- LOG INFO satu baris per run setelah "Configuration has %d problems...":
  `View floor kept >=2 neighbors for %d views...`
- Satu komentar why: `Floor anti-lubang strip: tiap view pertahankan >=2 tetangga.`
- Hasil mengalir lewat seleksi top-N existing (`partial_sort` + `eff_max_num_src_images`)
  tanpa perubahan — tidak ada path khusus baru.
- **Tidak ada flag baru**: floor selalu aktif; perilaku upstream berubah hanya
  pada kasus yang dulu gugur total (0/1 tetangga → 2).

Edge yang ditangani: kandidat 0 sisa (view tetap gugur + warning existing);
`overlapping_images.size()==1` (tambah 1, tetap <2 tapi tidak kosong);
duplikat dicegah (`already_selected`); `.at()` aman karena loop filter sudah
menyentuh semua key lebih dulu.

## Step 2 (Build)

- Pra-build: `tasklist /FI "IMAGENAME eq colmap.exe"` → tidak ada proses
  (cek 2x: sebelum build dan sesudah edit; single GPU, tanpa Windows lock).
- `build-mx150.ps1` → `[3/3] Linking CXX executable colmap.exe`, exit 0.
  `colmap.exe` baru: 2026-10-11 23:26, 31.260.672 B.
- Parse check: `colmap.exe patch_match_stereo -h` mencetak opsi (exit via help
  normal). Catatan: butuh `E:\dev\tools\cuda-env\bin` di PATH, pola sama
  seperti skrip build.
- String `View floor kept >=2 neighbors for %d views...` terkonfirmasi ada di
  binary (cek strings) — kode floor ter-link.

## Step 3 (Serah ablasi — TANPA run oleh subagent)

Konfirmasi: tidak ada flag baru. Controller run bila siap, contoh:

```
run-ablate.ps1 -Label tri15 -ExtraArgs '--PatchMatchStereo.max_triangulation_angle 15'
run-ablate.ps1 -Label tri65 -ExtraArgs '--PatchMatchStereo.max_triangulation_angle 65'
```

(plus flag pemenang Task 1/2 sesuai keputusan controller). Yang dibandingkan:
titik, waktu, jumlah baris `Ignoring reference image` vs baris
`View floor kept...` di log, screenshot tepi strip. Per-piksel ≤4 ala OpenMVS
eksplisit DITUNDA (brief).

## Step 4 (Tanpa commit)

JANGAN commit — working tree tetap dirty, tidak ada commit baru dibuat.
Hanya `patch_match.cc` region ReadProblems yang disentuh task ini.

## Skip / risiko

- Skip: run ablasi + determinisme double-run (milik controller); ctest
  (TESTS_ENABLED=OFF, di luar scope plan); `<algorithm>` include eksplisit
  (file sudah pakai `partial_sort`/`min` tanpa include langsung — `std::sort`
  ikut pola existing, build membuktikan cukup).
- Risiko: view yang floor-nya diisi tetangga bersudut lebar (>max) dapat depth
  lebih berisik di tepi strip — trade-off anti-lubang yang disengaja; ablasi
  tri15 vs tri65 yang menilai. Bila floor counter = 0 di semua run adil, berarti
  kasus gugur tidak muncul di operating point itu (bukan bug floor).
