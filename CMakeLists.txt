# Chat Module CMakeLists.txt
# Uses logos-module-builder with module-specific protobuf handling

cmake_minimum_required(VERSION 3.14)
project(ChatModulePlugin LANGUAGES CXX)

# Include the Logos Module CMake helper
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# --- Module-specific: Protobuf handling ---
find_package(Protobuf REQUIRED)

# Get absolute paths for proto files
set(PROTO_FILES src/protobuf/message.proto)
set(PROTO_FILES_ABS "")
foreach(proto_file ${PROTO_FILES})
    get_filename_component(proto_abs "${proto_file}" ABSOLUTE)
    list(APPEND PROTO_FILES_ABS ${proto_abs})
endforeach()

# Generate protobuf sources
protobuf_generate_cpp(PROTO_SRCS PROTO_HDRS ${PROTO_FILES_ABS})

# Create proto library with AUTOMOC disabled
add_library(chat_proto_lib STATIC ${PROTO_SRCS} ${PROTO_HDRS})
set_target_properties(chat_proto_lib PROPERTIES AUTOMOC OFF AUTOUIC OFF AUTORCC OFF)
target_include_directories(chat_proto_lib PUBLIC 
    ${CMAKE_CURRENT_BINARY_DIR}
    ${Protobuf_INCLUDE_DIRS}
)
target_link_libraries(chat_proto_lib PUBLIC ${Protobuf_LIBRARIES})
# --- End module-specific ---

# Define the module using logos-module-builder
logos_module(
    NAME chat
    SOURCES 
        src/chat_interface.h
        src/chat_plugin.h
        src/chat_plugin.cpp
        src/chat_api.cpp
        src/chat_api.h
    FIND_PACKAGES
        Threads
    LINK_TARGETS
        chat_proto_lib
    AUTOGEN_DEPENDS
        chat_proto_lib
    INCLUDE_DIRS
        ${CMAKE_CURRENT_BINARY_DIR}
)
