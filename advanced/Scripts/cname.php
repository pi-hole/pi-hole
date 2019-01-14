<?php
$CNAMEFILE = "/etc/dnsmasq.d/05-pihole-cname.conf"; # Also in webpage.sh

if ($argc != 4) {
    echo "USAGE: php -f cname.php [add/remove] hostname alias1,alias2,alias3,...\n";
    exit(1);
}

$action = $argv[1];
$host = strtolower(trim($argv[2]));
$aliases = strtolower(trim($argv[3]));

if (!verifyHostname($host)) {
    echo "Invalid Hostname: $host\n";
    exit(1);
}

switch ($action) {
    case "add":
        echo "Trying to add CNAMEs to $host\n";
        $cnames = readCNameFile();
        if ($cnames === false) {
            exit(1);
        }
        $line = "cname=$aliases,$host\n";
        $changed = addLineToList($cnames, $line);
        if ($changed === true) {
            echo "Writing $CNAMEFILE...\n";
            sortCNames($cnames);
            writeCNAMEFile($cnames);
        } else {
            echo "No changes made.\n";
        }
        break;
    case "remove":
        echo "Removing $aliases from $host\n";
        $cnames = readCNameFile();
        if ($cnames === false) {
            exit(1);
        }
        $existingCnameEntry = &findCNAMEHostnameEntry($cnames, $host);
        if ($existingCnameEntry === false) {
            echo "No CNAME for $host found.\n";
            exit(0); # Not an error
        }

        $changed = false;
        $existingAliases = &$existingCnameEntry["aliases"];
        foreach (explode(",", $aliases) as $alias) {
            $alias = strtolower(trim($alias));
            $aliasKey = array_search($alias, $existingAliases);
            if ($aliasKey === false) {
                break;
            }
            $changed = true;
            unset($existingAliases[$aliasKey]);
        }

        if ($changed === true) {
            echo "Writing $CNAMEFILE...\n";
            sortCNames($cnames);
            writeCNAMEFile($cnames);
        } else {
            echo "No changes made.\n";
        }
        break;
    default:
        echo "Unsupported Action.\n";
        exit(1);
        break;
}
exit(0);

function readCNameFile()
{
    global $CNAMEFILE;
    $result = array();
    if (!file_exists($CNAMEFILE)) {
        return $result;
    }

    try
    {
        $cnames = @fopen($CNAMEFILE, 'r');
    } catch (Exception $e) {
        echo "Warning: Failed to read " . $CNAMEFILE . ", this is not an error";
        return false;
    }

    try
    {
        if (!is_resource($cnames)) {
            return false;
        }

        while (!feof($cnames)) {
            $line = fgets($cnames);
            addLineToList($result, $line);
        }

        return $result;
    } finally {
        if (is_resource($cnames)) {
            fclose($cnames);
        }
    }
}

function sortCNames(&$cnames)
{
    uasort($cnames, function ($a, $b) {
        return strnatcmp($a["host"], $b["host"]);
    });
    foreach ($cnames as &$host) {
        uasort($host["aliases"], 'strnatcmp');
    }
}

function addLineToList(&$cnames, $line)
{
    // cname=alias,hostname
    // cname=alias1,alias2,alias3,hostname
    $line = strtolower(trim($line));
    if (!$line) {
        return false;
    }

    $m = preg_match('/^\s*(#){0}\s*cname\s*=\s*(?<Aliases>.+),(?<Hostname>.+)\s*/im', $line, $matches);
    if ($m !== 1) {
        return false;
    }

    $hostname = strtolower(trim($matches["Hostname"]));
    $aliases = explode(",", $matches["Aliases"]);

    $result = false;

    $hasHost = array_search($hostname, $aliases);
    if ($hasHost !== false) {
        unset($aliases[$hasHost]);
    }

    $goodAliases = array();
    foreach ($aliases as $alias) {
        if (verifyHostname($alias)) {
            array_push($goodAliases, $alias);
        } else {
            echo "Invalid Alias: $alias\n";
        }
    }

    $existing = &findCNAMEHostnameEntry($cnames, $hostname);
    if ($existing !== false) {
        foreach ($goodAliases as $alias) {
            if (addCNAMEAlias($existing, $alias)) {
                echo "Added $alias\n";
                $result = true;
            } else {
                echo "$alias already exists\n";
            }
        }
    } else {
        array_push($cnames, ["host" => $hostname, "aliases" => $goodAliases]);
        $result = true;
    }
    return $result;
}

function addCNAMEAlias(&$entry, $alias)
{
    $eAlias = &$entry["aliases"];
    $alias = strtolower(trim($alias));
    if (strlen($alias) < 1) {
        return false;
    }
    if (array_search($alias, $eAlias) === false) {
        array_push($eAlias, $alias);
        return true;
    }
    return false;
}

function &findCNAMEHostnameEntry(&$cnames, $hostname)
{
    $key = array_search($hostname, array_column($cnames, "host"));
    if ($key === false) {
        $entry = false;
    } else {
        $entry = &$cnames[$key];
    }
    return $entry;
}

function writeCNAMEFile($cnames)
{
    global $CNAMEFILE;

    $outFile = null;
    try
    {
        $outFile = @fopen($CNAMEFILE, 'w');
        foreach ($cnames as $hostAliases) {
            $aliases = $hostAliases["aliases"];
            if (count($aliases) < 1) {
                continue;
            }

            fwrite($outFile, sprintf("cname=%s,%s\n", implode(",", $aliases), $hostAliases["host"]));
        }
        fflush($outFile);
    } catch (Exception $e) {
        $errorMsg = sprintf("Failed to save CNAMEs: %s", $e->message);
        error_log($errorMsg);
        echo $errorMsg;
        return false;
    } finally {
        if (is_resource($outFile)) {
            fclose($outFile);
        }

    }
}

function verifyHostname($hostname)
{
    return (preg_match("/^([a-z\d](-*[a-z\d])*)(\.([a-z\d](-*[a-z\d])*))*$/i", $hostname) //valid chars check
         && preg_match("/^.{1,253}$/", $hostname) //overall length check
         && preg_match("/^[^\.]{1,63}(\.[^\.]{1,63})*$/", $hostname)); //length of each label
}
