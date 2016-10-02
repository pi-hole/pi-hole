#!/usr/bin/env python
# -*- coding: utf-8 -*-

# Copyright (c) 2015, LCI Technology Group, LLC
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#  Redistributions of source code must retain the above copyright notice, this
#  list of conditions and the following disclaimer.
#
#  Redistributions in binary form must reproduce the above copyright notice,
#  this list of conditions and the following disclaimer in the documentation
#  and/or other materials provided with the distribution.
#
#  Neither the name of LCI Technology Group, LLC nor the names of its
#  contributors may be used to endorse or promote products derived from this
#  software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Controller for all pihole scripts and functions.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

import sqlite3

#-----------------------------------------------------------------------------
# Functions
#-----------------------------------------------------------------------------
def create_tables():

    qt = 'DROP TABLE IF EXISTS gravity'
    c.execute(qt)
    conn.commit()

    qt = '''
    CREATE TABLE IF NOT EXISTS gravity (
        idx integer primary key autoincrement,
        domain text
    )
    '''
    c.execute(qt)
    conn.commit()

#-----------------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------------

logfile = '/etc/pihole/pihole.2.eventHorizon.txt'

counts = {'lc': 0}

# Create the SQLite connection
conn = sqlite3.connect('/etc/pihole/pihole.db')
conn.text_factory = str  # I don't like it as a fix, but it works for now
c = conn.cursor()

create_tables()

sql = "DELETE FROM gravity"
c.execute(sql)
conn.commit()

# Parse the log file.
for line in open(logfile):
    line = line.rstrip()
    counts['lc'] += 1

    if (counts['lc'] % 10000) == 0:
        conn.commit()

    sql = "INSERT INTO gravity (domain) VALUES (?)"
    c.execute(sql, (line,))

conn.commit()
