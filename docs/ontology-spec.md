# Ontology Spec

Mapping to the standard vocabulary, so this is comparable to any other ontology work.

| Standard term | Plain meaning | Here | Status |
|---|---|---|---|
| **Attribute** | Information a thing carries | frontmatter fields | Enforced against enums |
| **Relation** | The arrow between things | inline fields (`hub::` …) | Type validated per domain |
| **Serialization** | The file format | JSON + YAML frontmatter | RDF-equivalent in substance |
| **Entity type** | The important nouns | `para_type` + hub notes | **Not declared** — see gaps |
| **Cardinality** | How many, on each end | — | **Not implemented** |

## Attributes

Defined in `config/ontology.json`, validated by `scripts/validate-vault.ps1`.

| Field | Rule |
|---|---|
| `para_type` | One of `project` / `area` / `resource` / `zk` — determines the folder via `folderMap` |
| `domain` | One of `validDomains` — also selects which relation vocabulary applies |
| `sector` | One of `validSectors` |
| `industry` | Must belong to *that note's* `sector` in `validIndustries` — this nesting is what stops taxonomy drift |
| `source` | One of `validSources` — provenance, so "where did this come from" is queryable |
| `title` | Must match the filename, unless `title_alias: true` |
| `created` / `updated` | ISO dates |

## Relations

Written as inline fields in a `## Relations` section, one per line:

```markdown
## Relations

hub:: [[AI]]
analyzes:: [[TICKER_A]]
supports:: [[Thesis note]]
```

Vocabulary is bucketed by domain, so a relation that is meaningless in a context cannot be used there:

| Bucket | Allowed types |
|---|---|
| `invest` | `hub` `analyzes` `basis` `supports` `peer` `holding` `related` |
| `biz` | `hub` `related` `project` `spec` |
| `default` | `hub` `related` |

`related` is the deliberate fallback in every bucket — a note is never blocked from linking just because no precise type fits.

**Direction.** Links are declared one-way. Asymmetric relations (`analyzes`, `basis`, `supports`, `hub`, `holding`) point in the direction the meaning runs; Dataview surfaces the reverse via `inlinks`, so writing both directions is duplication, not completeness. Symmetric relations (`peer`, `related`) may be written either way.

## Entity resolution

```json
"aliases": {
  "TICKER_A": ["Company A", "CompanyA", "company a"]
}
```

Every known surface form maps to one canonical name. The ingestion pipeline rewrites relation targets at write time, so `[[Company A]]` is stored as `[[TICKER_A]]`.

Matching is **exact only**, never substring — substring matching would rewrite `[[Company A Supply Chain]]` into something wrong. Adding an alias is a one-line edit; no code changes.

## Hubs

Hub notes in `000_Maps/` are the entry points a retrieval agent starts from. Keep the list small — hubs are doorways, not tags. A working heuristic for promoting a keyword to a hub:

| Signal | Points |
|---|---|
| Each note linking to it | +1 |
| Linked from an active/held item | +2 |
| At least one linking note updated in 30 days | +1 |

Three or more, and it earns a hub.

## Known gaps

Documented rather than hidden, because they define where this design stops scaling.

**Entity types are not declared.** `para_type` is a *workflow bucket* (where does this file live), not an *entity type* (what kind of thing is this). One `resource` value covers articles, reports, tweets, and interviews. Meanwhile the hub list flattens genuinely different kinds into one namespace:

- companies — `TICKER_A`, `TICKER_B`
- sectors — `Energy`, `Semiconductor`, `Defense`
- concepts — `AI`, `Ontology`, `On-Prem AI`
- projects — `SQL`, `Prompting`

The system *has* entity types; it just never says so, which means `hub:: [[TICKER_A]]` (a company) and `hub:: [[AI]]` (a concept) are indistinguishable to a query. A `hub_type` field on hub notes, validated against the SSOT, would close this.

**Relation range is unconstrained.** Relation *names* are checked per domain. Relation *targets* are not — nothing verifies that a `hub::` target is actually a registered hub. In formal terms, `domain`/`range` constraints are absent.

**No cardinality.** Nothing enforces "at most 3 hubs per note" or "exactly one sector on an invest note." Where such limits exist today they are instructions in a classification prompt, which is a request, not a constraint.

At single-vault scale none of this bites. It starts to bite when multiple agents write into the same graph — which is exactly when an ontology stops being documentation and starts being infrastructure.
