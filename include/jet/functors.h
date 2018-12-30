// Copyright (c) 2018 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.

#ifndef INCLUDE_JET_FUNCTORS_H_
#define INCLUDE_JET_FUNCTORS_H_

#include <functional>

namespace jet {

//! Type casting operator.
template <typename T, typename U>
struct TypeCast {
    constexpr U operator()(const T& a) const;
};

//! Performs std::ceil.
template <typename T>
struct Ceil {
    constexpr T operator()(const T& a) const;
};

//! Performs std::floor.
template <typename T>
struct Floor {
    constexpr T operator()(const T& a) const;
};

//! Reverse minus operator.
template <typename T>
struct RMinus {
    constexpr T operator()(const T& a, const T& b) const;
};

//! Reverse divides operator.
template <typename T>
struct RDivides {
    constexpr T operator()(const T& a, const T& b) const;
};

//! Add-and-assign operator (+=).
template <typename T>
struct IAdd {
    constexpr void operator()(T& a, const T& b) const;
};

//! Subtract-and-assign operator (-=).
template <typename T>
struct ISub {
    constexpr void operator()(T& a, const T& b) const;
};

//! Multiply-and-assign operator (*=).
template <typename T>
struct IMul {
    constexpr void operator()(T& a, const T& b) const;
};

//! Divide-and-assign operator (/=).
template <typename T>
struct IDiv {
    constexpr void operator()(T& a, const T& b) const;
};

//! Takes minimum value.
template <typename T>
struct Min {
    constexpr T operator()(const T& a, const T& b) const;
};

//! Takes maximum value.
template <typename T>
struct Max {
    constexpr T operator()(const T& a, const T& b) const;
};

//! Clamps the input value with low/high.
template <typename T>
struct Clamp {
    constexpr T operator()(const T& a, const T& low, const T& high) const;
};

}  // namespace jet

#include "detail/functors-inl.h"

#endif  // INCLUDE_JET_FUNCTORS_H_
