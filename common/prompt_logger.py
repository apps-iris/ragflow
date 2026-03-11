#
#  Copyright 2025 The InfiniFlow Authors. All Rights Reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

import json
import logging
import os
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler

from common.file_utils import get_project_base_directory

_prompt_logger = None


def get_prompt_logger():
    global _prompt_logger
    if _prompt_logger is not None:
        return _prompt_logger

    _prompt_logger = logging.getLogger("prompt_logger")
    _prompt_logger.setLevel(logging.INFO)
    _prompt_logger.propagate = False

    log_dir = os.path.join(get_project_base_directory(), "logs", "prompts")
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, "llm_prompts.log")

    handler = RotatingFileHandler(log_path, maxBytes=50 * 1024 * 1024, backupCount=10)
    handler.setFormatter(logging.Formatter("%(message)s"))
    _prompt_logger.addHandler(handler)

    return _prompt_logger


def log_llm_prompt(*, model_name, llm_factory, system, history, gen_conf, call_type="chat"):
    """Log the prompt and configuration sent to an LLM provider.

    Args:
        model_name: Name of the model being called.
        llm_factory: Provider/factory name (e.g. "OpenAI", "Tongyi-Qianwen").
        system: System prompt string.
        history: Conversation history (list of message dicts).
        gen_conf: Generation configuration (temperature, top_p, etc.).
        call_type: One of "chat", "chat_stream", "chat_stream_delta".
    """
    logger = get_prompt_logger()
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "call_type": call_type,
        "llm_factory": llm_factory,
        "model_name": model_name,
        "system_prompt": system,
        "history": history,
        "gen_conf": gen_conf,
    }
    try:
        logger.info(json.dumps(entry, ensure_ascii=False, default=str))
    except Exception:
        logging.getLogger().warning("Failed to log LLM prompt", exc_info=True)
