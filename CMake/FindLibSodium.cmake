# Finds sodium C client library
#
# This module defines:
# LIBSODIUM_INCLUDE_DIRS
# LIBSODIUM_LIBRARIES
#

find_package(PkgConfig)

if (LibSodium_FIND_VERSION)
  pkg_check_modules(LIBSODIUM libsodium>=${LibSodium_FIND_VERSION})
else()
  pkg_check_modules(LIBSODIUM libsodium)
endif()

find_library(
  LIBSODIUM_LIBRARY
  NAMES sodium libsodium
  HINTS ${LIBSODIUM_LIBRARY_DIRS} ${LIBSODIUM_LIBDIR}
)
if (LIBSODIUM_LIBRARY)
  set(LIBSODIUM_LIBRARIES "${LIBSODIUM_LIBRARY}")
endif()

include(FindPackageHandleStandardArgs)
FIND_PACKAGE_HANDLE_STANDARD_ARGS(
  libsodium
  DEFAULT_MSG
  LIBSODIUM_LIBRARIES
  LIBSODIUM_INCLUDEDIR)

set(LIBSODIUM_INCLUDE_DIR "${LIBSODIUM_INCLUDEDIR}")
set(LIBSODIUM_INCLUDE_DIRS "${LIBSODIUM_INCLUDEDIR}")

if (LIBSODIUM_INCLUDEDIR)
  add_definitions(-DHAVE_LIBSODIUM)
endif()
