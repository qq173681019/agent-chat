const c = require('./config.json');
console.log('key length:', c.apiKey.length);
console.log('first 10:', c.apiKey.substring(0, 10));
console.log('apiBase:', c.apiBase);
console.log('model:', c.model);
