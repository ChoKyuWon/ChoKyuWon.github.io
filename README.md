# ChoKyuWon.github.io

Personal academic website of **Kyuwon Cho** — Ph.D. student in systems security at
[SSLAB](https://sslab.skku.edu), Sungkyunkwan University.

Built with [Jekyll](https://jekyllrb.com/) and the
[al-folio](https://github.com/alshedivat/al-folio) theme.

## Structure

- `_pages/about.md` — landing page (about + selected publications + latest posts)
- `_bibliography/papers.bib` — publications (rendered by jekyll-scholar)
- `_data/cv.yml` — CV content (rendered on `/cv/`)
- `_projects/` — project cards shown on `/projects/`
- `_posts/` — blog posts / CTF writeups
- `_drafts/` — unpublished drafts (not built in production)
- `_pages/publickeys.md` — GPG public key
- `assets/` — images, PDFs, and the GPG key file

## Local development

al-folio is a gem-based theme (`theme: al_folio_core`) and uses plugins that GitHub Pages
does not build directly, so it is built and deployed via GitHub Actions
(`.github/workflows/deploy.yml`). To build locally you need Ruby 3.3+, Node 20, and ImageMagick:

```bash
bundle install
npm ci
bundle exec jekyll serve
```

Or use Docker: `docker compose up`.

## Deployment

On every push to `master`, the `Deploy site` workflow builds the site and pushes the compiled
output to the `gh-pages` branch. GitHub Pages must be configured to serve from the `gh-pages`
branch (Settings → Pages → Deploy from a branch → `gh-pages` / `(root)`).
