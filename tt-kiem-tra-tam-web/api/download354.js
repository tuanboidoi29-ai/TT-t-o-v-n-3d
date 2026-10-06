export default async function handler(req, res) {
  try {
    const url = 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/main/TT_kiem_tra_tam_pro/releases/TRAN_TUAN_NESTING_PRO_v3.5.4_2D_PROFILE.rbz.b64?ts=' + Date.now();
    const r = await fetch(url, { cache: 'no-store' });
    if (!r.ok) { res.statusCode = 502; return res.end('Cannot fetch package'); }
    const raw = (await r.text()).replace(/\s+/g, '');
    const buf = Buffer.from(raw, 'base64');
    if (buf.length < 60000 || buf[0] !== 0x50 || buf[1] !== 0x4b) {
      res.statusCode = 500; return res.end('Invalid package');
    }
    res.setHeader('Content-Type', 'application/zip');
    res.setHeader('Content-Disposition', 'attachment; filename="TT_NESTING_354.rbz"');
    res.setHeader('Content-Length', String(buf.length));
    res.setHeader('Cache-Control', 'no-store, max-age=0');
    return res.status(200).send(buf);
  } catch (e) {
    res.statusCode = 500;
    return res.end('Download error');
  }
}