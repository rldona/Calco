import { defineConfig } from 'vitepress'

// Calco user manual. English at the root, Spanish under /es/ with the same page names,
// so the language switch lands on the same page. Published to GitHub Pages under /Calco/.
const pages = [
  ['getting-started', 'Getting started', 'Primeros pasos'],
  ['gallery', 'Gallery and projects', 'Galería y proyectos'],
  ['drawing', 'Drawing tools', 'Herramientas de dibujo'],
  ['layers', 'Layers', 'Capas'],
  ['timeline', 'Timeline and drawings', 'Línea de tiempo y dibujos'],
  ['guide-sequence', 'Tracing a motion', 'Calcar un movimiento'],
  ['onion-skin', 'Onion skin', 'Papel cebolla'],
  ['cycles', 'Cycles and inbetweens', 'Ciclos e intermedios'],
  ['clips', 'Clips and pivot', 'Clips y pivote'],
  ['export', 'Export to your game', 'Exportar a tu juego'],
  ['pencil', 'Apple Pencil and gestures', 'Apple Pencil y gestos'],
  ['shortcuts', 'Keyboard shortcuts', 'Atajos de teclado'],
  ['preferences', 'Preferences', 'Preferencias'],
] as const

const sidebar = (prefix: string, title: 'en' | 'es') => [
  {
    text: title === 'en' ? 'User guide' : 'Guía de uso',
    items: pages.map(([slug, en, es]) => ({ text: title === 'en' ? en : es, link: `${prefix}/guide/${slug}` })),
  },
]

export default defineConfig({
  base: '/Calco/',
  title: 'Calco',
  cleanUrls: true,
  lastUpdated: true,
  head: [['link', { rel: 'icon', href: '/Calco/icon.png' }]],
  themeConfig: {
    logo: '/icon.png',
    socialLinks: [{ icon: 'github', link: 'https://github.com/rldona/Calco' }],
    search: { provider: 'local' },
  },
  locales: {
    root: {
      label: 'English',
      lang: 'en',
      description: 'Hand-drawn sprite animation for your game, on iPad.',
      themeConfig: {
        nav: [{ text: 'Guide', link: '/guide/getting-started' }],
        sidebar: sidebar('', 'en'),
        outline: { label: 'On this page' },
      },
    },
    es: {
      label: 'Español',
      lang: 'es',
      link: '/es/',
      description: 'Animación de sprites dibujada a mano para tu juego, en iPad.',
      themeConfig: {
        nav: [{ text: 'Guía', link: '/es/guide/getting-started' }],
        sidebar: sidebar('/es', 'es'),
        outline: { label: 'En esta página' },
        docFooter: { prev: 'Anterior', next: 'Siguiente' },
        lastUpdated: { text: 'Actualizado' },
        darkModeSwitchLabel: 'Apariencia',
        sidebarMenuLabel: 'Menú',
        returnToTopLabel: 'Volver arriba',
        langMenuLabel: 'Idioma',
      },
    },
  },
})
