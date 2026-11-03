# Wiki Maintenance

`docs/` in the repository is the **source of truth**. The GitHub wiki (`IRK.wiki.git`) is a mirror; do not edit it through the web UI.

## Manual sync
```bash
git clone git@github.com:AhmedYousriSobhi/IRK.wiki.git .wiki   # .wiki/ is gitignored
rsync -a --delete --exclude .git docs/ .wiki/
cd .wiki && git add -A && git commit -m "Sync docs" && git push
```

The wiki git repo only exists after the first page has been created in the GitHub UI.

Automating this sync is on the [roadmap](https://github.com/AhmedYousriSobhi/IRK/blob/main/SPEC.md#6-future-roadmap).
