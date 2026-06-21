import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';

// https://astro.build/config
export default defineConfig({
  site: 'https://ogunlearn.com',
  trailingSlash: 'never',
  integrations: [mdx()],
  build: {
    inlineStylesheets: 'auto',
    assets: 'static',
  },
  compressHTML: true,
});
