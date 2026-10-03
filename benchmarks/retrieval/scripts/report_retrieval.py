import html
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

AREA_DIR = ROOT / "benchmarks" / "retrieval"
RAW_DIR = AREA_DIR / "resultados_raw"
HTML_PATH = AREA_DIR / "resultados" / "retrieval.html"


def percent(value):
    return f"{value * 100:.1f}%"


PRETTY_FOCUS = {"top1": "top1", "first_fact_in_top3": "fact_top3"}


def suggested_threshold(sweep):
    best = max(row["positive_correct"] for row in sweep)
    candidates = [row for row in sweep if row["positive_correct"] == best]
    return min(
        candidates,
        key=lambda row: (row["negative_false_positive"], -row["threshold"]),
    )


def sub_cell(correct, stats, key):
    if stats is None or stats.get(key) is None:
        return f"{correct} · —"
    return f"{correct} · {percent(stats[key])}"


def comparison_table(runs):
    rows = []
    for run in runs:
        summary = run["summary"]
        current = run["current_threshold"]
        suggested = suggested_threshold(run["threshold_sweep"])
        rows.append(
            "<tr>"
            f'<td>{html.escape(run["run"])}</td>'
            f'<td>{html.escape(run["focus_strategy"])}</td>'
            f'<td><code>{html.escape(run["settings"]["embedding_model"])}</code></td>'
            f'<td>{current["threshold"]:.2f}</td>'
            f'<td>{suggested["threshold"]:.2f}</td>'
            f'<td>{current["positive_correct"]}</td>'
            f'<td>{sub_cell(current.get("fact_correct", "—"), summary.get("fact"), "hit_at_1")}</td>'
            f'<td>{sub_cell(current.get("support_correct", "—"), summary.get("support"), "hit_at_3")}</td>'
            f'<td>{current["positive_ranking_error"]}</td>'
            f'<td>{current["positive_abstention"]}</td>'
            f'<td>{current["negative_false_positive"]}</td>'
            f'<td>{percent(summary["hit_at_1"])}</td>'
            f'<td>{percent(summary["hit_at_3"])}</td>'
            f'<td>{summary["mrr"]:.3f}</td>'
            f'<td>{summary["embedding_ms_mean"]:.0f} ms</td>'
            "</tr>"
        )
    return f"""
    <h2>Comparacion de runs</h2>
    <table>
      <thead><tr><th>Run</th><th>Focus</th><th>Modelo</th><th>Threshold</th><th>Thr. sugerido</th><th>Correctas</th><th>Fact (Hit@1)</th><th>Sup (Hit@3)</th><th>Equivocadas</th><th>Omisiones</th><th>Falsos positivos</th><th>Hit@1</th><th>Hit@3</th><th>MRR</th><th>ms/emb</th></tr></thead>
      <tbody>{''.join(rows)}</tbody>
    </table>
    <p>Correctas: respondio con el chunk esperado. Fact: correctas con fact_id y su Hit@1 (mide progresion). Sup: correctas sin fact_id y su Hit@3 (mide recall en contexto). Equivocadas: respondio con otro chunk. Omisiones: se abstuvo debiendo responder. Falsos positivos: respondio debiendo abstenerse. Thr. sugerido: threshold con menos falsos positivos sin bajar las correctas del maximo.</p>
    """


def sweep_table(run):
    current = run["current_threshold"]
    rows = []
    shown = set()
    for step in range(21):
        shown.add(round(step / 20, 2))
    shown.add(current["threshold"])
    for row in run["threshold_sweep"]:
        if row["threshold"] not in shown:
            continue
        correct = f'{row["positive_correct"]}'
        if "fact_correct" in row:
            correct += f' ({row["fact_correct"]}/{row["support_correct"]})'
        rows.append(
            "<tr>"
            f'<td>{row["threshold"]:.2f}</td>'
            f"<td>{correct}</td>"
            f'<td>{row["positive_ranking_error"]}</td>'
            f'<td>{row["positive_abstention"]}</td>'
            f'<td>{row["negative_false_positive"]}</td>'
            "</tr>"
        )
    return f"""
    <h3>Barrido de thresholds</h3>
    <table>
      <thead><tr><th>Threshold</th><th>Correctas</th><th>Equivocadas</th><th>Omisiones</th><th>Falsos positivos</th></tr></thead>
      <tbody>{''.join(rows)}</tbody>
    </table>
    """


def case_table(title, cases):
    rows = []
    for case in cases:
        subset = case.get("subset") or "—"
        rows.append(
            "<tr>"
            f'<td>{html.escape(case["id"])}</td>'
            f'<td>{html.escape(subset)}</td>'
            f'<td>{html.escape(case["npc_id"])}</td>'
            f'<td>{html.escape(case["query"])}</td>'
            f'<td>{html.escape(str(case["expected_focus"]))}</td>'
            f'<td>{html.escape(case["top_chunk_id"])}</td>'
            f'<td>{case["top_score"]:.4f}</td>'
            f'<td>{html.escape(str(case["gold_rank"]))}</td>'
            f'<td>{"" if case["gold_score"] is None else f"{case["gold_score"]:.4f}"}</td>'
            "</tr>"
        )
    if not rows:
        rows.append('<tr><td colspan="9">Ninguno</td></tr>')
    return f"""
    <h3>{html.escape(title)}</h3>
    <table>
      <thead><tr><th>Caso</th><th>Subset</th><th>NPC</th><th>Consulta</th><th>Gold</th><th>Top</th><th>Top score</th><th>Gold rank</th><th>Gold score</th></tr></thead>
      <tbody>{''.join(rows)}</tbody>
    </table>
    """


def inner_label(run):
    slug = run["settings"]["embedding_model"].split("/")[-1]
    stem = Path(run.get("chunks", "")).stem
    if stem and stem != "chunks_v1":
        slug += " · " + stem
    return slug


def run_section(run, outer_index, inner_index):
    summary = run["summary"]
    worst = run["worst_cases"]
    generated_at = html.escape(run["generated_at"])
    model = html.escape(run["settings"]["embedding_model"])
    suggested = suggested_threshold(run["threshold_sweep"])
    fact = summary.get("fact") or {}
    support = summary.get("support") or {}
    fact_hit_at_1 = (
        percent(fact["hit_at_1"]) if fact.get("hit_at_1") is not None else "—"
    )
    support_hit_at_3 = (
        percent(support["hit_at_3"])
        if support.get("hit_at_3") is not None
        else "—"
    )
    active = " active" if inner_index == 0 else ""
    return f"""
    <div class="tab-panel{active}" id="tab-{outer_index}-{inner_index}">
    <h2>{html.escape(run["run"])}</h2>
    <p>Focus: <code>{html.escape(run["focus_strategy"])}</code><br>Generado: {generated_at}<br>Embedding: <code>{model}</code><br>Threshold sugerido: {suggested["threshold"]:.2f} ({suggested["positive_correct"]} correctas, {suggested["negative_false_positive"]} falsos positivos)</p>
    <div class="cards">
      <div class="card"><span class="value">{summary["positive_cases"]}</span>positivos</div>
      <div class="card"><span class="value">{summary["negative_cases"]}</span>negativos</div>
      <div class="card"><span class="value">{percent(summary["hit_at_1"])}</span>Hit@1</div>
      <div class="card"><span class="value">{percent(summary["hit_at_3"])}</span>Hit@3</div>
      <div class="card"><span class="value">{summary["mrr"]:.3f}</span>MRR</div>
      <div class="card"><span class="value">{fact_hit_at_1}</span>Hit@1 fact</div>
      <div class="card"><span class="value">{support_hit_at_3}</span>Hit@3 support</div>
      <div class="card"><span class="value">{summary["embedding_ms_mean"]:.0f} ms</span>por embedding</div>
    </div>
    {sweep_table(run)}
    {case_table("Errores de ranking", worst["ranking_errors"])}
    {case_table("Positivos con menor score gold", worst["weak_positives"])}
    {case_table("Negativos con mayor top score", worst["hard_negatives"])}
    </div>
    """


def main():
    paths = sorted(RAW_DIR.glob("*.json"))
    assert paths, f"no hay runs en {RAW_DIR}"
    runs = []
    for path in paths:
        runs.append(json.loads(path.read_text(encoding="utf-8")))

    groups = {}
    for run in runs:
        groups.setdefault(run["focus_strategy"], []).append(run)
    ordered = sorted(groups.items(), key=lambda item: (item[0] != "top1", item[0]))

    outer_tabs = ""
    outer_panels = ""
    for outer_index, (focus, group) in enumerate(ordered):
        outer_active = " active" if outer_index == 0 else ""
        outer_tabs += f'<button class="outer-tab{outer_active}" data-tab="outer-{outer_index}">{html.escape(PRETTY_FOCUS.get(focus, focus))}</button>'
        inner_tabs = "".join(
            f'<button class="tab{" active" if inner_index == 0 else ""}" data-tab="tab-{outer_index}-{inner_index}">{html.escape(inner_label(run))}</button>'
            for inner_index, run in enumerate(group)
        )
        inner_panels = "".join(
            run_section(run, outer_index, inner_index)
            for inner_index, run in enumerate(group)
        )
        outer_panels += f'<div class="outer-panel{outer_active}" id="outer-{outer_index}"><div class="tabs inner-tabs">{inner_tabs}</div>{inner_panels}</div>'
    HTML_PATH.parent.mkdir(parents=True, exist_ok=True)
    HTML_PATH.write_text(
        f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Benchmark retrieval</title>
<style>
body {{ font: 15px/1.45 system-ui, sans-serif; max-width: 1200px; margin: 32px auto; padding: 0 20px; color: #202124; }}
h1, h2, h3 {{ color: #18212b; }}
.cards {{ display: flex; flex-wrap: wrap; gap: 12px; }}
.card {{ border: 1px solid #d9dee3; border-radius: 8px; padding: 12px 16px; min-width: 145px; }}
.value {{ display: block; font-size: 25px; font-weight: 700; }}
table {{ border-collapse: collapse; width: 100%; margin: 12px 0 30px; }}
th, td {{ border: 1px solid #d9dee3; padding: 7px 9px; text-align: left; vertical-align: top; }}
th {{ background: #f3f5f7; }}
tbody tr:nth-child(even) {{ background: #fafbfc; }}
.tabs {{ display: flex; gap: 8px; margin: 12px 0 0; }}
.tab, .outer-tab {{ font: inherit; border: 1px solid #d9dee3; background: #f3f5f7; border-radius: 8px 8px 0 0; padding: 8px 16px; cursor: pointer; }}
.tab.active, .outer-tab.active {{ background: #fff; font-weight: 700; border-bottom-color: #fff; }}
.tab-panel, .outer-panel {{ display: none; border: 1px solid #d9dee3; border-radius: 0 8px 8px 8px; padding: 0 16px 16px; margin-top: -1px; }}
.tab-panel.active, .outer-panel.active {{ display: block; }}
.inner-tabs {{ margin-top: 12px; }}
</style>
</head>
<body>
<h1>Benchmark retrieval</h1>
{comparison_table(runs)}
<div class="tabs outer-tabs">{outer_tabs}</div>
{outer_panels}
<script>
function selectInner(group, button) {{
  group.querySelectorAll(".tab").forEach((other) => other.classList.remove("active"));
  group.querySelectorAll(".tab-panel").forEach((panel) => panel.classList.remove("active"));
  button.classList.add("active");
  document.getElementById(button.dataset.tab).classList.add("active");
}}
document.querySelectorAll(".outer-panel").forEach((group) => {{
  group.querySelectorAll(".inner-tabs .tab").forEach((button) => {{
    button.addEventListener("click", () => selectInner(group, button));
  }});
}});
document.querySelectorAll(".outer-tab").forEach((button) => {{
  button.addEventListener("click", () => {{
    document.querySelectorAll(".outer-tab").forEach((other) => other.classList.remove("active"));
    document.querySelectorAll(".outer-panel").forEach((panel) => panel.classList.remove("active"));
    button.classList.add("active");
    const group = document.getElementById(button.dataset.tab);
    group.classList.add("active");
    selectInner(group, group.querySelector(".tab.active") || group.querySelector(".tab"));
  }});
}});
</script>
</body>
</html>
""",
        encoding="utf-8",
    )
    print(f"Runs: {len(runs)}")
    print(f"HTML: {HTML_PATH}")


if __name__ == "__main__":
    main()
