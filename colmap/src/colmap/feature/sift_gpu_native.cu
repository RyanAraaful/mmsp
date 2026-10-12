// sift_gpu_native.cu — native CUDA SIFT extractor stub (Task 1).
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

namespace colmap {

NativeGpuSiftExtractor::NativeGpuSiftExtractor(
    const SiftExtractionOptions& /*options*/) {}

bool NativeGpuSiftExtractor::Extract(const Bitmap& /*bitmap*/,
                                     FeatureKeypoints* /*keypoints*/,
                                     FeatureDescriptors* /*descriptors*/) {
  LOG(FATAL) << "Native GPU SIFT extraction not implemented";
  return false;
}

std::unique_ptr<FeatureExtractor> CreateNativeGpuSiftExtractor(
    const SiftExtractionOptions& options) {
  return std::make_unique<NativeGpuSiftExtractor>(options);
}

}  // namespace colmap
