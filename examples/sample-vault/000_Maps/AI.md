---
title: "AI"
para_type: area
domain: general
status: active
tags: [hub]
created: 2026-01-05
updated: 2026-01-05
---

# AI

> Hub note. A retrieval agent enters here and traverses typed edges outward
> instead of full-text searching the vault.

## Related Notes

```dataview
TABLE file.folder AS "Folder", updated AS "Updated"
FROM ""
WHERE file.path != this.file.path AND contains(this.file.inlinks, file.link)
SORT updated DESC
```

## Relations

related:: [[Ontology]]
