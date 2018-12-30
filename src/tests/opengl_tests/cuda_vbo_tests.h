// Copyright (c) 2018 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.

#ifndef SRC_TESTS_OPENGL_TESTS_CUDA_VBO_TESTS_H_
#define SRC_TESTS_OPENGL_TESTS_CUDA_VBO_TESTS_H_

#include "opengl_tests.h"

class CudaVboTests final : public OpenGLTests {
 public:
    CudaVboTests() = default;

    void setup(jet::viz::GlfwWindow* window) override;
};

#endif  // SRC_TESTS_OPENGL_TESTS_CUDA_VBO_TESTS_H_
