# Instructions for adapations to difference environments

## Using pip for Python requirements 

To generate `pip` `requirements.txt` files for both _frontend_ and _backend_ use the following commands:


```bash
uv pip compile --project src/frontend src/frontend/pyproject.toml --no-deps | `
    grep -v '# via' | `
    grep -v ipykernel > src/frontend/requirements.txt 

uv pip compile --project src/backend src/backend/pyproject.toml --no-deps | `
    grep -v '# via' | `
    grep -v ipykernel > src/backend/requirements.txt
```
