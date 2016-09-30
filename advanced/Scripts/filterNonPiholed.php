<?php

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
