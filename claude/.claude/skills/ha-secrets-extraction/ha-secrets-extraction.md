---
name: ha-secrets-extraction
description: >
  Use this skill whenever the user wants to separate secrets from their Home Assistant configuration files for safe git storage. Triggers include: "secrets.yaml", "HA config git", "hide API keys from Home Assistant", "commit Home Assistant to git", "split secrets from config", "!secret", ".gitignore for Home Assistant", or any request involving making Home Assistant configs safe for version control. Also trigger when the user wants to audit their HA config for sensitive data, or when they ask to refactor or clean up Home Assistant configuration files. This skill should be used proactively whenever the user is working with Home Assistant config files and git is mentioned.
---

# Home Assistant Secrets Extraction Skill

A skill for safely separating secrets from Home Assistant configuration files to enable git version control without exposing sensitive data.

## Overview

Home Assistant configurations often accumulate inline secrets — API keys, passwords, tokens, IP addresses, and credentials scattered across many files. This skill guides a systematic process to extract those secrets into `secrets.yaml` (which stays out of git) while leaving `!secret` references in the config files (which go into git safely).

---

## Phase 1: Discovery & Config Mapping

Before touching anything, build a complete picture of the config structure.

### 1.1 Map the directory structure

Use the HA MCP (or file tools) to list the config directory tree. Look for:
- `configuration.yaml` — main entry point
- `secrets.yaml` — may already exist with some secrets
- `packages/` — often contains domain-specific configs
- `automations.yaml`, `scripts.yaml`, `scenes.yaml`
- `custom_components/` — third-party integrations, often have their own config
- `.storage/` — runtime storage, usually NOT in git (skip this)
- Any other `.yaml` files referenced via `!include` or `!include_dir_*`

**Output**: A file tree showing which files exist and which ones reference others via includes.

### 1.2 Identify all included files

Read `configuration.yaml` first and trace all `!include` and `!include_dir_*` directives to build a complete list of files that need scanning. Do not miss nested includes.

---

## Phase 2: Secret Pattern Detection

Scan each config file for the following categories. Flag every match with: file path, line number, key name, and category.

### Definite Secrets (always extract)
- Passwords: keys containing `password`, `passwd`, `pass`
- API keys/tokens: keys containing `api_key`, `token`, `secret`, `key`, `access_key`
- Credentials: keys containing `username` + `password` pairs
- Auth strings, bearer tokens, client secrets, client IDs (for OAuth integrations)

### Probable Secrets (extract by default, confirm with user)
- Internal IP addresses (192.168.x.x, 10.x.x.x, 172.16-31.x.x) embedded as values
- MAC addresses
- Latitude/longitude coordinates (used in `home_assistant:` core config)
- SMTP/email credentials
- Webhook URLs containing tokens or keys
- Database connection strings

### Context-Dependent (ask user)
- External domain names / DuckDNS hostnames
- Port numbers
- Device serial numbers or unique IDs
- Telegram/Pushover/notification service IDs

### Not Secrets (leave as-is)
- Entity IDs, room names, device names
- Automation/script names and aliases  
- Template strings (unless they embed a credential inline)
- `unit_of_measurement`, `friendly_name`, `icon` values
- Boolean flags, numeric thresholds

---

## Phase 3: Secret Policy Confirmation

Before generating any output, present the findings to the user:

```
Found X potential secrets across Y files:

DEFINITE (will extract):
- config/integrations/hue.yaml:12 — api_key: "abc123..."
- configuration.yaml:8 — latitude: 52.3xxx

PROBABLE (recommend extracting):
- packages/cameras.yaml:34 — host: "192.168.1.x"
- ...

CONTEXT-DEPENDENT (need your decision):
- packages/notify.yaml:5 — chat_id: "12345678"
```

Ask the user to confirm or adjust before proceeding. Also ask:
1. Should internal IP addresses be treated as secrets? (Recommended: yes, for security)
2. Are there any values that look like secrets but are actually public/harmless?
3. Are there any additional patterns specific to their setup to look for?

---

## Phase 4: Generate Refactored Output

Work file by file. For each file containing secrets:

### 4.1 Naming convention for secrets.yaml keys

Use a consistent, descriptive naming scheme:
```
{integration}_{credential_type}
```
Examples:
- `hue_api_key`
- `mqtt_password`  
- `home_latitude`
- `frigate_rtsp_password`
- `telegram_chat_id`

If a name would collide, add a qualifier: `camera_front_door_rtsp_password`

### 4.2 Replacement format

Replace inline values with `!secret` references:
```yaml
# Before
hue:
  api_key: "abc123def456"

# After  
hue:
  api_key: !secret hue_api_key
```

Note: `!secret` does NOT use quotes around the key name.

### 4.3 Build secrets.yaml

Accumulate all extracted secrets into a `secrets.yaml` template:
```yaml
# secrets.yaml
# DO NOT COMMIT THIS FILE
# Copy this file, fill in real values, keep it local

hue_api_key: "REPLACE_WITH_YOUR_HUE_API_KEY"
mqtt_password: "REPLACE_WITH_YOUR_MQTT_PASSWORD"
home_latitude: "REPLACE_WITH_YOUR_LATITUDE"
```

Use descriptive placeholder strings that explain what the value should be.

### 4.4 Output approach

**Always generate new files, never overwrite originals directly.**

Create refactored versions as:
- `secrets.yaml.template` — the template with placeholder values (safe to review)
- Modified config files in a subfolder like `refactored/` mirroring the original structure

Present a clear diff summary showing what changed in each file.

---

## Phase 5: Git Configuration

Generate a `.gitignore` appropriate for Home Assistant:

```gitignore
# Home Assistant - Never commit these
secrets.yaml
.storage/
*.db
*.db-shm  
*.db-wal
home-assistant.log
home-assistant.log.*
home-assistant_v2.db*

# Backups
*.tar.gz
backups/

# Custom component caches
__pycache__/
*.pyc
```

Also recommend a `secrets.yaml.example` (committed) that mirrors the structure of real `secrets.yaml` with placeholder values — this helps collaborators or future-you know what secrets are needed.

---

## Phase 6: Validation Checklist

Before the user applies any changes, verify:

- [ ] Every `!secret key_name` in config files has a matching `key_name:` entry in `secrets.yaml`
- [ ] No original secret values appear in any committed file
- [ ] `secrets.yaml` itself is in `.gitignore`
- [ ] The HA config checker (`ha core check` or Developer Tools → YAML) passes on the refactored config
- [ ] Existing `secrets.yaml` entries (if any existed before) are preserved and not duplicated

---

## Important Notes

### Working with the HA MCP
- Use read tools to scan files, never modify live config files directly
- Always work on copies or present output for the user to apply manually
- The user's HA instance may be running — config file errors could break automations

### Large configs
For configs with 1000+ entities or complex package structures, process one domain/package at a time rather than all at once. This makes review manageable.

### Already-partial secrets.yaml
If a `secrets.yaml` already exists, read it first. Don't re-extract values that are already there. Only add new entries.

### Integration-specific patterns
Some integrations store credentials in `.storage/` (managed via UI) rather than YAML — these don't need to be extracted as they're already outside the config files. Focus only on YAML-defined credentials.
