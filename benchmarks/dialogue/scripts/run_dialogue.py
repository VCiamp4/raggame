import argparse
import hashlib
import json
import sys
import time
from dataclasses import asdict
from datetime import datetime
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from backend.config import settings
from backend.rag.dialogue import DialogueService
from backend.rag.game_state import get_discovered_facts
from backend.rag.retrieval import CHUNKS


AREA_DIR = ROOT / "benchmarks" / "dialogue"
RAW_DIR = AREA_DIR / "resultados_raw"


TEXT_TO_CHUNK = {}
for chunk in CHUNKS:
    TEXT_TO_CHUNK.setdefault(chunk.retrieval_text, chunk.chunk_id)


def context_block(messages):
    content = messages[-1]["content"]
    start = content.find("<retrieved_context>")
    if start < 0:
        return ""
    end = content.find("</retrieved_context>")
    return "\n".join(content[start:end].splitlines()[1:]).strip()


def retrieved_ids(messages):
    ids = []
    for line in context_block(messages).splitlines():
        if line.startswith("- "):
            chunk_id = TEXT_TO_CHUNK.get(line[2:])
            if chunk_id is not None:
                ids.append(chunk_id)
    return ids


def openai_chat_turn(messages):
    headers = {
        "Authorization": f"Bearer {settings.openai_api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": settings.chat_model,
        "messages": messages,
        "stream": True,
        "max_completion_tokens": settings.num_predict,
        "reasoning_effort": "none",
        "temperature": settings.temperature,
    }
    reply = ""
    ttft_ms = None
    completed = False
    start = time.perf_counter()
    with requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers=headers,
        json=payload,
        stream=True,
        timeout=(5, 300),
    ) as response:
        if response.status_code >= 400:
            error = response.json()["error"]
            description = error["message"].split("sk-", 1)[0].strip()
            raise RuntimeError(
                f"OpenAI HTTP {response.status_code}: "
                f"{error['type']} ({error.get('code')}): {description}"
            )
        for line in response.iter_lines(decode_unicode=True):
            if not line or not line.startswith("data:"):
                continue
            event_data = line.removeprefix("data:").strip()
            if event_data == "[DONE]":
                completed = True
                break
            data = json.loads(event_data)
            if "error" in data:
                raise RuntimeError(data["error"]["message"])
            for choice in data.get("choices", []):
                chunk = choice["delta"].get("content")
                if chunk:
                    if ttft_ms is None:
                        ttft_ms = (time.perf_counter() - start) * 1000.0
                    reply += chunk
                reason = choice["finish_reason"]
                if reason and reason != "stop":
                    raise RuntimeError(f"OpenAI completion stopped: {reason}")
    if not completed:
        raise RuntimeError("OpenAI stream ended before completion")
    if ttft_ms is None:
        raise RuntimeError("OpenAI stream completed without text output")
    total_ms = (time.perf_counter() - start) * 1000.0
    return reply, ttft_ms, total_ms


def chat_turn(messages):
    if settings.chat_provider == "openai":
        return openai_chat_turn(messages)
    if settings.chat_provider != "ollama":
        raise ValueError(f"Unsupported chat provider: {settings.chat_provider}")
    payload = {
        "model": settings.chat_model,
        "messages": messages,
        "stream": True,
        "think": False,
        "options": {
            "num_predict": settings.num_predict,
            "temperature": settings.temperature,
        },
    }
    reply = ""
    ttft_ms = None
    start = time.perf_counter()
    with requests.post(
        f"{settings.ollama_url}/api/chat",
        json=payload,
        stream=True,
        timeout=(5, 300),
    ) as response:
        response.raise_for_status()
        for line in response.iter_lines():
            if not line:
                continue
            data = json.loads(line)
            chunk = data.get("message", {}).get("content", "")
            if chunk:
                if ttft_ms is None:
                    ttft_ms = (time.perf_counter() - start) * 1000.0
                reply += chunk
            if data.get("done", False):
                break
    if ttft_ms is None:
        raise RuntimeError("Ollama stream completed without text output")
    total_ms = (time.perf_counter() - start) * 1000.0
    return reply, ttft_ms, total_ms


def run_conversation(service, case):
    session_id = case["id"]
    turns = []
    for number, turn in enumerate(case["turns"], start=1):
        print(f'[{case["id"]}] turno {number}/{len(case["turns"])}', flush=True)
        before = set(get_discovered_facts(session_id))
        retrieval_start = time.perf_counter()
        messages = service.get_message(
            session_id=session_id,
            npc_id=case["npc_id"],
            player_input=turn["player"],
        )
        retrieval_ms = (time.perf_counter() - retrieval_start) * 1000.0
        response, ttft_ms, total_ms = chat_turn(messages)
        service.save_response(
            session_id=session_id,
            npc_id=case["npc_id"],
            player_input=turn["player"],
            response=response,
        )
        after = set(get_discovered_facts(session_id))
        context = context_block(messages)
        retrieved = retrieved_ids(messages)
        turns.append(
            {
                "player": turn["player"],
                "expect": turn.get("expect", ""),
                "expect_focus": turn.get("expect_focus"),
                "response": response,
                "context": context,
                "retrieved": retrieved,
                "retrieval_ms": retrieval_ms,
                "ttft_ms": ttft_ms,
                "total_ms": total_ms,
                "new_facts": sorted(after - before),
            }
        )
    return {**case, "turns": turns}


def validate_corpus(service, corpus):
    ids = [case["id"] for case in corpus["cases"]]
    assert len(ids) == len(set(ids)), "Hay ids de casos repetidos"
    known_chunks = set(TEXT_TO_CHUNK.values())
    for case in corpus["cases"]:
        service.get_persona(case["npc_id"])
        assert case["turns"], f'{case["id"]}: sin turnos'
        for turn in case["turns"]:
            if turn.get("expect_focus") is not None:
                assert turn["expect_focus"] in known_chunks, (
                    f'{case["id"]}: expect_focus desconocido'
                )
    turns = sum(len(case["turns"]) for case in corpus["cases"])
    return {"cases": len(ids), "turns": turns}


def model_slug(model):
    return model.split("/")[-1].replace(":", "-")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="valida el corpus sin consultar el modelo de chat",
    )
    parser.add_argument("--chat-provider", choices=("ollama", "openai"), default=None)
    parser.add_argument("--chat-model", default=None)
    parser.add_argument("--run-name", default=None)
    args = parser.parse_args()

    if args.chat_provider:
        settings.chat_provider = args.chat_provider
    if args.chat_model:
        settings.chat_model = args.chat_model
    corpus_path = AREA_DIR / "corpus" / "dialogue_v1.json"
    corpus_bytes = corpus_path.read_bytes()
    corpus = json.loads(corpus_bytes)
    service = DialogueService()
    counts = validate_corpus(service, corpus)
    if args.validate_only:
        print(
            f'Corpus valido: {counts["cases"]} conversaciones, '
            f'{counts["turns"]} turnos'
        )
        return

    if settings.chat_provider == "openai":
        if settings.chat_model != "gpt-6-luna":
            raise ValueError("OpenAI benchmark requires gpt-6-luna")
        if not settings.openai_api_key:
            raise ValueError("OPENAI_API_KEY is not configured")
        if counts["turns"] != 28:
            raise ValueError(
                f"OpenAI benchmark requires 28 turns; found {counts['turns']}"
            )
    elif settings.chat_provider != "ollama":
        raise ValueError(f"Unsupported chat provider: {settings.chat_provider}")

    run_name = args.run_name or (
        f'{corpus["name"]}.{settings.chat_provider}.'
        f'{model_slug(settings.chat_model)}'
    )
    json_path = RAW_DIR / f"{run_name}.json"
    if json_path.exists():
        raise FileExistsError(f"Results already exist: {json_path}")
    conversations = []
    for case in corpus["cases"]:
        conversations.append(run_conversation(service, case))

    turns = [turn for conversation in conversations for turn in conversation["turns"]]
    summary = {
        "conversations": len(conversations),
        "turns": len(turns),
        "chat_requests": len(turns),
        "ttft_ms_mean": sum(turn["ttft_ms"] for turn in turns) / len(turns),
        "retrieval_ms_mean": sum(turn["retrieval_ms"] for turn in turns)
        / len(turns),
    }
    saved_settings = asdict(settings)
    saved_settings.pop("openai_api_key")
    results = {
        "run": run_name,
        "benchmark": corpus["name"],
        "generated_at": datetime.now().astimezone().isoformat(),
        "corpus": str(corpus_path.relative_to(ROOT)),
        "corpus_sha256": hashlib.sha256(corpus_bytes).hexdigest(),
        "settings": saved_settings,
        "summary": summary,
        "conversations": conversations,
    }

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    json_path.write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"JSON: {json_path}")


if __name__ == "__main__":
    main()
