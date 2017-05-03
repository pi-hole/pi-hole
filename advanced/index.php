<?php
/* Pi-hole: A black hole for Internet advertisements
*  (c) 2017 Pi-hole, LLC (https://pi-hole.net)
*  Network-wide ad blocking via your own hardware.
*
*  This file is copyright under the latest version of the EUPL.
*  Please see LICENSE file for your rights under this license. */

// Function to validate server name (Including underscores & IPv6)
ini_set("pcre.recursion_limit", 1500); 
function validate_server_name($domain) { // Cr: http://stackoverflow.com/a/4694816
    if (filter_var($domain, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) return TRUE;
    return (preg_match("/^([a-z\d]((-|_)*[a-z\d])*)(\.([a-z\d]((-|_)*[a-z\d])*))*$/i", $domain) // Valid chars check
        && preg_match("/^.{1,253}$/", $domain) // Overall length check
        && preg_match("/^[^\.]{1,63}(\.[^\.]{1,63})*$/", $domain)); // Length of each label
}

// Validate SERVER_NAME output
if (validate_server_name($_SERVER["SERVER_NAME"]) === TRUE) {
    $serverName = $_SERVER["SERVER_NAME"];
} else {
    die("[ERROR]: <code>SERVER_NAME</code> header output does not appear to be valid: <code>".$_SERVER["SERVER_NAME"]."</code>");
}

// Get values from setupVars.conf
$setupVars = parse_ini_file("/etc/pihole/setupVars.conf");
$svFQDN = (!empty($setupVars["FQDN"]) && validate_server_name($setupVars["FQDN"]) === TRUE) ? $setupVars["FQDN"] : "";
$svPasswd = !empty($setupVars["WEBPASSWORD"]);
$svEmail = (!empty($setupVars["ADMIN_EMAIL"]) && filter_var($setupVars["ADMIN_EMAIL"], FILTER_VALIDATE_EMAIL)) ? $setupVars["ADMIN_EMAIL"] : "";
unset($setupVars);

// Set landing page name, found within /var/www/html/pihole/
$landPage = "../landing.php";

// Set empty array for hostnames to be accepted as self address for splash page
$authorizedHosts = [];

// Append FQDN to $authorizedHosts
if (!empty($svFQDN)) array_push($authorizedHosts, $svFQDN);
  
// Append virtual hostname to $authorizedHosts
if (!empty($_SERVER["VIRTUAL_HOST"])) {
    if (validate_server_name($_SERVER["VIRTUAL_HOST"]) === TRUE) {
        array_push($authorizedHosts, $_SERVER["VIRTUAL_HOST"]);
    } else {
        die("[ERROR]: <code>VIRTUAL_HOST</code> header output does not appear to be valid: <code>".$_SERVER["VIRTUAL_HOST"]."</code>");
    }
}

// Set which extension types get rendered as "Website Blocked" (Including "" for index file extensions)
$validExtTypes = array("asp", "htm", "html", "php", "rss", "xml", "");

// Get extension of current URL
$currentUrlExt = pathinfo($_SERVER["REQUEST_URI"], PATHINFO_EXTENSION);

// Set mobile friendly viewport
$viewPort = '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>';

// Set response header
function setHeader($type = "x") {
    header("X-Pi-hole: A black hole for Internet advertisements.");
    if (isset($type) && $type === "js") header("Content-Type: application/javascript");
}

// Determine block page redirect
if ($serverName === "pi.hole") {
    exit(header("Location: /admin"));
} elseif (filter_var($serverName, FILTER_VALIDATE_IP) || in_array($serverName, $authorizedHosts)) {
    // Show splash page or landing page when directly browsing via IP or auth'd hostname
    $splashPage = "
    <html><head>
        $viewPort
        <link rel='stylesheet' href='/pihole/blockingpage.css' type='text/css'/>
    </head><body id='splashpage'><img src='/admin/img/logo.svg'/><br/>Pi-<b>hole</b>: Your black hole for Internet advertisements</body></html>
    ";
    $pageType = is_file(getcwd()."/$landPage") ? include $landPage : "$splashPage";
    unset($serverName, $svFQDN, $svPasswd, $svEmail, $authorizedHosts, $validExtTypes, $currentUrlExt, $viewPort);
    exit($pageType);
} elseif ($currentUrlExt === "js") {
    // Set Javascript redirect for blocked sources
    exit(setHeader("js").'var x = "Pi-hole: A black hole for Internet advertisements."');
} elseif (strpos($_SERVER["REQUEST_URI"], "?") !== FALSE && isset($_SERVER["HTTP_REFERER"])) {
    // Set blank image upon receiving REQUEST_URI w/ query string & HTTP_REFERRER (Presumably from iframe)
    exit(setHeader().'<html>
        <head><script>window.close();</script></head>
        <body><img src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACwAAAAAAQABAAACAkQBADs="></body>
    </html>');
} elseif (!in_array($currentUrlExt, $validExtTypes) || substr_count($_SERVER["REQUEST_URI"], "?")) {
    // Set svg image upon receiving non $validExtTypes URL extension or query string (Presumably not from an iframe)
    $blockImg = '<a href="/"><svg xmlns="http://www.w3.org/2000/svg" width="110" height="16"><defs><style>a {text-decoration: none;} circle {stroke: rgba(152,2,2,0.5); fill: none; stroke-width: 2;} rect {fill: rgba(152,2,2,0.5);} text {opacity: 0.3; font: 11px Arial;}</style></defs><circle cx="8" cy="8" r="7"/><rect x="10.3" y="-6" width="2" height="12" transform="rotate(45)"/><text x="19.3" y="12">Blocked by Pi-hole</text></svg></a>';
    exit(setHeader()."<html>
        <head>$viewPort</head>
        <body>$blockImg</body>
    </html>");
}

/* Start processing block page from here */

// Get Pi-hole core branch name
$phBranch = exec("cd /etc/.pihole/ && git rev-parse --abbrev-ref HEAD");
if ($phBranch !== "master") {
    error_reporting(E_ALL);
    ini_set("display_errors", 1);
    ini_set("display_startup_errors", 1);
}

// Validate SERVER_IP output
if (filter_var($_SERVER['SERVER_ADDR'], FILTER_VALIDATE_IP)) {
    $serverAddr = $_SERVER["SERVER_ADDR"];
} else {
    die("[ERROR]: <code>SERVER_IP</code> header output does not appear to be valid: <code>".$_SERVER["SERVER_ADDR"]."</code>");
}

// Determine placeholder text based off $svPasswd presence
$wlPlaceHolder = empty($svPasswd) ? "No admin password set" : "Javascript disabled";

// Get admin email address
$bpAskAdmin = !empty($svEmail) ? '<a href="mailto:'.$svEmail.'?subject=Site Blocked: '.$serverName.'"></a>' : "<span/>";

// Determine if at least one block list has been generated
if (empty(glob("/etc/pihole/list.0.*.domains"))) die("[ERROR]: There are no domain lists generated lists within <code>/etc/pihole/</code>! Please update gravity by running <code>pihole -g</code>, or repair Pi-hole using <code>pihole -r</code>.");

// Get contents of adlist.list
$adLists = is_file("/etc/pihole/adlists.list") ? "/etc/pihole/adlists.list" : "/etc/pihole/adlists.default";
if (!is_file($adLists)) die("[ERROR]: Unable to find file: <code>$adLists</code>");

// Get all URLs starting with "http" or "www" from $adLists and re-index array numerically
$adlistsUrls = array_values(preg_grep("/(^http)|(^www)/i", file($adLists, FILE_IGNORE_NEW_LINES)));
if (empty($adlistsUrls)) die("[ERROR]: There are no adlist URL's found within <code>$adLists</code>");
$adlistsCount = count($adlistsUrls) + 3; // +1 because array starts at 0, +2 for Blacklist & Wildcard lists

// Get results of queryads.php exact search
ini_set("default_socket_timeout", 3);
function queryAds($serverName) {
    $preQueryTime = microtime(true)-$_SERVER["REQUEST_TIME_FLOAT"];
    $queryAds = file("http://127.0.0.1/admin/scripts/pi-hole/php/queryads.php?domain=$serverName&exact", FILE_IGNORE_NEW_LINES);
    $queryTime = sprintf("%.0f", (microtime(true)-$_SERVER["REQUEST_TIME_FLOAT"]) - $preQueryTime);
    try {
        if ($queryTime >= ini_get("default_socket_timeout")) {
            throw new Exception ("Connection timeout (".ini_get("default_socket_timeout")."s)");
        } elseif ($queryAds[0][0] === ":") {
            if (strpos($queryAds[0], "Invalid") !== FALSE) throw new Exception ("Invalid Domain ($serverName)");
            if (strpos($queryAds[0], "No exact") !== FALSE) return array("0" => "none");
            throw new Exception ("Unhandled error message (<code>$queryAds[0]</code>)");
        } elseif ($queryAds[0][0] !== "/") {
            throw new Exception ("Unexpected output (<code>$queryAds[0]</code>)");
        }
        return $queryAds;
    } catch (Exception $e) {
        return array("0" => "error", "1" => $e->getMessage());
    }
}
$queryAds = queryAds($serverName);

if ($queryAds[0] === "error") {
    die("[ERROR]: Unable to parse results from <i>queryads.php</i>: <code>".$queryAds[1]."</code>");
}

// Filter, sort, and count $queryAds array
if ($queryAds[0] !== "none") {
    $queryAds = preg_replace("/(\/etc\/pihole\/)|(\/etc\/dnsmasq\.d\/)/", "", $queryAds);
    $queryAds = preg_replace("/(^list\.)|(\..*domains)/", "", $queryAds);
    $featuredTotal = count($queryAds);
}

// Determine if domain has been blacklisted or wildcarded
if ($queryAds[0] === "blacklist.txt") {
    $intBlacklist = array("&#960;" => $queryAds[0]);
    $queryAds[0] = "&#960;"; // Manually blacklisted sites do not have a number
    $notableFlagClass = "blacklist";
} elseif ($queryAds[0] === "03-pihole-wildcard.conf") {
    $intBlacklist = array("&#960;" => $queryAds[0]);
    $queryAds[0] = "&#960;";
    $notableFlagClass = "wildcard";
} elseif ($queryAds[0] === "none") {
    $featuredTotal = "0";
    $notableFlagClass = "noblock";

    // Determine appropriate info message if CNAME exists
    $dnsRecord = dns_get_record("$serverName")[0];
    if (array_key_exists("target", $dnsRecord)) {
        $wlInfo = $dnsRecord['target'];
    } else {
        $wlInfo = "recentwl";
    }
}

// Merge $intBlacklist with $adlistsUrls if domain has been blacklisted or wildcarded
if (isset($intBlacklist)) $adlistsUrls = array_merge($intBlacklist, $adlistsUrls);

// Set #bpOutput notification
$wlOutputClass = (isset($wlInfo) && $wlInfo === "recentwl") ? $wlInfo : "hidden";
$wlOutput = (isset($wlInfo) && $wlInfo !== "recentwl") ? "<a href='http://$wlInfo'>$wlInfo</a>" : "";

// Get Pi-hole core version
if ($phBranch !== "master") {
    $phVersion = exec("cd /etc/.pihole/ && git describe --long --dirty --tags");
    $execTime = microtime(true)-$_SERVER["REQUEST_TIME_FLOAT"];
} else {
    $phVersion = exec("cd /etc/.pihole/ && git describe --tags --abbrev=0");
}
?>
<!DOCTYPE html>
<html>
<!-- Pi-hole: A black hole for Internet advertisements
*  (c) 2017 Pi-hole, LLC (https://pi-hole.net)
*  Network-wide ad blocking via your own hardware.
*
*  This file is copyright under the latest version of the EUPL. -->
<head>
  <meta charset="UTF-8">
  <?=$viewPort ?>
  <?=setHeader() ?>
  <meta name="robots" content="noindex,nofollow"/>
  <meta http-equiv="x-dns-prefetch-control" content="off">
  <link rel="shortcut icon" href="http://<?=$serverAddr ?>/admin/img/favicon.png" type="image/x-icon"/>
  <link rel="stylesheet" href="http://<?=$serverAddr ?>/blockpage.css" type="text/css"/>
  <title>● <?=$serverName ?></title>
  <script src="http://<?=$serverAddr ?>/admin/scripts/vendor/jquery.min.js"></script>
  <script>
    window.onload = function () {
      <?php
      // Remove href fallback from "Back to safety" button
      if ($featuredTotal > 0) echo '$("#bpBack").removeAttr("href");';
      // Enable whitelisting if $svPasswd is present & JS is available
      if (!empty($svPasswd) && $featuredTotal > 0) {
          echo '$("#bpWLPassword, #bpWhitelist").prop("disabled", false);';
          echo '$("#bpWLPassword").attr("placeholder", "Password");';
      }
      ?>
    }
  </script>
</head>
<body id="blockpage"><div id="bpWrapper">
<header>
  <h1 id="bpTitle">
    <a class="title" href="/"><?php //Website Blocked ?></a>
  </h1>
  <div class="spc"></div>

  <input id="bpAboutToggle" type="checkbox"/>
  <div id="bpAbout">
    <div class="aboutPH">
      <div class="aboutImg"/></div>
      <p>Open Source Ad Blocker
        <small>Designed for Raspberry Pi</small>
      </p>
    </div>
    <div class="aboutLink">
      <a class="linkPH" href="https://github.com/pi-hole/pi-hole/wiki/What-is-Pi-hole%3F-A-simple-explanation"><?php //About PH ?></a>
      <?php if (!empty($svEmail)) echo '<a class="linkEmail" href="mailto:'.$svEmail.'"></a>'; ?>
    </div>
  </div>

  <div id="bpAlt">
    <label class="altBtn" for="bpAboutToggle"><?php //Why am I here? ?></label>
  </div>
</header>

<main>
  <div id="bpOutput" class="<?=$wlOutputClass ?>"><?=$wlOutput ?></div>
  <div id="bpBlock">
    <p class="blockMsg"><?=$serverName ?></p>
  </div>
  <?php if(isset($notableFlagClass)) { ?>
    <div id="bpFlag">
        <p class="flagMsg <?=$notableFlagClass ?>"></p>
    </div>
  <?php } ?>
  <div id="bpHelpTxt"><?=$bpAskAdmin ?></div>
  <div id="bpButtons" class="buttons">
    <a id="bpBack" onclick="javascript:history.back()" href="about:home"></a>
    <?php if ($featuredTotal > 0) echo '<label id="bpInfo" for="bpMoreToggle"></label>'; ?>
  </div>
  <input id="bpMoreToggle" type="checkbox">
  <div id="bpMoreInfo">
    <span id="bpFoundIn"><span><?=$featuredTotal ?></span><?=$adlistsCount ?></span>
    <pre id='bpQueryOutput'><?php if ($featuredTotal > 0) foreach ($queryAds as $num) { echo "<span>[$num]:</span>$adlistsUrls[$num]\n"; } ?></pre>
    <form id="bpWLButtons" class="buttons">
      <input id="bpWLDomain" type="text" value="<?=$serverName ?>" disabled/>
      <input id="bpWLPassword" type="password" placeholder="<?=$wlPlaceHolder ?>" disabled/><button id="bpWhitelist" type="button" disabled></button>
    </form>
  </div>
</main>

<footer><span><?=date("l g:i A, F dS"); ?>.</span> Pi-hole <?=$phVersion ?> (<?=gethostname()."/".$serverAddr; if (isset($execTime)) printf("/%.2fs", $execTime); ?>)</footer>
</div>

<script>
  function add() {
    $("#bpOutput").removeClass("hidden error exception");
    $("#bpOutput").addClass("add");
    var domain = "<?=$serverName ?>";
    var pw = $("#bpWLPassword");
    if(domain.length === 0) {
      return;
    }

    $.ajax({
      url: "/admin/scripts/pi-hole/php/add.php",
      method: "post",
      data: {"domain":domain, "list":"white", "pw":pw.val()},
      success: function(response) {
        if(response.indexOf("Pi-hole blocking") !== -1) {
          setTimeout(function(){window.location.reload(1);}, 10000);
          $("#bpOutput").removeClass("add");
          $("#bpOutput").addClass("success");
        } else {
          $("#bpOutput").removeClass("add");
          $("#bpOutput").addClass("error");
          $("#bpOutput").html(""+response+"");
        }

      },
      error: function(jqXHR, exception) {
        $("#bpOutput").removeClass("add");
        $("#bpOutput").addClass("exception");
      }
    });
  }

  <?php if ($featuredTotal > 0) { ?>
    $(document).keypress(function(e) {
        if(e.which === 13 && $("#bpWLPassword").is(":focus")) {
            add();
        }
    });

    $("#bpWhitelist").on("click", function() {
        add();
    });
  <?php } ?>
</script>

</body></html>
