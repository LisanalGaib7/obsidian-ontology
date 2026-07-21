---
title: "{{title}}"
para_type: area
domain: general
status: active
tags: [hub]
created: {{date:YYYY-MM-DD}}
updated: {{date:YYYY-MM-DD}}
---

# {{title}}

> Graph entry point. Add this name to `hubList` in `config/ontology.json`
> so the validator and the classifier both recognize it.

## Notes in this hub

```dataview
TABLE file.folder AS "Folder", sector, updated AS "Updated"
FROM ""
WHERE file.path != this.file.path AND contains(this.file.inlinks, file.link)
SORT updated DESC
```

## Relations

related:: [[]]
