# NOTICE

GODKIT is an original delta kit: its skills, rules, law additions, docs, eval cases and
installer are the work of this repository's authors (MIT, see LICENSE). The kit layers on
top of two third-party projects and does not redistribute their source:

## seatwork — https://github.com/sting9k/seatwork

- seatwork is **not included** in this repository. `install.sh` expects you to clone it
  yourself; godkit only places files into your clone.
- seatwork carries **no license** at the time of this notice, so its code is
  all-rights-reserved: clone and use it under its own terms, and do not redistribute it.
- Two files in `delta/` are godkit's adaptations of seatwork's files (its author's setup was
  replaced with the placeholder-driven one this kit renders): `delta/seats.yml` and
  `delta/seats.dsh.yml`. They exist here as the kit's configuration of that project.
- `dsh/seatwork-dsh.patch` is a git patch **against** seatwork, applied by `install.sh
  --dsh-room` into your own clone. Most of the patch is new, original code (the dsh runtime
  tests, the dsh harness sheet); the remainder modifies a handful of seatwork lines. It is
  published here as a modification of a public repository, for personal/reference use, and
  remains subject to seatwork's terms — see `docs/DSH-PASEO.md §regenerating` for how the
  patch is regenerated when seatwork moves.

## mattpocock/skills — https://github.com/mattpocock/skills

- MIT-licensed. GODKIT ports the core of its `tdd` and `diagnosing-bugs` methods into the
  room as `delta/skills/peer/slp-tdd` and `delta/skills/peer/slp-diagnose`, and models its
  two-axis review on `/code-review`. The upstream plugin itself runs in your own session
  (HITL side of the pipeline); install it separately per its own README.

Other upstreams GODKIT documents or installs for you at runtime: `sting8k/piggery` (MIT),
the Paseo plugin `geoqiao/deepseek-harness` (MIT), and `paseo.sh` itself. Their code is not
part of this repository.