#!/usr/bin/env bash
# Flushes /var/log/pihole.log
# (c) 2015 by Jacob Salmela
# This file is part of Pi-hole.
#
#Pi-hole is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 2 of the License, or
#(at your option) any later version.

truncate -s 0 /var/log/pihole.log
