# AI Log Analyzer

Paste or upload a log file and get an AI-generated analysis — errors, warnings, patterns, and recommended fixes.

**Live demo:** https://log-analyzer.jimmyhubbard2.cc

**Full documentation:** [PROJECT_MASTER.md](./PROJECT_MASTER.md) — architecture, AWS operational reference, build history, and key decisions

## Overview

The AI Log Analyzer sends log file content to an AWS Lambda function, which calls the Anthropic API (Claude Haiku) to produce a structured analysis. The result identifies log type, overall severity, specific errors and warnings, recurring patterns, and actionable recommendations. Accepts `.log`, `.txt`, `.csv`, and `.json` files up to 50,000 characters.

## Features

- **File upload** — drag-and-drop or browse; accepts `.log`, `.txt`, `.csv`, `.json`
- **Live demo** — one-click load of a sample web server log
- **Structured analysis report:**
  - Log type classification (Application, System, Web Server, Database, Security, Network)
  - Severity rating (Critical / High / Medium / Low / Info)
  - 2–3 sentence summary
  - Timeline of key events (when timestamps are present)
  - Specific errors and warnings extracted from the log
  - Recurring patterns and anomalies
  - Recommended actions
  - Prevention tips
- **Synchronous** — result returned in a single API call; no polling required
- **50,000-character limit** — log content is truncated server-side if exceeded

## Tech stack

| Layer | Technology |
|---|---|
| Frontend | Vanilla HTML5, CSS3, JavaScript |
| Backend | AWS Lambda (Python 3.12) + API Gateway |
| AI | Anthropic API — claude-haiku-4-5-20251001 |
| Frontend hosting | AWS S3 + CloudFront |

No npm, no bundler, no framework, no external Python dependencies.

## Architecture

The frontend posts `{logContent, fileName}` to `POST /analyze` on API Gateway. Lambda receives the request, builds a structured prompt, and calls the Anthropic API directly via `urllib.request` (no SDK). The response is a raw JSON object parsed immediately and returned to the frontend. There is no async job queue or result storage — the analysis completes synchronously within the Lambda execution.

## Local development

```bash
python3 -m http.server 8080
```

Open `http://localhost:8080`. The frontend requires the deployed API Gateway endpoint — local-only testing will show a network error unless the Lambda is deployed.

## Deployment

`deploy.sh` automates infrastructure creation (IAM role, Lambda, API Gateway):

```bash
chmod +x deploy.sh
./deploy.sh
```

To update only the frontend after changes to `index.html`:

Frontend deploys automatically on push to main via GitHub Actions (.github/workflows/deploy.yml) — S3 sync + CloudFront invalidation handled by the workflow.

**S3 bucket:** `jimmy-log-analyzer` (us-east-1)  
**API Gateway:** `https://90rplm0obh.execute-api.us-east-1.amazonaws.com/prod/analyze`

## Environment variables

| Variable | Purpose |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic API key — set as encrypted Lambda env var |

## Project structure

```
log-analyzer/
├── index.html              # Frontend — upload UI, API call, results display
├── lambda_function.py      # Lambda handler — log parsing, Claude call, response
├── demo.log                # Sample web server log for the Live Demo button
└── deploy.sh               # Infra deploy script (IAM, Lambda, API Gateway)
```

## License

MIT — see [LICENSE](LICENSE)

## Author

Jimmy Hubbard — [github.com/jhubb88](https://github.com/jhubb88)

---

*Part of [jhubb88's portfolio](https://jimmyhubbard2.cc)*
