<?php
if ((isset($argv[1])) && (isset($argv[2]))) {
  $json="$argv[1]";
  $key="$argv[2]";
  $result=json_decode($json, true);
  if (is_array($result)) {
    if (array_key_exists($key, $result)) {
      echo "$result[$key]";
    } else {
      //key dosnt exist
      die("Error");
    }
  } else {
    //invalid json
    die("Error");
  }
} else {
  die("Usage: php json.php \"JSON DATA HERE\" \"Key\"");
}
?>
