include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(dev_test_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(dev_test_setup_options)
  option(dev_test_ENABLE_HARDENING "Enable hardening" ON)
  option(dev_test_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    dev_test_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    dev_test_ENABLE_HARDENING
    OFF)

  dev_test_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR dev_test_PACKAGING_MAINTAINER_MODE)
    option(dev_test_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(dev_test_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(dev_test_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(dev_test_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(dev_test_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(dev_test_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(dev_test_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(dev_test_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(dev_test_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(dev_test_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(dev_test_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(dev_test_ENABLE_PCH "Enable precompiled headers" OFF)
    option(dev_test_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(dev_test_ENABLE_IPO "Enable IPO/LTO" ON)
    option(dev_test_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(dev_test_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(dev_test_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(dev_test_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(dev_test_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(dev_test_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(dev_test_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(dev_test_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(dev_test_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(dev_test_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(dev_test_ENABLE_PCH "Enable precompiled headers" OFF)
    option(dev_test_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      dev_test_ENABLE_IPO
      dev_test_WARNINGS_AS_ERRORS
      dev_test_ENABLE_USER_LINKER
      dev_test_ENABLE_SANITIZER_ADDRESS
      dev_test_ENABLE_SANITIZER_LEAK
      dev_test_ENABLE_SANITIZER_UNDEFINED
      dev_test_ENABLE_SANITIZER_THREAD
      dev_test_ENABLE_SANITIZER_MEMORY
      dev_test_ENABLE_UNITY_BUILD
      dev_test_ENABLE_CLANG_TIDY
      dev_test_ENABLE_CPPCHECK
      dev_test_ENABLE_COVERAGE
      dev_test_ENABLE_PCH
      dev_test_ENABLE_CACHE)
  endif()

  dev_test_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (dev_test_ENABLE_SANITIZER_ADDRESS OR dev_test_ENABLE_SANITIZER_THREAD OR dev_test_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(dev_test_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(dev_test_global_options)
  if(dev_test_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    dev_test_enable_ipo()
  endif()

  dev_test_supports_sanitizers()

  if(dev_test_ENABLE_HARDENING AND dev_test_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR dev_test_ENABLE_SANITIZER_UNDEFINED
       OR dev_test_ENABLE_SANITIZER_ADDRESS
       OR dev_test_ENABLE_SANITIZER_THREAD
       OR dev_test_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${dev_test_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${dev_test_ENABLE_SANITIZER_UNDEFINED}")
    dev_test_enable_hardening(dev_test_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(dev_test_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(dev_test_warnings INTERFACE)
  add_library(dev_test_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  dev_test_set_project_warnings(
    dev_test_warnings
    ${dev_test_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(dev_test_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    dev_test_configure_linker(dev_test_options)
  endif()

  include(cmake/Sanitizers.cmake)
  dev_test_enable_sanitizers(
    dev_test_options
    ${dev_test_ENABLE_SANITIZER_ADDRESS}
    ${dev_test_ENABLE_SANITIZER_LEAK}
    ${dev_test_ENABLE_SANITIZER_UNDEFINED}
    ${dev_test_ENABLE_SANITIZER_THREAD}
    ${dev_test_ENABLE_SANITIZER_MEMORY})

  set_target_properties(dev_test_options PROPERTIES UNITY_BUILD ${dev_test_ENABLE_UNITY_BUILD})

  if(dev_test_ENABLE_PCH)
    target_precompile_headers(
      dev_test_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(dev_test_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    dev_test_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(dev_test_ENABLE_CLANG_TIDY)
    dev_test_enable_clang_tidy(dev_test_options ${dev_test_WARNINGS_AS_ERRORS})
  endif()

  if(dev_test_ENABLE_CPPCHECK)
    dev_test_enable_cppcheck(${dev_test_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(dev_test_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    dev_test_enable_coverage(dev_test_options)
  endif()

  if(dev_test_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(dev_test_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(dev_test_ENABLE_HARDENING AND NOT dev_test_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR dev_test_ENABLE_SANITIZER_UNDEFINED
       OR dev_test_ENABLE_SANITIZER_ADDRESS
       OR dev_test_ENABLE_SANITIZER_THREAD
       OR dev_test_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    dev_test_enable_hardening(dev_test_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
