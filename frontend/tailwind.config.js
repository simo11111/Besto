export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: 'var(--mx-bg)',
        panel: 'var(--mx-surface)',
        primary: 'var(--mx-primary)',
        secondary: 'var(--mx-secondary)',
        accent: 'var(--mx-accent)',
        success: 'var(--mx-success)',
        warning: 'var(--mx-warning)',
        danger: 'var(--mx-danger)'
      },
      boxShadow: { soft: 'var(--mx-shadow)' }
    }
  },
  plugins: []
};
