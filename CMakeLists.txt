cmake_minimum_required(VERSION 3.14)
project(ChatModulePlugin LANGUAGES C)

include(GNUInstallDirs)

# Minimal build configuration to satisfy Nix build requirements
# This creates a simple library without complex dependencies

# Create a minimal plugin library using a simple C file
add_library(chat_module_plugin SHARED
    ${CMAKE_CURRENT_SOURCE_DIR}/chat_plugin_simple.c
)

# Set output name without lib prefix
set_target_properties(chat_module_plugin PROPERTIES
    PREFIX ""
    OUTPUT_NAME "chat_plugin"
)

# Set output directory to match what Nix expects
set_target_properties(chat_module_plugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"
)

# Create the modules directory
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/modules")

# Install the library
install(TARGETS chat_module_plugin
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
    RUNTIME DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
)

# Install metadata
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/metadata.json
    DESTINATION ${CMAKE_INSTALL_DATADIR}/logos-chat-module
)

message(STATUS "Minimal Chat Plugin configured successfully")