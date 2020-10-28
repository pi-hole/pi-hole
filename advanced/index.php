<?php
/* Pi-hole: A black hole for Internet advertisements
*  (c) 2017 Pi-hole, LLC (https://pi-hole.net)
*  Network-wide ad blocking via your own hardware.
*
*  This file is copyright under the latest version of the EUPL.
*  Please see LICENSE file for your rights under this license. */

// Sanitize SERVER_NAME output
$serverName = htmlspecialchars($_SERVER["SERVER_NAME"]);
// Remove external ipv6 brackets if any
$serverName = preg_replace('/^\[(.*)\]$/', '${1}', $serverName);

if (!is_file("/etc/pihole/setupVars.conf"))
  die("[ERROR] File not found: <code>/etc/pihole/setupVars.conf</code>");

// Get values from setupVars.conf
$setupVars = parse_ini_file("/etc/pihole/setupVars.conf");
$svPasswd = !empty($setupVars["WEBPASSWORD"]);
$svEmail = (!empty($setupVars["ADMIN_EMAIL"]) && filter_var($setupVars["ADMIN_EMAIL"], FILTER_VALIDATE_EMAIL)) ? $setupVars["ADMIN_EMAIL"] : "";
unset($setupVars);

// Set landing page location, found within /var/www/html/
$landPage = "../landing.php";

// Define array for hostnames to be accepted as self address for splash page
$authorizedHosts = [ "localhost" ];
if (!empty($_SERVER["FQDN"])) {
    // If setenv.add-environment = ("fqdn" => "true") is configured in lighttpd,
    // append $serverName to $authorizedHosts
    array_push($authorizedHosts, $serverName);
} else if (!empty($_SERVER["VIRTUAL_HOST"])) {
    // Append virtual hostname to $authorizedHosts
    array_push($authorizedHosts, $_SERVER["VIRTUAL_HOST"]);
}

// Set which extension types render as Block Page (Including "" for index.ext)
$validExtTypes = array("asp", "htm", "html", "php", "rss", "xml", "");

// Get extension of current URL
$currentUrlExt = pathinfo($_SERVER["REQUEST_URI"], PATHINFO_EXTENSION);

// Set mobile friendly viewport
$viewPort = '<meta name="viewport" content="width=device-width, initial-scale=1">';

// Set response header
function setHeader($type = "x") {
    header("X-Pi-hole: A black hole for Internet advertisements.");
    if (isset($type) && $type === "js") header("Content-Type: application/javascript");
}

// Determine block page type
if ($serverName === "pi.hole"
    || (!empty($_SERVER["VIRTUAL_HOST"]) && $serverName === $_SERVER["VIRTUAL_HOST"])) {
    // Redirect to Web Interface
    exit(header("Location: /admin"));
} elseif (filter_var($serverName, FILTER_VALIDATE_IP) || in_array($serverName, $authorizedHosts)) {
    // When directly browsing via IP or authorized hostname
    // Render splash/landing page based off presence of $landPage file
    // Unset variables so as to not be included in $landPage or $splashPage
    unset($serverName, $svPasswd, $svEmail, $authorizedHosts, $validExtTypes, $currentUrlExt, $viewPort);
    // If $landPage file is present
    if (is_file(getcwd()."/$landPage")) {
        include $landPage;
        exit();
    }
    // If $landPage file was not present, Set Splash Page output
    $splashPage = "
    <!doctype html>
    <html lang='en'>
        <head>
            <meta charset='utf-8'>
            $viewPort
            <title>● $serverName</title>
            <link rel='stylesheet' href='pihole/blockingpage.css'>
            <link rel='shortcut icon' href='admin/img/favicons/favicon.ico' type='image/x-icon'>
        </head>
        <body id='splashpage'>
            <img src='admin/img/logo.svg' alt='Pi-hole logo' width='256' height='377'>
            <br>
            <p>Pi-<strong>hole</strong>: Your black hole for Internet advertisements</p>
            <a href='/admin'>Did you mean to go to the admin panel?</a>
        </body>
    </html>
    ";
    exit($splashPage);
} elseif ($currentUrlExt === "js") {
    // Serve Pi-hole JavaScript for blocked domains requesting JS
    exit(setHeader("js").'var x = "Pi-hole: A black hole for Internet advertisements."');
} elseif (strpos($_SERVER["REQUEST_URI"], "?") !== FALSE && isset($_SERVER["HTTP_REFERER"])) {
    // Serve blank image upon receiving REQUEST_URI w/ query string & HTTP_REFERRER
    // e.g: An iframe of a blocked domain
    exit(setHeader().'<!doctype html>
    <html lang="en">
        <head>
            <meta charset="utf-8"><script>window.close();</script>
        </head>
        <body>
            <img src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACwAAAAAAQABAAACAkQBADs=">
        </body>
    </html>');
} elseif (!in_array($currentUrlExt, $validExtTypes) || substr_count($_SERVER["REQUEST_URI"], "?")) {
    // Serve SVG upon receiving non $validExtTypes URL extension or query string
    // e.g: Not an iframe of a blocked domain, such as when browsing to a file/query directly
    // QoL addition: Allow the SVG to be clicked on in order to quickly show the full Block Page
    $blockImg = '<a href="/">
    <svg xmlns="http://www.w3.org/2000/svg" width="110" height="16">
      <circle cx="8" cy="8" r="7" fill="none" stroke="rgba(152,2,2,.5)" stroke-width="2"/>
      <path fill="rgba(152,2,2,.5)" d="M11.526 3.04l1.414 1.415-8.485 8.485-1.414-1.414z"/>
      <text x="19.3" y="12" opacity=".3" style="font:11px Arial">
        Blocked by Pi-hole
      </text>
    </svg>
    </a>';
    exit(setHeader()."<!doctype html>
    <html lang='en'>
        <head>
            <meta charset='utf-8'>
            $viewPort
        </head>
        <body>$blockImg</body>
    </html>");
}

/* Start processing Block Page from here */

// Define admin email address text based off $svEmail presence
$bpAskAdmin = !empty($svEmail) ? '<a href="mailto:'.$svEmail.'?subject=Site Blocked: '.$serverName.'"></a>' : "<span/>";

// Get possible non-standard location of FTL's database
$FTLsettings = parse_ini_file("/etc/pihole/pihole-FTL.conf");
if (isset($FTLsettings["GRAVITYDB"])) {
    $gravityDBFile = $FTLsettings["GRAVITYDB"];
} else {
    $gravityDBFile = "/etc/pihole/gravity.db";
}

// Connect to gravity.db
try {
    $db = new SQLite3($gravityDBFile, SQLITE3_OPEN_READONLY);
} catch (Exception $exception) {
    die("[ERROR]: Failed to connect to gravity.db");
}

// Get all adlist addresses
$adlistResults = $db->query("SELECT address FROM vw_adlist");
$adlistsUrls = array();
while ($row = $adlistResults->fetchArray()) {
    array_push($adlistsUrls, $row[0]);
}

if (empty($adlistsUrls))
    die("[ERROR]: There are no adlists enabled");

// Get total number of blocklists (Including Whitelist, Blacklist & Wildcard lists)
$adlistsCount = count($adlistsUrls) + 3;

// Set query timeout
ini_set("default_socket_timeout", 3);

// Logic for querying blocklists
function queryAds($serverName) {
    // Determine the time it takes while querying adlists
    $preQueryTime = microtime(true)-$_SERVER["REQUEST_TIME_FLOAT"];
    $queryAdsURL = sprintf(
        "http://127.0.0.1:%s/admin/scripts/pi-hole/php/queryads.php?domain=%s&bp",
        $_SERVER["SERVER_PORT"],
        $serverName
    );
    $queryAds = file($queryAdsURL, FILE_IGNORE_NEW_LINES);
    $queryAds = array_values(array_filter(preg_replace("/data:\s+/", "", $queryAds)));
    $queryTime = sprintf("%.0f", (microtime(true)-$_SERVER["REQUEST_TIME_FLOAT"]) - $preQueryTime);

    // Exception Handling
    try {
        // Define Exceptions
        if (strpos($queryAds[0], "No exact results") !== FALSE) {
            // Return "none" into $queryAds array
            return array("0" => "none");
        } else if ($queryTime >= ini_get("default_socket_timeout")) {
            // Connection Timeout
            throw new Exception ("Connection timeout (".ini_get("default_socket_timeout")."s)");
        } elseif (!strpos($queryAds[0], ".") !== false) {
            // Unknown $queryAds output
            throw new Exception ("Unhandled error message (<code>$queryAds[0]</code>)");
        }
        return $queryAds;
    } catch (Exception $e) {
        // Return exception as array
        return array("0" => "error", "1" => $e->getMessage());
    }
}

// Get results of queryads.php exact search
$queryAds = queryAds($serverName);

// Pass error through to Block Page
if ($queryAds[0] === "error")
    die("[ERROR]: Unable to parse results from <i>queryads.php</i>: <code>".$queryAds[1]."</code>");

// Count total number of matching blocklists
$featuredTotal = count($queryAds);

// Place results into key => value array
$queryResults = null;
foreach ($queryAds as $str) {
    $value = explode(" ", $str);
    @$queryResults[$value[0]] .= "$value[1]";
}

// Determine if domain has been blacklisted, whitelisted, wildcarded or CNAME blocked
if (strpos($queryAds[0], "blacklist") !== FALSE) {
    $notableFlagClass = "blacklist";
    $adlistsUrls = array("π" => substr($queryAds[0], 2));
} elseif (strpos($queryAds[0], "whitelist") !== FALSE) {
    $notableFlagClass = "noblock";
    $adlistsUrls = array("π" => substr($queryAds[0], 2));
    $wlInfo = "recentwl";
} elseif (strpos($queryAds[0], "wildcard") !== FALSE) {
    $notableFlagClass = "wildcard";
    $adlistsUrls = array("π" => substr($queryAds[0], 2));
} elseif ($queryAds[0] === "none") {
    $featuredTotal = "0";
    $notableFlagClass = "noblock";

    // QoL addition: Determine appropriate info message if CNAME exists
    // Suggests to the user that $serverName has a CNAME (alias) that may be blocked
    $dnsRecord = dns_get_record("$serverName")[0];
    if (array_key_exists("target", $dnsRecord)) {
        $wlInfo = $dnsRecord['target'];
    } else {
        $wlInfo = "unknown";
    }
}

// Set #bpOutput notification
$wlOutputClass = (isset($wlInfo) && $wlInfo === "recentwl") ? $wlInfo : "hidden";
$wlOutput = (isset($wlInfo) && $wlInfo !== "recentwl") ? "<a href='http://$wlInfo'>$wlInfo</a>" : "";

// Get Pi-hole Core version
$phVersion = exec("cd /etc/.pihole/ && git describe --long --tags");

// Print $execTime on development branches
// Testing for - is marginally faster than "git rev-parse --abbrev-ref HEAD"
if (explode("-", $phVersion)[1] != "0")
  $execTime = microtime(true)-$_SERVER["REQUEST_TIME_FLOAT"];

// Please Note: Text is added via CSS to allow an admin to provide a localized
// language without the need to edit this file

setHeader();
?>
<!doctype html>
<!-- Pi-hole: A black hole for Internet advertisements
*  (c) 2017 Pi-hole, LLC (https://pi-hole.net)
*  Network-wide ad blocking via your own hardware.
*
*  This file is copyright under the latest version of the EUPL. -->
<html>
<head>
  <meta charset="utf-8">
  <?=$viewPort ?>
  <meta name="robots" content="noindex,nofollow">
  <meta http-equiv="x-dns-prefetch-control" content="off">
  <link rel="stylesheet" href="pihole/blockingpage.css">
  <link rel="shortcut icon" href="admin/img/favicons/favicon.ico" type="image/x-icon">
  <title>● <?=$serverName ?></title>
  <script src="admin/scripts/vendor/jquery.min.js"></script>
  <script>
    window.onload = function () {
      <?php
      // Remove href fallback from "Back to safety" button
      if ($featuredTotal > 0) {
        echo '$("#bpBack").removeAttr("href");';

        // Enable whitelisting if JS is available
        echo '$("#bpWhitelist").prop("disabled", false);';

        // Enable password input if necessary
        if (!empty($svPasswd)) {
          echo '$("#bpWLPassword").attr("placeholder", "Password");';
          echo '$("#bpWLPassword").prop("disabled", false);';
        }
        // Otherwise hide the input
        else {
          echo '$("#bpWLPassword").hide();';
        }
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

  <input id="bpAboutToggle" type="checkbox">
  <div id="bpAbout">
    <div class="aboutPH">
      <div class="aboutImg"></div>
      <p>Open Source Ad Blocker
        <small>Designed for Raspberry Pi</small>
      </p>
    </div>
    <div class="aboutLink">
      <a class="linkPH" href="https://docs.pi-hole.net/"><?php //About PH ?></a>
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
    <pre id='bpQueryOutput'><?php if ($featuredTotal > 0) foreach ($queryResults as $num => $value) { echo "<span>[$num]:</span>$adlistsUrls[$num]\n"; } ?></pre>

    <form id="bpWLButtons" class="buttons">
      <input id="bpWLDomain" type="text" value="<?=$serverName ?>" disabled>
      <input id="bpWLPassword" type="password" placeholder="JavaScript disabled" disabled>
      <button id="bpWhitelist" type="button" disabled></button>
    </form>
  </div>
</main>

<footer><span><?=date("l g:i A, F dS"); ?>.</span> Pi-hole <?=$phVersion ?> (<?=gethostname()."/".$_SERVER["SERVER_ADDR"]; if (isset($execTime)) printf("/%.2fs", $execTime); ?>)</footer>
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
          $("#bpOutput").html("");
        } else {
          $("#bpOutput").removeClass("add");
          $("#bpOutput").addClass("error");
          $("#bpOutput").html(""+response+"");
        }
      },
      error: function(jqXHR, exception) {
        $("#bpOutput").removeClass("add");
        $("#bpOutput").addClass("exception");
        $("#bpOutput").html("");
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
