// CloudFront Function (viewer request), runtime cloudfront-js-2.0.
//
// All sites share one bucket, each under a <hostname>/ prefix, and S3 behind
// Origin Access Control has no index document, so:
//   www.esakurs.se/kurser/   → 301 https://esakurs.se/kurser/
//   esakurs.se/kurser        → 301 /kurser/
//   esakurs.se/kurser/       → esakurs.se/kurser/index.html in the bucket
//   esakurs.se/_astro/a.css  → esakurs.se/_astro/a.css in the bucket
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var host = request.headers.host ? request.headers.host.value.toLowerCase() : "";

  if (host.indexOf("www.") === 0) {
    return redirect("https://" + host.slice(4) + uri + queryString(request.querystring));
  }

  if (uri.endsWith("/")) {
    uri += "index.html";
  } else if (uri.substring(uri.lastIndexOf("/") + 1).indexOf(".") === -1) {
    return redirect(uri + "/" + queryString(request.querystring));
  }

  request.uri = "/" + host + uri;
  return request;
}

function redirect(location) {
  return {
    statusCode: 301,
    statusDescription: "Moved Permanently",
    headers: {
      location: { value: location },
      "cache-control": { value: "max-age=3600" },
    },
  };
}

function queryString(querystring) {
  var parts = [];
  for (var key in querystring) {
    var entry = querystring[key];
    var values = entry.multiValue ? entry.multiValue : [entry];
    for (var i = 0; i < values.length; i++) {
      parts.push(values[i].value === "" ? key : key + "=" + values[i].value);
    }
  }
  return parts.length ? "?" + parts.join("&") : "";
}
