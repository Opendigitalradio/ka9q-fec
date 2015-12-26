########################################################################
# Project setup
########################################################################
cmake_minimum_required(VERSION 2.8)
project(libfec ASM C)

option(BUILD_32BIT_ON_64BIT "Build a 32-bit library on a 64-bit system" OFF)

# Select the release build type by default to get optimization flags
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release")
    message(STATUS "Build type not specified: defaulting to release.")
endif(NOT CMAKE_BUILD_TYPE)
set(CMAKE_BUILD_TYPE ${CMAKE_BUILD_TYPE} CACHE STRING "")

list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake/Modules)

if(NOT LIB_INSTALL_DIR)
    set(LIB_INSTALL_DIR lib)
endif()


########################################################################
# Version information
########################################################################
set(VERSION_INFO_MAJOR  3)
set(VERSION_INFO_MINOR  0)
set(VERSION_INFO_PATCH  0)

if(NOT DEFINED VERSION_INFO_EXTRA)
    set(VERSION_INFO_EXTRA "git")
endif()
include(Version)

if(NOT DEFINED VERSION)
    #set(VERSION "\"${VERSION_INFO_MAJOR}.${VERSION_INFO_MINOR}.${VERSION_INFO_PATCH}\"")
    set(VERSION "\"${VERSION_INFO}\"")
endif()


########################################################################
# Compiler specific setup
########################################################################
if(BUILD_32BIT_ON_64BIT)
    set(CMAKE_SYSTEM_PROCESSOR "i386")
    set(CMAKE_SIZEOF_VOID_P 4)
    set(CMAKE_C_FLAGS -m32)
    set(CMAKE_CXX_FLAGS -m32)
    add_definitions(-m32)
endif()

if((CMAKE_SYSTEM_PROCESSOR MATCHES "i386|i686|x86|AMD64") AND (CMAKE_SIZEOF_VOID_P EQUAL 4))
    set(TARGET_ARCH "x86")
elseif((CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64") AND (CMAKE_SIZEOF_VOID_P EQUAL 8))
    set(TARGET_ARCH "x64")
elseif((CMAKE_SYSTEM_PROCESSOR MATCHES "i386") AND (CMAKE_SIZEOF_VOID_P EQUAL 8) AND (APPLE))
    # Mac is weird like that.
    set(TARGET_ARCH "x64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^arm*")
    set(TARGET_ARCH "ARM")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(powerpc|ppc)64le")
    set(TARGET_ARCH "ppc64" "ppc64le")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(powerpc|ppc)64")
    set(TARGET_ARCH "ppc64" "ppc")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(powerpc|ppc)")
    set(TARGET_ARCH "ppc")
endif()


if(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_CLANGCC)
    add_definitions(-Wall)
    add_definitions(-Wno-unused)

    if(TARGET_ARCH MATCHES "x64")
         add_definitions(-fPIC)
         add_definitions(-msse2)
    elseif(TARGET_ARCH MATCHES "x86")
         add_definitions(-mmmx)
         add_definitions(-msse)
         add_definitions(-msse2)
    elseif(TARGET_ARCH MATCHES "ppc|ppc64")
         add_definitions(-fno-common)
         add_definitions(-faltivec)
    endif()

endif()

########################################################################
# Find build dependencies
########################################################################

# libm
find_library(M_LIB m REQUIRED)


########################################################################
# config.h
########################################################################

#add_definitions(-DHAVE_CONFIG_H)

# Checks for includes
include(CheckIncludeFile)
check_include_file("getopt.h"           HAVE_GETOPT_H)
check_include_file("stdio.h"            HAVE_STDIO_H)
check_include_file("stdlib.h"           HAVE_STDLIB_H)
check_include_file("memory.h"           HAVE_MEMORY_H)
check_include_file("string.h"           HAVE_STRING_H)

# Checks for functions
include(CheckFunctionExists)
check_function_exists("getopt_long"      HAVE_GETOPT_LONG)
check_function_exists("memset"           HAVE_MEMSET)
check_function_exists("memmove"          HAVE_MEMMOVE)


########################################################################
# Setup apps
########################################################################

if(TARGET_ARCH MATCHES "x64")
    list(APPEND libfec_sources
        dotprod_port.c
        peakval_port.c
        sumsq.c
        sumsq_port.c
        cpu_mode_x86_64.c
	##asm
	#sse2bfly27-64.s
	#sse2bfly29-64.s
        )

elseif(TARGET_ARCH MATCHES "x86")
    list(APPEND libfec_sources
        viterbi27_mmx.c
        viterbi27_sse.c
        viterbi27_sse2.c
        viterbi29_mmx.c
        viterbi29_sse.c
        viterbi29_sse2.c
        viterbi39_sse2.c
        viterbi39_sse.c
        viterbi39_mmx.c
        viterbi615_mmx.c
        viterbi615_sse.c
        viterbi615_sse2.c
        dotprod_mmx.c
        dotprod_sse2.c
        #peakval_mmx.c
        #peakval_sse.c
        #peakval_sse2.c
        sumsq.c
        sumsq_port.c
        sumsq_sse2.c
        sumsq_mmx.c
        cpu_mode_x86.c
	#asm
	cpu_features.s
	dotprod_mmx_assist.s
	dotprod_sse2_assist.s
	mmxbfly27.s
	mmxbfly29.s
	peak_mmx_assist.s
	peak_sse2_assist.s
	peak_sse_assist.s
	peakval_mmx_assist.s
	peakval_sse2_assist.s
	peakval_sse_assist.s
	sse2bfly27.s
	sse2bfly29.s
	ssebfly27.s
	ssebfly29.s
	sumsq_mmx_assist.s
	sumsq_sse2_assist.s
        )

elseif(TARGET_ARCH MATCHES "ppc|ppc64")
    list(APPEND libfec_sources
        viterbi27_av.c
        viterbi29_av.c
        viterbi39_av.c
        viterbi615_av.c
        encode_rs_av.c
        dotprod_av.c
        sumsq_av.c
        peakval_av.c
        cpu_mode_ppc.c
        )
else()
    list(APPEND libfec_sources
        cpu_mode_generic.c
        )

endif()


list(APPEND libfec_sources
    fec.c
    sim.c
    viterbi27.c
    viterbi27_port.c
    viterbi29.c
    viterbi29_port.c
    viterbi39.c
    viterbi39_port.c
    viterbi615.c
    viterbi615_port.c
    encode_rs_char.c
    encode_rs_int.c
    encode_rs_8.c
    decode_rs_char.c
    decode_rs_int.c
    decode_rs_8.c
    init_rs_char.c
    init_rs_int.c
    encode_rs_ccsds.c
    decode_rs_ccsds.c
    dotprod.c
    dotprod_port.c
    peakval.c
    peakval_port.c
    sumsq.c
    sumsq_port.c
    ccsds_tab.c
    ccsds_tal.c
)


################################################################################
# Generate pkg-config file
################################################################################
foreach(inc ${LIBFEC_INCLUDE_DIR})
    list(APPEND LIBFEC_PC_CFLAGS "-I${inc}")
endforeach()

foreach(lib ${LIBFEC_LIBRARY_DIRS})
    list(APPEND LIBFEC_PC_PRIV_LIBS "-L${lib}")
endforeach()

set(LIBFEC_PC_PREFIX ${CMAKE_INSTALL_PREFIX})
set(LIBFEC_PC_EXEC_PREFIX \${prefix})
set(LIBFEC_PC_LIBDIR \${exec_prefix}/${LIB_INSTALL_DIR})
set(LIBFEC_PC_INCLUDEDIR \${prefix}/include)
set(LIBFEC_PC_VERSION ${VERSION})
set(LIBFEC_PC_LIBS "-lfec")

# Use space-delimiter in the .pc file, rather than CMake's semicolon separator
string(REPLACE ";" " " LIBFEC_PC_CFLAGS "${LIBFEC_PC_CFLAGS}")
string(REPLACE ";" " " LIBFEC_PC_LIBS "${LIBFEC_PC_LIBS}")

# Unset these to avoid hard-coded paths in a cross-environment
if(CMAKE_CROSSCOMPILING)
    unset(LIBFEC_PC_CFLAGS)
    unset(LIBFEC_PC_LIBS)
endif()

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/libfec.pc.in
    ${CMAKE_CURRENT_BINARY_DIR}/libfec.pc
    @ONLY
)

install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/libfec.pc
    DESTINATION ${LIB_INSTALL_DIR}/pkgconfig/
)


########################################################################
# Setup libraries
########################################################################

# generate ccsds_tab.c
add_executable(gen_ccsds gen_ccsds.c init_rs_char.c)
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/ccsds_tab.c
    COMMAND  ${CMAKE_BINARY_DIR}/gen_ccsds > ccsds_tab.c
    DEPENDS  gen_ccsds
)

# generate ccsds_tal.c
add_executable(gen_ccsds_tal gen_ccsds_tal.c)
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/ccsds_tal.c
    COMMAND  ${CMAKE_BINARY_DIR}/gen_ccsds_tal > ccsds_tal.c
    DEPENDS  gen_ccsds_tal
)

# libfec
add_library(libfec_shared SHARED ${libfec_sources})
set_target_properties(libfec_shared PROPERTIES OUTPUT_NAME fec)
set_target_properties(libfec_shared PROPERTIES SOVERSION ${VERSION_INFO_MAJOR})
target_link_libraries(libfec_shared ${M_LIB})


install(TARGETS libfec_shared
    DESTINATION ${LIB_INSTALL_DIR})
install(FILES "${PROJECT_SOURCE_DIR}/fec.h"
    DESTINATION include)


########################################################################
# Create uninstall target
########################################################################
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/cmake_uninstall.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    IMMEDIATE @ONLY)

add_custom_target(uninstall
    COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake)


########################################################################
# Print Summary
########################################################################
message(STATUS "")
message(STATUS "##########################################################")
message(STATUS "## Building for version: ${VERSION}")
message(STATUS "## Target Architecture:  ${TARGET_ARCH}")
message(STATUS "## Using install prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "##########################################################")
message(STATUS "")

