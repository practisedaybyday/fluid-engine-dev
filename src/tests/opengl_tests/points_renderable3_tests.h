// Copyright (c) 2017 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.

#ifndef SRC_TESTS_OPENGL_TESTS_POINTS_RENDERABLE3_TESTS_H_
#define SRC_TESTS_OPENGL_TESTS_POINTS_RENDERABLE3_TESTS_H_

#include "opengl_tests.h"

class PointsRenderable3Tests final : public OpenGLTests {
 public:
    PointsRenderable3Tests() = default;

    void setup(jet::viz::GlfwWindow* window) override;
};

#endif  // SRC_TESTS_OPENGL_TESTS_POINTS_RENDERABLE3_TESTS_H_
