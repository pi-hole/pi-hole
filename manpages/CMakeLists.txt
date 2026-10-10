# Pi-hole man pages

install(
    FILES ${CMAKE_CURRENT_SOURCE_DIR}/pihole.8
    DESTINATION ${CMAKE_INSTALL_MANDIR}/man8
    COMPONENT documentation
)

message(STATUS "Manpage will be installed to: ${CMAKE_INSTALL_MANDIR}/man8/pihole.8")
