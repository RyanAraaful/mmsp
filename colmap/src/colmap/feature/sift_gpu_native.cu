// sift_gpu_native.cu — native CUDA SIFT detection (Task 2).
//
// Octave pyramid + DoG run on the GPU (one stream, one device allocation per
// Extract); extrema search + subpixel refinement run on the host as an exact
// port of thirdparty/VLFeat/sift.c vl_sift_detect, so keypoint counts track
// the VLFeat CPU path. Orientation/descriptors arrive in Task 3.
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
};

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

bool DetectOnlySet() {
  const char* v = std::getenv("COLMAP_SIFT_GPU_NATIVE_DETECT_ONLY");
  return v != nullptr && std::string(v) == "1";
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
  // Full orientation + descriptor extraction lands in Task 3.
  if (!DetectOnlySet()) {
    LOG(FATAL) << "Native GPU SIFT extraction not implemented";
    return false;
  }

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
  // (blur ring x2, temp, DoG, s_best carry).
  const size_t oct0px = static_cast<size_t>(w0) * static_cast<size_t>(h0);
  const size_t dev_floats =
      static_cast<size_t>(W) * static_cast<size_t>(H) + 5 * oct0px;
  size_t free_bytes = 0, total_bytes = 0;
  if (cudaMemGetInfo(&free_bytes, &total_bytes) == cudaSuccess) {
    const size_t need = dev_floats * sizeof(float) + kVramHeadroomBytes;
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
      float* t = b_prev;
      b_prev = b_cur;
      b_cur = t;
    }

    NGS_CUDA_OK(cudaStreamSynchronize(st), "octave sync");
    if (w >= 3 && h >= 3) {
      host_dog_ptrs.resize(host_dogs.size());
      for (size_t i = 0; i < host_dogs.size(); ++i)
        host_dog_ptrs[i] = host_dogs[i].data();
      DetectOctave(host_dog_ptrs, w, h, oct, xper, sigma0, S,
                   peak_thresh, edge_thresh, s_min, s_max, &groups);
    }
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
  keypoints->clear();
  for (size_t i = first_to_keep; i < groups.size(); ++i)
    for (const RawDetection& d : groups[i])
      keypoints->emplace_back(d.x + 0.5f, d.y + 0.5f, d.sigma, 0.0f);

  // Detection-only: placeholder descriptors, replaced in Task 3.
  if (descriptors != nullptr) {
    descriptors->data.resize(keypoints->size(), kDescDim);
    descriptors->data.setZero();
    descriptors->type = FeatureExtractorType::SIFT;
  }
  return true;
}

std::unique_ptr<FeatureExtractor> CreateNativeGpuSiftExtractor(
    const SiftExtractionOptions& options) {
  return std::make_unique<NativeGpuSiftExtractor>(options);
}

}  // namespace colmap
