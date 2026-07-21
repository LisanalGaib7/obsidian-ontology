---
title: "Deliberately broken note"
para_type: resource
domain: invest
sector: Tech
industry: Shipbuilding
source: newsletter
tags: [invest]
created: 2026-01-08
updated: 2026-01-08
---

This note exists so `validate-vault.ps1` has something to catch on a fresh
clone. Two deliberate violations:

1. `industry: Shipbuilding` does not belong to `sector: Tech`
   (Shipbuilding is under Industrials).
2. `source: newsletter` is not in `validSources`.

Delete this file once you have seen the validator report it.

## Relations

hub:: [[AI]]
