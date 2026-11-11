import express from 'express';

import { config } from '../config.js';
import { queryAll, queryOne } from '../db/index.js';
import { notFound } from '../lib/errors.js';

/**
 * Public delivery pages for digital products.
 *
 * These are the only unauthenticated routes in the API. A buyer receives a
 * sale-specific token from the owner; the token is the credential, so every
 * lookup is scoped by it and by `payment_status = 'paid'`. Nothing here exposes
 * a customer list, a catalog, or a sale that has not been paid for.
 */
export const publicDeliveryRouter = express.Router();

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{20,80}$/;

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

/**
 * The public URL for a sale token. `PUBLIC_BASE_URL` is the API base (for
 * example `https://api.example.com/api/v1`); without it the request's own host
 * is used, so local development and Render both produce a working link.
 */
export function publicSaleUrl(req, token) {
  if (!token) return null;
  const base = (config.publicBaseUrl ?? `${req.protocol}://${req.get('host')}/api/v1`)
    .replace(/\/+$/, '');
  return `${base}/public/sales/${encodeURIComponent(token)}`;
}

function layout({ title, body }) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>${escapeHtml(title)}</title>
  <style>
    :root { color-scheme: light; }
    body { margin: 0; background: #f4f6f8; color: #14212b;
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
    main { max-width: 640px; margin: 0 auto; padding: 28px 20px 48px; }
    .card { background: #fff; border: 1px solid #e2e8ee; border-radius: 16px;
      padding: 22px; box-shadow: 0 8px 24px rgba(20, 33, 43, 0.06); }
    .brand { font-size: 13px; font-weight: 800; letter-spacing: .08em;
      text-transform: uppercase; color: #1f6feb; margin-bottom: 8px; }
    h1 { font-size: 24px; margin: 0 0 6px; }
    h2 { font-size: 16px; margin: 22px 0 8px; }
    p { line-height: 1.55; margin: 8px 0; }
    .muted { color: #607080; font-size: 13px; }
    .item { border: 1px solid #e2e8ee; border-radius: 12px; padding: 14px;
      margin-top: 12px; }
    .item h3 { font-size: 15px; margin: 0 0 6px; }
    a.button { display: inline-block; margin-top: 8px; background: #1f6feb;
      color: #fff; text-decoration: none; font-weight: 700; padding: 10px 16px;
      border-radius: 10px; }
    a.button.secondary { background: #eaf1fd; color: #1654b8; }
    .notice { background: #fff7e6; border: 1px solid #f2d08a; color: #7a5300;
      border-radius: 12px; padding: 12px 14px; }
    pre { white-space: pre-wrap; font-family: inherit; font-size: 14px;
      background: #f6f8fa; border-radius: 10px; padding: 10px 12px; margin: 8px 0 0; }
    footer { margin-top: 18px; text-align: center; }
  </style>
</head>
<body>
  <main>${body}</main>
</body>
</html>`;
}

async function saleForToken(token) {
  if (!TOKEN_PATTERN.test(token)) return null;
  return queryOne(
    `SELECT t.*, b.business_name
       FROM transactions t
       JOIN businesses b ON b.id = t.business_id
      WHERE t.public_token = ?`,
    token
  );
}

async function digitalItemsFor(transactionId) {
  return queryAll(
    `SELECT ti.*, df.file_name, df.mime_type, df.size_bytes
       FROM transaction_items ti
       LEFT JOIN digital_files df ON df.id = ti.digital_file_id
      WHERE ti.transaction_id = ? AND ti.is_digital = 1
      ORDER BY ti.created_at ASC`,
    transactionId
  );
}

// GET /api/v1/public/sales/:token
publicDeliveryRouter.get('/sales/:token', async (req, res) => {
  const sale = await saleForToken(req.params.token);
  if (!sale) {
    return res
      .status(404)
      .type('html')
      .send(
        layout({
          title: 'Download not found',
          body: `<div class="card">
            <div class="brand">Biziness</div>
            <h1>This link does not work</h1>
            <p class="muted">Ask the seller for a fresh download link.</p>
          </div>`,
        })
      );
  }

  const business = escapeHtml(sale.business_name);
  const heading = `<div class="brand">${business}</div>
    <h1>Your digital order</h1>
    <p class="muted">Sale ${escapeHtml(sale.transaction_number)}</p>`;
  const basePath = `${req.baseUrl}/sales/${encodeURIComponent(req.params.token)}`;

  if (sale.payment_status !== 'paid') {
    return res.type('html').send(
      layout({
        title: `Your order from ${sale.business_name}`,
        body: `<div class="card">
          ${heading}
          <div class="notice">
            Payment for this order has not been confirmed yet. Ask ${business} to
            confirm it, then open this link again.
          </div>
        </div>`,
      })
    );
  }

  const items = await digitalItemsFor(sale.id);
  const cards = items
    .map((item) => {
      const links = [];
      if (item.digital_url) {
        links.push(
          `<a class="button" href="${escapeHtml(item.digital_url)}" target="_blank" rel="noopener noreferrer">Open download link</a>`
        );
      }
      if (item.digital_file_id) {
        links.push(
          `<a class="button secondary" href="${basePath}/items/${encodeURIComponent(item.id)}/file">Download ${escapeHtml(item.file_name ?? 'file')}</a>`
        );
      }
      return `<div class="item">
        <h3>${escapeHtml(item.product_name_snapshot)}</h3>
        ${item.digital_instructions
          ? `<pre>${escapeHtml(item.digital_instructions)}</pre>`
          : ''}
        ${links.join(' ')}
      </div>`;
    })
    .join('');

  return res.type('html').send(
    layout({
      title: `Your order from ${sale.business_name}`,
      body: `<div class="card">
        ${heading}
        <p>Thank you. Your payment is confirmed — the files and links below are
        yours to download.</p>
        ${cards || '<p class="muted">This order has no digital items.</p>'}
        <footer class="muted">Keep this link private. Anyone with it can download your files.</footer>
      </div>`,
    })
  );
});

// GET /api/v1/public/sales/:token/items/:itemId/file
publicDeliveryRouter.get('/sales/:token/items/:itemId/file', async (req, res) => {
  const sale = await saleForToken(req.params.token);
  if (!sale || sale.payment_status !== 'paid') {
    throw notFound('That download is not available.');
  }
  const item = await queryOne(
    `SELECT ti.*, df.data_base64, df.mime_type, df.file_name
       FROM transaction_items ti
       JOIN digital_files df ON df.id = ti.digital_file_id
      WHERE ti.transaction_id = ? AND ti.id = ? AND ti.is_digital = 1`,
    sale.id,
    req.params.itemId
  );
  if (!item || !item.data_base64) {
    throw notFound('That download is not available.');
  }

  const bytes = Buffer.from(item.data_base64, 'base64');
  const fileName = String(item.file_name ?? 'download')
    .replace(/[\r\n"]/g, '')
    .slice(0, 180) || 'download';
  res.setHeader('Content-Type', item.mime_type || 'application/octet-stream');
  res.setHeader(
    'Content-Disposition',
    `attachment; filename="${fileName}"; filename*=UTF-8''${encodeURIComponent(fileName)}`
  );
  res.setHeader('Content-Length', String(bytes.length));
  res.setHeader('Cache-Control', 'private, no-store');
  res.send(bytes);
});
