// Privacy policy for the Moonrise app, linked from its settings and App Store listing.

export const PRIVACY_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Moonrise privacy policy</title>
<style>
body { font: 17px/1.55 -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif; max-width: 40em; margin: 2em auto; padding: 0 1em; color: #111; background: #fafaf7; }
h1 { font-weight: 500; margin-bottom: 0.2em; }
h2 { font-weight: 500; font-size: 1.1em; margin-top: 1.8em; border-top: 1px solid #111; padding-top: 0.6em; }
.rule { width: 48px; height: 5px; background: #e03c31; margin-bottom: 1.5em; }
@media (prefers-color-scheme: dark) { body { color: #f2f2ee; background: #0b1424; } h2 { border-color: #f2f2ee; } }
</style>
</head>
<body>
<h1>Moonrise privacy policy</h1>
<div class="rule"></div>
<p>Last updated 18 October 2026.</p>

<h2>Summary</h2>
<p>Moonrise has no accounts, no advertising, no analytics and no tracking. It does not collect personal data.</p>

<h2>Location</h2>
<p>If you allow it, Moonrise uses your location to work out where the Sun, Moon, planets and stars are in your sky. This happens on your device. Your location is not sent to us or to anyone else. You can choose a city instead in Settings.</p>

<h2>Network requests</h2>
<p>To show live data, the app requests:</p>
<ul>
<li>space weather and launch schedules from our server, moonrise-server.audit-labs.workers.dev, which runs on Cloudflare Workers;</li>
<li>space weather and aurora data directly from NOAA's Space Weather Prediction Center;</li>
<li>images of the Sun from NASA's Solar Dynamics Observatory;</li>
<li>images in the Library from NASA, ESA, ESO, NOIRLab and the Library of Congress.</li>
</ul>
<p>These requests contain no identifiers. As with any internet request, the servers receive your IP address. Cloudflare may keep short-lived logs; see Cloudflare's privacy policy.</p>

<h2>Notifications and Live Activities</h2>
<p>A launch countdown you add to the Lock Screen runs on your device. The app does not currently register your device with our server.</p>

<h2>Changes</h2>
<p>If this policy changes, the new version will be posted here with a new date.</p>
</body>
</html>`;
