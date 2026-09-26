const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3000;
const BACKEND_URL = process.env.BACKEND_URL || 'http://backend:8000/api/data';

// Forward distributed tracing headers to preserve Jaeger span continuity
const TRACE_HEADERS = [
  'x-request-id',
  'x-b3-traceid',
  'x-b3-spanid',
  'x-b3-parentspanid',
  'x-b3-sampled',
  'x-b3-flags'
];

app.get('/healthz', (req, res) => res.status(200).send('OK'));

app.get('/api/data', async (req, res) => {
  const headers = {};
  
  // Extract and propagate context headers from the incoming Istio/Envoy request
  TRACE_HEADERS.forEach(header => {
    if (req.headers[header]) {
      headers[header] = req.headers[header];
    }
  });

  try {
    const response = await axios.get(BACKEND_URL, { headers });
    res.json({ 
      service: 'frontend', 
      upstream_trace_propagated: Object.keys(headers).length > 0,
      backend_response: response.data 
    });
  } catch (error) {
    console.error(`Backend call failed: ${error.message}`);
    res.status(503).json({ error: 'Backend service unavailable' });
  }
});

app.listen(PORT, () => console.log(`Frontend listening on port ${PORT}`));