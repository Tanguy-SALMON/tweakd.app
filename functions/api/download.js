/**
 * GET /api/download — hand back the current Tweakd disk image from R2.
 *
 * Why a Function rather than a file in web/: Pages would happily serve a .dmg
 * as a static asset, but then every release is a full site redeploy and the
 * binary lives in git. Keeping it in R2 means publishing a new build is one
 * `wrangler r2 object put` and the page never changes.
 *
 * Which object is "current" is derived from the bucket itself rather than
 * pinned in a config or a database. A pointer that has to be updated in lockstep
 * with an upload is a pointer that eventually points at nothing; listing and
 * picking the highest version can't drift.
 *
 * Binding: DOWNLOADS → r2 bucket `tweakd-downloads` (see wrangler.toml).
 */

const PREFIX = 'Tweakd-';
const SUFFIX = '.dmg';

/** `Tweakd-0.10.0.dmg` → [0, 10, 0]. Non-matching keys sort last. */
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

async function serveCurrentRelease({ env, request }) {
  const bucket = env.DOWNLOADS;
  if (!bucket) {
    return new Response('Downloads are not configured.', { status: 500 });
  }

  const listed = await bucket.list({ prefix: PREFIX });
  const candidates = listed.objects
    .map((o) => ({ key: o.key, version: versionOf(o.key) }))
    .filter((o) => o.version !== null);

  if (candidates.length === 0) {
    return new Response('No release published yet. Please try again later.', {
      status: 404,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }

  candidates.sort((a, b) => compare(b.version, a.version));
  const current = candidates[0];

  const object = await bucket.get(current.key);
  if (!object) {
    // Listed a moment ago but gone now — a delete raced this request.
    return new Response('Download not available. Please try again later.', {
      status: 404,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }

  // A HEAD is how a link checker asks "does this work?" — answer without
  // shipping 3 MB to it.
  if (request.method === 'HEAD') {
    return new Response(null, {
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Length': String(object.size),
        'X-Tweakd-Version': current.version.join('.'),
      },
    });
  }

  return new Response(object.body, {
    headers: {
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': `attachment; filename="${current.key}"`,
      'Content-Length': String(object.size),
      'X-Tweakd-Version': current.version.join('.'),
      // Never cache a download. It's a discrete user action, not a
      // re-fetchable asset, and a cached response would keep handing out the
      // previous release for as long as the edge kept it.
      'Cache-Control': 'no-store, max-age=0',
    },
  });
}

// Pages routes each method to its own export; a bare `onRequestGet` leaves HEAD
// falling through to the static handler, which answers with the homepage. That
// makes every link checker — and this repo's own release script — believe the
// download is an HTML page.
export const onRequestGet = serveCurrentRelease;
export const onRequestHead = serveCurrentRelease;
