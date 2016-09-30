<?php

# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Blacklists domains
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
#
# This is a php script that uses the pi-hole admin dashboard
# to get a list of queries, and then filters the json result
# for the queries which were not pi-holed
#
# Usage: php filterNonPiholed.php
#
# Ref: https://github.com/pi-hole/AdminLTE#api
#
# Testing:
# Can run pi-hole in docker using https://hub.docker.com/r/diginc/pi-hole/

$url='http://localhost/admin/api.php?getAllQueries';
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_HEADER, false);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$var = curl_exec($ch);

$json=json_decode($var,true);
$json["data"]=array_filter($json["data"],function($x) {
  return !in_array("Pi-holed",$x);
});
$json=array_column($json["data"],2);
$json=array_unique($json);
sort($json);
echo implode(PHP_EOL,$json)."\n";
