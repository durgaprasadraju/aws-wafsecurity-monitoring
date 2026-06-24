"""HTML and CSV report generation for WAF security reports."""

import csv
import io
from datetime import datetime, timezone
from typing import Any


def generate_csv(sections: dict[str, list[list[str]]]) -> str:
    """Generate CSV content from multiple report sections."""
    output = io.StringIO()
    writer = csv.writer(output)
    for section_name, rows in sections.items():
        writer.writerow([f"=== {section_name} ==="])
        for row in rows:
            writer.writerow(row)
        writer.writerow([])
    return output.getvalue()


def generate_html(
    report_type: str,
    environment: str,
    project_name: str,
    sections: dict[str, list[list[str]]],
    summary: dict[str, Any],
) -> str:
    """Generate HTML security report."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    sections_html = ""
    for section_name, rows in sections.items():
        if not rows:
            continue
        header = rows[0]
        body_rows = rows[1:] if len(rows) > 1 else []
        table_rows = "".join(
            f"<tr>{''.join(f'<td>{cell}</td>' for cell in row)}</tr>" for row in body_rows
        )
        header_cells = "".join(f"<th>{h}</th>" for h in header)
        sections_html += f"""
        <section>
          <h2>{section_name}</h2>
          <table>
            <thead><tr>{header_cells}</tr></thead>
            <tbody>{table_rows}</tbody>
          </table>
        </section>
        """

    summary_items = "".join(
        f"<li><strong>{k.replace('_', ' ').title()}:</strong> {v}</li>" for k, v in summary.items()
    )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>{report_type.title()} WAF Security Report - {environment}</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 2rem; color: #333; }}
    h1 {{ color: #232f3e; border-bottom: 2px solid #ff9900; padding-bottom: 0.5rem; }}
    h2 {{ color: #232f3e; margin-top: 2rem; }}
    table {{ border-collapse: collapse; width: 100%; margin: 1rem 0; }}
    th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
    th {{ background-color: #232f3e; color: white; }}
    tr:nth-child(even) {{ background-color: #f9f9f9; }}
    .summary {{ background: #f0f8ff; padding: 1rem; border-radius: 4px; }}
    .meta {{ color: #666; font-size: 0.9rem; }}
  </style>
</head>
<body>
  <h1>{project_name} - {report_type.title()} WAF Security Report</h1>
  <p class="meta">Environment: {environment} | Generated: {now}</p>
  <div class="summary">
    <h2>Executive Summary</h2>
    <ul>{summary_items}</ul>
  </div>
  {sections_html}
  <footer><p class="meta">AWS WAF Security Intelligence Platform</p></footer>
</body>
</html>"""
