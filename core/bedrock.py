"""Amazon Bedrock Converse client used throughout deskai.

The course samples use retired Claude models and the legacy completion API.
This module provides the current Converse-based interface and returns the
request metadata needed for cost, latency, and CloudWatch evidence.
"""

from __future__ import annotations

import os
import time
from dataclasses import asdict, dataclass
from typing import Any

import boto3


DEFAULT_REGION = "ap-southeast-1"

# APAC cross-Region inference profiles called through the Singapore endpoint.
MODELS = {
    "micro": "apac.amazon.nova-micro-v1:0",
    "lite": "apac.amazon.nova-lite-v1:0",
    "pro": "apac.amazon.nova-pro-v1:0",
}

# Standard on-demand USD per 1M input/output tokens. Verified 2026-07-28.
PRICING = {
    "apac.amazon.nova-micro-v1:0": (0.035, 0.14),
    "apac.amazon.nova-lite-v1:0": (0.06, 0.24),
    "apac.amazon.nova-pro-v1:0": (0.80, 3.20),
}

_client: Any | None = None


@dataclass(frozen=True)
class Result:
    """Normalized response plus evidence metadata for one model call."""

    text: str
    request_id: str
    model_id: str
    input_tokens: int
    output_tokens: int
    latency_ms: int
    est_cost_usd: float

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def _bedrock_client() -> Any:
    """Create the runtime client lazily so imports never require credentials."""

    global _client
    if _client is None:
        region = os.environ.get("AWS_REGION", DEFAULT_REGION)
        _client = boto3.client("bedrock-runtime", region_name=region)
    return _client


def _response_text(response: dict[str, Any]) -> str:
    """Join every textual content block returned by Converse."""

    blocks = response["output"]["message"]["content"]
    return "\n".join(block["text"] for block in blocks if "text" in block)


def converse(
    prompt: str,
    model: str = "micro",
    system: str | None = None,
    max_tokens: int = 1_000,
    temperature: float = 0.0,
) -> Result:
    """Run a single-turn Converse request through a named model profile."""

    if not prompt.strip():
        raise ValueError("prompt must not be empty")
    if max_tokens < 1:
        raise ValueError("max_tokens must be at least 1")
    if not 0.0 <= temperature <= 1.0:
        raise ValueError("temperature must be between 0.0 and 1.0")

    model_id = MODELS.get(model, model)
    request: dict[str, Any] = {
        "modelId": model_id,
        "messages": [{"role": "user", "content": [{"text": prompt}]}],
        "inferenceConfig": {
            "maxTokens": max_tokens,
            "temperature": temperature,
        },
    }
    if system:
        request["system"] = [{"text": system}]

    started = time.perf_counter()
    response = _bedrock_client().converse(**request)
    latency_ms = round((time.perf_counter() - started) * 1_000)

    usage = response.get("usage", {})
    input_tokens = int(usage.get("inputTokens", 0))
    output_tokens = int(usage.get("outputTokens", 0))
    input_price, output_price = PRICING.get(model_id, (0.0, 0.0))
    estimated_cost = (
        input_tokens * input_price + output_tokens * output_price
    ) / 1_000_000

    return Result(
        text=_response_text(response),
        request_id=response["ResponseMetadata"]["RequestId"],
        model_id=model_id,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        latency_ms=latency_ms,
        est_cost_usd=estimated_cost,
    )
