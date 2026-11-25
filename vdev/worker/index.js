const GH = "https://github.com/T4n-Labs/repo-t4nos/releases/download";
const RAW = "https://raw.githubusercontent.com/T4n-Labs/repo-t4nos/main";
const TAGS = new Set(["x86_64","x86_64-musl","aarch64","aarch64-musl",
  "armv6l","armv6l-musl","armv7l","armv7l-musl","i686"]);
const FILE = /^[A-Za-z0-9._+-]+$/;
const PASS = ["range","if-modified-since","if-none-match","user-agent"];

export default {
  async fetch(request) {
    if (request.method !== "GET" && request.method !== "HEAD")
      return new Response("Method Not Allowed", { status: 405 });
    const parts = new URL(request.url).pathname.split("/").filter(Boolean);

    if (parts.length === 0)
      return Response.redirect("https://repo-web.t4nlabs.web.id/", 302);

    // /setup.sh -> skrip user dari main
    if (parts.length === 1 && parts[0] === "setup.sh") {
      const r = await fetch(`${RAW}/setup.sh`);
      return new Response(r.body, {
        status: r.status,
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": r.ok ? "public, max-age=300" : "no-store",
        },
      });
    }

    // /json/<tag>/packages.json -> indeks pencarian untuk website (CORS terbuka)
    if (parts.length === 3 && parts[0] === "json" && TAGS.has(parts[1]) && parts[2] === "packages.json") {
      const r = await fetch(`${RAW}/json/${parts[1]}/packages.json`);
      if (!r.ok)
        return new Response("Not Found", {
          status: r.status === 404 ? 404 : 502,
          headers: { "cache-control": "no-store", "access-control-allow-origin": "*" },
        });
      return new Response(r.body, {
        status: 200,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "access-control-allow-origin": "*",
          "cache-control": "public, max-age=300",
        },
      });
    }

    if (parts.length === 1 && TAGS.has(parts[0]))
      return Response.redirect(
        `https://github.com/T4n-Labs/repo-t4nos/releases/tag/${parts[0]}`, 302);
    if (parts.length !== 2 || !TAGS.has(parts[0]) || !FILE.test(parts[1]))
      return new Response("Not Found", { status: 404 });

    const headers = new Headers();
    for (const h of PASS) if (request.headers.has(h)) headers.set(h, request.headers.get(h));

    const resp = await fetch(`${GH}/${parts[0]}/${parts[1]}`,
      { method: request.method, headers, redirect: "follow" });
    const out = new Headers(resp.headers);
    out.delete("set-cookie");
    return new Response(resp.body, { status: resp.status, headers: out });
  },
};