/**
 * GET|HEAD /api/download on Cloudflare Pages (tweakd-app.pages.dev).
 *
 * The logic lives in shared/r2-download.js so the Worker that serves
 * tweakd.app answers identically. Pages routes each HTTP method to its own
 * export — a bare `onRequestGet` leaves HEAD falling through to the static
 * handler, which cheerfully replies with the homepage.
 */
import { serveCurrentRelease } from '../../shared/r2-download.js';

export const onRequestGet = serveCurrentRelease;
export const onRequestHead = serveCurrentRelease;
