#!/bin/bash
# Flushes /var/log/pihole.log
truncate -s 0 /var/log/pihole.log
