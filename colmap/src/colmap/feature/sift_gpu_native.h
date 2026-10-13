// sift_gpu_native.h — native CUDA SIFT extractor (Task 2: detection).
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

#pragma once

#include "colmap/feature/extractor.h"
#include "colmap/feature/sift.h"

namespace colmap {

// Native CUDA SIFT feature extractor (Apache-2.0, zero new dependencies).
// Task 3: GPU octave pyramid + DoG + gradients, host extrema ported from
// VLFeat, GPU 36-bin orientation + 4x4x8 descriptors with L1_ROOT uint8
// output matching the CPU path format.
class NativeGpuSiftExtractor : public FeatureExtractor {
 public:
  explicit NativeGpuSiftExtractor(const SiftExtractionOptions& options);
  bool Extract(const Bitmap& bitmap,
               FeatureKeypoints* keypoints,
               FeatureDescriptors* descriptors) override;

 private:
  SiftExtractionOptions options_;
};

}  // namespace colmap
