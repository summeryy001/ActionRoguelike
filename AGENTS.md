# AR2 local development instructions

This repository is a local PSO workflow rehearsal. Do not configure a remote or push unless the user explicitly requests it.

After each completed logical change, perform appropriate verification, update PSO-WORKFLOW.md, and commit locally. Keep distinct workflow stages in separate commits. Do not amend or squash completed stage commits unless requested: their history documents the progression from the baseline.

Preserve user changes. Never commit unrelated changes, credentials, generated binaries, Cook/stage outputs, driver caches or trace recordings. Keep scripts, source, configuration, required game assets and concise verification summaries versioned. A deliberately generated Build/Windows/PipelineCaches/*.spc is a later-stage build input and may be committed with provenance.

Record the actual effective settings and validation limits. An editor run is not a cold-cache packaged benchmark. Do not clear system driver caches merely to prepare a commit.
