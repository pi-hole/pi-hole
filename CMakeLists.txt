cmake_minimum_required(VERSION 3.12)

# Script-only project - no compilation required
project(PIHOLE_CORE NONE)

# Set default install prefix to /opt/pihole for backward compatibility
# Packagers (e.g., Yocto) can override with -DCMAKE_INSTALL_PREFIX=/usr
if(NOT DEFINED CMAKE_INSTALL_PREFIX OR CMAKE_INSTALL_PREFIX STREQUAL "/usr/local")
    set(CMAKE_INSTALL_PREFIX "/opt/pihole" CACHE PATH "Install prefix" FORCE)
endif()

# Suppress GNUInstallDirs warning for architecture-independent script project
# We don't use CMAKE_INSTALL_LIBDIR (only CMAKE_INSTALL_LIBSTATEDIR for /var/lib)
set(CMAKE_INSTALL_LIBDIR "lib" CACHE PATH "Library directory (unused)")

# Force FHS system directories BEFORE GNUInstallDirs (CMake <4.1 workaround)
# In CMake 4.1+, CMP0192 would handle this automatically for /opt prefixes
# These directories are ALWAYS absolute (/etc, /var, /run) per FHS 3.0
set(CMAKE_INSTALL_SYSCONFDIR "/etc" CACHE PATH "System configuration (/etc)" FORCE)
set(CMAKE_INSTALL_LOCALSTATEDIR "/var" CACHE PATH "Variable state data (/var)" FORCE)
set(CMAKE_INSTALL_RUNSTATEDIR "/run" CACHE PATH "Runtime data (/run)" FORCE)

include(GNUInstallDirs)

# XXX maybe a gap, maybe not. But we need it for dealing with several other packages variable state
if(NOT DEFINED CMAKE_INSTALL_LIBSTATEDIR)
    set(CMAKE_INSTALL_LIBSTATEDIR "${CMAKE_INSTALL_LOCALSTATEDIR}/lib" CACHE PATH "Binary directory")
endif()

# Pi-hole specific paths (PREFIX-dependent)
if(CMAKE_INSTALL_PREFIX MATCHES "^/opt/")
    # ====== BACKWARD COMPATIBILITY MODE (PREFIX=/opt/pihole) ======
    # Original pi-hole layout:
    # - Scripts directly in /opt/pihole (not /opt/pihole/libexec!)
    # - Binary in /usr/local/bin (outside PREFIX!)
    # - Data with config in /etc/pihole (not /var/lib!)

    set(PIHOLE_INSTALL_SCRIPTDIR "${CMAKE_INSTALL_PREFIX}" CACHE PATH "Script directory")
    set(CMAKE_INSTALL_BINDIR "/usr/local/bin" CACHE PATH "Binary directory" FORCE)
    set(PIHOLE_INSTALL_DATADIR "/etc/pihole" CACHE PATH "Data directory")
    set(PIHOLE_SUMMARY_MSG "Backward Compat")

else()
    # ====== FHS 3.0 MODE (PREFIX=/usr or other) ======
    # Standard FHS layout:
    # - Scripts in /usr/libexec/pihole
    # - Binary in /usr/bin
    # - Data in /var/lib/pihole (separate from config)

    set(PIHOLE_INSTALL_SCRIPTDIR "${CMAKE_INSTALL_FULL_LIBEXECDIR}/pihole" CACHE PATH "Script directory")
    set(PIHOLE_INSTALL_DATADIR "${CMAKE_INSTALL_DATADIR}/pihole" CACHE PATH "Data directory")
    set(PIHOLE_SUMMARY_MSG "FHS 3.0")
endif()

# Shared paths (same in both modes)
set(PIHOLE_INSTALL_SYSCONFDIR "${CMAKE_INSTALL_FULL_SYSCONFDIR}/pihole" CACHE PATH "Config directory")
set(PIHOLE_INSTALL_LIBSTATEDIR "${CMAKE_INSTALL_LIBSTATEDIR}/pihole" CACHE PATH "Variable state directory")
set(PIHOLE_INSTALL_LOGDIR "${CMAKE_INSTALL_LOCALSTATEDIR}/log/pihole" CACHE PATH "Log directory")
set(PIHOLE_INSTALL_RUNDIR "${CMAKE_INSTALL_RUNSTATEDIR}/pihole" CACHE PATH "Runtime directory")
set(PIHOLE_INSTALL_WEBROOT "${CMAKE_INSTALL_LOCALSTATEDIR}/www" CACHE PATH "Web server root directory")
set(PIHOLE_INSTALL_WEBDIR "${PIHOLE_INSTALL_WEBROOT}/html/admin" CACHE PATH "Web interface directory")

# Absolute path variants for use in configuration files (systemd units, shell scripts, pkg-config)
# These must be used in configure_file() templates because systemd Exec* directives and
# shell script shebangs require absolute paths at runtime.
# Reference: https://cmake.org/cmake/help/latest/module/GNUInstallDirs.html
# Note: CMAKE_INSTALL_FULL_* variables respect DESTDIR during installation, making them
# safe for packaging systems (Yocto, Debian, RPM). They expand at configure-time with
# the correct prefix, and install(FILES ...) automatically handles DESTDIR staging.
# Note: PIHOLE_INSTALL_SCRIPTDIR is already absolute in both modes (lines 37, 49),
# but we define _FULL variants for consistency with FTL and future template usage.
set(PIHOLE_INSTALL_FULL_SCRIPTDIR "${PIHOLE_INSTALL_SCRIPTDIR}")  # Already absolute
set(PIHOLE_INSTALL_FULL_LOGDIR "${PIHOLE_INSTALL_LOGDIR}")  # Already absolute
set(PIHOLE_INSTALL_FULL_RUNDIR "${PIHOLE_INSTALL_RUNDIR}")  # Already absolute
set(PIHOLE_INSTALL_FULL_LIBSTATEDIR "${PIHOLE_INSTALL_LIBSTATEDIR}")  # Already absolute
set(PIHOLE_INSTALL_FULL_WEBROOT "${PIHOLE_INSTALL_WEBROOT}")  # Already absolute
set(PIHOLE_INSTALL_FULL_WEBDIR "${PIHOLE_INSTALL_WEBDIR}")  # Already absolute

# FTL integration (provided by FTL package)
# Try to use FTL's CMake config if available (FTL v6.4.1+)
find_package(PiholeFTL QUIET)

if(PiholeFTL_FOUND)
    # Use paths provided by FTL's CMake config
    set(PIHOLE_FTL_BINARY "${PiholeFTL_BINARY}" CACHE PATH "FTL binary (from PiholeFTL package)" FORCE)
    set(PIHOLE_FTL_SCRIPT_DIR "${PiholeFTL_SCRIPTS_DIR}" CACHE PATH "FTL scripts directory (from PiholeFTL package)" FORCE)
    message(STATUS "Found PiholeFTL v${PiholeFTL_VERSION}")
else()
    # Fallback to assumed paths if FTL config not found
    # Note: These are heuristic guesses. Install FTL first to generate PiholeFTLConfig.cmake for accurate paths.
    message(STATUS "PiholeFTL package not found, using fallback paths")
    if(CMAKE_INSTALL_PREFIX MATCHES "^/opt/")
        # Backward compat mode: FTL typically installed system-wide in /usr/bin
        # (not in /usr/local/bin like CMAKE_INSTALL_BINDIR suggests)
        set(PIHOLE_FTL_BINARY "/usr/bin/pihole-FTL" CACHE PATH "FTL binary (fallback)")
        set(PIHOLE_FTL_SCRIPT_DIR "${PIHOLE_INSTALL_FULL_SCRIPTDIR}" CACHE PATH "FTL scripts directory (fallback)")
    else()
        # FHS mode: Use CMAKE paths consistently
        set(PIHOLE_FTL_BINARY "${CMAKE_INSTALL_FULL_BINDIR}/pihole-FTL" CACHE PATH "FTL binary (fallback)")
        set(PIHOLE_FTL_SCRIPT_DIR "${PIHOLE_INSTALL_FULL_SCRIPTDIR}" CACHE PATH "FTL scripts directory (fallback)")
    endif()
endif()

# Legacy path for basic-install.sh compatibility
set(PIHOLE_GIT_CLONE_DIR "/etc/.pihole" CACHE PATH "Git clone directory (basic-install.sh only)")

# Debug output (use absolute _FULL_ paths for clarity)
message(STATUS "Pi-hole Core Installation Paths:")
message(STATUS "  Mode:     ${CMAKE_INSTALL_PREFIX} (${PIHOLE_SUMMARY_MSG})")
message(STATUS "  Binaries: ${CMAKE_INSTALL_BINDIR} (${CMAKE_INSTALL_FULL_BINDIR})")
message(STATUS "  Scripts:  ${PIHOLE_INSTALL_SCRIPTDIR} (${PIHOLE_INSTALL_FULL_SCRIPTDIR})")
message(STATUS "  Config:   ${PIHOLE_INSTALL_SYSCONFDIR} (${CMAKE_INSTALL_FULL_SYSCONFDIR})")
message(STATUS "  Data:     ${PIHOLE_INSTALL_DATADIR}")
message(STATUS "  Logs:     ${PIHOLE_INSTALL_LOGDIR}")
message(STATUS "  Runtime:  ${PIHOLE_INSTALL_RUNDIR}")
message(STATUS "  Webroot:  ${PIHOLE_INSTALL_WEBROOT}")
message(STATUS "  Web UI:   ${PIHOLE_INSTALL_WEBDIR}")
message(STATUS "  FTL bin:     ${PIHOLE_FTL_BINARY}")
message(STATUS "  FTL scripts: ${PIHOLE_FTL_SCRIPT_DIR}")

# Components
add_subdirectory(src)
add_subdirectory(advanced)
add_subdirectory(manpages)

# Optional Docker support
option(BUILD_DOCKER "Build Docker image" OFF)
if(BUILD_DOCKER)
    add_subdirectory(docker)
endif()
