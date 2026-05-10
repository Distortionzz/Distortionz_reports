# Distortionz Reports

> Premium player report / support ticket system for Qbox/FiveM — NUI submit form, staff queue, threaded conversation view. Tier-gated via distortionz_perms.

![FiveM](https://img.shields.io/badge/FiveM-cerulean-yellow?style=flat-square&labelColor=181b20)
![Qbox](https://img.shields.io/badge/Qbox-required-red?style=flat-square&labelColor=dfb317)
![License](https://img.shields.io/badge/License-MIT-brightgreen?style=flat-square)
![Version](https://img.shields.io/github/v/release/Distortionzz/Distortionz_Reports?style=flat-square&color=d4aa62&label=version)

---

## Overview

Premium support / report system replacing in-game `/report` chat spam. Players submit tickets via NUI, staff triage them in a queue, and conversations thread between reporter and staff with full MySQL persistence.

## Features

- Player-facing **submit form** with category, description, attachments
- Staff **queue dashboard** with filters (open / claimed / closed) and sort
- **Threaded conversation** between reporter and staff
- **MySQL ticket persistence** — full history retained
- **Tier-gated** Staff Queue tab — visible only to mod+ via `distortionz_perms`
- **Default keybind** F6 + `/report` command
- In-NUI confirm + toast (no native dialogs)

## Dependencies

| Resource | Required | Purpose |
|---|---|---|
| `qbx_core` | yes | Player data |
| `ox_lib` | yes | Callbacks |
| `oxmysql` | yes | Ticket persistence |
| `distortionz_perms` | yes | Staff tier gating |
| `distortionz_notify` | optional | Branded notifications |

## Installation

```cfg
ensure oxmysql
ensure distortionz_perms
ensure distortionz_reports
```

## Configuration

See [`config.lua`](config.lua) for keybind, ticket categories, max attachments, retention period, tier requirements per action.

## Credits

- **Author:** Distortionz
- **Framework:** [Qbox Project](https://github.com/Qbox-project)

## License

MIT — see [LICENSE](LICENSE).
