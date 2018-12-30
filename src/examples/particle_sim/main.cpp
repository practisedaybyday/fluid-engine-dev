// Copyright (c) 2018 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.

#include <example_app.h>

#include <jet/jet.h>

using namespace jet;

int main(int, const char**) {
    Logging::mute();

    ExampleApp::initialize("Particle Sim", 1280, 720);
    ExampleApp::run();
    ExampleApp::finalize();

    return 0;
}
