# Pi-hole template files (cron, logrotate, SQL)

# Configure templates (explicit source/build separation)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/pihole.cron.in
    ${CMAKE_CURRENT_BINARY_DIR}/pihole.cron
    @ONLY
)

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/logrotate.in
    ${CMAKE_CURRENT_BINARY_DIR}/logrotate
    @ONLY
)

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/gravity_copy.sql.in
    ${CMAKE_CURRENT_BINARY_DIR}/gravity_copy.sql
    @ONLY
)

# Install cron job to system cron.d directory
install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/pihole.cron
    DESTINATION ${CMAKE_INSTALL_SYSCONFDIR}/cron.d
    RENAME pihole
    PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ
    COMPONENT cron
)

# Install logrotate config to pi-hole config directory
install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/logrotate
    DESTINATION ${PIHOLE_INSTALL_SYSCONFDIR}
    PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ
    COMPONENT config
)

# Install database templates to /usr/share/pihole/sql/
install(
    FILES
        ${CMAKE_CURRENT_SOURCE_DIR}/gravity.db.sql
        ${CMAKE_CURRENT_BINARY_DIR}/gravity_copy.sql
    DESTINATION ${PIHOLE_INSTALL_DATADIR}/sql
    COMPONENT data
)

message(STATUS "Templates will be installed:")
message(STATUS "  Cron:      ${CMAKE_INSTALL_FULL_SYSCONFDIR}/cron.d/pihole")
message(STATUS "  Logrotate: ${PIHOLE_INSTALL_SYSCONFDIR}/logrotate")
message(STATUS "  SQL:       ${PIHOLE_INSTALL_DATADIR}/sql/")
