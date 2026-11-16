export const stableBackendOrigin='https://luvly-api-127519727979.asia-southeast1.run.app';
export const validBackendOrigin=value=>typeof value==='string'&&
  (value===stableBackendOrigin||/^https:\/\/[a-z0-9]+(?:-[a-z0-9]+)*\.trycloudflare\.com$/.test(value));
