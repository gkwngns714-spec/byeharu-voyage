import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// base '/byeharu-voyage/' = served as a GitHub Pages project site at
// https://<owner>.github.io/byeharu-voyage/. BrowserRouter reads this via BASE_URL
// (src/app/App.tsx passes import.meta.env.BASE_URL as its basename), and public/404.html
// encodes deep links back through index.html's decoder.
export default defineConfig({
  base: '/byeharu-voyage/',
  plugins: [react(), tailwindcss()],
})
