# Desain: kernel COLMAP MVS dense setara/melebihi OpenMVS (kecepatan + kepadatan)

Tanggal: 2026-10-11. Status: disetujui pemilik untuk ditulis; belum boleh bangun kode sampai dokumen ini disetujui.

## Intent dan why

Kernel dense COLMAP (`patch_match_stereo` + `stereo_fusion`) kalah telak dari
OpenMVS `DensifyPointCloud` pada foto drone DJI nadir di titik operasi yang
sama (@700px, 117 foto Lewoleba, GPU MX150 2GB): COLMAP 819.366 titik dalam
20,90 mnt (~39rb titik/mnt) vs OpenMVS 4.514.363 titik dalam 2,91 mnt
(~1,55jt titik/mnt) — gap ~40x throughput, 5,5x titik. Duel 1400-vs-700
sebelumnya dinyatakan TIDAK RELEVAN. Sumber angka: `MODS.md` (milestone
head-to-head adil @700px), log `log_patch700.txt` / `log_fusion700.txt` /
`vram_700.csv` / `openmvs/DensifyPointCloud-261011204302001811.log`.

Prioritas pemilik: (1) kecepatan, (2) kepadatan. Cara: bedah mekanisme
OpenMVS, porting idenya sebagai tulis-ulang native di kernel COLMAP dengan
optimasi lebih baik. Koreksi penting: kedua kubu jalan di CUDA GPU — gap
murni organisasi algoritma, bukan CPU-vs-GPU.

## Goals

1. Waktu depth+fusion @700px Lewoleba turun orde besar (target arah: paritas
   OpenMVS ~3 mnt; ambang "cukup" final ditentukan pemilik setelah Mod 1–2).
2. Titik naik orde besar di resolusi sama (arah: paritas ~4,5jt; tanpa
   menambah lubang di atap/jalan/strip tepi).
3. Tiap mod terbukti angka via ablasi langsung di full 117 @700px, lalu
   Midai 51 foto. Subset strip ±30 (sempat di wacana) DICORET atas koreksi
   pemilik 2026-10-11 — tanpa subset, tanpa regresi @1400px untuk sekarang.
4. Peak VRAM <1,5GB selalu; 0 OOM di 117 view; fallback deterministik.
   Panggilan penulis: ukur high-water `nvidia-smi` sampling 5dtk + puncak
   alokator CUDA bila tersedia; budget mencakup semua alokasi GPU Mod 5,
   buffer pinned-host dicatat terpisah.

## Non-goals

- Sparse, mesh, tekstur, GUI: tidak disentuh.
- Ekstraktor fitur (PopSIFT dkk): tunda, sparse 116/117 sudah cukup.
- Porting kode OpenMVS (AGPL-3.0): dilarang — hanya ide, tulis ulang native.
- Dekomposisi paralel red-black penuh per piksel: jangka panjang (risiko CUDA
  dalam, dikecualikan sejak G1).

## Anti-goals (gagal walau cepat+padat)

- View kehilangan semua tetangga lalu gugur total (lubang strip) — tiap
  perubahan view selection wajib floor anti-kosong.
- Kepadatan naik dari false positive (titik noise vegetasi/tepi) — kepadatan
  harus lolos uji visual zona atap/jalan/strip tepi.
- OOM di MX150 2GB atau hasil tidak deterministik antar-run. Definisi
  deterministik (panggilan penulis): seed RNG tetap per (view, iterasi);
  verifikasi via double-run. REVISI 2026-10-11 (bukti: fusion upstream
  order-nondeterministik — input identik → 819.227 vs 819.366 pts):
  operasional = double-run jumlah titik dalam ±0,1%; bit-identik
  `fused.ply` TIDAK dituntut untuk fusion multithread. CDF sampling +
  multi-instance wajib seed dan ordering tetap.

## Constraints

- Scope kode: `colmap/src/colmap/mvs/` + registrasi flag
  (`controllers/option_manager.cc`, `mvs/patch_match_options.*`) saja.
- Lisensi: tanpa GPL/AGPL/non-komersial masuk build/eksekusi (`MODS.md`
  seksi lisensi). SiftGPU tidak dieksekusi.
- Target: MX150 2GB sm_61; dataset primer Lewoleba-15AGUSTUS (117 foto),
  pembanding Midai 14-Agustus-2025 (51 foto).
- Shell repo: bash tanpa coreutils — bungkus PowerShell via file `.ps1`,
  jangan inline `$`. Jangan rebuild saat biner dipakai run (Windows lock).
- Klaim hanya dari angka benchmark + CUPTI/CUDA-events, bukan aritmetika.

## Cara kerja OpenMVS yang diporting (hasil bedah read-only)

1. Piramid coarse-to-fine (2 sublevel): depth kasar jadi prior level halus
   (upsample nearest agar depth/normal/view-ID utuh); init dari sparse.
2. View adaptif: cap global 8 + skor sudut (Gaussian ~12°) + skala + ROI;
   per-piksel ≤4 view tersimpan, sampling CDF, top-K.
3. Checkerboard red-black paralel penuh per piksel (256 thread/blok).
4. Confidence terkalibrasi + lantai (~0,07): titik fotometrik lemah tapi
   konsisten lolos.
5. Prior intra-map berbobot: selamatkan inlier 1–2 view di permukaan homogen.
6. Fusion flood-fill multi-piksel + median + keep-rule (piksel+prior virtual,
   view+prior virtual); guard kontradiksi free-space.
7. Overlap host-prep vs kernel (antrean event, prefetch, urutan lokalitas
   view) + image cache LRU + multi-instance (4 worker, buffer pinned/stream
   sendiri; kernel diserialisasi via event chain).

## Urutan mod yang diputuskan pemilik

1. **Hapus/gabung pass ganda** (`mvs/patch_match.cc:183-204` menjalankan
   tiap view 2x: fotometrik lalu geometrik ≈50% waktu). Panggilan penulis:
   Mod 1 berdiri sendiri tanpa piramid — satu pass skala-sama dengan
   geometri+filter terlipat. Opsi "init pass-1 dari depth kasar" pindah ke
   Mod 2, bukan alternatif Mod 1.
2. **Mod 4 coarse-to-fine**: orkestrasi multi-skala + baca init maps existing
   di `patch_match.cc`; depth kasar sebagai prior (bukan acak). Dibangun di
   atas hasil Mod 1 (tiap level memanggil single-pass).
3. **View adaptif per-piksel + floor anti-kosong**: cap + skor sudut/skala
   (ganti top-N shared-points buta), CDF sampling; ablasi wajib 15° vs 65°
   @700px (baseline 819rb diukur pada 65°). Panggilan penulis: floor = tiap
   view pertahankan ≥2 tetangga terlemah menurut skor walau lolos sudut;
   view tanpa shared-points tetap gugur + log.
4. **Confidence terkalibrasi + prior-virtual di fusion** (`mvs/fusion.cc`,
   `patch_match_cuda.cu` filter sweep-terakhir): ganti tolak-biner
   (`kMinVar`, konsisten≥2, geom≤1px) dengan skor+lantai; prior intra-map
   untuk permukaan koheren miskin view.
5. **Konkurensi 2–3 instance + prefetch** (F8): VRAM headroom ada (133MB <<
   2GB); I/O overlap agar idle antar-view <10%; fallback sekuensial bila
   alokasi gagal.
6. **Ablasi murah `window_step=2`** (opsi ada, belum dicoba @700px).

## Baseline ablasi yang mengikat (jawaban builder-check #1)

Acuan delta semua mod = run adil @700px: `dense700/` dari `undistort700.ps1`
(`--max_image_size 700`) + `g3-patch700.ps1` (`__auto__` 8, min_tri 1°,
max_tri 65°, num_samples 10, num_iterations 4, window 5/1, geom_consistency 1,
filter 1, cache 4; backup cfg di `stereo/patch-match.cfg.full`) + fusion
(min_num_pixels 3, reproj 4, depth_err 0.05, normal 20°, check 30). Parameter
penuh + log di `MODS.md` milestone adil. Harness freeze: sebelum Mod 1 catat
hash skrip + cfg + biner; tiap mod rerun harness identik.

## Yang diserahkan ke builder

- Pilihan struktur kode persis tiap mod (fungsi/kelas baru vs ubah existing),
  selama diff minimal dan konvensi file dipertahankan.
- Nilai threshold awal (mulai dari nilai OpenMVS sebagai titik awal ablasi,
  bukan kebenaran).
- Instrumen ukur (CUDA events vs CUPTI) per Mod 1–2.
- Keputusan saya sebagai penulis: urutan di atas mengikat; red-black penuh
  dan PopSIFT tetap di luar scope.

## Verifikasi per mod

Full 117 @700px: waktu depth, waktu fusion, jumlah titik, peak VRAM
(nvidia-smi 5dtk), lubang visual atap/jalan/tepi. Oracle lubang/noise
(keputusan pemilik 2026-10-12, revisi): gate numerik per mod — grid
okupansi top-down (sel kosong = lubang), outlier-ratio jarak
tetangga-terdekat, cloud-to-cloud distance dua arah vs `scene_dense`
OpenMVS (asumsi eksplisit: OpenMVS ≈ acuan, bukan kebenaran absolut) —
dihitung identik untuk kedua kubu tanpa dependensi baru; plus 6 screenshot
sudut tetap oleh manusia SEKALI di akhir sebelum vonis. Lolos → Midai.
REVISI 2026-10-12 (dataset semua-nadir; CLI CC tak bisa render): oblik
dicoret, nadir = PGM hole-map dari metrics.cpp (union bbox, langsung
sebanding) untuk tiap pasangan cloud; tanpa screenshot GUI.
Catat di `MODS.md` + revisi plan goal. Mod yang memperlambat atau menambah
lubang di-revert.
