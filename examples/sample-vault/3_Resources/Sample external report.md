---
title: "Sample external report"
para_type: resource
domain: invest
sector: Tech
industry: Semiconductor
source: report
url: "https://example.com/report"
tags: [invest, Report]
created: 2026-01-06
updated: 2026-01-06
---

A note written by someone else (article, report, tweet, interview) is a
`resource`. Authorship is the rule: external author -> resource.

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

hub:: [[AI]]
analyzes:: [[TICKER_A]]
