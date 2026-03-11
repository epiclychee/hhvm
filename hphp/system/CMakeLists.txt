set(CXX_SOURCES "systemlib.cpp")

add_library(hphp_system STATIC ${CXX_SOURCES})
target_link_libraries(hphp_system hphp_util proxygen hhvm_base_headers)

auto_sources(files "*.h" "${CMAKE_CURRENT_SOURCE_DIR}")
HHVM_PUBLIC_HEADERS(system ${files})

set(SYSTEMLIB_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/../runtime/ext/core/php.txt")
set(SYSTEMLIB_GENERATOR "${CMAKE_CURRENT_SOURCE_DIR}/../runtime/ext/core/make_systemlib.sh")

FILE(STRINGS "${SYSTEMLIB_MANIFEST}" SYSTEMLIB_CLASSES)
set(SYSTEMLIB_SRCS)
set(SYSTEMLIB_SRCS_STR)
foreach(cls ${SYSTEMLIB_CLASSES})
  STRING(REGEX REPLACE "[ \t]*#.*" "" cls "${cls}")
  if (NOT "${cls}" STREQUAL "")
    STRING(REGEX REPLACE "^hphp/system/php/" "hphp/runtime/ext/core/php/" cls "${cls}")
    list(APPEND SYSTEMLIB_SRCS "${CMAKE_SOURCE_DIR}/${cls}")
    set(
      SYSTEMLIB_SRCS_STR
      "${SYSTEMLIB_SRCS_STR} ${CMAKE_SOURCE_DIR}/${cls}"
    )
  endif()
endforeach()

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/systemlib.php
  DEPENDS "${SYSTEMLIB_MANIFEST}" ${SYSTEMLIB_SRCS}
  COMMAND "${SYSTEMLIB_GENERATOR}"
          "${CMAKE_CURRENT_BINARY_DIR}/systemlib.php"
          "${SYSTEMLIB_SRCS_STR}"
  COMMENT "Generating systemlib.php")

add_custom_target(
  systemlib
  DEPENDS
  ${CMAKE_CURRENT_BINARY_DIR}/systemlib.php
  generated_systemlib
)
