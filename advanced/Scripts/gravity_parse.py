#!/usr/bin/env python
# -*- coding: utf-8 -*-

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

# Logfile containing unique list of all domains on downloaded lists.
logfile = '/etc/pihole/pihole.2.eventHorizon.txt'

# Create the SQLite connection
conn = sqlite3.connect('/etc/pihole/gravity.db')

# Python auto-handle commits, no need to call for commits manually
with conn:
    c = conn.cursor()

    # Lists have just been downloaded, clear out the existing data
    c.execute('DROP TABLE IF EXISTS gravity')

    # Ready new table for list of domains
    gt = '''
    CREATE TABLE IF NOT EXISTS gravity (
        idx INTEGER PRIMARY KEY ASC,
        domain text
    )
    '''
    c.execute(gt)

    # enable WAL mode
    c.execute('PRAGMA journal_mode=WAL;')

    # Parse the log file into the database
    with open(logfile) as f:
        for line in f:
            line = line.rstrip()
            sql = "INSERT INTO gravity (domain) VALUES (?)"
            c.execute(sql, (line,))
