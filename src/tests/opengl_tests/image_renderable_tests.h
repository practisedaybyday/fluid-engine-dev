// Copyright (c) 2018 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.

#ifndef SRC_TESTS_OPENGL_TESTS_IMAGE_RENDERABLE_TESTS_H_
#define SRC_TESTS_OPENGL_TESTS_IMAGE_RENDERABLE_TESTS_H_

#include "opengl_tests.h"

class ImageRenderableTests final : public OpenGLTests {
 public:
    ImageRenderableTests(bool useOrthoCam);

    void setup(jet::viz::GlfwWindow* window) override;

 private:
    bool _useOrthoCam = true;
};

#endif  // SRC_TESTS_OPENGL_TESTS_IMAGE_RENDERABLE_TESTS_H_
