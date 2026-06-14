module.exports = function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=600');

  const clientId = process.env.APPLE_CLIENT_ID || '';
  const redirectURI = process.env.APPLE_REDIRECT_URI || '';

  res.status(200).end(JSON.stringify({
    configured: Boolean(clientId && redirectURI),
    clientId,
    redirectURI,
    scope: process.env.APPLE_SIGN_IN_SCOPE || 'name email',
  }));
};
