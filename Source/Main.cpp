#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <getopt.h>
#include <json.h>

#include "Program.h"

static bool LoadConfigFile(ProgramConfig &config)
{
    constexpr auto userConfigPathFormat = "%s/.config/chemica/chemica.txt";

    const auto homePath = std::getenv("HOME");

    const auto userConfigPathSize = std::snprintf(nullptr, 0, userConfigPathFormat, homePath) + 1;

    const auto userConfigPath = new char[userConfigPathSize];

    std::snprintf(userConfigPath, userConfigPathSize, userConfigPathFormat, homePath);

    auto file = std::fopen(userConfigPath, "r+");

    std::fprintf(stderr, "Config Path: %s\n", userConfigPath);

    delete[] userConfigPath;

    if (file == nullptr)
    {
        std::fputs("Could not create or open configuration file\n", stderr);

        return false;
    }

    std::fseek(file, 0, SEEK_END);

    const auto bufferSize = std::ftell(file);

    std::fseek(file, 0, SEEK_SET);

    const auto buffer = new char[bufferSize];
    const auto bufferEnd = buffer + bufferSize;

    std::fread(buffer, bufferSize, 1, file);

    std::fclose(file);

    char errorMessage[100]{};

    json_settings jsonSettings{};

    const auto json = json_parse_ex(&jsonSettings, buffer, bufferSize, errorMessage);

    if (json != nullptr)
    {
        for (int i = 0; i < json->u.object.length; i++)
        {
            const auto value = json->u.object.values[i];

            if (std::strncmp(value.name, "dev_mode", value.name_length) == 0)
            {
                config.devMode = value.value->u.boolean;
            }
        }

        json_value_free(json);
    }
    else
    {
        std::fprintf(stderr, "Failed to parse config file: %s\n", errorMessage);
    }

    std::fprintf(stderr, "Config File: %s\n", buffer);

    delete[] buffer;

    return true;
};

static bool ParseArguments(ProgramConfig &config, const int argc, char **argv)
{
    while (true)
    {
        static option longOptions[]{
            {"dev", no_argument, 0, 'd'},
            {0, 0, 0, 0}};

        int optionIndex = 0;

        const auto option = getopt_long(argc, argv, "d", longOptions, &optionIndex);

        if (option == -1)
        {
            break;
        }

        switch (option)
        {
        case 'd':
            config.devMode = true;

            break;
        }
    }

    return true;
}

extern "C"
{
    int cppMain(const int argc, char **argv)
    {
        static Program program{};

        LoadConfigFile(program.config);
        ParseArguments(program.config, argc, argv);

        program.Initialize();
        program.Run();
        program.Shutdown();

        return 0;
    }
}

#if 0
int main(const int argc, char** argv) {
    return cppMain(argc, argv);
}
#endif