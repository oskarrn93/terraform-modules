// Unit tests for the CloudFront Functions (request.js, response.js).
// Run from the repo root: node --test
//
// CloudFront Functions aren't modules: each file declares a global `handler`.
// The tests run each file in its own VM context and call that handler with
// events shaped like CloudFront's (cloudfront-js-2.0 event structure).

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";
import vm from "node:vm";

const dir = new URL("../", import.meta.url);

function load(file) {
  const code = readFileSync(new URL(file, dir), "utf8");
  return vm.runInNewContext(`${code}\n;handler`, {}, { filename: file });
}

const onRequest = load("request.js");
const onResponse = load("response.js");

// querystring: { name: "value" } or { name: ["v1", "v2"] } for repeated keys.
function request(host, uri, querystring = {}) {
  const qs = {};
  for (const [key, value] of Object.entries(querystring)) {
    qs[key] = Array.isArray(value)
      ? { value: value[0], multiValue: value.map((v) => ({ value: v })) }
      : { value };
  }
  return {
    request: {
      method: "GET",
      uri,
      querystring: qs,
      headers: host === undefined ? {} : { host: { value: host } },
      cookies: {},
    },
  };
}

function assertRedirect(result, location) {
  assert.equal(result.statusCode, 301);
  assert.equal(result.headers.location.value, location);
  assert.ok(result.headers["cache-control"], "redirects should be cacheable");
}

// --- request.js: bucket prefix and directory index ---------------------------

test("serves the root from the hostname's prefix", () => {
  assert.equal(onRequest(request("example.com", "/")).uri, "/example.com/index.html");
});

test("serves a directory's index.html", () => {
  assert.equal(onRequest(request("example.com", "/kurser/")).uri, "/example.com/kurser/index.html");
});

test("serves files as they are", () => {
  assert.equal(onRequest(request("example.com", "/_astro/a.css")).uri, "/example.com/_astro/a.css");
});

test("treats a dot in a directory name as part of the path, not an extension", () => {
  assert.equal(onRequest(request("example.com", "/v1.2/docs/")).uri, "/example.com/v1.2/docs/index.html");
  assertRedirect(onRequest(request("example.com", "/v1.2/docs")), "/v1.2/docs/");
});

test("serves preview hosts from their own prefix", () => {
  assert.equal(onRequest(request("preview.example.com", "/a/")).uri, "/preview.example.com/a/index.html");
});

test("lowercases the host header", () => {
  assert.equal(onRequest(request("Example.COM", "/")).uri, "/example.com/index.html");
});

test("passes the rest of the request through", () => {
  const event = request("example.com", "/a.css", { v: "1" });
  const result = onRequest(event);
  assert.equal(result, event.request);
  assert.equal(result.querystring.v.value, "1");
});

// --- request.js: redirects ---------------------------------------------------

test("redirects a directory without trailing slash to the slashed URL", () => {
  assertRedirect(onRequest(request("example.com", "/kurser")), "/kurser/");
});

test("keeps the query string on the trailing-slash redirect", () => {
  assertRedirect(onRequest(request("example.com", "/kurser", { utm_source: "x" })), "/kurser/?utm_source=x");
});

test("redirects www. to the apex over https, keeping path and query string", () => {
  assertRedirect(onRequest(request("www.example.com", "/a/b/", { q: "1" })), "https://example.com/a/b/?q=1");
});

test("redirects www. before anything else, so the apex handles the trailing slash", () => {
  assertRedirect(onRequest(request("www.example.com", "/kurser")), "https://example.com/kurser");
});

test("rebuilds repeated and valueless query parameters", () => {
  assertRedirect(
    onRequest(request("www.example.com", "/", { a: ["1", "2"], flag: "" })),
    "https://example.com/?a=1&a=2&flag",
  );
});

test("redirects without a query string when there is none", () => {
  assertRedirect(onRequest(request("www.example.com", "/")), "https://example.com/");
});

// --- response.js -------------------------------------------------------------

function response(host, headers = {}) {
  return { ...request(host, "/"), response: { statusCode: 200, headers: { ...headers } } };
}

test("marks preview hosts noindex", () => {
  const result = onResponse(response("preview.example.com"));
  assert.equal(result.headers["x-robots-tag"].value, "noindex, nofollow");
});

test("leaves live hosts indexable", () => {
  const result = onResponse(response("example.com"));
  assert.equal(result.headers["x-robots-tag"], undefined);
});

test("keeps the origin's headers", () => {
  const result = onResponse(response("preview.example.com", { "content-type": { value: "text/html" } }));
  assert.equal(result.headers["content-type"].value, "text/html");
  assert.equal(result.statusCode, 200);
});

test("handles a missing host header", () => {
  assert.equal(onResponse(response(undefined)).headers["x-robots-tag"], undefined);
});

// --- CloudFront Functions limits ---------------------------------------------

test("functions fit CloudFront's 10 KB code size limit", () => {
  for (const file of ["request.js", "response.js"]) {
    const size = statSync(new URL(file, dir)).size;
    assert.ok(size <= 10240, `${file} is ${size} bytes`);
  }
});
