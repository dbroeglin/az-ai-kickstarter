# Instructions for adapations to difference environments

## Using pip for Python requirements 


### Generate requirements.txt files from uv

To generate `pip` `requirements.txt` files for both _frontend_ and _backend_ use the following commands:


```bash
uv pip compile --project src/frontend src/frontend/pyproject.toml --no-deps | `
    grep -v '# via' | `
    grep -v ipykernel > src/frontend/requirements.txt 
```

### Create virtual environments and install

#### Bash/Zsh

```bash
cd src/frontend 
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
```

#### In Powershell

```pwsh 
cd src\frontend 
python -m venv .venv
. .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```
```

### Use .env files rather than AZD environement

In `src/frontend` copy the `sample.env` file into the `.env` 
file and manually fill the variables. Optional fields are indicated.