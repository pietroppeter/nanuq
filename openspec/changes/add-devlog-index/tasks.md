# Tasks

## 1. Theme and posts

- [ ] 1.1 Add a `summary` parameter (default empty) to `useNanuqTheme` that writes `<meta name="description">`; verify a post renders with the tag
- [ ] 1.2 Give the three posts a one-line summary; verify each renders

## 2. Index page

- [ ] 2.1 Add `docs/index.nim`: scan `docs/blog/*.html`, read date and slug from the file name, title from `<title>`, summary from the meta tag; render a newest-first list with the Nanuq theme to `docs/index.html`; verify locally after rendering the posts
- [ ] 2.2 Check the index at phone width and in dark mode

## 3. CI and README

- [ ] 3.1 In the docs job, render the index after the posts and publish it as `_site/index.html`, with relative links into `blog/`; drop the redirect; verify the uploaded Pages artifact on the PR
- [ ] 3.2 Point the README's Documentation section to the index; verify the links
- [ ] 3.3 Check CI is green on the PR

## Workflow follow-up

- Archive the change: remove "Blog index page" from BACKLOG.md and add a CHANGELOG line.
