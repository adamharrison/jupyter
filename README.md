# Jupyter Notebooks for Lite XL

Adds support for Jupyter Notebooks in Lite XL.

A thin wrapper over a small python kernel.

Requires the new canvas API in Lite XL 3.0.

![jupyter notebooks for lite-xl](screenshot.png)

### TODO

1. Create a floating toolbar.
2. Dump compressed images instead of uncompressed from stdout.
3. Render markdown
4. Optimize logic and actually put the `draw` stuff in the right place.
5. Decode base64 better.

### Preview

```
lpm run https://github.com/adamharrison/lite-xl:3.0-preview --update https://github.com/adamharrison/jupyter:master 3.0-preview jupyter
```

1. `Jupyter: New Notebook` 
2. `Jupyter: Add Markdown Block` 
3. `Jupyter: Add Code Block` 
4. Type things.
5. `F8`

