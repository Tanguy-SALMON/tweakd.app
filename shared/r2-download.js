/**
 * Serve the current Tweakd disk image out of R2.
 *
 * Shared by both front doors: the Pages Function (functions/api/download.js,
 * serving tweakd-app.pages.dev) and the Worker (worker/index.js, serving
 * tweakd.app). One copy, because two copies drift and only one of them gets
 * tested.
 *
 * Which object is "current" is derived from the bucket rather than pinned in a
 * config or a database row. A pointer that has to be updated in lockstep with
 * an upload is a pointer that eventually points at nothing; listing and picking
 * the highest version can't drift.
 *
 * Requires an R2 binding named DOWNLOADS -> bucket `tweakd-downloads`.
 */

const PREFIX = 'Tweakd-';

/** `Tweakd-0.10.0.dmg` -> [0, 10, 0]. Non-matching keys are ignored. */
function versionOf(key) {
  const m = key.match(/^Tweakd-(\d+)\.(\d+)\.(\d+)\.dmg$/);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

function compare(a, b) {
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return 0;
}

const plain = (body, status) =>
  new Response(body, { status, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });

export async function serveCurrentRelease({ env, request }) {
  const bucket = env.DOWNLOADS;
  if (!bucket) return plain('Downloads are not configured.', 500);

  const listed = await bucket.list({ prefix: PREFIX });
  const candidates = listed.objects
    .map((o) => ({ key: o.key, version: versionOf(o.key) }))
    .filter((o) => o.version !== null);

  if (candidates.length === 0) {
    return plain('No release published yet. Please try again later.', 404);
  }

  candidates.sort((a, b) => compare(b.version, a.version));
  const current = candidates[0];

  const object = await bucket.get(current.key);
  // Listed a moment ago but gone now — a delete raced this request.
  if (!object) return plain('Download not available. Please try again later.', 404);

  const version = current.version.join('.');
  const headers = {
    'Content-Type': 'application/octet-stream',
    'Content-Disposition': `attachment; filename="${current.key}"`,
    'Content-Length': String(object.size),
    'X-Tweakd-Version': version,
    // Never cache a download. It's a discrete user action, not a re-fetchable
    // asset, and a cached response would keep handing out the previous release
    // for as long as the edge kept it.
    'Cache-Control': 'no-store, max-age=0',
  };

  // A HEAD is how a link checker — and this repo's release script — asks
  // "does this work?". Answer without shipping 3 MB to it.
  if (request.method === 'HEAD') return new Response(null, { headers });

  return new Response(object.body, { headers });
}
