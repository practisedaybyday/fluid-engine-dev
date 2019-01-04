// Copyright (c) 2018 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.

#ifdef JET_USE_GL

#include <common.h>

#include <jet.gfx/gl_common.h>
#include <jet.gfx/gl_shader.h>
#include <jet.gfx/renderer.h>

namespace jet {
namespace gfx {

static void printShaderInfoLog(GLuint obj) {
    int infologLength = 0;
    int charsWritten = 0;
    char *infoLog;

    glGetShaderiv(obj, GL_INFO_LOG_LENGTH, &infologLength);

    if (infologLength > 0) {
        std::string strInfoLog;
        infoLog = (char *)malloc(infologLength);
        glGetShaderInfoLog(obj, infologLength, &charsWritten, infoLog);
        if (strInfoLog != "") {
            JET_DEBUG << "Shader Info:\n" << infoLog;
        }
        free(infoLog);
    }
}

static void printProgramInfoLog(GLuint obj) {
    int infologLength = 0;
    int charsWritten = 0;
    char *infoLog;

    glGetProgramiv(obj, GL_INFO_LOG_LENGTH, &infologLength);

    if (infologLength > 0) {
        std::string strInfoLog;
        infoLog = (char *)malloc(infologLength);
        glGetProgramInfoLog(obj, infologLength, &charsWritten, infoLog);
        if (strInfoLog != "") {
            JET_DEBUG << "Shader Info:\n" << infoLog;
        }
        free(infoLog);
    }
}

static void applyParameters(GLuint program, const RenderParameters &params) {
    const auto &paramNames = params.names();
    for (const auto &paramName : paramNames) {
        GLint location = glGetUniformLocation(program, paramName.c_str());

        if (location >= 0) {
            RenderParameters::Metadata metadata = params.metadata(paramName);
            const int32_t *buffer = params.buffer(paramName);

            const GLint *intData = reinterpret_cast<const GLint *>(buffer);
            const GLuint *uintData = reinterpret_cast<const GLuint *>(buffer);
            const GLfloat *floatData =
                reinterpret_cast<const GLfloat *>(buffer);

            switch (metadata.type) {
                case RenderParameters::Type::Int:
                    glUniform1i(location, intData[0]);
                    break;
                case RenderParameters::Type::UInt:
                    glUniform1i(location, uintData[0]);
                    break;
                case RenderParameters::Type::Float:
                    glUniform1f(location, floatData[0]);
                    break;
                case RenderParameters::Type::Float2:
                    glUniform2fv(location, 1, floatData);
                    break;
                case RenderParameters::Type::Float3:
                    glUniform3fv(location, 1, floatData);
                    break;
                case RenderParameters::Type::Float4:
                    glUniform4fv(location, 1, floatData);
                    break;
                case RenderParameters::Type::Matrix:
                    glUniformMatrix4fv(location, 1, GL_TRUE, floatData);
                    break;
            }
        }
    }
}

GLShader::GLShader(const RenderParameters &userRenderParams)
    : Shader(userRenderParams) {}

GLShader::GLShader(const RenderParameters &userRenderParams,
                   const VertexFormat &vertexFormat,
                   const std::string &vertexShaderSource,
                   const std::string &fragmentShaderSource)
    : Shader(userRenderParams) {
    load(vertexFormat, vertexShaderSource, fragmentShaderSource);
}

GLShader::GLShader(const RenderParameters &userRenderParams,
                   const VertexFormat &vertexFormat,
                   const std::string &vertexShaderSource,
                   const std::string &geometryShaderSource,
                   const std::string &fragmentShaderSource)
    : Shader(userRenderParams) {
    load(vertexFormat, vertexShaderSource, geometryShaderSource,
         fragmentShaderSource);
}

GLShader::~GLShader() { clear(); }

void GLShader::clear() {
    if (_program > 0) {
        glDeleteProgram(_program);
        _program = 0;
    }
}

void GLShader::load(const VertexFormat &vertexFormat,
                    const std::string &vertexShaderSource,
                    const std::string &fragmentShaderSource) {
    _vertexFormat = vertexFormat;

    GLuint vs = glCreateShader(GL_VERTEX_SHADER);
    const char *vertexShaderSourceStr = vertexShaderSource.c_str();
    glShaderSource(vs, 1, &vertexShaderSourceStr, nullptr);
    glCompileShader(vs);

    printShaderInfoLog(vs);

    GLuint fs = glCreateShader(GL_FRAGMENT_SHADER);
    const char *fragmentShaderSourceStr = fragmentShaderSource.c_str();
    glShaderSource(fs, 1, &fragmentShaderSourceStr, nullptr);
    glCompileShader(fs);

    printShaderInfoLog(fs);

    _program = glCreateProgram();
    glAttachShader(_program, fs);
    glAttachShader(_program, vs);
    glLinkProgram(_program);

    printProgramInfoLog(_program);
}

void GLShader::load(const VertexFormat &vertexFormat,
                    const std::string &vertexShaderSource,
                    const std::string &geometryShaderSource,
                    const std::string &fragmentShaderSource) {
    _vertexFormat = vertexFormat;

    GLuint vs = glCreateShader(GL_VERTEX_SHADER);
    const char *vertexShaderSourceStr = vertexShaderSource.c_str();
    glShaderSource(vs, 1, &vertexShaderSourceStr, nullptr);
    glCompileShader(vs);

    printShaderInfoLog(vs);

    GLuint gs = glCreateShader(GL_GEOMETRY_SHADER);
    const char *geometryShaderSourceStr = geometryShaderSource.c_str();
    glShaderSource(gs, 1, &geometryShaderSourceStr, nullptr);
    glCompileShader(gs);

    printShaderInfoLog(gs);

    GLuint fs = glCreateShader(GL_FRAGMENT_SHADER);
    const char *fragmentShaderSourceStr = fragmentShaderSource.c_str();
    glShaderSource(fs, 1, &fragmentShaderSourceStr, nullptr);
    glCompileShader(fs);

    printShaderInfoLog(fs);

    _program = glCreateProgram();
    glAttachShader(_program, fs);
    glAttachShader(_program, gs);
    glAttachShader(_program, vs);
    glLinkProgram(_program);

    printProgramInfoLog(_program);
}

void GLShader::onBind(const Renderer *renderer) {
    glUseProgram(_program);

    // Load default parameters
    const auto &camera = renderer->camera();
    const Matrix4x4F matrix = camera->projectionMatrix() * camera->state.viewMatrix();

    setModelViewProjectionMatrix(matrix);
    setViewWidth(camera->state.viewport.width);
    setViewHeight(camera->state.viewport.height);

    // Apply parameters
    applyParameters(_program, defaultRenderParameters());
    applyParameters(_program, userRenderParameters());
}

void GLShader::onUnbind(const Renderer *renderer) {
    UNUSED_VARIABLE(renderer);

    glUseProgram(0);
}

unsigned int GLShader::program() const { return _program; }

}  // namespace gfx
}  // namespace jet

#endif  // JET_USE_GL
