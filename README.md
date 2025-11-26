# Jupyter Notebooks for Lite XL

Adds support for Jupyter Notebooks in Lite XL.

A thin wrapper over a small python kernel.

Requires the new canvas API in Lite XL 3.0.

![jupyter notebooks for lite-xl](screenshot.png)

### TODO

1. Allow you to scroll the document correctly vertically.
2. Adjust some clicking issues with the code blocks.
3. Create a floating toolbar.
4. Dump compressed images instead of uncompressed from stdout.
5. Render markdown
6. Save the file as a `.ipynb`.
7. Open `.ipynb` files.
8. Optimize logic and actually put the `draw` stuff in the right place.
9. Decode base64 better.

### Preview

```
lpm run https://github.com/adamharrison/lite-xl:3.0-preview --update https://github.com/adamharrison/jupyter:master 3.0-preview jupyter
```

1. `Jupyter: New Notebook` 
2. `Jupyter: Add Markdown Block` 
3. `Jupyter: Add Code Block` 
4. Type things.
5. `F8`

