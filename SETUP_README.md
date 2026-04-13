# LMS setup package

Contents:
- `Makefile`
- `scripts/setup.sh`

## Install into `learn-ops-infrastructure`

Copy these files into your `learn-ops-infrastructure` repo:

```text
learn-ops-infrastructure/
├── Makefile
└── scripts/
    └── setup.sh
```

Then run:

```bash
chmod +x scripts/setup.sh
make doctor
make setup
```

## Notes

- This package does not include a modified `docker-compose.yml`.
- `make up` uses whatever compose file already exists in `learn-ops-infrastructure`.
- The script clones sibling repos into `~/lms`.
