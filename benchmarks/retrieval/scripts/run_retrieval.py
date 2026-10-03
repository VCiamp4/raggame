import argparse
import hashlib
import json
import sys
import time
from dataclasses import asdict
from datetime import datetime
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from backend.config import settings
from backend.rag.retrieval import (
    Chunk,
    cosine_similarity,
    get_embedding,
)


def load_run_chunks(chunks_path, embeddings_path):
    chunks_path = Path(chunks_path)
    files = (
        [chunks_path]
        if chunks_path.is_file()
        else sorted(chunks_path.glob("*.json"))
    )
    with np.load(embeddings_path) as data:
        embeddings = {}
        for chunk_id, chunk_embeddings in zip(
            data["chunk_ids"], data["embeddings"]
        ):
            embeddings[chunk_id] = chunk_embeddings

    chunks = []
    for path in files:
        for raw_chunk in json.loads(path.read_text(encoding="utf-8"))["chunks"]:
            chunk_embeddings = embeddings[raw_chunk["chunk_id"]]
            chunks.append(
                Chunk(
                    **raw_chunk,
                    retrieval_embedding=chunk_embeddings[0].tolist(),
                    q1_embedding=chunk_embeddings[1].tolist(),
                    q2_embedding=chunk_embeddings[2].tolist(),
                )
            )
    return chunks


AREA_DIR = ROOT / "benchmarks" / "retrieval"
FIXTURES_DIR = AREA_DIR / "fixtures"
RAW_DIR = AREA_DIR / "resultados_raw"
DEFAULT_CHUNKS = FIXTURES_DIR / "chunks_v1.json"

FOCUS_ALL = "all"
FOCUS_TOP1 = "top1"
FOCUS_FACT_TOP3 = "fact_top3"
FOCUS_CHOICES = [FOCUS_TOP1, FOCUS_FACT_TOP3]
FOCUS_STRATEGIES = {
    FOCUS_TOP1: FOCUS_TOP1,
    FOCUS_FACT_TOP3: "first_fact_in_top3",
}


def model_slug(model):
    return model.split("/")[-1].replace(":", "-")


def fixture_model(path):
    with np.load(path) as data:
        if "model" not in data:
            raise KeyError(
                f"{path} no guarda el modelo; regeneralo con build_embeddings"
            )
        return str(data["model"])


def chunk_is_available(chunk, npc_id, known_facts):
    if npc_id not in chunk.knowledge_holders:
        return False
    if not set(chunk.necessary_facts) <= known_facts:
        return False
    if not chunk.sufficient_facts:
        return True
    return bool(set(chunk.sufficient_facts) & known_facts)


def validate_corpus(corpus, chunks):
    chunks_by_id = {}
    for chunk in chunks:
        chunks_by_id[chunk.chunk_id] = chunk

    ids = []
    for case in corpus["cases"]:
        ids.append(case["id"])
    assert len(ids) == len(set(ids)), "Hay ids de casos repetidos"

    positives = 0
    fact_positives = 0
    support_positives = 0
    negatives = 0
    for case in corpus["cases"]:
        known_facts = set(case["known_facts"])
        if case["kind"] == "positive":
            positives += 1
            expected = chunks_by_id[case["expected_focus"]]
            assert chunk_is_available(expected, case["npc_id"], known_facts), (
                f'{case["id"]}: el focus esperado no esta disponible'
            )
            if expected.fact_id is not None:
                fact_positives += 1
            else:
                support_positives += 1
        else:
            negatives += 1
            assert case["expected_focus"] is None

    return {
        "cases": len(ids),
        "positives": positives,
        "fact_positives": fact_positives,
        "support_positives": support_positives,
        "negatives": negatives,
    }


def select_focus(ranking, focus):
    if focus == FOCUS_FACT_TOP3:
        return next(
            (item for item in ranking[:3] if item["fact_id"] is not None),
            ranking[0],
        )
    return ranking[0]


def score_case(case, chunks, focus):
    known_facts = set(case["known_facts"])
    available_chunks = []
    for chunk in chunks:
        if chunk_is_available(chunk, case["npc_id"], known_facts):
            available_chunks.append(chunk)

    start = time.perf_counter()
    query_embedding = get_embedding(case["query"])
    embedding_ms = (time.perf_counter() - start) * 1000.0
    ranking = []
    for chunk in available_chunks:
        retrieval_score = cosine_similarity(
            query_embedding, chunk.retrieval_embedding
        )
        q1_score = cosine_similarity(query_embedding, chunk.q1_embedding)
        q2_score = cosine_similarity(query_embedding, chunk.q2_embedding)
        ranking.append(
            {
                "chunk_id": chunk.chunk_id,
                "fact_id": chunk.fact_id,
                "score": max(retrieval_score, q1_score, q2_score),
                "retrieval_score": retrieval_score,
                "q1_score": q1_score,
                "q2_score": q2_score,
            }
        )
    ranking.sort(key=lambda item: item["score"], reverse=True)

    expected = case["expected_focus"]
    expected_chunk = next(
        (chunk for chunk in chunks if chunk.chunk_id == expected), None
    )
    subset = None
    if expected_chunk is not None:
        subset = (
            "fact" if expected_chunk.fact_id is not None else "support"
        )
    gold = None
    for item in ranking:
        if item["chunk_id"] == expected:
            gold = item
            break
    gold_rank = ranking.index(gold) + 1 if gold else None
    top = select_focus(ranking, focus)
    return {
        **case,
        "subset": subset,
        "available_chunks": len(available_chunks),
        "embedding_ms": embedding_ms,
        "top_chunk_id": top["chunk_id"],
        "top_score": top["score"],
        "gold_available": gold is not None if expected else None,
        "gold_rank": gold_rank,
        "gold_score": gold["score"] if gold else None,
        "ranking_correct": top["chunk_id"] == expected if expected else None,
        "top_results": ranking[:10],
    }


def focus_at_threshold(case, threshold, focus):
    if focus == FOCUS_FACT_TOP3:
        accepted = [
            item
            for item in case["top_results"][:3]
            if item["score"] >= threshold
        ]
        if not accepted:
            return None
        for item in accepted:
            if item["fact_id"] is not None:
                return item
        return accepted[0]
    if case["top_score"] >= threshold:
        return {"chunk_id": case["top_chunk_id"]}
    return None


def metrics_at_threshold(cases, threshold, focus):
    positive_correct = 0
    fact_correct = 0
    support_correct = 0
    positive_ranking_error = 0
    positive_abstention = 0
    negative_false_positive = 0
    negative_abstention = 0

    for case in cases:
        answered = focus_at_threshold(case, threshold, focus)
        if case["kind"] == "positive":
            if answered is None:
                positive_abstention += 1
            elif answered["chunk_id"] == case["expected_focus"]:
                positive_correct += 1
                if case.get("subset") == "support":
                    support_correct += 1
                else:
                    fact_correct += 1
            else:
                positive_ranking_error += 1
        elif answered is not None:
            negative_false_positive += 1
        else:
            negative_abstention += 1

    positives = positive_correct + positive_ranking_error + positive_abstention
    negatives = negative_false_positive + negative_abstention
    return {
        "threshold": threshold,
        "positive_correct": positive_correct,
        "fact_correct": fact_correct,
        "support_correct": support_correct,
        "positive_ranking_error": positive_ranking_error,
        "positive_abstention": positive_abstention,
        "positive_accuracy": positive_correct / positives,
        "negative_false_positive": negative_false_positive,
        "negative_abstention": negative_abstention,
        "negative_false_positive_rate": negative_false_positive / negatives,
    }


def threshold_sweep(cases, focus):
    sweep = []
    for step in range(101):
        sweep.append(metrics_at_threshold(cases, step / 100, focus))
    return sweep


def ranking_summary(cases):
    positives = [
        case for case in cases if case["kind"] == "positive"
    ]
    hit_at_1 = sum(1 for case in positives if case["ranking_correct"])
    hit_at_3 = sum(1 for case in positives if case["gold_rank"] <= 3)
    reciprocal_rank = sum(1 / case["gold_rank"] for case in positives)
    total = len(positives)
    summary = {
        "hit_at_1": hit_at_1 / total,
        "hit_at_3": hit_at_3 / total,
        "mrr": reciprocal_rank / total,
    }
    for subset in ("fact", "support"):
        subset_cases = [
            case for case in positives if case.get("subset") == subset
        ]
        if not subset_cases:
            summary[subset] = None
            continue
        subset_hit_at_1 = sum(
            1 for case in subset_cases if case["ranking_correct"]
        )
        subset_hit_at_3 = sum(
            1 for case in subset_cases if case["gold_rank"] <= 3
        )
        subset_reciprocal = sum(
            1 / case["gold_rank"] for case in subset_cases
        )
        total_subset = len(subset_cases)
        summary[subset] = {
            "positives": total_subset,
            "hit_at_1": subset_hit_at_1 / total_subset,
            "hit_at_3": subset_hit_at_3 / total_subset,
            "mrr": subset_reciprocal / total_subset,
        }
    return summary


def worst_cases(cases):
    ranking_errors = []
    weak_positives = []
    hard_negatives = []
    for case in cases:
        if case["kind"] == "positive":
            weak_positives.append(case)
            if not case["ranking_correct"]:
                ranking_errors.append(case)
        else:
            hard_negatives.append(case)

    ranking_errors.sort(
        key=lambda case: (-case["gold_rank"], case["gold_score"])
    )
    weak_positives.sort(key=lambda case: case["gold_score"])
    hard_negatives.sort(key=lambda case: case["top_score"], reverse=True)
    ranking_errors = ranking_errors[:20]
    weak_positives = weak_positives[:20]
    hard_negatives = hard_negatives[:20]
    fields = (
        "id",
        "npc_id",
        "query",
        "expected_focus",
        "top_chunk_id",
        "top_score",
        "gold_rank",
        "gold_score",
    )
    ranking_error_results = []
    for case in ranking_errors:
        result = {}
        for field in fields:
            result[field] = case[field]
        ranking_error_results.append(result)

    weak_positive_results = []
    for case in weak_positives:
        result = {}
        for field in fields:
            result[field] = case[field]
        weak_positive_results.append(result)

    hard_negative_results = []
    for case in hard_negatives:
        result = {}
        for field in fields:
            result[field] = case[field]
        hard_negative_results.append(result)

    return {
        "ranking_errors": ranking_error_results,
        "weak_positives": weak_positive_results,
        "hard_negatives": hard_negative_results,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="valida el corpus sin consultar Ollama",
    )
    parser.add_argument(
        "--focus",
        choices=[FOCUS_ALL, *FOCUS_CHOICES],
        default=FOCUS_ALL,
        help="variante a correr (por defecto: todas)",
    )
    parser.add_argument("--corpus", default=None, type=Path)
    parser.add_argument("--chunks", default=None, type=Path)
    parser.add_argument("--embeddings", default=None, type=Path)
    parser.add_argument("--embedding-model", default=None)
    parser.add_argument("--run-name", default=None)
    args = parser.parse_args()

    if args.embedding_model:
        settings.embedding_model = args.embedding_model
    corpus_path = args.corpus or (AREA_DIR / "corpus" / "retrieval_v1.json")
    corpus_bytes = corpus_path.read_bytes()
    corpus = json.loads(corpus_bytes)
    chunks_source = args.chunks or DEFAULT_CHUNKS
    if args.embeddings:
        embeddings_path = Path(args.embeddings)
        combos = [
            (args.embedding_model or fixture_model(embeddings_path), embeddings_path)
        ]
    elif args.embedding_model:
        embeddings_path = (
            FIXTURES_DIR / f"embeddings_{args.embedding_model.split('/')[-1]}.npz"
        )
        if not embeddings_path.exists():
            parser.error(
                f"falta {embeddings_path}; generala con build_embeddings "
                f"--model {args.embedding_model} --out {embeddings_path}"
            )
        combos = [(args.embedding_model, embeddings_path)]
    else:
        combos = [
            (fixture_model(path), path)
            for path in sorted(FIXTURES_DIR.glob("embeddings_*.npz"))
        ]
        if not combos:
            parser.error(f"no hay embeddings en {FIXTURES_DIR}")

    counts = validate_corpus(
        corpus, load_run_chunks(chunks_source, combos[0][1])
    )
    if args.validate_only:
        print(
            f'Corpus valido: {counts["cases"]} casos '
            f'({counts["positives"]} positivos '
            f'[{counts["fact_positives"]} fact, {counts["support_positives"]} support], '
            f'{counts["negatives"]} negativos)'
        )
        return

    focuses = FOCUS_CHOICES if args.focus == FOCUS_ALL else [args.focus]
    if args.run_name and (len(combos) > 1 or len(focuses) > 1):
        parser.error("--run-name solo se puede usar con un unico modelo y focus")

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    for model, embeddings_path in combos:
        settings.embedding_model = model
        chunks = load_run_chunks(chunks_source, embeddings_path)
        for focus in focuses:
            run_name = (
                args.run_name
                or f'{corpus["name"]}.{focus}.{model_slug(model)}'
            )
            scored_cases = []
            for index, case in enumerate(corpus["cases"], start=1):
                print(f'[{index}/{counts["cases"]}] {case["id"]}', flush=True)
                scored_cases.append(score_case(case, chunks, focus))

            ranking = ranking_summary(scored_cases)
            ranking["embedding_ms_mean"] = sum(
                case["embedding_ms"] for case in scored_cases
            ) / len(scored_cases)
            sweep = threshold_sweep(scored_cases, focus)
            current_threshold = metrics_at_threshold(
                scored_cases, settings.min_similarity, focus
            )
            results = {
                "run": run_name,
                "benchmark": corpus["name"],
                "focus_strategy": FOCUS_STRATEGIES[focus],
                "chunks": str(chunks_source),
                "chunk_embeddings": str(embeddings_path),
                "generated_at": datetime.now().astimezone().isoformat(),
                "corpus": str(corpus_path.relative_to(ROOT)),
                "corpus_sha256": hashlib.sha256(corpus_bytes).hexdigest(),
                "settings": asdict(settings),
                "summary": {
                    "cases": counts["cases"],
                    "positive_cases": counts["positives"],
                    "positive_fact_cases": counts["fact_positives"],
                    "positive_support_cases": counts["support_positives"],
                    "negative_cases": counts["negatives"],
                    **ranking,
                },
                "current_threshold": current_threshold,
                "threshold_sweep": sweep,
                "worst_cases": worst_cases(scored_cases),
                "cases": scored_cases,
            }

            json_path = RAW_DIR / f"{run_name}.json"
            json_path.write_text(
                json.dumps(results, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            print(f"JSON: {json_path}")


if __name__ == "__main__":
    main()
