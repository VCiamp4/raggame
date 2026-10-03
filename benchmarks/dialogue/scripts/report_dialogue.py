import html
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]

RAW_DIR = ROOT / "benchmarks" / "dialogue" / "resultados_raw"
JUICIOS_DIR = RAW_DIR / "juicios"
HTML_PATH = ROOT / "benchmarks" / "dialogue" / "resultados" / "dialogue.html"
CHUNKS_DIR = ROOT / "story" / "chunks"


def load_chunk_texts():
    chunks = {}
    for path in sorted(CHUNKS_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for chunk in data["chunks"]:
            chunks[chunk["chunk_id"]] = chunk["retrieval_text"]
    return chunks


def load_verdicts():
    merged = {}
    if JUICIOS_DIR.is_dir():
        for path in sorted(JUICIOS_DIR.glob("*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            for run_name, verdicts in data.items():
                merged.setdefault(run_name, {}).update(verdicts)
    return merged


def juicio_summary(run_name, verdicts):
    judged = verdicts.get(run_name, {})
    if not judged:
        return ("—", "—", "—", "—")
    counts = {
        rating: sum(1 for verdict in judged.values() if verdict.get("rating") == rating)
        for rating in ("bien", "medio", "mal")
    }
    return (counts["bien"], counts["medio"], counts["mal"], len(judged))


def comparison_table(runs, verdicts):
    rows = []
    for run in runs:
        summary = run["summary"]
        bien, medio, mal, total_juzgado = juicio_summary(run["run"], verdicts)
        rows.append(
            "<tr>"
            f'<td>{html.escape(run["run"])}</td>'
            f'<td><code>{html.escape(run["settings"]["chat_model"])}</code></td>'
            f'<td>{summary["conversations"]}</td>'
            f'<td>{summary["turns"]}</td>'
            f'<td>{bien}</td><td>{medio}</td><td>{mal}</td><td>{total_juzgado}</td>'
            f'<td>{summary["ttft_ms_mean"]:.0f} ms</td>'
            f'<td>{summary["retrieval_ms_mean"]:.0f} ms</td>'
            "</tr>"
        )
    return f"""
    <h2>Comparacion de runs</h2>
    <table>
      <thead><tr><th>Run</th><th>Modelo</th><th>Conversaciones</th><th>Turnos</th><th>Bien</th><th>Medio</th><th>Mal</th><th>Juzgados</th><th>TTFT medio</th><th>Retrieval medio</th></tr></thead>
      <tbody>{''.join(rows)}</tbody>
    </table>
    <p>Juicio: valoración humana por turno. Chunk ideal: texto que debería haber recibido el LLM. ¿En contexto?: indica si ese chunk apareció entre los recuperados para el turno.</p>
    """


def verdict_cell(run_name, key, saved):
    verdict = saved.get(key, {})
    note = html.escape(verdict.get("note", ""), quote=True)
    buttons = "".join(
        f'<button class="vbtn" data-run="{html.escape(run_name)}" '
        f'data-key="{html.escape(key)}" data-rating="{rating}">{label}</button>'
        for rating, label in (("bien", "Bien"), ("medio", "Medio"), ("mal", "Mal"))
    )
    return (
        f'{buttons}<br><input type="text" data-run="{html.escape(run_name)}" '
        f'data-key="{html.escape(key)}" data-note placeholder="nota" value="{note}">'
    )


def context_cell(turn):
    if not turn.get("context"):
        return "—"
    return (
        "<details><summary>ver</summary><pre>"
        f"{html.escape(turn['context'])}"
        "</pre></details>"
    )


def conversation_section(run_name, conversation, saved, chunk_texts):
    rows = []
    for number, turn in enumerate(conversation["turns"], start=1):
        key = f'{conversation["id"]}#{number}'
        expected_chunk = turn.get("expect_focus")
        if expected_chunk:
            ideal_chunk = chunk_texts[expected_chunk]
            in_context = "Sí" if expected_chunk in turn["retrieved"] else "No"
        else:
            ideal_chunk = in_context = "—"
        rows.append(
            "<tr>"
            f"<td>{number}</td>"
            f"<td>{html.escape(turn['player'])}</td>"
            f"<td>{html.escape(turn.get('expect', '')) or '—'}</td>"
            f"<td>{html.escape(turn['response'])}</td>"
            f'<td class="ideal-chunk">{html.escape(ideal_chunk)}</td>'
            f"<td>{in_context}</td>"
            f"<td>{context_cell(turn)}</td>"
            f"<td>{html.escape(', '.join(turn['new_facts']) or '—')}</td>"
            f"<td>{turn['ttft_ms']:.0f} ms</td>"
            f"<td>{verdict_cell(run_name, key, saved)}</td>"
            "</tr>"
        )
    return f"""
    <h2>{html.escape(conversation["id"])} <small>({html.escape(conversation["npc_id"])})</small></h2>
    <table>
      <thead><tr><th>#</th><th>Jugador</th><th>Esperado</th><th>NPC</th><th>Chunk ideal</th><th>¿En contexto?</th><th>Contexto</th><th>Facts nuevos</th><th>TTFT</th><th>Juicio</th></tr></thead>
      <tbody>{''.join(rows)}</tbody>
    </table>
    """


def main():
    paths = sorted(RAW_DIR.glob("*.json"))
    assert paths, f"no hay runs en {RAW_DIR}"
    runs = []
    for path in paths:
        runs.append(json.loads(path.read_text(encoding="utf-8")))

    chunk_texts = load_chunk_texts()
    verdicts = load_verdicts()
    active_verdicts = {
        run["run"]: verdicts.get(run["run"], {})
        for run in runs
    }
    embedded = json.dumps(active_verdicts, ensure_ascii=False).replace("</", "<\\/")
    def short(run):
        return run["settings"]["chat_model"].split("/")[-1]

    tabs = "".join(
        f'<button class="tab{" active" if index == 0 else ""}" data-tab="tab-{index}">{html.escape(short(run))}</button>'
        for index, run in enumerate(runs)
    )
    sections = "".join(
        f'<div class="tab-panel{" active" if index == 0 else ""}" id="tab-{index}">'
        + "".join(
            conversation_section(
                run["run"], conversation, verdicts.get(run["run"], {}), chunk_texts
            )
            for conversation in run["conversations"]
        )
        + "</div>"
        for index, run in enumerate(runs)
    )
    HTML_PATH.parent.mkdir(parents=True, exist_ok=True)
    HTML_PATH.write_text(
        f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Benchmark dialogue</title>
<style>
body {{ font: 15px/1.45 system-ui, sans-serif; max-width: 1200px; margin: 32px auto; padding: 0 20px; color: #202124; }}
h1, h2 {{ color: #18212b; }}
small {{ font-weight: 400; color: #5f6368; }}
table {{ border-collapse: collapse; width: 100%; margin: 12px 0 30px; }}
th, td {{ border: 1px solid #d9dee3; padding: 7px 9px; text-align: left; vertical-align: top; }}
th {{ background: #f3f5f7; }}
td.ideal-chunk {{ min-width: 240px; overflow-wrap: anywhere; }}
tbody tr:nth-child(even) {{ background: #fafbfc; }}
.vbtn {{ margin-right: 3px; cursor: pointer; }}
.vbtn.sel-bien {{ background: #c8e6c9; }}
.vbtn.sel-medio {{ background: #fff2cc; }}
.vbtn.sel-mal {{ background: #ffcdd2; }}
input[data-note] {{ width: 140px; margin-top: 4px; }}
.tabs {{ display: flex; gap: 8px; margin: 12px 0 0; }}
.tab {{ font: inherit; border: 1px solid #d9dee3; background: #f3f5f7; border-radius: 8px 8px 0 0; padding: 8px 16px; cursor: pointer; }}
.tab.active {{ background: #fff; font-weight: 700; border-bottom-color: #fff; }}
.tab-panel {{ display: none; border: 1px solid #d9dee3; border-radius: 0 8px 8px 8px; padding: 0 16px 16px; margin-top: -1px; }}
.tab-panel.active {{ display: block; }}
</style>
</head>
<body>
<h1>Benchmark dialogue</h1>
<p><button id="export">Exportar juicios</button> <button id="clear-draft">Descartar borrador</button> Juzgá cada turno como Bien, Medio o Mal, con nota opcional. Tus clics quedan como borrador en este navegador; Exportar los fija en un archivo que va en <code>benchmarks/dialogue/resultados_raw/juicios/</code> y al regenerar el reporte quedan fijos en el HTML. Descartar borrador vuelve a lo último guardado.</p>
{comparison_table(runs, verdicts)}
<div class="tabs">{tabs}</div>
{sections}
<script>
window.__VERDICTS__ = {embedded};
const state = JSON.parse(JSON.stringify(window.__VERDICTS__ || {{}}));
const LS_KEY = "dialogue-juicios-v2";
try {{
  const saved = JSON.parse(localStorage.getItem(LS_KEY) || "{{}}");
  for (const run of Object.keys(saved)) {{
    state[run] = Object.assign({{}}, state[run] || {{}}, saved[run]);
  }}
}} catch (e) {{}}
function persist() {{
  try {{ localStorage.setItem(LS_KEY, JSON.stringify(state)); }} catch (e) {{}}
}}
function paint() {{
  document.querySelectorAll(".vbtn").forEach((button) => {{
    const verdict = (state[button.dataset.run] || {{}})[button.dataset.key] || {{}};
    for (const rating of ["bien", "medio", "mal"]) {{
      button.classList.toggle("sel-" + rating, button.dataset.rating === rating && verdict.rating === rating);
    }}
  }});
  document.querySelectorAll("input[data-note]").forEach((input) => {{
    const verdict = (state[input.dataset.run] || {{}})[input.dataset.key] || {{}};
    if (document.activeElement !== input) input.value = verdict.note || "";
  }});
}}
function entry(run, key) {{
  state[run] = state[run] || {{}};
  state[run][key] = state[run][key] || {{}};
  return state[run][key];
}}
document.querySelectorAll(".vbtn").forEach((button) => {{
  button.addEventListener("click", () => {{
    entry(button.dataset.run, button.dataset.key).rating = button.dataset.rating;
    persist();
    paint();
  }});
}});
document.querySelectorAll("input[data-note]").forEach((input) => {{
  input.addEventListener("input", () => {{
    entry(input.dataset.run, input.dataset.key).note = input.value;
    persist();
  }});
}});
document.getElementById("export").addEventListener("click", () => {{
  const blob = new Blob([JSON.stringify(state, null, 2)], {{type: "application/json"}});
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = "juicios.json";
  link.click();
  alert("Guardá juicios.json en benchmarks/dialogue/resultados_raw/juicios/ y regenerá el reporte.");
}});
document.getElementById("clear-draft").addEventListener("click", () => {{
  try {{ localStorage.removeItem(LS_KEY); }} catch (e) {{}}
  location.reload();
}});
document.querySelectorAll(".tab").forEach((button) => {{
  button.addEventListener("click", () => {{
    document.querySelectorAll(".tab").forEach((other) => other.classList.remove("active"));
    document.querySelectorAll(".tab-panel").forEach((panel) => panel.classList.remove("active"));
    button.classList.add("active");
    document.getElementById(button.dataset.tab).classList.add("active");
  }});
}});
paint();
</script>
""",
        encoding="utf-8",
    )
    print(f"Runs: {len(runs)}")
    print(f"HTML: {HTML_PATH}")


if __name__ == "__main__":
    main()
