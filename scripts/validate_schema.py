#!/usr/bin/env python3

import json
import sys
from pathlib import Path
from jsonschema import validate, ValidationError

def load_json(file_path):
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error parsing {file_path}: {e}")
        return None
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return None

def main():
    # Pad naar schema en config
    schema_path = Path("schema/repos-config-schema.json")
    config_path = Path("data/repos-config.json")

    # Laad schema
    schema = load_json(schema_path)
    if not schema:
        sys.exit(1)

    # Laad config
    config = load_json(config_path)
    if not config:
        sys.exit(1)

    # Valideer config tegen schema
    try:
        validate(instance=config, schema=schema)
        print("✅ Configuratie is geldig volgens schema")
        sys.exit(0)
    except ValidationError as e:
        print(f"❌ Configuratie is ongeldig: {e.message}")
        print(f"   Op pad: {' -> '.join(str(p) for p in e.path)}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Onverwachte fout tijdens validatie: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()