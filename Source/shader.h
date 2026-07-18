#pragma once

#include <cstdint>
#include <cstdio>
#include <stdio.h>
#include <glad/glad.h>
#include <cstring>
#include <stdlib.h>

struct ShaderSource
{
    int type = 0;
    const void *binary = nullptr;
    std::size_t size = 0;
};

inline std::uint32_t LoadShader(const ShaderSource &source)
{
    const auto shader = glCreateShader(source.type);

    glShaderBinary(1, &shader, GL_SHADER_BINARY_FORMAT_SPIR_V, source.binary, source.size);
    glSpecializeShader(shader, "main", 0, nullptr, nullptr);

    int success = 0;

    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);

    if (success == 0)
    {
        std::fprintf(stderr, "Shader rejected binary\n");

        return 0;
    }

    return shader;
}

inline std::uint32_t LoadProgram(const ShaderSource *sources, std::size_t count)
{
    const auto program = glCreateProgram();
    assert(program != 0);

    const auto shaders = new std::uint32_t[count];

    for (int i = 0; i < count; i++)
    {
        shaders[i] = LoadShader(sources[i]);

        glAttachShader(program, shaders[i]);
    }

    glLinkProgram(program);

    int linkStatus = 0;

    glGetProgramiv(program, GL_LINK_STATUS, &linkStatus);

    if (linkStatus == 0)
    {
        int infoLogLength = 0;

        glGetProgramiv(program, GL_INFO_LOG_LENGTH, &infoLogLength);

        const auto infoLog = new char[infoLogLength];

        glGetProgramInfoLog(program, infoLogLength, &infoLogLength, infoLog);

        std::fprintf(stderr, "[OpenGL]: Shader Program failed to link: %s\n", infoLog);

        delete[] infoLog;

        std::exit(EXIT_FAILURE);

        return 0;
    }

    for (int i = 0; i < count; i++)
    {
        glDetachShader(program, shaders[i]);
        glDeleteShader(shaders[i]);
    }

    delete[] shaders;

    return program;
}