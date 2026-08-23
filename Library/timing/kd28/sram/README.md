# KD28 SRAM Synthetic Liberty

This directory contains generated fast, typical, and slow Liberty scenarios for every fixed cell listed in
`Library/models/kd28/sram/macros.yaml`. The tables are scalar repository assumptions, not characterized
memory data.

Run `make sta-kd28` to verify the profiles, checksums, black-box link, setup/hold constraints, and
clock-to-output paths. Generated OpenSTA reports are written below `technology/work/kd28_sta/`.
