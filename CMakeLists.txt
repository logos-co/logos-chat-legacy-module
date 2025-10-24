cmake_minimum_required(VERSION 3.14)
project(ChatModulePlugin LANGUAGES CXX)

include(GNUInstallDirs)

set(CMAKE_AUTOMOC ON)

option(LOGOS_CHAT_MODULE_USE_VENDOR "Force use of vendored Logos dependencies" OFF)

set(_parent_liblogos "${CMAKE_SOURCE_DIR}/../logos-liblogos")
set(_parent_cpp_sdk "${CMAKE_SOURCE_DIR}/../logos-cpp-sdk")
set(_use_vendor ${LOGOS_CHAT_MODULE_USE_VENDOR})
if(NOT _use_vendor)
    if(NOT EXISTS "${_parent_liblogos}/interface.h" OR NOT EXISTS "${_parent_cpp_sdk}/cpp/logos_api.h")
        set(_use_vendor ON)
    endif()
endif()
if(_use_vendor)
    set(LOGOS_LIBLOGOS_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-liblogos")
    set(LOGOS_CPP_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-cpp-sdk")
else()
    set(LOGOS_LIBLOGOS_ROOT "${_parent_liblogos}")
    set(LOGOS_CPP_SDK_ROOT "${_parent_cpp_sdk}")
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

# Run Logos C++ generator on metadata before compilation
set(METADATA_JSON "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json")

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
    ${LOGOS_LIBLOGOS_ROOT}/interface.h
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
    ${LOGOS_CPP_SDK_ROOT}/cpp/generated/logos_sdk.cpp
)

# Mark generated sources
set_source_files_properties(
    ${LOGOS_CPP_SDK_ROOT}/cpp/generated/logos_sdk.cpp
    PROPERTIES GENERATED TRUE
)

# Create the plugin library
add_library(chat_module_plugin SHARED ${PLUGIN_SOURCES})

# Set output name without lib prefix and with correct name for generator
set_target_properties(chat_module_plugin PROPERTIES
    PREFIX ""
    OUTPUT_NAME "chat_plugin")

# Make sure protocol buffers are generated before building
add_dependencies(chat_module_plugin generate_protos)

# Include directories
target_include_directories(chat_module_plugin PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_BINARY_DIR}
    ${Protobuf_INCLUDE_DIRS}
    ${LOGOS_LIBLOGOS_ROOT}
    ${LOGOS_CPP_SDK_ROOT}/cpp
    ${LOGOS_CPP_SDK_ROOT}/cpp/generated
)

# Link against libraries
target_link_libraries(chat_module_plugin PRIVATE 
    Qt${QT_VERSION_MAJOR}::Core
    Qt${QT_VERSION_MAJOR}::RemoteObjects
    ${Protobuf_LIBRARIES}
    Threads::Threads
)

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
