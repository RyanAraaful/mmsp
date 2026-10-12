# Third-party notices (MMSP)

This file lists the third-party components built into MMSP binaries and
what their licenses require from redistributors. Original MMSP work
(`scripts/`, `tools/metrics.cpp`, `docs/`, engine modifications under
`colmap/`) is under the Apache License 2.0 — see `LICENSE`.

Rule of thumb: when you distribute MMSP (source or binary), ship this
file plus `LICENSE` alongside it, keep all copyright notices below, and
for the MPL-2.0 component keep its sources available unmodified.

Removed components (formerly bundled upstream, purged 2026-10-12, NOT
shipped): SiftGPU (educational/research/non-profit-only license) and LSD
(AGPL-3.0). GPU feature extraction/matching is therefore unavailable;
CPU SIFT is the only extractor.

## BSD 3-Clause

The following components share the BSD 3-Clause terms reproduced here:

> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are met:
>
> * Redistributions of source code must retain the above copyright notice,
>   this list of conditions and the following disclaimer.
> * Redistributions in binary form must reproduce the above copyright notice,
>   this list of conditions and the following disclaimer in the documentation
>   and/or other materials provided with the distribution.
> * Neither the name of the copyright holder nor the names of its
>   contributors may be used to endorse or promote products derived from
>   this software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
> AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
> IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
> ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
> LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
> CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
> SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
> INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
> CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
> ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
> POSSIBILITY OF SUCH DAMAGE.

Applies to (verified from in-tree license files / declarations):

- COLMAP base (`colmap/`, upstream at `bd1fcf6`) — Copyright ETH Zurich
  and UNC Chapel Hill; declared `BSD-3-Clause` in `colmap/vcpkg.json`.
- Ceres Solver — Copyright 2023 Google Inc. (verified from the vcpkg
  copyright file; corrects any source calling it Apache-2.0).
- PoseLib — Copyright (c) 2020, Viktor Larsson.
- glog, gflags — BSD-3-Clause (Google and contributors).
- OpenBLAS / LAPACK reference — BSD-3-Clause.

## BSD 2-Clause (VLFeat, CPU SIFT)

Copyright (C) 2007-11, Andrea Vedaldi and Brian Fulkerson;
Copyright (C) 2012-13, The VLFeat Team. All rights reserved.
(`colmap/src/thirdparty/VLFeat/LICENSE`, reproduced verbatim.)

> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are
> met:
> 1. Redistributions of source code must retain the above copyright
>    notice, this list of conditions and the following disclaimer.
> 2. Redistributions in binary form must reproduce the above copyright
>    notice, this list of conditions and the following disclaimer in the
>    documentation and/or other materials provided with the
>    distribution.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
> "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
> LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
> A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
> HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
> SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
> LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
> DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
> THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
> (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
> OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## MIT

The following components share the MIT terms (verified pattern — full
license files ship with each component as noted):

> Permission is hereby granted, free of charge, to any person obtaining a
> copy of this software and associated documentation files (the
> "Software"), to deal in the Software without restriction, including
> without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so, subject to
> the following conditions:
>
> The above copyright notice and this permission notice shall be included
> in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
> OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
> MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
> IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
> CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
> TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
> SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Applies to (copyright lines verified in-tree):

- PoissonRecon (`colmap/src/thirdparty/PoissonRecon/LICENSE`) —
  Copyright (c) 2015 mkazhdan.
- faiss (fetched at build time) — Copyright (c) Facebook, Inc. and
  its affiliates.
- ONNX Runtime (fetched at build time) — Copyright (c) Microsoft
  Corporation.

## Apache License 2.0 (same terms as `LICENSE`)

- METIS, OpenImageIO — Apache-2.0; see `LICENSE` for the full text.

## Mozilla Public License 2.0 (file-level copyleft)

- Eigen (header-only linear algebra, used unmodified) — MPL-2.0. A larger
  work combining unmodified MPL files stays under its own license; keep
  Eigen's sources and headers (with their `SPDX-License-Identifier:
  MPL-2.0` notices) available. Full text: https://mozilla.org/MPL/2.0/

## Other permissive components (name + pointer)

- Boost — Boost Software License 1.0,
  https://www.boost.org/LICENSE_1_0.txt
- SQLite — public domain (https://www.sqlite.org/copyright.html).
- GLEW — BSD/MIT-style (see its upstream headers).
- JasPer — JasPer License 2.0, MIT-style (see the vcpkg port's
  copyright file).
- OpenEXR/TIFF/PNG/zlib/bzip2/LZMA/zstd and similar image/codec
  helpers pulled in via vcpkg/OpenImageIO — all permissive
 (BSD/MIT/Zlib-style); full texts ship in their vcpkg ports.

## Toolchain (not distributed as source)

- CUDA Toolkit (conda channel) and MSVC — proprietary toolchains. CUDA
  redistributables linked into MMSP binaries are covered by the NVIDIA
  CUDA EULA; binary redistributors must reproduce NVIDIA's notices.
  System libraries (OpenGL, MSVC runtime) fall under the system-library
  exception.
