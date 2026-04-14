import json
import os
import urllib.request
import urllib.error

ANTHROPIC_API_KEY = os.environ.get('ANTHROPIC_API_KEY', '')


def lambda_handler(event, context):
    if event.get('httpMethod') == 'OPTIONS':
        return cors_response(200, {})

    try:
        body = json.loads(event.get('body', '{}'))
        log_content = body.get('logContent', '').strip()
        file_name = body.get('fileName', 'unknown')

        if not log_content:
            return cors_response(400, {'error': 'No log content provided.'})

        if len(log_content) > 50000:
            log_content = log_content[:50000] + '\n... [truncated for analysis]'

        prompt = f"""You are an expert log analyst. Analyze the following log file and return a single JSON object with exactly these fields:

{{
  "logType": "string — type of log (e.g., Application, System, Web Server, Database, Security, Network)",
  "severity": "string — one of: Critical, High, Medium, Low, Info",
  "summary": "string — 2 to 3 sentence summary of what the log shows overall",
  "timeline": "string — describe the time range and key events in chronological order, or empty string if no timestamps found",
  "errors": ["array of strings — each item is a specific error found in the log"],
  "warnings": ["array of strings — each item is a specific warning found in the log"],
  "patterns": ["array of strings — each item describes a recurring pattern or anomaly"],
  "recommendedActions": ["array of strings — each item is a specific actionable fix or next step"],
  "preventionTips": ["array of strings — each item is a tip to prevent these issues in the future"]
}}

Rules:
- Return ONLY the raw JSON object. No markdown, no code blocks, no explanation.
- If a list field has no items, return an empty array [].
- If timeline has no timestamps, return an empty string "".

Log file name: {file_name}

Log content:
{log_content}"""

        request_body = json.dumps({
            'model': 'claude-haiku-4-5-20251001',
            'max_tokens': 2000,
            'temperature': 0.1,
            'messages': [{'role': 'user', 'content': prompt}]
        }).encode('utf-8')

        req = urllib.request.Request(
            'https://api.anthropic.com/v1/messages',
            data=request_body,
            headers={
                'x-api-key': ANTHROPIC_API_KEY,
                'anthropic-version': '2023-06-01',
                'content-type': 'application/json'
            },
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=25) as resp:
            result = json.loads(resp.read().decode('utf-8'))

        result_text = result['content'][0]['text'].strip()

        if result_text.startswith('```'):
            lines = result_text.split('\n')
            lines = [l for l in lines if not l.strip().startswith('```')]
            result_text = '\n'.join(lines).strip()

        analysis = json.loads(result_text)
        return cors_response(200, analysis)

    except json.JSONDecodeError as e:
        return cors_response(500, {'error': f'AI returned unparseable response: {str(e)}'})
    except urllib.error.HTTPError as e:
        return cors_response(500, {'error': f'Anthropic API error: {e.code} {e.read().decode()}'})
    except Exception as e:
        return cors_response(500, {'error': str(e)})


def cors_response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Content-Type': 'application/json'
        },
        'body': json.dumps(body)
    }
