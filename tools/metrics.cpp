// metrics.cpp — occupancy + outlier-ratio + bidirectional cloud-to-cloud.
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
//
// Task 7a. Single file, C++17, STL only. Usage: metrics.exe <plyA> <plyB> [--pgm <prefix>]
// (exit 0, numbers on stdout; with --pgm also writes <prefix>_A.pgm + <prefix>_B.pgm)
// PLY: binary_little_endian, one vertex element with scalar float x,y,z;
//      any other scalar props and list props are skipped (OpenMVS view lists OK).
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

int typeSize(const std::string& t) {
  if (t == "char" || t == "int8" || t == "uchar" || t == "uint8") return 1;
  if (t == "short" || t == "int16" || t == "ushort" || t == "uint16") return 2;
  if (t == "int" || t == "int32" || t == "uint" || t == "uint32" ||
      t == "float" || t == "float32")
    return 4;
  if (t == "double" || t == "float64" || t == "int64" || t == "uint64") return 8;
  return -1;
}

struct Prop {
  bool isList = false;
  int size = 0;      // scalar byte size
  int cntSize = 0;   // list count byte size
  int elemSize = 0;  // list element byte size
  std::string ctype; // scalar type (for x/y/z read)
};

struct Cloud {
  std::vector<float> xyz;
  size_t n = 0;
};

// Reads whole file, parses header, extracts xyz. Returns false + err on failure.
bool loadPLY(const char* path, Cloud& c, std::string& layout, std::string& err) {
  std::ifstream f(path, std::ios::binary);
  if (!f) {
    err = "cannot open file";
    return false;
  }
  std::string data((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  if (data.size() < 16) {
    err = "file too small";
    return false;
  }
  size_t he = data.find("end_header");
  if (he == std::string::npos) {
    err = "end_header not found";
    return false;
  }
  size_t eol = data.find('\n', he);
  if (eol == std::string::npos) {
    err = "no newline after end_header";
    return false;
  }
  std::string header = data.substr(0, eol);
  std::istringstream hs(header);
  std::string line;
  bool haveFormat = false, isLE = false;
  size_t verts = 0;
  bool inVertex = false, seenVertex = false;
  std::vector<Prop> props;
  int ix = -1, iy = -1, iz = -1;
  std::ostringstream lay;
  while (std::getline(hs, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    std::istringstream ls(line);
    std::string tok;
    ls >> tok;
    if (tok == "format") {
      haveFormat = true;
      std::string fmt;
      ls >> fmt;
      isLE = (fmt == "binary_little_endian");
      lay << "format=" << fmt << " ";
    } else if (tok == "element") {
      std::string name;
      size_t count = 0;
      ls >> name >> count;
      inVertex = (name == "vertex");
      if (inVertex) {
        verts = count;
        seenVertex = true;
        lay << "vertex=" << verts << " ";
      } else {
        err = std::string("unsupported element: ") + name;
        return false;
      }
    } else if (tok == "property" && inVertex) {
      std::string t2;
      ls >> t2;
      Prop p;
      if (t2 == "list") {
        std::string ct, et, nm;
        ls >> ct >> et >> nm;
        p.isList = true;
        p.cntSize = typeSize(ct);
        p.elemSize = typeSize(et);
        if (p.cntSize <= 0 || p.elemSize <= 0) {
          err = "bad list type";
          return false;
        }
        lay << "list<" << ct << "," << et << ">(" << nm << ") ";
      } else {
        std::string nm;
        ls >> nm;
        int s = typeSize(t2);
        if (s <= 0) {
          err = std::string("bad scalar type: ") + t2;
          return false;
        }
        p.size = s;
        p.ctype = t2;
        if (nm == "x") ix = (int)props.size();
        if (nm == "y") iy = (int)props.size();
        if (nm == "z") iz = (int)props.size();
        lay << t2 << "(" << nm << ") ";
      }
      props.push_back(p);
    }
  }
  if (!haveFormat || !isLE) {
    err = "only binary_little_endian supported";
    return false;
  }
  if (!seenVertex || verts == 0) {
    err = "no vertex element";
    return false;
  }
  if (ix < 0 || iy < 0 || iz < 0) {
    err = "missing x/y/z";
    return false;
  }
  for (int k : {ix, iy, iz}) {
    const std::string& t = props[k].ctype;
    if (t != "float" && t != "float32" && t != "double" && t != "float64") {
      err = "x/y/z must be float or double";
      return false;
    }
  }
  layout = lay.str();
  const unsigned char* p = reinterpret_cast<const unsigned char*>(data.data()) + eol + 1;
  const unsigned char* end = reinterpret_cast<const unsigned char*>(data.data()) + data.size();
  c.xyz.resize(verts * 3);
  for (size_t i = 0; i < verts; ++i) {
    double v[3] = {0, 0, 0};
    for (size_t j = 0; j < props.size(); ++j) {
      const Prop& pr = props[j];
      if (!pr.isList) {
        if ((int)j == ix || (int)j == iy || (int)j == iz) {
          if (p + pr.size > end) {
            err = "truncated body";
            return false;
          }
          double d = 0;
          if (pr.size == 4) {
            float fv = 0;
            memcpy(&fv, p, 4);
            d = (double)fv;
          } else {
            memcpy(&d, p, 8);
          }
          p += pr.size;
          if ((int)j == ix) v[0] = d;
          if ((int)j == iy) v[1] = d;
          if ((int)j == iz) v[2] = d;
        } else {
          if (p + pr.size > end) {
            err = "truncated body";
            return false;
          }
          p += pr.size;
        }
      } else {
        if (p + pr.cntSize > end) {
          err = "truncated list count";
          return false;
        }
        uint64_t cnt = 0;
        memcpy(&cnt, p, pr.cntSize);
        if (pr.cntSize < 8) cnt &= (pr.cntSize == 4 ? 0xFFFFFFFFULL : (pr.cntSize == 2 ? 0xFFFFULL : 0xFFULL));
        p += pr.cntSize;
        uint64_t skip = cnt * (uint64_t)pr.elemSize;
        if (p + skip > end) {
          err = "truncated list data";
          return false;
        }
        p += skip;
      }
    }
    c.xyz[i * 3 + 0] = (float)v[0];
    c.xyz[i * 3 + 1] = (float)v[1];
    c.xyz[i * 3 + 2] = (float)v[2];
  }
  c.n = verts;
  return true;
}

const int64_t CELL_BIAS = (1 << 20);
const int64_t CELL_MAX = (1 << 21) - 1;

inline uint64_t packCell(int64_t ix, int64_t iy, int64_t iz) {
  return ((uint64_t)(ix + CELL_BIAS) << 42) | ((uint64_t)(iy + CELL_BIAS) << 21) |
         (uint64_t)(iz + CELL_BIAS);
}

// Sort-based voxel index: O(1) memory overhead beyond keys+order, binary search per cell.
struct NNIndex {
  std::vector<uint64_t> sk; // sorted cell keys
  std::vector<uint32_t> ord; // sk[i] belongs to point ord[i]
  const float* pts = nullptr;
  double vs = 0.25, ox = 0, oy = 0, oz = 0;

  bool build(const float* p, size_t n, double voxel, double x0, double y0, double z0) {
    pts = p;
    vs = voxel;
    ox = x0;
    oy = y0;
    oz = z0;
    std::vector<uint64_t> keys(n);
    for (size_t i = 0; i < n; ++i) {
      int64_t cx = (int64_t)floor(((double)p[i * 3 + 0] - ox) / vs);
      int64_t cy = (int64_t)floor(((double)p[i * 3 + 1] - oy) / vs);
      int64_t cz = (int64_t)floor(((double)p[i * 3 + 2] - oz) / vs);
      if (cx + CELL_BIAS < 0 || cx + CELL_BIAS > CELL_MAX || cy + CELL_BIAS < 0 ||
          cy + CELL_BIAS > CELL_MAX || cz + CELL_BIAS < 0 || cz + CELL_BIAS > CELL_MAX)
        return false;
      keys[i] = packCell(cx, cy, cz);
    }
    ord.resize(n);
    for (size_t i = 0; i < n; ++i) ord[i] = (uint32_t)i;
    std::sort(ord.begin(), ord.end(), [&](uint32_t a, uint32_t b) { return keys[a] < keys[b]; });
    sk.resize(n);
    for (size_t i = 0; i < n; ++i) sk[i] = keys[ord[i]];
    return true;
  }

  // k smallest distances (k or fewer if cloud too sparse within Hmax rings).
  // skipIdx: point index to exclude (self); use UINT32_MAX for none.
  void queryKN(double qx, double qy, double qz, int k, uint32_t skipIdx, int hmax,
               std::vector<double>& out) const {
    out.clear();
    int64_t cx = (int64_t)floor((qx - ox) / vs);
    int64_t cy = (int64_t)floor((qy - oy) / vs);
    int64_t cz = (int64_t)floor((qz - oz) / vs);
    std::vector<std::pair<double, uint32_t>> cand;
    cand.reserve(256);
    for (int h = 1; h <= hmax; ++h) {
      size_t before = cand.size();
      for (int64_t dz = -h; dz <= h; ++dz)
        for (int64_t dy = -h; dy <= h; ++dy)
          for (int64_t dx = -h; dx <= h; ++dx) {
            int64_t m = std::max(std::max(std::llabs(dx), std::llabs(dy)), std::llabs(dz));
            if (m != h) continue; // shell only (h==1 covers the 27-cell cube)
            uint64_t key = packCell(cx + dx, cy + dy, cz + dz);
            auto r = std::equal_range(sk.begin(), sk.end(), key);
            for (auto it = r.first; it != r.second; ++it) {
              uint32_t idx = ord[it - sk.begin()];
              if (idx == skipIdx) continue;
              double ddx = (double)pts[idx * 3 + 0] - qx;
              double ddy = (double)pts[idx * 3 + 1] - qy;
              double ddz = (double)pts[idx * 3 + 2] - qz;
              cand.emplace_back(ddx * ddx + ddy * ddy + ddz * ddz, idx);
            }
          }
      if ((int)cand.size() >= k) break;
      (void)before;
    }
    size_t take = std::min(cand.size(), (size_t)k);
    if (take == 0) return;
    std::nth_element(cand.begin(), cand.begin() + take - 1, cand.end(),
                     [](const auto& a, const auto& b) { return a.first < b.first; });
    out.resize(take);
    for (size_t i = 0; i < take; ++i) out[i] = sqrt(cand[i].first);
    std::sort(out.begin(), out.end());
  }
};

double medianOf(std::vector<double> v) {
  if (v.empty()) return 0;
  size_t n = v.size();
  std::nth_element(v.begin(), v.begin() + n / 2, v.end());
  double m = v[n / 2];
  if (n % 2 == 0) {
    std::nth_element(v.begin(), v.begin() + n / 2 - 1, v.end());
    m = 0.5 * (m + v[n / 2 - 1]);
  }
  return m;
}

void bboxOf(const Cloud& c, double& x0, double& y0, double& z0, double& x1, double& y1,
            double& z1) {
  x0 = y0 = z0 = 1e30;
  x1 = y1 = z1 = -1e30;
  for (size_t i = 0; i < c.n; ++i) {
    double x = c.xyz[i * 3 + 0], y = c.xyz[i * 3 + 1], z = c.xyz[i * 3 + 2];
    if (x < x0) x0 = x;
    if (y < y0) y0 = y;
    if (z < z0) z0 = z;
    if (x > x1) x1 = x;
    if (y > y1) y1 = y;
    if (z > z1) z1 = z;
  }
}

} // namespace

int main(int argc, char** argv) {
  std::string pgmPrefix;
  if (argc == 3) {
  } else if (argc == 5 && std::string(argv[3]) == "--pgm") {
    pgmPrefix = argv[4];
  } else {
    std::cerr << "usage: metrics.exe <plyA> <plyB> [--pgm <prefix>]\n";
    return 2;
  }
  auto t0 = std::chrono::steady_clock::now();
  auto secs = [&]() {
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  };

  const double OCC = 0.5;   // occupancy cell (m)
  const double VOX = 0.25;  // NN voxel (m)
  const size_t NS = 50000;  // sample size per cloud
  const int KNN = 8;        // outlier kNN order

  Cloud A, B;
  std::string layA, layB, err;
  if (!loadPLY(argv[1], A, layA, err)) {
    std::cerr << "A: " << err << "\n";
    return 1;
  }
  printf("load_A_sec %.1f\n", secs());
  if (!loadPLY(argv[2], B, layB, err)) {
    std::cerr << "B: " << err << "\n";
    return 1;
  }
  printf("load_B_sec %.1f\n", secs());
  printf("points_A %llu\n", (unsigned long long)A.n);
  printf("points_B %llu\n", (unsigned long long)B.n);
  printf("layout_A %s\n", layA.c_str());
  printf("layout_B %s\n", layB.c_str());

  // Union bbox.
  double ax0, ay0, az0, ax1, ay1, az1, bx0, by0, bz0, bx1, by1, bz1;
  bboxOf(A, ax0, ay0, az0, ax1, ay1, az1);
  bboxOf(B, bx0, by0, bz0, bx1, by1, bz1);
  double ux0 = std::min(ax0, bx0), uy0 = std::min(ay0, by0), uz0 = std::min(az0, bz0);
  double ux1 = std::max(ax1, bx1), uy1 = std::max(ay1, by1), uz1 = std::max(az1, bz1);
  printf("bbox_union_min %.3f %.3f %.3f\n", ux0, uy0, uz0);
  printf("bbox_union_max %.3f %.3f %.3f\n", ux1, uy1, uz1);
  printf("bbox_A_min %.3f %.3f %.3f\n", ax0, ay0, az0);
  printf("bbox_A_max %.3f %.3f %.3f\n", ax1, ay1, az1);
  printf("bbox_B_min %.3f %.3f %.3f\n", bx0, by0, bz0);
  printf("bbox_B_max %.3f %.3f %.3f\n", bx1, by1, bz1);

  // Occupancy: sorted-unique cell keys per cloud + two-pointer set ops.
  // Keep full per-point keys too, to count how many points sit in shared vs halo cells.
  auto cellKeysFull = [&](const Cloud& c, double vs) {
    std::vector<uint64_t> k(c.n);
    for (size_t i = 0; i < c.n; ++i)
      k[i] = packCell((int64_t)floor(((double)c.xyz[i * 3 + 0] - ux0) / vs),
                      (int64_t)floor(((double)c.xyz[i * 3 + 1] - uy0) / vs),
                      (int64_t)floor(((double)c.xyz[i * 3 + 2] - uz0) / vs));
    std::sort(k.begin(), k.end());
    return k;
  };
  std::vector<uint64_t> fa = cellKeysFull(A, OCC), fb = cellKeysFull(B, OCC);
  std::vector<uint64_t> ka = fa, kb = fb;
  ka.erase(std::unique(ka.begin(), ka.end()), ka.end());
  kb.erase(std::unique(kb.begin(), kb.end()), kb.end());
  size_t i = 0, j = 0, both = 0;
  while (i < ka.size() && j < kb.size()) {
    if (ka[i] == kb[j]) {
      ++both;
      ++i;
      ++j;
    } else if (ka[i] < kb[j])
      ++i;
    else
      ++j;
  }
  size_t onlyA = ka.size() - both, onlyB = kb.size() - both;
  size_t uni = ka.size() + kb.size() - both;
  printf("occupancy_cell_m %.2f\n", OCC);
  printf("cells_A %llu\n", (unsigned long long)ka.size());
  printf("cells_B %llu\n", (unsigned long long)kb.size());
  printf("cells_onlyA %llu\n", (unsigned long long)onlyA);
  printf("cells_onlyB %llu\n", (unsigned long long)onlyB);
  printf("cells_both %llu\n", (unsigned long long)both);
  printf("cells_union %llu\n", (unsigned long long)uni);
  printf("fill_jaccard %.6f\n", uni ? (double)both / (double)uni : 0);
  printf("coverage_A_of_B %.6f\n", kb.size() ? (double)both / (double)kb.size() : 0);
  printf("coverage_B_of_A %.6f\n", ka.size() ? (double)both / (double)ka.size() : 0);
  // Points of each cloud falling in cells shared with the other cloud (two-pointer
  // over sorted full key arrays; duplicates in fa/fb count individually).
  auto sharedPts = [](const std::vector<uint64_t>& full,
                      const std::vector<uint64_t>& otherUniq) {
    size_t p = 0, q = 0, cnt = 0;
    while (p < full.size() && q < otherUniq.size()) {
      if (full[p] == otherUniq[q]) {
        ++cnt;
        ++p;
      } else if (full[p] < otherUniq[q])
        ++p;
      else
        ++q;
    }
    return cnt;
  };
  size_t ptsAshared = sharedPts(fa, kb), ptsBshared = sharedPts(fb, ka);
  printf("points_A_in_shared %.6f\n", A.n ? (double)ptsAshared / (double)A.n : 0);
  printf("points_B_in_shared %.6f\n", B.n ? (double)ptsBshared / (double)B.n : 0);
  printf("occupancy_sec %.1f\n", secs());
  // Nadir hole-map: top-down (x-y) projection of the same 0.5 m union-bbox cells.
  // Identical dimensions for A and B by construction (shared union bbox).
  if (!pgmPrefix.empty()) {
    int64_t nx = (int64_t)floor((ux1 - ux0) / OCC) + 1;
    int64_t ny = (int64_t)floor((uy1 - uy0) / OCC) + 1;
    if (nx < 1 || ny < 1 || nx > 20000 || ny > 20000 || nx * ny > 250000000) {
      std::cerr << "pgm dimensions out of range\n";
      return 1;
    }
    auto writePGM = [&](const Cloud& c, const std::string& path) {
      std::vector<unsigned char> img((size_t)nx * (size_t)ny, 0);
      for (size_t k = 0; k < c.n; ++k) {
        int64_t col = (int64_t)floor(((double)c.xyz[k * 3 + 0] - ux0) / OCC);
        int64_t row = (int64_t)floor((uy1 - (double)c.xyz[k * 3 + 1]) / OCC); // row 0 = max y
        if (col < 0 || col >= nx || row < 0 || row >= ny) continue;
        img[(size_t)row * (size_t)nx + (size_t)col] = 255; // filled = white
      }
      std::ofstream o(path, std::ios::binary);
      if (!o) return false;
      o << "P5\n" << nx << " " << ny << "\n255\n";
      o.write(reinterpret_cast<const char*>(img.data()), (std::streamsize)img.size());
      o.close();
      return (bool)o;
    };
    std::string pa = pgmPrefix + "_A.pgm", pb = pgmPrefix + "_B.pgm";
    if (!writePGM(A, pa) || !writePGM(B, pb)) {
      std::cerr << "pgm write failed\n";
      return 1;
    }
    printf("pgm_A %s %lld %lld\n", pa.c_str(), (long long)nx, (long long)ny);
    printf("pgm_B %s %lld %lld\n", pb.c_str(), (long long)nx, (long long)ny);
  }
  ka.clear();
  ka.shrink_to_fit();
  kb.clear();
  kb.shrink_to_fit();

  // Deterministic stride samples (no RNG: fixed stride => fixed seed by construction).
  size_t nAS = std::min(NS, A.n), nBS = std::min(NS, B.n);
  size_t stA = A.n / nAS, stB = B.n / nBS;
  if (stA < 1) stA = 1;
  if (stB < 1) stB = 1;
  printf("sample_A %llu stride %llu\n", (unsigned long long)nAS, (unsigned long long)stA);
  printf("sample_B %llu stride %llu\n", (unsigned long long)nBS, (unsigned long long)stB);
  std::vector<float> sA(nAS * 3), sB(nBS * 3);
  for (size_t s = 0; s < nAS; ++s)
    for (int d = 0; d < 3; ++d) sA[s * 3 + d] = A.xyz[(s * stA) * 3 + d];
  for (size_t s = 0; s < nBS; ++s)
    for (int d = 0; d < 3; ++d) sB[s * 3 + d] = B.xyz[(s * stB) * 3 + d];

  // Outlier ratio per cloud: 8th-NN distance within own sample; outlier if > median+3*MAD.
  auto outlier = [&](const float* s, size_t ns, const char* tag) {
    NNIndex idx;
    if (!idx.build(s, ns, VOX, ux0, uy0, uz0)) {
      std::cerr << "cell range overflow\n";
      exit(1);
    }
    const double INF = 1e30;
    std::vector<double> d8(ns);
    std::vector<double> q;
    for (size_t s2 = 0; s2 < ns; ++s2) {
      idx.queryKN(s[s2 * 3 + 0], s[s2 * 3 + 1], s[s2 * 3 + 2], KNN, (uint32_t)s2, 8, q);
      d8[s2] = (q.size() >= (size_t)KNN) ? q[KNN - 1] : INF; // too isolated => outlier
    }
    double med = medianOf(d8);
    std::vector<double> dev(d8.size());
    for (size_t k = 0; k < d8.size(); ++k) dev[k] = fabs(d8[k] - med);
    double mad = medianOf(dev);
    double thr = med + 3.0 * mad;
    size_t no = 0;
    for (double v : d8)
      if (v > thr) ++no;
    printf("outlier_%s_median %.6f\n", tag, med);
    printf("outlier_%s_mad %.6f\n", tag, mad);
    printf("outlier_%s_thr %.6f\n", tag, thr);
    printf("outlier_%s_ratio %.6f\n", tag, (double)no / (double)ns);
  };
  outlier(sA.data(), nAS, "A");
  printf("outlier_A_sec %.1f\n", secs());
  outlier(sB.data(), nBS, "B");
  printf("outlier_B_sec %.1f\n", secs());

  // Bidirectional cloud-to-cloud: sample->full cloud NN (0.25 m voxels, 27-cell + expansion).
  auto c2c = [&](const float* s, size_t ns, const Cloud& ref, const char* tag) {
    NNIndex idx;
    if (!idx.build(ref.xyz.data(), ref.n, VOX, ux0, uy0, uz0)) {
      std::cerr << "cell range overflow\n";
      exit(1);
    }
    std::vector<double> d;
    d.reserve(ns);
    size_t missing = 0;
    std::vector<double> q;
    for (size_t s2 = 0; s2 < ns; ++s2) {
      idx.queryKN(s[s2 * 3 + 0], s[s2 * 3 + 1], s[s2 * 3 + 2], 1, UINT32_MAX, 4, q);
      if (q.empty())
        ++missing;
      else
        d.push_back(q[0]);
    }
    std::sort(d.begin(), d.end());
    double mean = 0;
    for (double v : d) mean += v;
    if (!d.empty()) mean /= (double)d.size();
    double med = d.empty() ? 0 : d[d.size() / 2];
    double p90 = d.empty() ? 0 : d[std::min(d.size() - 1, (size_t)(0.9 * d.size()))];
    printf("c2c_%s_found %llu missing %llu\n", tag, (unsigned long long)d.size(),
           (unsigned long long)missing);
    printf("c2c_%s_mean %.6f\n", tag, mean);
    printf("c2c_%s_median %.6f\n", tag, med);
    printf("c2c_%s_p90 %.6f\n", tag, p90);
  };
  c2c(sA.data(), nAS, B, "AtoB");
  printf("c2c_AtoB_sec %.1f\n", secs());
  c2c(sB.data(), nBS, A, "BtoA");
  printf("c2c_BtoA_sec %.1f\n", secs());

  printf("total_sec %.1f\n", secs());
  return 0;
}
