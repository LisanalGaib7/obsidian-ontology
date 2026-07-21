---
title: "Typed edges beat full-text search"
para_type: zk
domain: general
source: self
tags: [zk]
created: 2026-01-07
updated: 2026-01-07
---

> [!note] Key insight
> An untyped `[[link]]` says two notes are related. A typed edge
> (`analyzes::`, `supports::`, `peer::`) says *how* - which is what makes
> multi-hop retrieval possible: "every note that supports thesis X".

Your own thinking is a `zk` note. External material is a `resource`.

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

hub:: [[Ontology]]
