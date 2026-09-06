# Pi-hole Core main scripts

# Configure main scripts (explicit source/build separation)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/pihole.in
    ${CMAKE_CURRENT_BINARY_DIR}/pihole
    @ONLY
)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/gravity.sh.in
    ${CMAKE_CURRENT_BINARY_DIR}/gravity.sh
    @ONLY
)

# Install main pihole command to bin directory
install(
    PROGRAMS ${CMAKE_CURRENT_BINARY_DIR}/pihole
    DESTINATION ${CMAKE_INSTALL_BINDIR}
    COMPONENT runtime
)

# Install gravity.sh to script directory
install(
    PROGRAMS ${CMAKE_CURRENT_BINARY_DIR}/gravity.sh
    DESTINATION ${PIHOLE_INSTALL_SCRIPTDIR}
    COMPONENT runtime
)

message(STATUS "Main scripts will be installed to:")
message(STATUS "  pihole -> ${CMAKE_INSTALL_BINDIR}/pihole")
message(STATUS "  gravity.sh -> ${PIHOLE_INSTALL_SCRIPTDIR}/gravity.sh")
