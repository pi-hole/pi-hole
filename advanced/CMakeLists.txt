# Pi-hole advanced scripts and templates

# List of all scripts to configure
set(PIHOLE_SCRIPTS
    api.sh
    list.sh
    piholeCheckout.sh
    piholeDebug.sh
    piholeLogFlush.sh
    piholeNetworkFlush.sh
    query.sh
    update.sh
    updatecheck.sh
    utils.sh
    version.sh
)

# Configure all scripts and build list for installation
set(PIHOLE_SCRIPTS_BUILT "")
foreach(script ${PIHOLE_SCRIPTS})
    set(script_source "${CMAKE_CURRENT_SOURCE_DIR}/Scripts/${script}.in")
    set(script_built "${CMAKE_CURRENT_BINARY_DIR}/Scripts/${script}")

    configure_file(${script_source} ${script_built} @ONLY)
    list(APPEND PIHOLE_SCRIPTS_BUILT ${script_built})
endforeach()

# Install all configured scripts (DRY: built from PIHOLE_SCRIPTS list)
install(
    PROGRAMS ${PIHOLE_SCRIPTS_BUILT}
    DESTINATION ${PIHOLE_INSTALL_SCRIPTDIR}
    COMPONENT runtime
)

# Install COL_TABLE (no processing needed)
install(
    FILES ${CMAKE_CURRENT_SOURCE_DIR}/Scripts/COL_TABLE
    DESTINATION ${PIHOLE_INSTALL_SCRIPTDIR}
    COMPONENT runtime
)

# Configure database migration script
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/Scripts/database_migration/gravity-db.sh.in
    ${CMAKE_CURRENT_BINARY_DIR}/Scripts/database_migration/gravity-db.sh
    @ONLY
)

# Install database migration script
install(
    PROGRAMS ${CMAKE_CURRENT_BINARY_DIR}/Scripts/database_migration/gravity-db.sh
    DESTINATION ${PIHOLE_INSTALL_SCRIPTDIR}/database_migration
    COMPONENT runtime
)

# Install database migration SQL files (glob all *_to_*.sql files)
file(GLOB GRAVITY_MIGRATION_SQL_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/Scripts/database_migration/gravity/*_to_*.sql"
)
install(
    FILES ${GRAVITY_MIGRATION_SQL_FILES}
    DESTINATION ${PIHOLE_INSTALL_DATADIR}/database_migration/gravity
    COMPONENT data
)

# Install bash completions
install(
    FILES
        ${CMAKE_CURRENT_SOURCE_DIR}/bash-completion/pihole.bash
        ${CMAKE_CURRENT_SOURCE_DIR}/bash-completion/pihole-ftl.bash
    DESTINATION ${CMAKE_INSTALL_DATADIR}/bash-completion/completions
    COMPONENT runtime
)

# Install uninstall script (if keeping it for manual installations)
install(
    PROGRAMS "${CMAKE_SOURCE_DIR}/automated install/uninstall.sh"
    DESTINATION ${PIHOLE_INSTALL_SCRIPTDIR}
    COMPONENT runtime
)

message(STATUS "Advanced scripts will be installed to: ${PIHOLE_INSTALL_SCRIPTDIR}")

# Templates (cron, logrotate, SQL)
add_subdirectory(Templates)
