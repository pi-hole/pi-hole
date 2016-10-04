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

import sqlite3, urllib, json
from datetime import datetime

#API to get the summary information from
url = "http://127.0.0.1/admin/api.php?summaryRaw"
response = urllib.urlopen(url)
data = json.loads(response.read())

api_domains_being_blocked = data["domains_being_blocked"]
api_dns_queries_today = data["dns_queries_today"]
api_ads_blocked_today = data["ads_blocked_today"]
api_ads_percentage_today = data["ads_percentage_today"]


# Create the SQLite connection
conn = sqlite3.connect('/etc/pihole/pihole.db')

# Python auto-handle commits, no need to call for commits manually
with conn:
    c = conn.cursor()

    # enable WAL mode
    c.execute('PRAGMA journal_mode=WAL;')

    # Ready new table for list of domains
    gt = '''
    CREATE TABLE IF NOT EXISTS summaries (
        ts datetime,
        domains_being_blocked text,
        dns_queries_today text,
        ads_blocked_today text,
        ads_percentage_today text
    )
    '''
    c.execute(gt)

    #Insert values into summaries table
    sql = "INSERT INTO summaries (ts, domains_being_blocked, dns_queries_today, ads_blocked_today, ads_percentage_today) VALUES (?,?,?,?,?)"
    c.execute(sql, (datetime.now(), api_domains_being_blocked, api_dns_queries_today, api_ads_blocked_today, api_ads_percentage_today))

