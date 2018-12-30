// Copyright (c) 2018 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.

#include <pch.h>

#include <jet/constants.h>
#include <jet/cuda_sph_kernels3.h>
#include <jet/cuda_utils.h>
#include <jet/cuda_wc_sph_solver3.h>
#include <jet/timer.h>

#include <thrust/fill.h>
#include <thrust/for_each.h>
#include <thrust/tuple.h>

#include <algorithm>

using namespace jet;
using thrust::get;
using thrust::make_tuple;
using thrust::make_zip_iterator;

namespace {

class ComputePressureFunc {
 public:
    inline ComputePressureFunc(float targetDensity, float eosScale,
                               float eosExponent, float negativePressureScale)
        : _targetDensity(targetDensity),
          _eosScale(eosScale),
          _eosExponent(eosExponent),
          _negativePressureScale(negativePressureScale) {}

    template <typename Float>
    inline JET_CUDA_HOST_DEVICE float operator()(Float d) {
        return computePressureFromEos(d, _targetDensity, _eosScale,
                                      _eosExponent, _negativePressureScale);
    }

    template <typename Float>
    inline JET_CUDA_HOST_DEVICE float computePressureFromEos(
        Float density, float targetDensity, float eosScale, float eosExponent,
        float negativePressureScale) {
        // Equation of state
        // (http://www.ifi.uzh.ch/vmml/publications/pcisph/pcisph.pdf)
        float p = eosScale / eosExponent *
                  (powf((density / targetDensity), eosExponent) - 1.0f);

        // Negative pressure scaling
        if (p < 0) {
            p *= negativePressureScale;
        }

        return p;
    }

 private:
    float _targetDensity;
    float _eosScale;
    float _eosExponent;
    float _negativePressureScale;
};

class ComputeForces {
 public:
    inline ComputeForces(float m, float h, float4 gravity, float viscosity,
                         const uint32_t* neighborStarts,
                         const uint32_t* neighborEnds,
                         const uint32_t* neighborLists, const float4* positions,
                         const float4* velocities, float4* smoothedVelocities,
                         float4* forces, const float* densities,
                         const float* pressures)
        : _mass(m),
          _massSquared(m * m),
          _gravity(gravity),
          _viscosity(viscosity),
          _spikyKernel(h),
          _neighborStarts(neighborStarts),
          _neighborEnds(neighborEnds),
          _neighborLists(neighborLists),
          _positions(positions),
          _velocities(velocities),
          _smoothedVelocities(smoothedVelocities),
          _forces(forces),
          _densities(densities),
          _pressures(pressures) {}

    template <typename Index>
    inline JET_CUDA_HOST_DEVICE void operator()(Index i) {
        uint32_t ns = _neighborStarts[i];
        uint32_t ne = _neighborEnds[i];

        float4 x_i = _positions[i];
        float4 v_i = _velocities[i];
        float d_i = _densities[i];
        float p_i = _pressures[i];
        float4 f = _gravity;

        float w_i = _mass / d_i * _spikyKernel(0.0f);
        float weightSum = w_i;
        float4 smoothedVelocity = w_i * v_i;

        for (uint32_t jj = ns; jj < ne; ++jj) {
            uint32_t j = _neighborLists[jj];

            float4 r = _positions[j] - x_i;
            float dist = length(r);

            if (dist > 0.0f) {
                float4 dir = r / dist;

                float4 v_j = _velocities[j];
                float d_j = _densities[j];
                float p_j = _pressures[j];

                // Pressure force
                f -= _massSquared * (p_i / (d_i * d_i) + p_j / (d_j * d_j)) *
                     _spikyKernel.gradient(dist, dir);

                // Viscosity force
                f += _viscosity * _massSquared * (v_j - v_i) / d_j *
                     _spikyKernel.secondDerivative(dist);

                // Pseudo viscosity
                float w_j = _mass / d_j * _spikyKernel(dist);
                weightSum += w_j;
                smoothedVelocity += w_j * v_j;
            }
        }

        _forces[i] = f;

        smoothedVelocity /= weightSum;
        _smoothedVelocities[i] = smoothedVelocity;
    }

 private:
    float _mass;
    float _massSquared;
    float4 _gravity;
    float _viscosity;
    CudaSphSpikyKernel3 _spikyKernel;
    const uint32_t* _neighborStarts;
    const uint32_t* _neighborEnds;
    const uint32_t* _neighborLists;
    const float4* _positions;
    const float4* _velocities;
    float4* _smoothedVelocities;
    float4* _forces;
    const float* _densities;
    const float* _pressures;
};

#define BND_R 0.0f

class TimeIntegration {
 public:
    TimeIntegration(float dt, float m, float smoothFactor, float3 lower,
                    float3 upper, float4* positions, float4* velocities,
                    float4* smoothedVelocities, float4* forces)
        : _dt(dt),
          _mass(m),
          _smoothFactor(smoothFactor),
          _lower(lower),
          _upper(upper),
          _positions(positions),
          _velocities(velocities),
          _smoothedVelocities(smoothedVelocities),
          _forces(forces) {}

    template <typename Index>
    inline JET_CUDA_HOST_DEVICE void operator()(Index i) {
        float4 x = _positions[i];
        float4 v = _velocities[i];
        float4 s = _smoothedVelocities[i];
        float4 f = _forces[i];

        v = (1.0f - _smoothFactor) * v + _smoothFactor * s;
        v += _dt * f / _mass;
        x += _dt * v;

        // TODO: Add proper collider support
        if (x.x > _upper.x) {
            x.x = _upper.x;
            v.x *= BND_R;
        }
        if (x.x < _lower.x) {
            x.x = _lower.x;
            v.x *= BND_R;
        }
        if (x.y > _upper.y) {
            x.y = _upper.y;
            v.y *= BND_R;
        }
        if (x.y < _lower.y) {
            x.y = _lower.y;
            v.y *= BND_R;
        }
        if (x.z > _upper.z) {
            x.z = _upper.z;
            v.z *= BND_R;
        }
        if (x.z < _lower.z) {
            x.z = _lower.z;
            v.z *= BND_R;
        }

        _positions[i] = x;
        _velocities[i] = v;
    }

 private:
    float _dt;
    float _mass;
    float _smoothFactor;
    float3 _lower;
    float3 _upper;
    float4* _positions;
    float4* _velocities;
    float4* _smoothedVelocities;
    float4* _forces;
};

}  // namespace

void CudaWcSphSolver3::onAdvanceTimeStep(double timeStepInSeconds) {
    auto sph = sphSystemData();

    // Build neighbor searcher
    sph->buildNeighborSearcher();
    sph->buildNeighborListsAndUpdateDensities();

    // Compute pressure
    auto d = sph->densities();
    auto p = sph->pressures();
    const float targetDensity = sph->targetDensity();
    const float eosScale =
        targetDensity * square(speedOfSound()) / _eosExponent;
    thrust::transform(
        d.begin(), d.end(), p.begin(),
        ComputePressureFunc(targetDensity, eosScale, eosExponent(),
                            negativePressureScale()));

    // Compute pressure / viscosity forces and smoothed velocity
    size_t n = sph->numberOfParticles();
    float mass = sph->mass();
    float h = sph->kernelRadius();
    auto ns = sph->neighborStarts();
    auto ne = sph->neighborEnds();
    auto nl = sph->neighborLists();
    auto x = sph->positions();
    auto v = sph->velocities();
    auto s = smoothedVelocities();
    auto f = forces();

    thrust::for_each(thrust::counting_iterator<size_t>(0),
                     thrust::counting_iterator<size_t>(n),

                     ComputeForces(mass, h, toFloat4(gravity(), 0.0f),
                                   viscosityCoefficient(), ns.data(), ne.data(),
                                   nl.data(), x.data(), v.data(), s.data(),
                                   f.data(), d.data(), p.data()));

    // Time-integration
    float dt = static_cast<float>(timeStepInSeconds);
    float factor = dt * pseudoViscosityCoefficient();
    factor = clamp(factor, 0.0f, 1.0f);
    auto lower = toFloat3(container().lowerCorner);
    auto upper = toFloat3(container().upperCorner);

    thrust::for_each(thrust::counting_iterator<size_t>(0),
                     thrust::counting_iterator<size_t>(n),

                     TimeIntegration(dt, mass, factor, lower, upper, x.data(),
                                     v.data(), s.data(), f.data()));
}
