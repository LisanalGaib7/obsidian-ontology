---
title: "{{title}}"
para_type: resource
domain: general
sector: Other
industry:
source: web
url: ""
tags: []
created: {{date:YYYY-MM-DD}}
updated: {{date:YYYY-MM-DD}}
---

## Related Notes

```dataview
TABLE file.folder AS "Folder", updated AS "Updated"
FROM ""
WHERE file.path != this.file.path AND (
  contains(this.file.outlinks, file.link) OR
  contains(this.file.inlinks, file.link)
)
SORT updated DESC
```

## Relations

hub:: [[]]
