# MMSP standalone Windows runtime

This runtime format is intended to run the photos-to-dense-cloud pipeline
without a source checkout or `env.local.ps1`. The packaging script audits the
Release executable's import closure, copies its app-local dependencies,
including CUDA Runtime 12 (`cudart64_12.dll`), and adds the pipeline and
required license notices. Per-port vcpkg copyright files are copied under
`licenses/vcpkg/`; Eigen's MPL-covered headers are copied under
`licenses/eigen3-source/`.

## Verified dependency profile

The old local `build-mx150` CMake cache points to a different source checkout,
so its executable and DLL list are stale artifacts and are rejected by the
packager. That old DLL closure included `libgfortran-5.dll` and
`libgcc_s_seh-1.dll` (GPL-3.0 with GCC Runtime Library Exception 3.1),
`libquadmath-0.dll` (LGPL-2.1), and `libwinpthread-1.dll` (MIT-style). The MIT
component is permissively licensed, but it was not part of the verified runtime
profile and would need an explicit license entry before the packager could copy
it. MMSP excludes the GPL/LGPL components despite the GCC runtime exception.

The current configure profile uses vcpkg `x64-windows-static` (static
libraries and CRT) and sets CMake policy `CMP0091` plus
`CMAKE_MSVC_RUNTIME_LIBRARY` so COLMAP and its fetched targets use `/MT`,
matching the triplet. The pinned vcpkg `lapack` port selects CLAPACK, the
f2c-translated LAPACK implementation, with OpenBLAS as its BLAS provider.
OpenBLAS 0.3.33 is BSD-3-Clause and the port builds with `NOFORTRAN=ON`;
CLAPACK's upstream `COPYING` grants BSD-3-Clause redistribution rights.
Zstandard 1.5.7 offers BSD-3-Clause or GPL-2.0-only; this profile selects the
BSD-3-Clause option. Its complete vcpkg copyright file is included in the
runtime license folder. `ONNX_ENABLED=OFF` omits optional neural extractors;
the packaged pipeline uses CPU SIFT and does not require ONNX Runtime.

PoseLib and Faiss are fetched from their pinned CMake URLs and verified with
the declared SHA-256 hashes. The configure script clears stale
`FETCHCONTENT_SOURCE_DIR_*` cache entries so an unrelated developer source
tree cannot bypass those pins. The pinned PoseLib source needs a small
MSVC/Eigen 5 template-forwarding patch at configure time; it forwards to the
existing accumulator functions and does not alter their calculations.

The Release executable's recursive PE audit found one app-local DLL,
`cudart64_12.dll`, which the package carries with the NVIDIA CUDA license.
Windows supplies `dbghelp.dll`, `bcrypt.dll`, `KERNEL32.dll`, `ole32.dll`, and
`VCOMP140.DLL`; the last comes from the Microsoft Visual C++ 2015–2022 x64
Redistributable. CUDA loads the NVIDIA driver (`nvcuda.dll`) from the system;
the driver is not bundled. The final import closure contains no
`libgfortran`, `libgcc`, `libquadmath`, `libstdc++`, or `libgomp` DLLs. The
stale dynamic build's `libgfortran`/`libgcc` components were GPL-3.0 with GCC
Runtime Library Exception 3.1; MMSP policy excludes them despite that
exception. Its `libquadmath` was LGPL-2.1 and is also excluded. The packager
uses explicit app-local and System32 dependency maps; an unknown DLL blocks
packaging until its source, license, and redistribution terms are reviewed.

The verified closure is classified as follows:

| Component | License/source | Distribution |
| --- | --- | --- |
| `cudart64_12.dll` | NVIDIA CUDA Toolkit EULA; redistributable runtime component | Bundled with the CUDA license file |
| `bcrypt.dll`, `dbghelp.dll`, `KERNEL32.dll`, `ole32.dll` | Microsoft Windows components | Supplied by Windows; not bundled |
| `VCOMP140.DLL` | Microsoft Visual C++ 2015–2022 x64 Redistributable | External prerequisite; not bundled |
| `api-ms-win-*`, `ext-ms-win-*` | Windows API-set contracts | Supplied by Windows; not bundled |
| NVIDIA display driver | NVIDIA driver license | External prerequisite; not bundled |

The package includes 110 vcpkg copyright files, Eigen's MPL source headers,
project notices, and the NVIDIA CUDA license. No Faiss, index, or matching
source was changed.

## Create the package

From the repository root, choose a new or empty folder outside the repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup/package-runtime.ps1 `
  -RuntimeDir '<runtime-folder>'
```

The script refuses to package a CMake cache from another source checkout, to
write inside the repository, through a junction or
symbolic link, or into a non-empty folder. It reads the CUDA DLL location from
the selected build's `CMakeCache.txt` and copies only the files needed by its
executable dependency closure. When using a non-default build folder, pass the same
`-BuildDirectory` value to the configure, build, and package scripts.
The package step accepts app-local and System32 DLLs only when their names are
present in the script's explicit license maps. New or unclassified dependencies
fail packaging until their origin, license, and redistribution terms are audited.

## Run the pipeline

Pass the packaged executable explicitly so the runner does not need the
checkout's machine configuration:

```powershell
$runtime = '<runtime-folder>'
powershell -NoProfile -ExecutionPolicy Bypass -File "$runtime\scripts\run\process-drone.ps1" `
  -ImagesPath '<photo-folder>' `
  -OutputDir '<new-output-folder>' `
  -ColmapExe "$runtime\bin\colmap.exe"
```

The output folder must be new or empty and outside the source checkout. The
runtime bundle includes `LICENSE`, `THIRD_PARTY_NOTICES.md`,
`NVIDIA_CUDA_LICENSE.txt`, per-port vcpkg copyright files, and Eigen source
headers for MPL-2.0 compliance; keep them with the executable when redistributing it.
The NVIDIA file is copied verbatim from the CUDA Toolkit `LICENSE` adjacent to
the bin directory selected by `CMakeCache.txt`. Its section 2.6, Attachment A,
lists the CUDA Runtime files that may be redistributed and describes versioned
file names. The official CUDA EULA is at
<https://docs.nvidia.com/cuda/eula/index.html?type=2>.

## External system requirements

- 64-bit Windows.
- Windows PowerShell 5.1 or PowerShell 7 to run the pipeline script.
- The Microsoft Visual C++ 2015–2022 Redistributable (x64).
- An NVIDIA driver that supports CUDA 12 and a GPU matching a compiled CUDA
  architecture. `configure-mx150.ps1` defaults to `sm_61`; pass
  `-CudaArchitectures '61;86'` to build for both `sm_61` and `sm_86`.
- `nvidia-smi.exe` is optional and is used only for the runner's VRAM samples.

The CUDA toolkit, Visual Studio, vcpkg, source checkout, and `env.local.ps1`
are not runtime requirements. The CUDA driver is a system component and is not
included. The packaged `colmap.exe version` smoke check succeeds without the
CUDA Toolkit on `PATH`; the MX150 E2E run validates this GPU profile only and
does not establish RTX 3050 runtime compatibility.
