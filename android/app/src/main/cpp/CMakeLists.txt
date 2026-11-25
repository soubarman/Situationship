cmake_minimum_required(VERSION 3.22.1)
project(cupid_llm LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Check if llama.cpp source is present in subdirectory (e.g. cloned in CI or git submodule)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/CMakeLists.txt")
    message(STATUS "Found llama.cpp source at ${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp")
    set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
    add_subdirectory(llama.cpp)
    set(LLAMA_LIB llama)
    add_definitions(-DHAS_LLAMA_CPP=1)
    include_directories(
        "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/ggml/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp"
    )
else()
    message(STATUS "llama.cpp source not found at ${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp. Building JNI wrapper in modular mode.")
    set(LLAMA_LIB "")
endif()

add_library(
    cupid_llm
    SHARED
    cupid_llm_jni.cpp
)

target_include_directories(
    cupid_llm
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

find_library(log-lib log)

if(LLAMA_LIB)
    target_link_libraries(
        cupid_llm
        PRIVATE
        ${LLAMA_LIB}
        ${log-lib}
    )
else()
    target_link_libraries(
        cupid_llm
        PRIVATE
        ${log-lib}
    )
endif()
