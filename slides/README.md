# Presentation Slides

This directory contains the Quarto source files for the project slides.

## Instructions

### 1. Render Locally
To preview the slides locally, run the following command from the **project root** directory:
```bash
quarto render slides/slides.qmd
```
The output will be generated at `/_site/slides/index.html`.

### 2. Publish to GitHub Pages
The slides are published using the `gh-pages` branch. To update the online version, run from the **project root**:
```bash
quarto publish gh-pages
```
> [!NOTE]
> Make sure the GitHub repository is configured to deploy from the `gh-pages` branch (Settings > Pages).

## Assets
-   **Images**: All images used in the presentation are stored in `slides/images/`.
-   **Styles**: Custom CSS is in `slides/styles.css`.

## Output
The rendered slides are served at: [temospena.github.io/Sydney/slides/](https://temospena.github.io/Sydney/slides/)
