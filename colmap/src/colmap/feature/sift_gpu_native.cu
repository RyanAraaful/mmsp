// sift_gpu_native.cu — native CUDA SIFT detection + orientation + descriptors.
//
// Octave pyramid + DoG + gradients run on the GPU (one stream, one device
// allocation per Extract); extrema search runs on the host as an exact port
// of thirdparty/VLFeat/sift.c vl_sift_detect. Orientation (36-bin) and 4x4x8
// descriptors run in GPU kernels mirroring vl_sift_calc_keypoint_
// orientations/descriptor; L1_ROOT + uint8 quantization reuse utils.h so the
// output format matches the CPU path byte for byte.
//
// Copyright 2026 RyanAraaful
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "colmap/feature/sift_gpu_native.h"

#include "colmap/feature/sift.h"
#include "colmap/feature/utils.h"
#include "colmap/util/logging.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace colmap {
namespace {

// VLFeat level bookkeeping (mirrors thirdparty/VLFeat/sift.c, not options).
constexpr int kLevelMin = -1;  // s_min; s_max = S + 1.
constexpr int kDescDim = 128;
constexpr size_t kVramHeadroomBytes = 128 << 20;

// Single device buffer + one stream; freed on all paths via dtor.
struct GpuScope {
  float* buffer = nullptr;
  cudaStream_t stream = nullptr;
  ~GpuScope() {
    if (stream != nullptr) cudaStreamDestroy(stream);
    if (buffer != nullptr) cudaFree(buffer);
  }
};

#define NGS_CUDA_OK(call, what)                                           \
  do {                                                                    \
    const cudaError_t ngs_err = (call);                                   \
    if (ngs_err != cudaSuccess) {                                         \
      LOG(WARNING) << "Native GPU SIFT: " << (what)                       \
                   << " failed: " << cudaGetErrorString(ngs_err);         \
      return false;                                                       \
    }                                                                     \
  } while (false)

// Bilinear 2x upsample; fused equivalent of VLFeat's double
// copy_and_upsample_rows pass (linear interp, edge duplication).
__global__ void Upsample2xKernel(const float* src, int w, int h, float* dst) {
  const int x = blockIdx.x * blockDim.x + threadIdx.x;
  const int y = blockIdx.y * blockDim.y + threadIdx.y;
  const int w2 = w * 2;
  const int h2 = h * 2;
  if (x >= w2 || y >= h2) return;
  const int ix = x >> 1;
  const int iy = y >> 1;
  const int ix1 = (ix + 1 < w) ? ix + 1 : w - 1;
  const int iy1 = (iy + 1 < h) ? iy + 1 : h - 1;
  const float a = src[iy * w + ix];
  float v;
  const int fx = x & 1;
  const int fy = y & 1;
  if (!fx && !fy) {
    v = a;
  } else if (fx && !fy) {
    v = 0.5f * (a + src[iy * w + ix1]);
  } else if (!fx && fy) {
    v = 0.5f * (a + src[iy1 * w + ix]);
  } else {
    v = 0.5f * (0.5f * (a + src[iy * w + ix1]) +
                0.5f * (src[iy1 * w + ix] + src[iy1 * w + ix1]));
  }
  dst[y * w2 + x] = v;
}

// Nearest 2x downsample (VLFeat copy_and_downsample, d = 1).
__global__ void Downsample2xKernel(const float* src, int w, float* dst, int n) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n) return;
  const int w2 = w / 2;
  const int x = i % w2;
  const int y = i / w2;
  dst[i] = src[(2 * y) * w + 2 * x];
}

__global__ void BlurColKernel(const float* src, int w, int h, const float* filt,
                              int fw, float* dst) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= w * h) return;
  const int x = i % w;
  const int y = i / w;
  float acc = 0;
  for (int j = 0; j < 2 * fw + 1; ++j) {
    int yy = y + j - fw;
    yy = (yy < 0) ? 0 : ((yy >= h) ? h - 1 : yy);
    acc += filt[j] * src[yy * w + x];
  }
  dst[i] = acc;
}

__global__ void BlurRowKernel(const float* src, int w, int h, const float* filt,
                              int fw, float* dst) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= w * h) return;
  const int x = i % w;
  const int y = i / w;
  float acc = 0;
  for (int j = 0; j < 2 * fw + 1; ++j) {
    int xx = x + j - fw;
    xx = (xx < 0) ? 0 : ((xx >= w) ? w - 1 : xx);
    acc += filt[j] * src[y * w + xx];
  }
  dst[i] = acc;
}

__global__ void DogKernel(const float* hi, const float* lo, float* dog, int n) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n) return;
  dog[i] = hi[i] - lo[i];
}

__device__ float Mod2Pi(float x) {
  const float t = 6.283185307179586f;  // 2 * VL_PI, float (VLFeat float cast)
  while (x > t) x -= t;
  while (x < 0) x += t;
  return x;
}

// Gradient magnitude + angle, exact port of VLFeat update_gradient
// (one-sided borders, central interior, angle = mod2pi(atan2(gy,gx)+2pi)).
__global__ void GradKernel(const float* src, int w, int h, float* grad) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= w * h) return;
  const int x = i % w;
  const int y = i / w;
  const float c = src[i];
  const float gx = (x == 0) ? src[i + 1] - c
                   : (x == w - 1)
                       ? c - src[i - 1]
                       : 0.5f * (src[i + 1] - src[i - 1]);
  const float gy = (y == 0) ? src[i + w] - c
                   : (y == h - 1)
                       ? c - src[i - w]
                       : 0.5f * (src[i + w] - src[i - w]);
  grad[2 * i] = sqrtf(gx * gx + gy * gy);
  grad[2 * i + 1] = Mod2Pi(atan2f(gy, gx) + 6.283185307179586f);
}

struct DetIn {
  float x, y, sigma;  // octave units
  int jl;             // gradient level index (si - s_min - 1)
};

struct AngOut {
  int n;
  float a[4];
};

// 36-bin bilinear orientation histogram, port of
// vl_sift_calc_keypoint_orientations (VL_SIFT_BILINEAR_ORIENTATIONS branch).
__global__ void OrientKernel(const float* grad, int w, int h,
                             const DetIn* dets, int ndet, int s_min, int s_max,
                             AngOut* out) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= ndet) return;
  const float x = dets[i].x;
  const float y = dets[i].y;
  const float sigma = dets[i].sigma;
  const int xi = static_cast<int>(x + 0.5f);
  const int yi = static_cast<int>(y + 0.5f);
  const int si = dets[i].jl + s_min + 1;
  if (xi < 0 || xi > w - 1 || yi < 0 || yi > h - 1 || si < s_min + 1 ||
      si > s_max - 2) {
    out[i].n = 0;
    return;
  }
  const float sigmaw = 1.5f * sigma;
  const int W = (static_cast<int>(floorf(3.0f * sigmaw)) > 1)
                    ? static_cast<int>(floorf(3.0f * sigmaw))
                    : 1;
  double hist[36];
  for (int k = 0; k < 36; ++k) hist[k] = 0;
  // grad already points at this detection level's base (jl used for si only).
  const float* g = grad;
  const int xs0 = (-W > -xi) ? -W : -xi;
  const int xs1 = (W < w - 1 - xi) ? W : w - 1 - xi;
  const int ys0 = (-W > -yi) ? -W : -yi;
  const int ys1 = (W < h - 1 - yi) ? W : h - 1 - yi;
  for (int ys = ys0; ys <= ys1; ++ys) {
    for (int xs = xs0; xs <= xs1; ++xs) {
      const double dx = static_cast<double>(xi + xs) - x;
      const double dy = static_cast<double>(yi + ys) - y;
      const double r2 = dx * dx + dy * dy;
      if (r2 >= W * W + 0.6) continue;
      const double wgt = exp(-r2 / (2.0 * sigmaw * sigmaw));
      const double mod = g[(yi + ys) * w * 2 + (xi + xs) * 2];
      const double ang = g[(yi + ys) * w * 2 + (xi + xs) * 2 + 1];
      const double fbin = 36.0 * ang / 6.283185307179586;
      const int bin = static_cast<int>(floor(fbin - 0.5));
      const double rbin = fbin - bin - 0.5;
      hist[(bin + 36) % 36] += (1 - rbin) * mod * wgt;
      hist[(bin + 1) % 36] += rbin * mod * wgt;
    }
  }
  for (int iter = 0; iter < 6; ++iter) {
    double prev = hist[35];
    const double first = hist[0];
    for (int k = 0; k < 35; ++k) {
      const double nh = (prev + hist[k] + hist[k + 1]) / 3.0;
      prev = hist[k];
      hist[k] = nh;
    }
    hist[35] = (prev + hist[35] + first) / 3.0;
  }
  double maxh = 0;
  for (int k = 0; k < 36; ++k) maxh = (maxh > hist[k]) ? maxh : hist[k];
  int n = 0;
  for (int k = 0; k < 36 && n < 4; ++k) {
    const double h0 = hist[k];
    const double hm = hist[(k + 35) % 36];
    const double hp = hist[(k + 1) % 36];
    if (h0 > 0.8 * maxh && h0 > hm && h0 > hp) {
      const double di = -0.5 * (hp - hm) / (hp + hm - 2 * h0);
      out[i].a[n++] =
          static_cast<float>(6.283185307179586 * (k + di + 0.5) / 36.0);
    }
  }
  out[i].n = n;
}

struct OrnIn {
  float x, y, sigma, angle;  // octave units, angle in radians
};

// 4x4x8 descriptor, port of vl_sift_calc_keypoint_descriptor raw loop +
// L2-normalize, truncate at 0.2, normalize again (COLMAP applies L1_ROOT
// afterwards on the host via utils.h, exactly like the CPU path).
__global__ void DescKernel(const float* grad, int w, int h, const OrnIn* keys,
                           int nkeys, float* desc) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= nkeys) return;
  const float x = keys[i].x;
  const float y = keys[i].y;
  const float sigma = keys[i].sigma;
  const float angle0 = keys[i].angle;
  const int xi = static_cast<int>(x + 0.5f);
  const int yi = static_cast<int>(y + 0.5f);
  float* d = desc + static_cast<size_t>(i) * 128;
  if (xi < 0 || xi >= w || yi < 0 || yi >= h - 1) return;  // d stays zeroed
  const double st0 = sin(static_cast<double>(angle0));
  const double ct0 = cos(static_cast<double>(angle0));
  const double sbp = 3.0 * sigma + 2.220446049250313e-16;
  const int W =
      static_cast<int>(floor(1.4142135623730951 * sbp * 5.0 / 2.0 + 0.5));
  const int dxs0 = (-W > 1 - xi) ? -W : 1 - xi;
  const int dxs1 = (W < w - xi - 2) ? W : w - xi - 2;
  const int dys0 = (-W > 1 - yi) ? -W : 1 - yi;
  const int dys1 = (W < h - yi - 2) ? W : h - yi - 2;
  for (int dyi = dys0; dyi <= dys1; ++dyi) {
    for (int dxi = dxs0; dxi <= dxs1; ++dxi) {
      const float mod = grad[(yi + dyi) * w * 2 + (xi + dxi) * 2];
      const float angle = grad[(yi + dyi) * w * 2 + (xi + dxi) * 2 + 1];
      const float theta = Mod2Pi(angle - angle0);
      const float dx = xi + dxi - x;
      const float dy = yi + dyi - y;
      const float nx = static_cast<float>((ct0 * dx + st0 * dy) / sbp);
      const float ny = static_cast<float>((-st0 * dx + ct0 * dy) / sbp);
      const float nt =
          static_cast<float>(8.0 * theta / 6.283185307179586);
      const float win = expf(-(nx * nx + ny * ny) / 8.0f);
      const int binx = static_cast<int>(floorf(nx - 0.5f));
      const int biny = static_cast<int>(floorf(ny - 0.5f));
      const int bint = static_cast<int>(floorf(nt));
      const float rbinx = nx - (binx + 0.5f);
      const float rbiny = ny - (biny + 0.5f);
      const float rbint = nt - bint;
      for (int dbinx = 0; dbinx < 2; ++dbinx) {
        for (int dbiny = 0; dbiny < 2; ++dbiny) {
          for (int dbint = 0; dbint < 2; ++dbint) {
            if (binx + dbinx >= -2 && binx + dbinx < 2 &&
                biny + dbiny >= -2 && biny + dbiny < 2) {
              const float weight =
                  win * mod * fabsf(1 - dbinx - rbinx) *
                  fabsf(1 - dbiny - rbiny) * fabsf(1 - dbint - rbint);
              d[(bint + dbint) % 8 + (biny + dbiny + 2) * 32 +
                (binx + dbinx + 2) * 8] += weight;
            }
          }
        }
      }
    }
  }
  float norm = 1.19209290E-07F;
  for (int k = 0; k < 128; ++k) norm += d[k] * d[k];
  norm = sqrtf(norm);
  for (int k = 0; k < 128; ++k) d[k] /= norm;
  for (int k = 0; k < 128; ++k) d[k] = (d[k] > 0.2f) ? 0.2f : d[k];
  norm = 1.19209290E-07F;
  for (int k = 0; k < 128; ++k) norm += d[k] * d[k];
  norm = sqrtf(norm);
  for (int k = 0; k < 128; ++k) d[k] /= norm;
}

// Gaussian kernel with VLFeat's float rounding (sift.c _vl_sift_smooth).
void GaussianKernel(double sigma, std::vector<float>* filt, int* fw) {
  *fw = std::max(static_cast<int>(std::ceil(4.0 * sigma)), 1);
  filt->resize(2 * (*fw) + 1);
  float acc = 0;
  for (int j = 0; j < 2 * (*fw) + 1; ++j) {
    const float d = static_cast<float>(j - (*fw)) / static_cast<float>(sigma);
    (*filt)[j] = static_cast<float>(std::exp(-0.5 * d * d));
    acc += (*filt)[j];
  }
  for (int j = 0; j < 2 * (*fw) + 1; ++j) (*filt)[j] /= acc;
}

struct RawDetection {
  float x;  // original-image pixels (before +0.5 COLMAP shift)
  float y;
  float sigma;
  int octave;
  int level;  // DoG level s
  int det_idx;  // octave-local detection index (for descriptor gather)
};

// Per-octave oriented expansion + raw float descriptors, gathered globally
// after the tail-scale capping (CPU sift.cc order: cap raw, then orient).
struct OctaveKeep {
  std::vector<std::pair<int, int>> ranges;  // per det_idx: (start row, count)
  std::vector<float> kx, ky, ksig, kang;    // expanded rows, original units
  std::vector<float> fdesc;                 // expanded rows x 128
};

// Small auxiliary device buffers; freed on all paths via dtor.
struct AuxScope {
  std::vector<void*> ptrs;
  ~AuxScope() {
    for (void* p : ptrs) cudaFree(p);
  }
  bool Alloc(void** p, size_t bytes, const char* what) {
    if (cudaMalloc(p, bytes) != cudaSuccess) {
      LOG(WARNING) << "Native GPU SIFT: " << what << " alloc failed";
      return false;
    }
    ptrs.push_back(*p);
    return true;
  }
};

// Byte order permutation from sift.cc TransformVLFeatToUBCFeatureDescriptors.
void ToUBCOrder(const FeatureDescriptorsData& src, FeatureDescriptorsData* dst) {
  static const int q[8] = {0, 7, 6, 5, 4, 3, 2, 1};
  dst->resize(src.rows(), src.cols());
  for (Eigen::Index n = 0; n < src.rows(); ++n)
    for (int i = 0; i < 4; ++i)
      for (int j = 0; j < 4; ++j)
        for (int k = 0; k < 8; ++k)
          (*dst)(n, 8 * (j + 4 * i) + q[k]) = src(n, 8 * (j + 4 * i) + k);
}

// Bounds (never hit on real photos; graceful empty result past them).
constexpr size_t kMaxDetPerOctave = 1 << 20;
constexpr size_t kMaxOrnPerOctave = 1 << 17;
constexpr size_t kAuxBytes = 110 << 20;

// Extrema search + refinement for one octave, exact port of VLFeat
// vl_sift_detect (pre-check 0.8*tp, strict 26-neighborhood, <=5 refinement
// iterations, contrast |val| > tp, Lowe edge score (te+1)^2/te).
void DetectOctave(const std::vector<const float*>& dog, int w,
                  int h, int octave, double xper, double sigma0, int S,
                  double tp, double te, int s_min, int s_max,
                  std::vector<std::vector<RawDetection>>* groups) {
  // Levels are separate host buffers (unlike VLFeat's strided cube), so
  // (dx,dy,ds) access is spelled out explicitly with identical math.
  const auto D = [&](int xx, int yy, int jj) -> double {
    return dog[jj][yy * w + xx];
  };
  for (int s = s_min + 1; s <= s_max - 2; ++s) {
    groups->emplace_back();
    std::vector<RawDetection>& group = groups->back();
    struct Cand {
      int x, y, s;
    };
    std::vector<Cand> cands;
    const float* d0 = dog[s - s_min];
    for (int y = 1; y < h - 1; ++y) {
      for (int x = 1; x < w - 1; ++x) {
        const float v = d0[y * w + x];
        const float* pu = dog[s - 1 - s_min] + y * w + x;
        const float* pl = dog[s + 1 - s_min] + y * w + x;
        bool is_max = (v >= 0.8 * tp);
        if (is_max) {
          const float* pc = d0 + y * w + x;
          const float* q[3] = {pu, pc, pl};
          for (int k = 0; k < 3 && is_max; ++k)
            for (int dy = -1; dy <= 1 && is_max; ++dy)
              for (int dx = -1; dx <= 1 && is_max; ++dx)
                if (dx != 0 || dy != 0 || k != 1)
                  is_max = v > q[k][dy * w + dx];
        }
        bool is_min = (!is_max && v <= -0.8 * tp);
        if (is_min) {
          const float* pc = d0 + y * w + x;
          const float* q[3] = {pu, pc, pl};
          for (int k = 0; k < 3 && is_min; ++k)
            for (int dy = -1; dy <= 1 && is_min; ++dy)
              for (int dx = -1; dx <= 1 && is_min; ++dx)
                if (dx != 0 || dy != 0 || k != 1)
                  is_min = v < q[k][dy * w + dx];
        }
        if (is_max || is_min) cands.push_back({x, y, s});
      }
    }
    for (const Cand& c : cands) {
      int x = c.x, y = c.y, s2 = c.s;
      double Dx = 0, Dy = 0, Ds = 0, Dxx = 0, Dyy = 0, Dss = 0, Dxy = 0,
             Dxs = 0, Dys = 0;
      double b[3] = {0, 0, 0};
      int dx = 0, dy = 0;
      for (int iter = 0; iter < 5; ++iter) {
        x += dx;
        y += dy;
        const int jj = s2 - s_min;
        Dx = 0.5 * (D(x + 1, y, jj) - D(x - 1, y, jj));
        Dy = 0.5 * (D(x, y + 1, jj) - D(x, y - 1, jj));
        Ds = 0.5 * (D(x, y, jj + 1) - D(x, y, jj - 1));
        Dxx = D(x + 1, y, jj) + D(x - 1, y, jj) - 2.0 * D(x, y, jj);
        Dyy = D(x, y + 1, jj) + D(x, y - 1, jj) - 2.0 * D(x, y, jj);
        Dss = D(x, y, jj + 1) + D(x, y, jj - 1) - 2.0 * D(x, y, jj);
        Dxy = 0.25 * (D(x + 1, y + 1, jj) + D(x - 1, y - 1, jj) -
                      D(x - 1, y + 1, jj) - D(x + 1, y - 1, jj));
        Dxs = 0.25 * (D(x + 1, y, jj + 1) + D(x - 1, y, jj - 1) -
                      D(x - 1, y, jj + 1) - D(x + 1, y, jj - 1));
        Dys = 0.25 * (D(x, y + 1, jj + 1) + D(x, y - 1, jj - 1) -
                      D(x, y - 1, jj + 1) - D(x, y + 1, jj - 1));
        // Solve 3x3 with partial-pivot Gauss elimination (VLFeat order).
        double A[9];
        auto Aat = [&](int i, int j) -> double& { return A[i + j * 3]; };
        Aat(0, 0) = Dxx;
        Aat(1, 1) = Dyy;
        Aat(2, 2) = Dss;
        Aat(0, 1) = Aat(1, 0) = Dxy;
        Aat(0, 2) = Aat(2, 0) = Dxs;
        Aat(1, 2) = Aat(2, 1) = Dys;
        b[0] = -Dx;
        b[1] = -Dy;
        b[2] = -Ds;
        for (int j = 0; j < 3; ++j) {
          double maxa = 0, maxabsa = 0;
          int maxi = -1;
          for (int i = j; i < 3; ++i) {
            const double a = Aat(i, j);
            const double absa = std::abs(a);
            if (absa > maxabsa) {
              maxa = a;
              maxabsa = absa;
              maxi = i;
            }
          }
          if (maxabsa < 1e-10f) {
            b[0] = b[1] = b[2] = 0;
            break;
          }
          const int ii = maxi;
          for (int jj = j; jj < 3; ++jj) {
            const double tmp = Aat(ii, jj);
            Aat(ii, jj) = Aat(j, jj);
            Aat(j, jj) = tmp;
            Aat(j, jj) /= maxa;
          }
          double tmp = b[j];
          b[j] = b[ii];
          b[ii] = tmp;
          b[j] /= maxa;
          for (int iii = j + 1; iii < 3; ++iii) {
            const double xx = Aat(iii, j);
            for (int jj = j; jj < 3; ++jj) Aat(iii, jj) -= xx * Aat(j, jj);
            b[iii] -= xx * b[j];
          }
        }
        for (int i = 2; i > 0; --i) {
          const double xx = b[i];
          for (int iii = i - 1; iii >= 0; --iii) b[iii] -= xx * Aat(iii, i);
        }
        dx = ((b[0] > 0.6 && x < w - 2) ? 1 : 0) +
             ((b[0] < -0.6 && x > 1) ? -1 : 0);
        dy = ((b[1] > 0.6 && y < h - 2) ? 1 : 0) +
             ((b[1] < -0.6 && y > 1) ? -1 : 0);
        if (dx == 0 && dy == 0) break;
      }
      const double val = D(x, y, s2 - s_min) +
                         0.5 * (Dx * b[0] + Dy * b[1] + Ds * b[2]);
      const double denom = Dxx * Dyy - Dxy * Dxy;
      const double score =
          denom == 0 ? -1.0 : (Dxx + Dyy) * (Dxx + Dyy) / denom;
      const double xn = x + b[0];
      const double yn = y + b[1];
      const double sn = s2 + b[2];
      const bool good =
          std::abs(val) > tp && score < (te + 1) * (te + 1) / te &&
          score >= 0 && std::abs(b[0]) < 1.5 && std::abs(b[1]) < 1.5 &&
          std::abs(b[2]) < 1.5 && xn >= 0 && xn <= w - 1 && yn >= 0 &&
          yn <= h - 1 && sn >= s_min && sn <= s_max;
      if (good) {
        RawDetection d;
        d.x = static_cast<float>(xn * xper);
        d.y = static_cast<float>(yn * xper);
        d.sigma =
            static_cast<float>(sigma0 * std::pow(2.0, sn / S) * xper);
        d.octave = octave;
        d.level = s2;
        group.push_back(d);
      }
    }
  }
}

// One GPU extraction at a time: the controller spawns an extractor thread per
// CPU thread, and concurrent full-res pyramids would OOM the 2GB card
// (same pattern as sift_gpu_mutexes_ in sift.cc).
std::mutex& ExtractionMutex() {
  static std::mutex mutex;
  return mutex;
}

}  // namespace

NativeGpuSiftExtractor::NativeGpuSiftExtractor(
    const SiftExtractionOptions& options)
    : options_(options) {}

bool NativeGpuSiftExtractor::Extract(const Bitmap& bitmap,
                                     FeatureKeypoints* keypoints,
                                     FeatureDescriptors* descriptors) {
  THROW_CHECK(bitmap.IsGrey());
  THROW_CHECK_NOTNULL(keypoints);
  keypoints->clear();

  const std::lock_guard<std::mutex> gpu_lock(ExtractionMutex());

  const int omin = options_.first_octave;
  const int num_octaves = options_.num_octaves;
  const int S = options_.octave_resolution;
  const double peak_thresh = options_.peak_threshold;
  const double edge_thresh = options_.edge_threshold;
  const int max_num_features = options_.max_num_features;
  const int s_min = kLevelMin;
  const int s_max = S + 1;
  const int num_dogs = s_max - s_min;        // DoG levels per octave (S+2)
  const double sigmak = std::pow(2.0, 1.0 / S);
  const double sigma0 = 1.6 * sigmak;
  const double dsigma0 = sigma0 * std::sqrt(1.0 - 1.0 / (sigmak * sigmak));
  constexpr double sigman = 0.5;

  const int W = bitmap.Width();
  const int H = bitmap.Height();
  if (W <= 0 || H <= 0 || num_octaves <= 0 || S <= 0) {
    LOG(WARNING) << "Native GPU SIFT: invalid image or options";
    return false;
  }

  int dev_count = 0;
  if (cudaGetDeviceCount(&dev_count) != cudaSuccess || dev_count < 1) {
    LOG(WARNING) << "Native GPU SIFT: no CUDA device, skipping image";
    return false;
  }

  // Base octave dimensions from first_octave (VLFeat VL_SHIFT_LEFT).
  int w0 = W, h0 = H;
  if (omin < 0) {
    for (int o = 0; o < -omin; ++o) {
      w0 *= 2;
      h0 *= 2;
    }
  } else if (omin > 0) {
    for (int o = 0; o < omin; ++o) {
      w0 /= 2;
      h0 /= 2;
    }
  }
  if (w0 < 8 || h0 < 8) {
    LOG(WARNING) << "Native GPU SIFT: base octave too small, skipping image";
    return false;
  }

  // One allocation per Extract: input + 5 first-octave-sized slots
  // (blur ring x2, temp, DoG, s_best carry) + S gradient levels x2 floats.
  const size_t oct0px = static_cast<size_t>(w0) * static_cast<size_t>(h0);
  const size_t dev_floats = static_cast<size_t>(W) * static_cast<size_t>(H) +
                            (5 + 2 * static_cast<size_t>(S)) * oct0px;
  size_t free_bytes = 0, total_bytes = 0;
  if (cudaMemGetInfo(&free_bytes, &total_bytes) == cudaSuccess) {
    const size_t need =
        dev_floats * sizeof(float) + kAuxBytes + kVramHeadroomBytes;
    if (need >= free_bytes) {
      LOG(WARNING) << "Native GPU SIFT: image " << W << "x" << H
                   << " needs ~" << (need >> 20)
                   << "MB of VRAM but only " << (free_bytes >> 20)
                   << "MB free, skipping image";
      return false;
    }
  }

  GpuScope gpu;
  NGS_CUDA_OK(cudaStreamCreate(&gpu.stream), "stream create");
  NGS_CUDA_OK(cudaMalloc(&gpu.buffer, dev_floats * sizeof(float)),
              "pyramid alloc");

  float* d_input = gpu.buffer;
  float* d_b0 = d_input + static_cast<size_t>(W) * H;
  float* d_b1 = d_b0 + oct0px;
  float* d_tmp = d_b1 + oct0px;
  float* d_dog = d_tmp + oct0px;
  float* d_prev = d_dog + oct0px;
  float* d_grad = d_prev + oct0px;  // S levels x (mag, angle)
  cudaStream_t st = gpu.stream;

  // Grayscale float 0..1, host-side once (CPU sift.cc pattern).
  std::vector<float> image(static_cast<size_t>(W) * H);
  {
    const std::vector<uint8_t>& data = bitmap.RowMajorData();
    if (data.size() != image.size()) {
      LOG(WARNING) << "Native GPU SIFT: bitmap size mismatch";
      return false;
    }
    for (size_t i = 0; i < image.size(); ++i)
      image[i] = static_cast<float>(data[i]) / 255.0f;
  }
  NGS_CUDA_OK(cudaMemcpyAsync(d_input, image.data(),
                              image.size() * sizeof(float),
                              cudaMemcpyHostToDevice, st),
              "H2D image");
  image.clear();
  image.shrink_to_fit();

  // Worst-case filter taps across base + level smooths (options-driven).
  int filt_taps = 1;
  {
    std::vector<float> tmp;
    int fw = 0;
    GaussianKernel(std::sqrt(std::max(
                       sigma0 * sigma0 * std::pow(sigmak, 2 * s_min) -
                           sigman * sigman * std::pow(2.0, -2 * omin),
                       0.0)),
                   &tmp, &fw);
    filt_taps = std::max(filt_taps, 2 * fw + 1);
    for (int s = s_min + 1; s <= s_max; ++s) {
      GaussianKernel(dsigma0 * std::pow(sigmak, s), &tmp, &fw);
      filt_taps = std::max(filt_taps, 2 * fw + 1);
    }
  }

  // Small device-side filter upload buffer.
  float* d_f = nullptr;
  NGS_CUDA_OK(
      cudaMalloc(&d_f, static_cast<size_t>(filt_taps) * sizeof(float)),
      "filter alloc");
  struct FreeFilt {
    float* p;
    ~FreeFilt() { cudaFree(p); }
  } free_filt{d_f};

  // Auxiliary per-octave buffers (bounds in the header comment block).
  AuxScope aux;
  DetIn* d_det = nullptr;
  AngOut* d_ang = nullptr;
  OrnIn* d_orn = nullptr;
  float* d_desc = nullptr;
  if (!aux.Alloc(reinterpret_cast<void**>(&d_det),
                 kMaxDetPerOctave * sizeof(DetIn), "detections") ||
      !aux.Alloc(reinterpret_cast<void**>(&d_ang),
                 kMaxDetPerOctave * sizeof(AngOut), "angles") ||
      !aux.Alloc(reinterpret_cast<void**>(&d_orn),
                 kMaxOrnPerOctave * sizeof(OrnIn), "oriented") ||
      !aux.Alloc(reinterpret_cast<void**>(&d_desc),
                 kMaxOrnPerOctave * kDescDim * sizeof(float),
                 "descriptors")) {
    return false;
  }

  const int max_num_orientations = options_.max_num_orientations;
  const bool upright = options_.upright;
  const auto normalization = options_.normalization;

  std::vector<float> filt_host;  // reused scratch for Gaussian taps
  auto smooth_in_place = [&](float* img, int w, int h,
                             double sigma) -> bool {
    int fw = 0;
    GaussianKernel(sigma, &filt_host, &fw);
    if (cudaMemcpyAsync(d_f, filt_host.data(),
                        filt_host.size() * sizeof(float),
                        cudaMemcpyHostToDevice, st) != cudaSuccess)
      return false;
    const int n = w * h;
    const int bs = 256;
    const int gs = (n + bs - 1) / bs;
    BlurColKernel<<<gs, bs, 0, st>>>(img, w, h, d_f, fw, d_tmp);
    if (cudaGetLastError() != cudaSuccess) return false;
    BlurRowKernel<<<gs, bs, 0, st>>>(d_tmp, w, h, d_f, fw, img);
    if (cudaGetLastError() != cudaSuccess) return false;
    return true;
  };

  const int s_best = std::min(s_min + S, s_max);
  const int j_best = s_best - s_min;

  std::vector<std::vector<RawDetection>> groups;
  std::vector<OctaveKeep> oct_keeps;
  std::vector<std::vector<float>> host_dogs;
  std::vector<const float*> host_dog_ptrs;

  int w = w0, h = h0;
  // Build first-octave base.
  float* d_base = d_b0;
  if (omin < 0) {
    int cw = W, ch = H;
    float* src = d_input;
    float* dst = d_b1;
    for (int o = 0; o < -omin; ++o) {
      const int w2 = cw * 2, h2 = ch * 2;
      const dim3 bs(16, 16);
      const dim3 gs((w2 + 15) / 16, (h2 + 15) / 16);
      Upsample2xKernel<<<gs, bs, 0, st>>>(src, cw, ch, dst);
      if (cudaGetLastError() != cudaSuccess) {
        LOG(WARNING) << "Native GPU SIFT: upsample failed";
        return false;
      }
      src = dst;
      dst = (dst == d_b1) ? d_b0 : d_b1;
      cw = w2;
      ch = h2;
    }
    d_base = src;
    if (d_base != d_b0) {
      NGS_CUDA_OK(cudaMemcpyAsync(d_b0, d_base,
                                  static_cast<size_t>(w0) * h0 * sizeof(float),
                                  cudaMemcpyDeviceToDevice, st),
                  "base carry");
      d_base = d_b0;
    }
  } else if (omin > 0) {
    int cw = W, ch = H;
    float* src = d_input;
    for (int o = 0; o < omin; ++o) {
      const int w2 = cw / 2, h2 = (ch + 1) / 2;
      const int n = w2 * h2;
      const int bs = 256;
      Downsample2xKernel<<<(n + bs - 1) / bs, bs, 0, st>>>(src, cw, d_b0, n);
      if (cudaGetLastError() != cudaSuccess) {
        LOG(WARNING) << "Native GPU SIFT: downsample failed";
        return false;
      }
      src = d_b0;
      cw = w2;
      ch = h2;
    }
    d_base = d_b0;
  } else {
    NGS_CUDA_OK(cudaMemcpyAsync(d_b0, d_input,
                                static_cast<size_t>(W) * H * sizeof(float),
                                cudaMemcpyDeviceToDevice, st),
                "base copy");
    d_base = d_b0;
  }
  (void)d_base;

  for (int o = 0; o < num_octaves; ++o) {
    const int oct = omin + o;
    if (w < 8 || h < 8) break;
    const size_t px = static_cast<size_t>(w) * h;
    const double xper = std::pow(2.0, oct);

    if (o > 0) {
      // Base = downsample of previous octave's s_best level.
      const int w2 = w / 2, h2 = h / 2;
      if (w2 < 1 || h2 < 1) break;
      const int bs = 256;
      const int n = w2 * h2;
      Downsample2xKernel<<<(n + bs - 1) / bs, bs, 0, st>>>(d_prev, w, d_b0, n);
      NGS_CUDA_OK(cudaGetLastError(), "downsample launch");
      w = w2;
      h = h2;
    }

    // Adjust base smoothing (VLFeat first/next octave logic).
    double sa, sb;
    if (o == 0) {
      sa = sigma0 * std::pow(sigmak, s_min);
      sb = sigman * std::pow(2.0, -omin);
    } else {
      sa = sigma0 * std::pow(sigmak, s_min);
      sb = sigma0 * std::pow(sigmak, s_best - S);
    }
    float* b_prev = d_b0;
    float* b_cur = d_b1;
    if (sa > sb) {
      if (!smooth_in_place(b_prev, w, h, std::sqrt(sa * sa - sb * sb))) {
        LOG(WARNING) << "Native GPU SIFT: base smooth failed";
        return false;
      }
    }

    try {
      host_dogs.assign(num_dogs, std::vector<float>(px));
    } catch (const std::bad_alloc&) {
      LOG(WARNING) << "Native GPU SIFT: host DoG alloc failed";
      return false;
    }

    for (int s = s_min + 1; s <= s_max; ++s) {
      const double sd = dsigma0 * std::pow(sigmak, s);
      int fw = 0;
      GaussianKernel(sd, &filt_host, &fw);
      NGS_CUDA_OK(cudaMemcpyAsync(d_f, filt_host.data(),
                                  filt_host.size() * sizeof(float),
                                  cudaMemcpyHostToDevice, st),
                  "H2D filter");
      const int bs = 256;
      const int gs = (static_cast<int>(px) + bs - 1) / bs;
      BlurColKernel<<<gs, bs, 0, st>>>(b_prev, w, h, d_f, fw, d_tmp);
      NGS_CUDA_OK(cudaGetLastError(), "blur col launch");
      BlurRowKernel<<<gs, bs, 0, st>>>(d_tmp, w, h, d_f, fw, b_cur);
      NGS_CUDA_OK(cudaGetLastError(), "blur row launch");
      DogKernel<<<gs, bs, 0, st>>>(b_cur, b_prev, d_dog,
                                   static_cast<int>(px));
      NGS_CUDA_OK(cudaGetLastError(), "dog launch");
      NGS_CUDA_OK(cudaMemcpyAsync(host_dogs[s - s_min - 1].data(), d_dog,
                                  px * sizeof(float), cudaMemcpyDeviceToHost,
                                  st),
                  "D2H dog");
      if (s - s_min == j_best) {
        NGS_CUDA_OK(cudaMemcpyAsync(d_prev, b_cur, px * sizeof(float),
                                    cudaMemcpyDeviceToDevice, st),
                    "s_best carry");
      }
      if (s >= s_min + 1 && s <= s_max - 2) {
        float* g = d_grad +
                   static_cast<size_t>(s - s_min - 1) * 2 * oct0px;
        GradKernel<<<gs, bs, 0, st>>>(b_cur, w, h, g);
        NGS_CUDA_OK(cudaGetLastError(), "grad launch");
      }
      float* t = b_prev;
      b_prev = b_cur;
      b_cur = t;
    }

    NGS_CUDA_OK(cudaStreamSynchronize(st), "octave sync");
    OctaveKeep keep;
    if (w >= 3 && h >= 3) {
      host_dog_ptrs.resize(host_dogs.size());
      for (size_t i = 0; i < host_dogs.size(); ++i)
        host_dog_ptrs[i] = host_dogs[i].data();
      const size_t gprev = groups.size();
      DetectOctave(host_dog_ptrs, w, h, oct, xper, sigma0, S,
                   peak_thresh, edge_thresh, s_min, s_max, &groups);
      // Octave-local detection order with per-level index lists.
      std::vector<const RawDetection*> order;
      for (size_t g = gprev; g < groups.size(); ++g)
        for (RawDetection& d : groups[g]) {
          d.det_idx = static_cast<int>(order.size());
          order.push_back(&d);
        }
      const size_t ndet = order.size();
      if (ndet > kMaxDetPerOctave) {
        LOG(WARNING) << "Native GPU SIFT: too many detections, skipping image";
        return false;
      }
      std::vector<std::vector<int>> byjl(S);
      for (size_t p = 0; p < ndet; ++p)
        byjl[order[p]->level - s_min - 1].push_back(static_cast<int>(p));
      // Orientations, one level at a time (grad levels are 2*oct0px apart).
      std::vector<AngOut> hang(ndet);
      if (!upright) {
        std::vector<DetIn> din;
        std::vector<AngOut> aout;
        for (int j = 0; j < S; ++j) {
          if (byjl[j].empty()) continue;
          din.clear();
          for (int p : byjl[j]) {
            const RawDetection* d = order[p];
            din.push_back({static_cast<float>(d->x / xper),
                           static_cast<float>(d->y / xper),
                           static_cast<float>(d->sigma / xper), j});
          }
          NGS_CUDA_OK(cudaMemcpyAsync(d_det, din.data(),
                                      din.size() * sizeof(DetIn),
                                      cudaMemcpyHostToDevice, st),
                      "H2D dets");
          const int bs = 128;
          const int gs =
              (static_cast<int>(din.size()) + bs - 1) / bs;
          OrientKernel<<<gs, bs, 0, st>>>(
              d_grad + static_cast<size_t>(j) * 2 * oct0px, w, h, d_det,
              static_cast<int>(din.size()), s_min, s_max, d_ang);
          NGS_CUDA_OK(cudaGetLastError(), "orient launch");
          NGS_CUDA_OK(cudaStreamSynchronize(st), "orient sync");
          aout.resize(din.size());
          NGS_CUDA_OK(cudaMemcpy(aout.data(), d_ang,
                                 aout.size() * sizeof(AngOut),
                                 cudaMemcpyDeviceToHost),
                      "D2H angles");
          for (size_t k = 0; k < byjl[j].size(); ++k)
            hang[byjl[j][k]] = aout[k];
        }
      }
      // Expand orientations (CPU sift.cc: first-K in bin order; fallback 0 so
      // every keypoint gets at least one descriptor).
      keep.ranges.assign(ndet, {0, 0});
      std::vector<OrnIn> orn_all;
      std::vector<int> orn_jl;
      std::vector<std::vector<int>> ornjl(S);
      for (size_t p = 0; p < ndet; ++p) {
        const RawDetection* d = order[p];
        const int jl = d->level - s_min - 1;
        const int st = static_cast<int>(orn_all.size());
        if (upright) {
          orn_all.push_back({static_cast<float>(d->x / xper),
                             static_cast<float>(d->y / xper),
                             static_cast<float>(d->sigma / xper), 0.0f});
        } else {
          int cnt = 0;
          for (int k = 0; k < hang[p].n && cnt < max_num_orientations;
               ++k, ++cnt) {
            orn_all.push_back({static_cast<float>(d->x / xper),
                               static_cast<float>(d->y / xper),
                               static_cast<float>(d->sigma / xper),
                               hang[p].a[k]});
          }
          if (cnt == 0) {
            orn_all.push_back({static_cast<float>(d->x / xper),
                               static_cast<float>(d->y / xper),
                               static_cast<float>(d->sigma / xper), 0.0f});
          }
        }
        for (size_t r = st; r < orn_all.size(); ++r) {
          ornjl[jl].push_back(static_cast<int>(r));
          keep.kx.push_back(d->x);
          keep.ky.push_back(d->y);
          keep.ksig.push_back(d->sigma);
          keep.kang.push_back(orn_all[r].angle);
        }
        keep.ranges[p] = {st, static_cast<int>(orn_all.size()) - st};
      }
      if (descriptors != nullptr && !orn_all.empty()) {
        if (orn_all.size() > kMaxOrnPerOctave) {
          LOG(WARNING) << "Native GPU SIFT: too many orientations, "
                          "skipping image";
          return false;
        }
        keep.fdesc.assign(orn_all.size() * kDescDim, 0.0f);
        std::vector<OrnIn> oslice;
        std::vector<float> dslice;
        for (int j = 0; j < S; ++j) {
          if (ornjl[j].empty()) continue;
          oslice.clear();
          for (int r : ornjl[j]) oslice.push_back(orn_all[r]);
          NGS_CUDA_OK(cudaMemcpyAsync(d_orn, oslice.data(),
                                      oslice.size() * sizeof(OrnIn),
                                      cudaMemcpyHostToDevice, st),
                      "H2D oriented");
          NGS_CUDA_OK(cudaMemsetAsync(d_desc, 0,
                                      oslice.size() * kDescDim * sizeof(float),
                                      st),
                      "zero desc");
          const int bs = 128;
          const int gs =
              (static_cast<int>(oslice.size()) + bs - 1) / bs;
          DescKernel<<<gs, bs, 0, st>>>(
              d_grad + static_cast<size_t>(j) * 2 * oct0px, w, h, d_orn,
              static_cast<int>(oslice.size()), d_desc);
          NGS_CUDA_OK(cudaGetLastError(), "desc launch");
          NGS_CUDA_OK(cudaStreamSynchronize(st), "desc sync");
          dslice.assign(oslice.size() * kDescDim, 0.0f);
          NGS_CUDA_OK(cudaMemcpy(dslice.data(), d_desc,
                                 dslice.size() * sizeof(float),
                                 cudaMemcpyDeviceToHost),
                      "D2H desc");
          for (size_t k = 0; k < ornjl[j].size(); ++k)
            memcpy(&keep.fdesc[static_cast<size_t>(ornjl[j][k]) * kDescDim],
                   &dslice[k * kDescDim], kDescDim * sizeof(float));
        }
      }
    }
    oct_keeps.push_back(std::move(keep));
    host_dogs.clear();
    host_dogs.shrink_to_fit();
  }
  // Keep larger-scale levels first (CPU sift.cc capping rule on raw counts).
  std::vector<size_t> raw_counts(groups.size());
  for (size_t i = 0; i < groups.size(); ++i) raw_counts[i] = groups[i].size();
  size_t first_to_keep = 0;
  if (!groups.empty()) {
    long long acc = 0;
    for (long long i = static_cast<long long>(groups.size()) - 1; i >= 0;
         --i) {
      acc += static_cast<long long>(raw_counts[i]);
      if (acc > max_num_features) {
        first_to_keep = static_cast<size_t>(i);
        break;
      }
    }
  }
  // Gather kept rows across octaves (cap rule unchanged from Task 2).
  std::vector<float> gx, gy, gs, ga, gf;
  for (size_t i = first_to_keep; i < groups.size(); ++i) {
    for (const RawDetection& d : groups[i]) {
      const OctaveKeep& ok = oct_keeps[d.octave - omin];
      const std::pair<int, int>& rg = ok.ranges[d.det_idx];
      for (int r = rg.first; r < rg.first + rg.second; ++r) {
        gx.push_back(ok.kx[r]);
        gy.push_back(ok.ky[r]);
        gs.push_back(ok.ksig[r]);
        ga.push_back(ok.kang[r]);
        if (descriptors != nullptr) {
          gf.insert(gf.end(),
                    ok.fdesc.begin() + static_cast<size_t>(r) * kDescDim,
                    ok.fdesc.begin() + static_cast<size_t>(r + 1) * kDescDim);
        }
      }
    }
  }
  keypoints->clear();
  keypoints->reserve(gx.size());
  for (size_t i = 0; i < gx.size(); ++i)
    keypoints->emplace_back(gx[i] + 0.5f, gy[i] + 0.5f, gs[i], ga[i]);

  if (descriptors != nullptr) {
    THROW_CHECK_EQ(gx.size() * kDescDim, gf.size());
    FeatureDescriptorsFloatData fmat =
        Eigen::Map<FeatureDescriptorsFloatData>(
            gf.data(), static_cast<Eigen::Index>(gx.size()), kDescDim);
    if (normalization == SiftExtractionOptions::Normalization::L2) {
      L2NormalizeFeatureDescriptors(&fmat);
    } else if (normalization ==
               SiftExtractionOptions::Normalization::L1_ROOT) {
      L1RootNormalizeFeatureDescriptors(&fmat);
    } else {
      LOG(FATAL_THROW) << "Normalization type not supported";
    }
    FeatureDescriptorsData ubc;
    ToUBCOrder(FeatureDescriptorsToUnsignedByte(fmat), &ubc);
    descriptors->data = std::move(ubc);
    descriptors->type = FeatureExtractorType::SIFT;
    THROW_CHECK_EQ(keypoints->size(), descriptors->data.rows());
  }
  return true;
}

std::unique_ptr<FeatureExtractor> CreateNativeGpuSiftExtractor(
    const SiftExtractionOptions& options) {
  return std::make_unique<NativeGpuSiftExtractor>(options);
}

}  // namespace colmap
