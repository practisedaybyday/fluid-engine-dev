// Copyright (c) 2017 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.

#include <pch.h>

#include <jet/constants.h>
#include <jet/cuda_sph_solver3.h>
#include <jet/cuda_utils.h>
#include <jet/timer.h>

#include <thrust/fill.h>
#include <thrust/for_each.h>
#include <thrust/tuple.h>

#include <algorithm>

using namespace jet;
using namespace experimental;
using thrust::get;
using thrust::make_tuple;
using thrust::make_zip_iterator;

static double kTimeStepLimitBySpeedFactor = 0.4;
static double kTimeStepLimitByForceFactor = 0.25;

namespace {

struct CudaSphSpikyKernel3 {
    float h;
    float h2;
    float h3;
    float h4;
    float h5;

    inline JET_CUDA_HOST_DEVICE CudaSphSpikyKernel3(float h_)
        : h(h_), h2(h * h), h3(h2 * h), h4(h2 * h2), h5(h3 * h2) {}

    inline JET_CUDA_HOST_DEVICE float operator()(float distance) const {
        if (distance >= h) {
            return 0.0f;
        } else {
            float x = 1.0f - distance / h;
            return 15.0f / (kPiF * h3) * x * x * x;
        }
    }

    inline JET_CUDA_HOST_DEVICE float firstDerivative(float distance) const {
        if (distance >= h) {
            return 0.0f;
        } else {
            float x = 1.0f - distance / h;
            return -45.0f / (kPiF * h4) * x * x;
        }
    }

    inline JET_CUDA_HOST_DEVICE float4 gradient(float4 point) const {
        float dist = length(point);
        if (dist > 0.0f) {
            return gradient(dist, point / dist);
        } else {
            return make_float4(0, 0, 0, 0);
        }
    }

    inline JET_CUDA_HOST_DEVICE float4
    gradient(float distance, float4 directionToCenter) const {
        return -firstDerivative(distance) * directionToCenter;
    }

    inline JET_CUDA_HOST_DEVICE float secondDerivative(float distance) const {
        if (distance >= h) {
            return 0.0f;
        } else {
            float x = 1.0f - distance / h;
            return 90.0f / (kPiF * h5) * x;
        }
    }
};

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
                         uint32_t* neighborStarts, uint32_t* neighborEnds,
                         uint32_t* neighborLists, float4* positions,
                         float4* velocities, float4* smoothedVelocities,
                         float4* forces, float* densities, float* pressures)
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

        float w_i = _mass / d_i;
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
    uint32_t* _neighborStarts;
    uint32_t* _neighborEnds;
    uint32_t* _neighborLists;
    float4* _positions;
    float4* _velocities;
    float4* _smoothedVelocities;
    float4* _forces;
    float* _densities;
    float* _pressures;
};

#define LOWER_X 0.0f
#define UPPER_X 1.0f
#define LOWER_Y 0.0f
#define UPPER_Y 1.0f
#define LOWER_Z 0.0f
#define UPPER_Z 1.0f
#define BND_R -0.5f

class TimeIntegration {
 public:
    TimeIntegration(float dt, float smoothFactor, float4* positions,
                    float4* velocities, float4* smoothedVelocities,
                    float4* forces)
        : _dt(dt),
          _smoothFactor(smoothFactor),
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
        v += _dt * f;
        x += _dt * v;

        if (x.x > UPPER_X) {
            x.x = UPPER_X;
            v.x *= BND_R;
        }
        if (x.x < LOWER_X) {
            x.x = LOWER_X;
            v.x *= BND_R;
        }
        if (x.y > UPPER_Y) {
            x.y = UPPER_Y;
            v.y *= BND_R;
        }
        if (x.y < LOWER_Y) {
            x.y = LOWER_Y;
            v.y *= BND_R;
        }
        if (x.z > UPPER_Z) {
            x.z = UPPER_Z;
            v.z *= BND_R;
        }
        if (x.z < LOWER_Z) {
            x.z = LOWER_Z;
            v.z *= BND_R;
        }

        _positions[i] = x;
        _velocities[i] = v;
    }

 private:
    float _dt;
    float _smoothFactor;
    float4* _positions;
    float4* _velocities;
    float4* _smoothedVelocities;
    float4* _forces;
};

}  // namespace

CudaSphSolver3::CudaSphSolver3()
    : CudaSphSolver3(static_cast<float>(kWaterDensity), 0.1f, 1.8f) {}

CudaSphSolver3::CudaSphSolver3(float targetDensity, float targetSpacing,
                               float relativeKernelRadius)
    : _targetDensity(targetDensity),
      _targetSpacing(targetSpacing),
      _relativeKernelRadius(relativeKernelRadius) {
    _sphSystemData = std::make_shared<CudaSphSystemData3>();

    _forcesIdx = _sphSystemData->addVectorData();
    _smoothedVelIdx = _sphSystemData->addVectorData();

    setIsUsingFixedSubTimeSteps(false);
}

CudaSphSolver3::~CudaSphSolver3() {}

float CudaSphSolver3::dragCoefficient() const { return _dragCoefficient; }

void CudaSphSolver3::setDragCoefficient(float newDragCoefficient) {
    _dragCoefficient = std::max(newDragCoefficient, 0.0f);
}

float CudaSphSolver3::restitutionCoefficient() const {
    return _restitutionCoefficient;
}

void CudaSphSolver3::setRestitutionCoefficient(
    float newRestitutionCoefficient) {
    _restitutionCoefficient = clamp(newRestitutionCoefficient, 0.0f, 1.0f);
}

const Vector3F& CudaSphSolver3::gravity() const { return _gravity; }

void CudaSphSolver3::setGravity(const Vector3F& newGravity) {
    _gravity = newGravity;
}

float CudaSphSolver3::eosExponent() const { return _eosExponent; }

void CudaSphSolver3::setEosExponent(float newEosExponent) {
    _eosExponent = std::max(newEosExponent, 1.0f);
}

float CudaSphSolver3::negativePressureScale() const {
    return _negativePressureScale;
}

void CudaSphSolver3::setNegativePressureScale(float newNegativePressureScale) {
    _negativePressureScale = clamp(newNegativePressureScale, 0.0f, 1.0f);
}

float CudaSphSolver3::viscosityCoefficient() const {
    return _viscosityCoefficient;
}

void CudaSphSolver3::setViscosityCoefficient(float newViscosityCoefficient) {
    _viscosityCoefficient = std::max(newViscosityCoefficient, 0.0f);
}

float CudaSphSolver3::pseudoViscosityCoefficient() const {
    return _pseudoViscosityCoefficient;
}

void CudaSphSolver3::setPseudoViscosityCoefficient(
    float newPseudoViscosityCoefficient) {
    _pseudoViscosityCoefficient = std::max(newPseudoViscosityCoefficient, 0.0f);
}

float CudaSphSolver3::speedOfSound() const { return _speedOfSound; }

void CudaSphSolver3::setSpeedOfSound(float newSpeedOfSound) {
    _speedOfSound = std::max(newSpeedOfSound, kEpsilonF);
}

float CudaSphSolver3::timeStepLimitScale() const { return _timeStepLimitScale; }

void CudaSphSolver3::setTimeStepLimitScale(float newScale) {
    _timeStepLimitScale = std::max(newScale, 0.0f);
}

CudaSphSystemData3* CudaSphSolver3::particleSystemData() {
    return _sphSystemData.get();
}

const CudaSphSystemData3* CudaSphSolver3::particleSystemData() const {
    return _sphSystemData.get();
}

unsigned int CudaSphSolver3::numberOfSubTimeSteps(
    double timeIntervalInSeconds) const {
    auto particles = particleSystemData();
    size_t numberOfParticles = particles->numberOfParticles();
    // auto f = particles->forces();

    const double kernelRadius = particles->kernelRadius();
    const double mass = particles->mass();

    double maxForceMagnitude = 0.0;

    // for (size_t i = 0; i < numberOfParticles; ++i) {
    //     maxForceMagnitude = std::max(maxForceMagnitude, f[i].length());
    // }
    maxForceMagnitude = kGravity;

    double timeStepLimitBySpeed =
        kTimeStepLimitBySpeedFactor * kernelRadius / _speedOfSound;
    double timeStepLimitByForce =
        kTimeStepLimitByForceFactor *
        std::sqrt(kernelRadius * mass / maxForceMagnitude);

    double desiredTimeStep =
        _timeStepLimitScale *
        std::min(timeStepLimitBySpeed, timeStepLimitByForce);

    return static_cast<unsigned int>(
        std::ceil(timeIntervalInSeconds / desiredTimeStep));
}

void CudaSphSolver3::onInitialize() {
    // When initializing the solver, update the collider and emitter state as
    // well since they also affects the initial condition of the simulation.
    Timer timer;
    updateCollider(0.0f);
    JET_INFO << "Update collider took " << timer.durationInSeconds()
             << " seconds";

    timer.reset();
    updateEmitter(0.0f);
    JET_INFO << "Update emitter took " << timer.durationInSeconds()
             << " seconds";
}

void CudaSphSolver3::onAdvanceTimeStep(double timeStepInSeconds) {
    beginAdvanceTimeStep(timeStepInSeconds);

    // Build neighbor searcher
    _sphSystemData->buildNeighborSearcher();
    _sphSystemData->buildNeighborListsAndUpdateDensities();

    // Compute pressure
    auto d = _sphSystemData->densities();
    auto p = _sphSystemData->pressures();
    const float targetDensity = _sphSystemData->targetDensity();
    const float eosScale = targetDensity * square(_speedOfSound) / _eosExponent;
    thrust::transform(
        d.begin(), d.end(), p.begin(),
        ComputePressureFunc(targetDensity, eosScale, eosExponent(),
                            negativePressureScale()));

    // Compute pressure / viscosity forces and smoothed velocity
    size_t n = _sphSystemData->numberOfParticles();
    float mass = _sphSystemData->mass();
    float h = _sphSystemData->kernelRadius();
    auto ns = _sphSystemData->neighborStarts();
    auto ne = _sphSystemData->neighborEnds();
    auto nl = _sphSystemData->neighborLists();
    auto x = _sphSystemData->positions();
    auto v = _sphSystemData->velocities();
    auto s = _sphSystemData->vectorDataAt(_smoothedVelIdx);
    auto f = _sphSystemData->vectorDataAt(_forcesIdx);

    thrust::for_each(
        thrust::counting_iterator<size_t>(0),
        thrust::counting_iterator<size_t>(n),

        ComputeForces(mass, h, toFloat4(_gravity, 0.0f), viscosityCoefficient(),
                      ns.data(), ne.data(), nl.data(), x.data(), v.data(),
                      s.data(), f.data(), d.data(), p.data()));

    // Time-integration
    float dt = static_cast<float>(timeStepInSeconds);
    float factor = dt * _pseudoViscosityCoefficient;
    factor = clamp(factor, 0.0f, 1.0f);

    thrust::for_each(
        thrust::counting_iterator<size_t>(0),
        thrust::counting_iterator<size_t>(n),

        TimeIntegration(dt, factor, x.data(), v.data(), s.data(), f.data()));

    endAdvanceTimeStep(timeStepInSeconds);
}

void CudaSphSolver3::onBeginAdvanceTimeStep(double timeStepInSeconds) {
    // Update collider and emitter
    Timer timer;
    updateCollider(timeStepInSeconds);
    JET_INFO << "Update collider took " << timer.durationInSeconds()
             << " seconds";

    timer.reset();
    updateEmitter(timeStepInSeconds);
    JET_INFO << "Update emitter took " << timer.durationInSeconds()
             << " seconds";
}

void CudaSphSolver3::onEndAdvanceTimeStep(double timeStepInSeconds) {
    UNUSED_VARIABLE(timeStepInSeconds);
}

void CudaSphSolver3::beginAdvanceTimeStep(double timeStepInSeconds) {
    onBeginAdvanceTimeStep(timeStepInSeconds);
}

void CudaSphSolver3::endAdvanceTimeStep(double timeStepInSeconds) {
    onEndAdvanceTimeStep(timeStepInSeconds);
}

void CudaSphSolver3::updateCollider(double timeStepInSeconds) {
    UNUSED_VARIABLE(timeStepInSeconds);
}

void CudaSphSolver3::updateEmitter(double timeStepInSeconds) {
    UNUSED_VARIABLE(timeStepInSeconds);
}

CudaSphSolver3::Builder CudaSphSolver3::builder() { return Builder(); }

//

CudaSphSolver3::Builder& CudaSphSolver3::Builder::withTargetDensity(
    float targetDensity) {
    _targetDensity = targetDensity;
    return (*this);
}

CudaSphSolver3::Builder& CudaSphSolver3::Builder::withTargetSpacing(
    float targetSpacing) {
    _targetSpacing = targetSpacing;
    return (*this);
}

CudaSphSolver3::Builder& CudaSphSolver3::Builder::withRelativeKernelRadius(
    float relativeKernelRadius) {
    _relativeKernelRadius = relativeKernelRadius;
    return (*this);
}

CudaSphSolver3 CudaSphSolver3::Builder::build() const {
    return CudaSphSolver3(_targetDensity, _targetSpacing,
                          _relativeKernelRadius);
}

CudaSphSolver3Ptr CudaSphSolver3::Builder::makeShared() const {
    return std::shared_ptr<CudaSphSolver3>(
        new CudaSphSolver3(_targetDensity, _targetSpacing,
                           _relativeKernelRadius),
        [](CudaSphSolver3* obj) { delete obj; });
}
