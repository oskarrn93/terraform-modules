// CloudFront Function (viewer response), runtime cloudfront-js-2.0.
//
// preview.<domain> must never be indexed by search engines. Canonical links
// and sitemaps still point to the live domain.
function handler(event) {
  var response = event.response;
  var host = event.request.headers.host ? event.request.headers.host.value.toLowerCase() : "";

  if (host.indexOf("preview.") === 0) {
    response.headers["x-robots-tag"] = { value: "noindex, nofollow" };
  }

  return response;
}
