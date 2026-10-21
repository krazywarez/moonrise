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
<p>Last updated 21 October 2026.</p>

<h2>Summary</h2>
<p>Moonrise has no accounts, no advertising, no analytics and no tracking. Your location is never sent to our server. If you turn on aurora alerts or news alerts, it sends our server four things needed to deliver them, described below. If you turn on cloud forecasts, it sends a rounded location to Apple's weather service. Nothing else is collected.</p>

<h2>Location</h2>
<p>If you allow it, Moonrise uses your location to work out where the Sun, Moon, planets and stars are in your sky. This happens on your device. Your location is never sent to us. You can choose a city instead in Settings.</p>

<h2 id="cloud-forecasts">Cloud forecasts</h2>
<p>Cloud forecasts are off until you turn them on in Settings. When they are on, the app asks Apple's weather service (WeatherKit) for an hourly forecast, sending your location or chosen city rounded to 0.1° of latitude and longitude, about 10 km. It asks at most once every three hours for each place, and only while the app is open. The request goes from your device to Apple, not through our server. Apple states that this location is used only to provide the forecast, is not associated with personally identifiable information and is not tracked between requests. The forecast is kept on your device. Turning cloud forecasts off deletes it.</p>

<h2>Network requests</h2>
<p>To show live data, the app requests:</p>
<ul>
<li>space weather and launch schedules from our server, moonrise.krz.sh, which runs on Cloudflare Workers;</li>
<li>space weather and aurora data directly from NOAA's Space Weather Prediction Center;</li>
<li>images of the Sun from NASA's Solar Dynamics Observatory;</li>
<li>images in the Library from NASA, ESA, ESO, NOIRLab and the Library of Congress;</li>
<li>Deep Space Network status and Mars rover raw images from NASA/JPL;</li>
<li>space news headlines from the Spaceflight News API, run by The Space Devs.</li>
</ul>
<p>These requests contain no identifiers. As with any internet request, the servers receive your IP address. Cloudflare may keep short-lived logs; see Cloudflare's privacy policy.</p>

<h2>Aurora and news alerts</h2>
<p>Aurora alerts and news alerts are off until you turn them on in Settings. When they are on, the app sends our server:</p>
<ul>
<li>this device's push notification token, which Apple issues so a server can send it notifications;</li>
<li>a 5° band of geomagnetic latitude worked out from your location on the device (for example "50° to 55° north"), not your location itself;</li>
<li>your time zone offset from UTC, so aurora alerts arrive at night and the news digest at 9 a.m.;</li>
<li>which of the two alerts you turned on.</li>
</ul>
<p>These are stored with the time the device last checked in, and used only to send those alerts. They are not linked to your identity or shared. Turning both alerts off deletes them from the server. A token that Apple reports as no longer valid is deleted automatically.</p>

<h2>Live Activities</h2>
<p>A launch countdown you add to the Lock Screen runs on your device and sends nothing to our server.</p>

<h2>Changes</h2>
<p>If this policy changes, the new version will be posted here with a new date.</p>
</body>
</html>`;
