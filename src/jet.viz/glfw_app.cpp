// Copyright (c) 2017 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.

#include <pch.h>

#ifdef JET_USE_GL

#include <jet.viz/glfw_app.h>
#include <jet.viz/glfw_window.h>

using namespace jet;
using namespace viz;

namespace {

std::vector<GlfwWindowPtr> sWindows;
GlfwWindowPtr sCurrentWindow;

Event<GLFWwindow*, int, int, int, int> sOnBeginGlfwKeyEvent;
Event<GLFWwindow*, int, int, int> sOnBeginGlfwMouseButtonEvent;
Event<GLFWwindow*, double, double> sOnBeginGlfwMouseCursorPosEvent;
Event<GLFWwindow*, int> sOnBeginGlfwMouseCursorEnterEvent;
Event<GLFWwindow*, double, double> sOnBeginGlfwMouseScrollEvent;
Event<GLFWwindow*, unsigned int> sOnBeginGlfwCharEvent;
Event<GLFWwindow*, unsigned int, int> sOnBeginGlfwCharModsEvent;
Event<GLFWwindow*, int, const char**> sOnBeginGlfwDropEvent;

}  // namespace

int GlfwApp::initialize() {
    glfwSetErrorCallback(onErrorEvent);

    if (!glfwInit()) {
        return -1;
    }

    // Use OpenGL 3.3
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
#ifdef JET_MACOSX
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

    return 0;
}

int GlfwApp::run() {
    // Force render first frame
    if (sCurrentWindow != nullptr) {
        sCurrentWindow->requestRender();
    }

    while (sCurrentWindow != nullptr) {
        glfwWaitEvents();

        auto window = sCurrentWindow->glfwWindow();

        if (sCurrentWindow->isAnimationEnabled() ||
            sCurrentWindow->_numRequestedRenderFrames > 0) {
            int width, height;
            glfwGetFramebufferSize(window, &width, &height);
            sCurrentWindow->resize(width, height);

            if (sCurrentWindow->isAnimationEnabled()) {
                sCurrentWindow->update();
            }

            sCurrentWindow->render();

            // Decrease render request count
            sCurrentWindow->_numRequestedRenderFrames -= 1;

            if (sCurrentWindow->isAnimationEnabled()) {
                glfwPostEmptyEvent();
            }

            glfwSwapBuffers(sCurrentWindow->glfwWindow());
        }

        if (glfwWindowShouldClose(window)) {
            onCloseCurrentWindow(sCurrentWindow);
        }
    }

    glfwTerminate();

    return 0;
}

GlfwWindowPtr GlfwApp::createWindow(const std::string& title, int width,
                                    int height) {
    sCurrentWindow = GlfwWindowPtr(new GlfwWindow(title, width, height));
    sWindows.push_back(sCurrentWindow);

    auto glfwWindow = sCurrentWindow->glfwWindow();

    glfwSetKeyCallback(glfwWindow, onKey);
    glfwSetMouseButtonCallback(glfwWindow, onMouseButton);
    glfwSetCursorPosCallback(glfwWindow, onMouseCursorPos);
    glfwSetCursorEnterCallback(glfwWindow, onMouseCursorEnter);
    glfwSetScrollCallback(glfwWindow, onMouseScroll);
    glfwSetCharCallback(glfwWindow, onChar);
    glfwSetCharModsCallback(glfwWindow, onCharMods);
    glfwSetDropCallback(glfwWindow, onDrop);

    return sCurrentWindow;
}

GlfwWindowPtr GlfwApp::findWindow(GLFWwindow* glfwWindow) {
    for (auto w : sWindows) {
        if (w->glfwWindow() == glfwWindow) {
            return w;
        }
    }

    return nullptr;
}

Event<GLFWwindow*, int, int, int, int>& GlfwApp::onBeginGlfwKeyEvent() {
    return sOnBeginGlfwKeyEvent;
}

Event<GLFWwindow*, int, int, int>& GlfwApp::onBeginGlfwMouseButtonEvent() {
    return sOnBeginGlfwMouseButtonEvent;
}

Event<GLFWwindow*, double, double>& GlfwApp::onBeginGlfwMouseCursorPosEvent() {
    return sOnBeginGlfwMouseCursorPosEvent;
}

Event<GLFWwindow*, int>& GlfwApp::onBeginGlfwMouseCursorEnterEvent() {
    return sOnBeginGlfwMouseCursorEnterEvent;
}

Event<GLFWwindow*, double, double>& GlfwApp::onBeginGlfwMouseScrollEvent() {
    return sOnBeginGlfwMouseScrollEvent;
}

Event<GLFWwindow*, unsigned int>& GlfwApp::onBeginGlfwCharEvent() {
    return sOnBeginGlfwCharEvent;
}

Event<GLFWwindow*, unsigned int, int>& GlfwApp::onBeginGlfwCharModsEvent() {
    return sOnBeginGlfwCharModsEvent;
}

Event<GLFWwindow*, int, const char**>& GlfwApp::onBeginGlfwDropEvent() {
    return sOnBeginGlfwDropEvent;
}

void GlfwApp::onSetCurrentWindow(const GlfwWindowPtr& window) {
    assert(std::find(sWindows.begin(), sWindows.end(), window) !=
           sWindows.end());

    sCurrentWindow = window;
}

void GlfwApp::onCloseCurrentWindow(const GlfwWindowPtr& window) {
    auto it = std::find(sWindows.begin(), sWindows.end(), window);
    sWindows.erase(it);

    if (sCurrentWindow == window) {
        sCurrentWindow.reset();

        if (!sWindows.empty()) {
            sCurrentWindow = *sWindows.rbegin();
        }
    }
}

void GlfwApp::onKey(GLFWwindow* glfwWindow, int key, int scancode, int action,
                    int mods) {
    GlfwWindowPtr window = findWindow(glfwWindow);
    assert(window != nullptr);
    window->requestRender();

    bool handled =
        sOnBeginGlfwKeyEvent(glfwWindow, key, scancode, action, mods);
    if (handled) {
        return;
    }

    window->key(key, scancode, action, mods);
}

void GlfwApp::onMouseButton(GLFWwindow* glfwWindow, int button, int action,
                            int mods) {
    GlfwWindowPtr window = findWindow(glfwWindow);
    assert(window != nullptr);
    window->requestRender();

    bool handled =
        sOnBeginGlfwMouseButtonEvent(glfwWindow, button, action, mods);
    if (handled) {
        return;
    }

    window->pointerButton(button, action, mods);
}

void GlfwApp::onMouseCursorEnter(GLFWwindow* glfwWindow, int entered) {
    GlfwWindowPtr window = findWindow(glfwWindow);
    assert(window != nullptr);
    window->requestRender();

    bool handled = sOnBeginGlfwMouseCursorEnterEvent(glfwWindow, entered);
    if (handled) {
        return;
    }

    window->pointerEnter(entered == GL_TRUE);
}

void GlfwApp::onMouseCursorPos(GLFWwindow* glfwWindow, double x, double y) {
    GlfwWindowPtr window = findWindow(glfwWindow);
    assert(window != nullptr);
    window->requestRender();

    bool handled = sOnBeginGlfwMouseCursorPosEvent(glfwWindow, x, y);
    if (handled) {
        return;
    }

    window->pointerMoved(x, y);
}

void GlfwApp::onMouseScroll(GLFWwindow* glfwWindow, double deltaX,
                            double deltaY) {
    GlfwWindowPtr window = findWindow(glfwWindow);
    assert(window != nullptr);
    window->requestRender();

    bool handled = sOnBeginGlfwMouseScrollEvent(glfwWindow, deltaX, deltaY);
    if (handled) {
        return;
    }

    window->mouseWheel(deltaX, deltaY);
}

void GlfwApp::onChar(GLFWwindow* glfwWindow, unsigned int code) {
    GlfwWindowPtr window = findWindow(glfwWindow);
    assert(window != nullptr);
    window->requestRender();

    bool handled = sOnBeginGlfwCharEvent(glfwWindow, code);
    if (handled) {
        return;
    }
}

void GlfwApp::onCharMods(GLFWwindow* glfwWindow, unsigned int code, int mods) {
    GlfwWindowPtr window = findWindow(glfwWindow);
    assert(window != nullptr);
    window->requestRender();

    bool handled = sOnBeginGlfwCharModsEvent(glfwWindow, code, mods);
    if (handled) {
        return;
    }
}

void GlfwApp::onDrop(GLFWwindow* glfwWindow, int numDroppedFiles,
                     const char** pathNames) {
    GlfwWindowPtr window = findWindow(glfwWindow);
    assert(window != nullptr);
    window->requestRender();

    bool handled =
        sOnBeginGlfwDropEvent(glfwWindow, numDroppedFiles, pathNames);
    if (handled) {
        return;
    }

    // TODO: Handle from Window
}

void GlfwApp::onErrorEvent(int error, const char* description) {
    JET_ERROR << "GLFW Error [" << error << "] " << description;
}

#endif  // JET_USE_GL
