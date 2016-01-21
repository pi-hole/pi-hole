<?php
// lrs.php (Long-rang Scanners)
// Parses pihole.log to extract the top 10 advertisers and the long-term queries vs. ads
date_default_timezone_set('UTC');

//---------------------------------------------------------------------------------------------------
//config

$info_DEBUG = true;
$file_name = "/var/log/pihole.log";
$pie_chart_regexp_query = "query";
$pie_chart_regexp_adver = ": /etc/pihole/gravity.list";

$db_host = "localhost";
$db_name = "charts";
$db_user = "root";
$db_pass = "hi";

//---------------------------------------------------------------------------------------------------
//logging

function errorlog($error_log) {
	global $info_DEBUG;
	if ($info_DEBUG === true) {
		print_r("[".date("Y-m-d H:i:s")."][".getmypid()."][error] ".$error_log."\n");
		print_r("[".date("Y-m-d H:i:s")."][".getmypid()."][error] Script terminated under abnormal conditions\n");
		print_r("[".date("Y-m-d H:i:s")."][".getmypid()."][error] Exiting\n");
		exit;
	}
}

function debuglog($debug_log) {
	global $info_DEBUG;
	if ($info_DEBUG === true)
	print_r("[".date("Y-m-d H:i:s")."][".getmypid()."][debug] ".$debug_log."\n");
}

//---------------------------------------------------------------------------------------------------
//func

function parse_top_chart_advertiser($file_line) {
	global $pie_chart_regexp_adver;
	$adver_position = stripos($file_line, $pie_chart_regexp_adver);
	$adver_substr = substr($file_line, $adver_position);
	$adver_array = explode(" ", $adver_substr);
	$adver = $adver_array[2];
	return $adver;
}

function update_top_chart_stats($db_conn, $top_chart_array, $pie_chart_date) {
	$top_sorted = array_count_values($top_chart_array);
	foreach ($top_sorted as $top_id => $value) {
		$sql_replace_top_chart_stats = "REPLACE INTO top_chart_stats VALUES ('$pie_chart_date', '$top_id', $value)";
		if (!mysqli_query($db_conn, $sql_replace_top_chart_stats)) {
			errorlog("SQL query failed for some reason: $sql_replace_top_chart_stats");
		}else{
			debuglog("SQL query successfully executed: $sql_replace_top_chart_stats");
		}
	}
}

function update_pie_chart_stats($db_conn, $pie_chart_date, $pie_chart_count_query, $pie_chart_count_adver) {
	//daily insert
	$sql_insert_pie_chart_stats = "INSERT IGNORE INTO pie_chart_stats VALUES ('$pie_chart_date', $pie_chart_count_query, $pie_chart_count_adver)";
	if (!mysqli_query($db_conn, $sql_insert_pie_chart_stats)) {
		errorlog("SQL query failed for some reason: $sql_insert_pie_chart_stats");
	}else{
		debuglog("SQL query successfully executed: $sql_insert_pie_chart_stats");
	}
	//total calc
	$sql_select_pie_chart_stats  = "SELECT SUM(query_cnt) AS q_cnt, SUM(adver_cnt) AS a_cnt FROM pie_chart_stats WHERE insert_date != '0000-00-00'";
	if ($res_select_pie_chart_stats = mysqli_query($db_conn, $sql_select_pie_chart_stats)) {
		$arr_select_pie_chart_stats = mysqli_fetch_array($res_select_pie_chart_stats);
		$total_query = $arr_select_pie_chart_stats['q_cnt'];
		$total_adver = $arr_select_pie_chart_stats['a_cnt'];
	}else{
		errorlog("SQL query failed for some reason: $sql_select_pie_chart_stats");
	}
	//total update
	$sql_update_pie_chart_stats = "UPDATE pie_chart_stats SET query_cnt = $total_query, adver_cnt = $total_adver WHERE insert_date = '0000-00-00'";
	if (!mysqli_query($db_conn, $sql_update_pie_chart_stats)) {
		errorlog("SQL query failed for some reason: $sql_update_pie_chart_stats");
	}else{
		debuglog("SQL query successfully executed: $sql_update_pie_chart_stats");
	}
}

//---------------------------------------------------------------------------------------------------
//main

debuglog("Script is started");
$file_name = (isset($argv[1])) ? $argv[1] : $file_name;
if (!file_exists($file_name)) {
	errorlog("Provided log file does not exist ".$file_name);
}else{
	debuglog("Trying to read and parse log file ".$file_name);
}

$pie_chart_date = date("Y-m-d");
$pie_chart_count_query = 0;
$pie_chart_count_adver = 0;
debuglog("Current date == ".$pie_chart_date);
debuglog("Initial amount of 'query' regexp for ".$pie_chart_date." == ".$pie_chart_count_query);
debuglog("Initial amount of 'adver' regexp for ".$pie_chart_date." == ".$pie_chart_count_adver);
$top_chart_array = array();

$file_open = fopen($file_name, "r");
while (!feof($file_open)) {
	$file_line = fgets($file_open);
	if (strpos($file_line, $pie_chart_regexp_query)) debuglog("\tIncremented amount of 'query' regexp for ".$pie_chart_date." == ".++$pie_chart_count_query);
	if (strpos($file_line, $pie_chart_regexp_adver)) {
		debuglog("\tIncremented amount of 'adver' regexp for ".$pie_chart_date." == ".++$pie_chart_count_adver);
		array_push($top_chart_array, parse_top_chart_advertiser($file_line));
	}
}
fclose($file_open);

debuglog("Total amount of 'query' regexp for ".$pie_chart_date." == ".$pie_chart_count_query);
debuglog("Total amount of 'adver' regexp for ".$pie_chart_date." == ".$pie_chart_count_adver);

//---------------------------------------------------------------------------------------------------
//mysql

debuglog("** Trying to connect to database with db_host = $db_host");
debuglog("** Trying to connect to database with db_user = $db_user");
debuglog("** Trying to connect to database with db_pass = __skipped");
debuglog("** Trying to connect to database with db_name = $db_name");
if ($db_conn = mysqli_connect($db_host, $db_user, $db_pass, $db_name)) {
	debuglog("Database connection succesfully established");
}else{
	errorlog("Could not connect to database, check configured DB credentials");
}

debuglog("--- Going to populate data into pie_chart_stats");
update_pie_chart_stats($db_conn, $pie_chart_date, $pie_chart_count_query, $pie_chart_count_adver);
debuglog("--- Data populated into pie_chart_stats");
debuglog("--- Going to populate data into top_chart_stats");
update_top_chart_stats($db_conn, $top_chart_array, $pie_chart_date);
debuglog("--- Data populated into top_chart_stats");
debuglog("Script is finished");
