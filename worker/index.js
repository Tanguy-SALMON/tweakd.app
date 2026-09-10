/**
 * The tweakd.app Worker.
 *
 * tweakd.app is a Workers custom domain on the service `still-pond-7677`, NOT a
 * Cloudflare Pages custom domain — deploying the Pages project has no effect on
 * it whatsoever. That surprise cost real time, so: this Worker is the thing that
 * serves the apex domain.
 *
 * Everything except /api/download is a static file from web/, handed straight to
 * the assets binding.
 */
import { serveCurrentRelease } from '../shared/r2-download.js';

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);

    if (pathname === '/api/download') {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
      }
      return serveCurrentRelease({ env, request });
    }

    return env.ASSETS.fetch(request);
  },
};
