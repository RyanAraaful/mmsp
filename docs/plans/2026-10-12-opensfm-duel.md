# OpenSfM Duel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OpenSfM (BSD-2-Clause, fork hidup OpenSfM/OpenSfM) terinstall dan jalan di mesin ini sebagai pembanding SfM, duel adil Secondary 51 foto vs pipeline kita (CPU dulu, native-GPU menyusul).

**Architecture:** Python 3.11 via micromamba (`tools/micromamba.exe`, pola `cuda-env`), `pip install opensfm`, smoke 3 foto, duel Secondary 51. OpenSfM = proses-terpisah seperti OpenMVS (AGPL): tidak ada salin kode, hanya angka pembanding. Tanpa Python di PATH hari ini — env Python adalah prasyarat Task 1.

**Tech Stack:** micromamba + Python 3.11 + OpenSfM pip, PowerShell `.ps1`.

**Spec:** Goal decisions rev 10 (pembanding = install OpenSfM + duel Secondary kecepatan + kualitas).

## Global Constraints

- OpenSfM hanya pembanding proses-terpisah; lisensi BSD-2-Clause dicatat di `THIRD_PARTY_NOTICES.md` saat install lolos.
- Dataset Secondary 51 foto yang sama; metrik SfM numerik saja: wall extract, wall match, reg rate, mean track length, mean reproj error (px), #3D points.
- Klaim hanya dari angka; tiap task berhenti bila prasyarat gagal (catat blocker, bukan failure plan).

## Review Focus

- OpenSfM tanpa CUDA di MX150 (fitur HAHOG/GPU-opsional) → duel CPU-vs-CPU yang adil dicatat eksplisit; klaim GPU-vs-OpenSfM hanya setelah Part A selesai.
- EXIF/GPS Secondary dibaca OpenSfM berbeda → reg rate bisa bias; catat pemakaian GPS kedua sisi.
- Windows-path dengan spasi di foto → quote path di skrip, jangan inline `$`.
- Versi OpenSfM pip vs dokumentasi → pin versi di log task saat install lolos.

---

### Task 1: Env Python 3.11 via micromamba

**Files:**
- Create: `scripts/setup/install-python.ps1` (`tools/micromamba.exe create -p <repo>/../tools/py311 -y python=3.11`, pin path di `env.local.example.ps1` sebagai `PyEnv`, BUKAN hardpath).

**Interfaces:**
- Consumes: `tools/micromamba.exe` (existing).
- Produces: `$PyEnv/python.exe` (dikonsumsi Task 2–4).

- [ ] **Step 1: run skrip.**

Run: `powershell -File scripts/setup/install-python.ps1`.
Expected: `$PyEnv/python.exe --version` → 3.11.x. Gagal unduh = transien, retry 1x lalu STOP + catat blocker.

- [ ] **Step 2: parsecheck + commit.** Pesan `setup: python 3.11 env for opensfm duel`.

### Task 2: Install OpenSfM dari source + catat pin di laporan duel (amendemen: PyPI tak menerbitkan `opensfm`, putusan pemilik = source install; pembanding eksternal TAK masuk THIRD_PARTY_NOTICES — preseden OpenMVS)

**Files:**
- Modify: `scripts/setup/install-opensfm.ps1` (dapatkan source OpenSfM/OpenSfM branch master ke `$OpenSfMRoot` + install dari source ke `$PyEnv` + `import opensfm` probe). Cara dapat source, SATU jalur tanpa ulang-ulang: klon HTTP/1.1 dangkal yang sedang jalan; bila gagal → unduh zip codeload `https://github.com/OpenSfM/OpenSfM/archive/refs/heads/master.zip` + ekstrak (pin = tanggal + nama file). Gagal keduanya = STOP blocker.
- Catat: pin versi (hash commit, atau tanggal+nama-zip bila via arsip) + lisensi BSD-2-Clause di `MODS.md`/laporan duel sebagai provenesansi angka — BUKAN di notices.
- Test: probe import exit 0 + `opensfm --help` mencetak usage.

- [ ] **Step 1 (RED): probe gagal sebelum install.** Expected: import error tercatat.
- [ ] **Step 2: install dari source.** Run skrip. Expected: probe lolos. Build C-extension gagal di Windows → STOP + catat blocker (fallback: duel vs baseline internal, putusan pemilik).
- [ ] **Step 3: commit + catat pin.** Pesan `setup: opensfm <pin> source install`; pin + lisensi masuk `MODS.md`/laporan duel (bukan notices).

### Task 3: Smoke 3 foto + duel Secondary 51

**Files:**
- Create: `scripts/measure/duel-opensfm.ps1` (run OpenSfM 3 foto → `reconstruction.json`; run Secondary 51 → tabel metrik; bandingkan vs angka SfM kita: extract 5,45 + match 3,18 + mapper 0,72 mnt, 50–51/51 reg).

- [ ] **Step 1: smoke 3 foto.** Expected: `reconstruction.json` valid + wall tercatat.
- [ ] **Step 2: duel Secondary 51.** Expected: tabel lengkap kedua sisi (wall extract/match, reg rate, track length, reproj px, #3D points).
- [ ] **Step 3: vonis + MODS.md.** MENANG bila wall < kita DAN kualitas ≥ (reg rate + reproj tidak lebih buruk). Catat apa adanya bila kalah salah satu sisi.
- [ ] **Step 4: commit.** Pesan `measure: opensfm duel Secondary + verdict`.
