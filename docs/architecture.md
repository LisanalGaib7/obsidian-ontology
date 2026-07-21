# Architecture

## One ontology, two directions

The same schema does opposite jobs depending on which way information is moving.

| Flow | Role | What it is |
|---|---|---|
| **Write** (capture, classify) | Injects the taxonomy as context so generation is constrained | Grounding context — schema enforcement |
| **Read** (review, query) | Walks typed edges out from hub nodes | Ontology-based Graph RAG |

Most PKM setups only have the read side, and only as full-text search. Most "AI + notes" setups only have the write side, and only as a prompt. The leverage comes from both halves pointing at the *same* definition file.

## Why this is not vector RAG

No embeddings are computed and no similarity search happens. Retrieval is **symbolic**:

1. Enter at a hub note (`000_Maps/`)
2. Traverse typed edges (`hub::`, `analyzes::`, `supports::`, `peer::`, `holding::`)
3. Filter on frontmatter (`sector`, `domain`, `status`, `updated`)
4. Fall back to raw text search only when the graph comes up empty

Trade-offs, stated plainly:

| Symbolic graph | Vector RAG |
|---|---|
| Exact multi-hop queries ("all notes supporting thesis X") | Fuzzy semantic recall |
| Requires disciplined tagging | Works on unstructured dumps |
| Explains *why* a note was retrieved (the edge) | Similarity score only |
| Breaks loudly when the schema drifts | Degrades silently |

For a curated personal vault the discipline is affordable and the precision is worth more. At larger scale the two compose — embeddings can be layered on as a fallback tier without changing anything here.

## Components

| Component | Role | Where |
|---|---|---|
| **SSOT** | Every legal value: domain, sector, industry, source, relation type, alias, hub | `config/ontology.json` |
| **Vault structure** | PARA + Zettelkasten folders | `0_Inbox` … `5_Zettelkasten` |
| **Typed relations** | `## Relations` inline fields | bottom of each note |
| **Hub nodes** | Graph entry points for traversal | `000_Maps/` |
| **Validator** | Schema + graph integrity, with `-AutoFix` | `scripts/validate-vault.ps1` |
| **Sync** | Push SSOT into derived docs and dataview blocks | `scripts/sync-ontology.ps1` |
| **Hub rename** | Rename a hub across links, file, SSOT, docs | `scripts/rename-hub.ps1` |
| **Ingestion** | Message → classified note (optional) | see [pipeline.md](pipeline.md) |

## The runtime-read decision

The obvious way to keep code and schema aligned is to **generate** constants from the schema and fail the build when they diverge. This repo does something simpler: every consumer **reads the SSOT at runtime**.

```powershell
$config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
```

```javascript
const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
```

Consequences:

- Adding a hub or an industry is a one-line JSON edit. Nothing to regenerate, nothing to redeploy.
- There is no generated artifact that can drift, because there is no generated artifact.
- The cost is a file read per run, and a hard dependency on the file being present — so consumers must degrade safely when the read fails (the ingestion pipeline disables its write gate rather than blocking capture).

## Failure modes worth measuring

| Mode | Meaning | Why it matters |
|---|---|---|
| **Dangling** | A typed edge points at a note that does not exist | The graph claims a connection it cannot deliver — traversal dead-ends |
| **Orphan** | A note with no inbound and no outgoing links | Unreachable by any traversal; effectively invisible to an agent |
| **Schema violation** | A value outside the SSOT vocabulary | Silently splits a category; queries start missing rows |
| **Entity split** | One real entity under several names | The worst one — every query returns a fraction of the truth |

The first three are caught by `validate-vault.ps1`. The fourth is prevented at write time by `aliases`, because detecting it after the fact is far harder than never creating it.
