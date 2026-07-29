"""Streamlit shell for the deskai support assistant."""

from __future__ import annotations

import pathlib
import sys

import streamlit as st
from botocore.exceptions import BotoCoreError, ClientError


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from core.bedrock import MODELS, converse  # noqa: E402


st.set_page_config(page_title="deskai", page_icon="🎧", layout="wide")

st.title("deskai — support assistant")
st.caption("Sprint 0 · foundation · Amazon Bedrock Converse API")

with st.sidebar:
    st.header("Invocation")
    model = st.selectbox("Model", options=list(MODELS), index=0)
    temperature = st.slider(
        "Temperature",
        min_value=0.0,
        max_value=1.0,
        value=0.0,
        step=0.1,
    )
    st.caption("Region: ap-southeast-1 · APAC cross-region inference")

prompt = st.text_area(
    "Ask something",
    value="Summarise what a support ticket triage system does.",
    height=140,
)

if st.button("Send", type="primary", disabled=not prompt.strip()):
    try:
        with st.spinner("Calling Amazon Bedrock…"):
            result = converse(
                prompt,
                model=model,
                temperature=temperature,
            )
    except (BotoCoreError, ClientError, ValueError) as error:
        st.error(f"Bedrock request failed: {error}")
    else:
        st.subheader("Response")
        st.write(result.text)

        st.subheader("Trace")
        latency, input_tokens, output_tokens, cost = st.columns(4)
        latency.metric("Latency", f"{result.latency_ms:,} ms")
        input_tokens.metric("Input tokens", result.input_tokens)
        output_tokens.metric("Output tokens", result.output_tokens)
        cost.metric("Estimated cost", f"${result.est_cost_usd:.8f}")

        st.code(result.request_id, language=None)
        st.caption(f"Bedrock request ID · model {result.model_id}")
