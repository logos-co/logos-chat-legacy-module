cmake_minimum_required(VERSION 3.14)
project(ChatModulePlugin LANGUAGES CXX)

include(GNUInstallDirs)

set(CMAKE_AUTOMOC ON)

option(LOGOS_CHAT_MODULE_USE_VENDOR "Force use of vendored Logos dependencies" OFF)

# Allow override from environment or command line
if(NOT DEFINED LOGOS_LIBLOGOS_ROOT)
    set(_parent_liblogos "${CMAKE_SOURCE_DIR}/../logos-liblogos")
    set(_use_vendor ${LOGOS_CHAT_MODULE_USE_VENDOR})
    if(NOT _use_vendor)
        if(NOT EXISTS "${_parent_liblogos}/interface.h")
            set(_use_vendor ON)
        endif()
    endif()
    if(_use_vendor)
        set(LOGOS_LIBLOGOS_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-liblogos")
    else()
        set(LOGOS_LIBLOGOS_ROOT "${_parent_liblogos}")
    endif()
endif()

if(NOT DEFINED LOGOS_CPP_SDK_ROOT)
    set(_parent_cpp_sdk "${CMAKE_SOURCE_DIR}/../logos-cpp-sdk")
    set(_use_vendor ${LOGOS_CHAT_MODULE_USE_VENDOR})
    if(NOT _use_vendor)
        if(NOT EXISTS "${_parent_cpp_sdk}/cpp/logos_api.h")
            set(_use_vendor ON)
        endif()
    endif()
    if(_use_vendor)
        set(LOGOS_CPP_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-cpp-sdk")
    else()
        set(LOGOS_CPP_SDK_ROOT "${_parent_cpp_sdk}")
    endif()
endif()

# Check if dependencies are available (support both source and installed layouts)
set(_liblogos_found FALSE)
if(EXISTS "${LOGOS_LIBLOGOS_ROOT}/interface.h")
    set(_liblogos_found TRUE)
    set(_liblogos_is_source TRUE)
elseif(EXISTS "${LOGOS_LIBLOGOS_ROOT}/include/interface.h")
    set(_liblogos_found TRUE)
    set(_liblogos_is_source FALSE)
endif()

set(_cpp_sdk_found FALSE)
if(EXISTS "${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.h")
    set(_cpp_sdk_found TRUE)
    set(_cpp_sdk_is_source TRUE)
elseif(EXISTS "${LOGOS_CPP_SDK_ROOT}/include/cpp/logos_api.h")
    set(_cpp_sdk_found TRUE)
    set(_cpp_sdk_is_source FALSE)
endif()

if(NOT _liblogos_found)
    message(FATAL_ERROR "logos-liblogos not found at ${LOGOS_LIBLOGOS_ROOT}. "
                        "Set LOGOS_LIBLOGOS_ROOT or run git submodule update --init --recursive.")
endif()

if(NOT _cpp_sdk_found)
    message(FATAL_ERROR "logos-cpp-sdk not found at ${LOGOS_CPP_SDK_ROOT}. "
                        "Set LOGOS_CPP_SDK_ROOT or run git submodule update --init --recursive.")
endif()

# Root that contains the vendored dependencies (logos-core checkout or script vendor directory)
get_filename_component(LOGOS_DEPS_ROOT "${LOGOS_CPP_SDK_ROOT}" DIRECTORY)

# Find Qt RemoteObjects (needed for LogosAPI)
if(NOT DEFINED QT_VERSION_MAJOR)
    find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core RemoteObjects)
    if(Qt6_FOUND)
        set(QT_VERSION_MAJOR 6)
    else()
        set(QT_VERSION_MAJOR 5)
    endif()
endif()
find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core RemoteObjects)

# Run Logos C++ generator on metadata before compilation (only for source layout)
set(METADATA_JSON "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json")

# Only run generator for source layout - nix builds already have generated files
if(_cpp_sdk_is_source)
    # Source layout: build and run the generator
    # Generate into build directory
    set(PLUGINS_OUTPUT_DIR "${CMAKE_BINARY_DIR}/some_folder")
    set(CPP_GENERATOR_BUILD_DIR "${LOGOS_DEPS_ROOT}/build/cpp-generator")
    set(CPP_GENERATOR "${CPP_GENERATOR_BUILD_DIR}/bin/logos-cpp-generator")
    
    if(NOT TARGET cpp_generator_build)
        add_custom_target(cpp_generator_build
            COMMAND bash "${LOGOS_CPP_SDK_ROOT}/cpp-generator/compile.sh"
            WORKING_DIRECTORY "${LOGOS_DEPS_ROOT}"
            COMMENT "Building logos-cpp-generator via ${LOGOS_CPP_SDK_ROOT}/cpp-generator/compile.sh"
            VERBATIM
        )
    endif()
    
    add_custom_target(run_cpp_generator_chat
        COMMAND "${CPP_GENERATOR}" --metadata "${METADATA_JSON}" --general-only --output-dir "${PLUGINS_OUTPUT_DIR}"
        WORKING_DIRECTORY "${LOGOS_DEPS_ROOT}"
        COMMENT "Running logos-cpp-generator on ${METADATA_JSON} with output-dir ${PLUGINS_OUTPUT_DIR}"
        VERBATIM
    )
    add_dependencies(run_cpp_generator_chat cpp_generator_build)
else()
    # Installed/nix layout: files are already in source tree from lib.nix preConfigure
    # lib.nix creates ./some_folder in source directory before CMake runs
    set(PLUGINS_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/some_folder")
endif()

# Find Protocol Buffers
find_package(Protobuf REQUIRED)
find_package(Threads REQUIRED)
find_package(absl QUIET)

# Generate protobuf files
set(PROTO_FILE "${CMAKE_CURRENT_SOURCE_DIR}/src/protobuf/message.proto")
set(PROTO_SRC "${CMAKE_CURRENT_BINARY_DIR}/message.pb.cc")
set(PROTO_HDR "${CMAKE_CURRENT_BINARY_DIR}/message.pb.h")

add_custom_command(
    OUTPUT ${PROTO_SRC} ${PROTO_HDR}
    COMMAND ${Protobuf_PROTOC_EXECUTABLE}
    ARGS --cpp_out=${CMAKE_CURRENT_BINARY_DIR} -I${CMAKE_CURRENT_SOURCE_DIR}/src/protobuf ${PROTO_FILE}
    DEPENDS ${PROTO_FILE}
    COMMENT "Running C++ protocol buffer compiler on message.proto"
    VERBATIM
)

# Create custom target for protocol buffers
add_custom_target(generate_protos DEPENDS ${PROTO_SRC} ${PROTO_HDR})

# Plugin sources
set(PLUGIN_SOURCES
    chat_plugin.cpp
    chat_plugin.h
    chat_interface.h
    src/chat_api.cpp
    src/chat_api.h
    ${PROTO_SRC}
    ${PROTO_HDR}
)

# Add liblogos interface header
if(_liblogos_is_source)
    list(APPEND PLUGIN_SOURCES ${LOGOS_LIBLOGOS_ROOT}/interface.h)
else()
    list(APPEND PLUGIN_SOURCES ${LOGOS_LIBLOGOS_ROOT}/include/interface.h)
endif()

# Add SDK sources (only if source layout, installed layout uses the library)
if(_cpp_sdk_is_source)
    list(APPEND PLUGIN_SOURCES
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_client.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_client.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_consumer.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_consumer.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_provider.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_provider.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/token_manager.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/token_manager.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/module_proxy.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/module_proxy.h
    )
    # Add generated logos_sdk.cpp - will be generated by run_cpp_generator_chat
    list(APPEND PLUGIN_SOURCES ${PLUGINS_OUTPUT_DIR}/logos_sdk.cpp)
    # Mark as generated so CMake knows to wait for it
    set_source_files_properties(
        ${PLUGINS_OUTPUT_DIR}/logos_sdk.cpp
        PROPERTIES GENERATED TRUE
    )
else()
    # For installed/nix layout, logos_sdk.cpp is already in ${PLUGINS_OUTPUT_DIR}
    # (generated by nix build preConfigure phase in lib.nix before CMake runs)
    list(APPEND PLUGIN_SOURCES ${PLUGINS_OUTPUT_DIR}/logos_sdk.cpp)
endif()

# Create the plugin library
add_library(chat_module_plugin SHARED ${PLUGIN_SOURCES})

# Set output name without lib prefix and with correct name for generator
set_target_properties(chat_module_plugin PROPERTIES
    PREFIX ""
    OUTPUT_NAME "chat_plugin")

# Make sure protocol buffers are generated before building
add_dependencies(chat_module_plugin generate_protos)

# Ensure generator runs before building the plugin (only for source layout)
if(_cpp_sdk_is_source)
    add_dependencies(chat_module_plugin run_cpp_generator_chat)
endif()

# Include directories
target_include_directories(chat_module_plugin PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_BINARY_DIR}
    ${Protobuf_INCLUDE_DIRS}
    ${PLUGINS_OUTPUT_DIR}
)

# Add include directories based on layout type
if(_liblogos_is_source)
    target_include_directories(chat_module_plugin PRIVATE ${LOGOS_LIBLOGOS_ROOT})
else()
    target_include_directories(chat_module_plugin PRIVATE ${LOGOS_LIBLOGOS_ROOT}/include)
endif()

if(_cpp_sdk_is_source)
    target_include_directories(chat_module_plugin PRIVATE 
        ${LOGOS_CPP_SDK_ROOT}/cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/generated
    )
else()
    # For nix builds, also include the include subdirectory
    # (lib.nix moves header files to ./some_folder/include/)
    target_include_directories(chat_module_plugin PRIVATE 
        ${LOGOS_CPP_SDK_ROOT}/include
        ${LOGOS_CPP_SDK_ROOT}/include/cpp
        ${LOGOS_CPP_SDK_ROOT}/include/core
        ${PLUGINS_OUTPUT_DIR}/include
    )
endif()

# Link against libraries
target_link_libraries(chat_module_plugin PRIVATE 
    Qt${QT_VERSION_MAJOR}::Core
    Qt${QT_VERSION_MAJOR}::RemoteObjects
    ${Protobuf_LIBRARIES}
    Threads::Threads
)

# Link SDK library if using installed layout
if(NOT _cpp_sdk_is_source)
    find_library(LOGOS_SDK_LIB logos_sdk PATHS ${LOGOS_CPP_SDK_ROOT}/lib NO_DEFAULT_PATH REQUIRED)
    target_link_libraries(chat_module_plugin PRIVATE ${LOGOS_SDK_LIB})
endif()

# Link against Abseil libraries if found
if(absl_FOUND)
    target_link_libraries(chat_module_plugin PRIVATE
        absl::base
        absl::strings
        absl::log
        absl::check
    )
endif()

# Set common properties for both platforms
set_target_properties(chat_module_plugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"  # For Windows .dll
    BUILD_WITH_INSTALL_RPATH TRUE
    SKIP_BUILD_RPATH FALSE)

if(APPLE)
    # macOS specific settings
    set_target_properties(chat_module_plugin PROPERTIES
        INSTALL_RPATH "@loader_path"
        INSTALL_NAME_DIR "@rpath"
        BUILD_WITH_INSTALL_NAME_DIR TRUE)
    
    add_custom_command(TARGET chat_module_plugin POST_BUILD
        COMMAND install_name_tool -id "@rpath/chat_plugin.dylib" $<TARGET_FILE:chat_module_plugin>
        COMMENT "Updating library paths for macOS"
    )
else()
    # Linux specific settings
    set_target_properties(chat_module_plugin PROPERTIES
        INSTALL_RPATH "$ORIGIN"
        INSTALL_RPATH_USE_LINK_PATH FALSE)
endif()

install(TARGETS chat_module_plugin
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
    RUNTIME DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
)

install(FILES ${METADATA_JSON}
    DESTINATION ${CMAKE_INSTALL_DATADIR}/logos-chat-module
)

install(DIRECTORY "${PLUGINS_OUTPUT_DIR}/"
    DESTINATION ${CMAKE_INSTALL_DATADIR}/logos-chat-module/generated
    OPTIONAL
)

# Print status messages
message(STATUS "Protobuf version: ${Protobuf_VERSION}")
message(STATUS "Protobuf include dirs: ${Protobuf_INCLUDE_DIRS}")
message(STATUS "Protobuf libraries: ${Protobuf_LIBRARIES}")
message(STATUS "Chat Plugin configured successfully") 
