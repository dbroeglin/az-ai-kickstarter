import os

import pytest
from azure.ai.inference.aio import ChatCompletionsClient
from azure.identity.aio import DefaultAzureCredential
from pydantic import ConfigDict
from semantic_kernel import Kernel
from semantic_kernel.agents.orchestration.group_chat import (
    StringResult,
)
from semantic_kernel.connectors.ai.azure_ai_inference import (
    AzureAIInferenceChatCompletion,
)
from semantic_kernel.connectors.ai.prompt_execution_settings import (
    PromptExecutionSettings,
)
from semantic_kernel.contents import ChatHistory, ChatMessageContent

from utils import get_model_deployment, load_dotenv_from_azd

load_dotenv_from_azd()


async def test_inference():
    credential = DefaultAzureCredential()
    kernel = Kernel()

    kernel.add_service(
        AzureAIInferenceChatCompletion(
            service_id="utility",
            ai_model_id=get_model_deployment("gpt-4.1-nano").name,
            client=ChatCompletionsClient(
                endpoint=os.environ["AZURE_AI_INFERENCE_ENDPOINT"],
                credential=credential,
                credential_scopes=["https://cognitiveservices.azure.com/.default"],
            ),
        )
    )

    result = await kernel.invoke_prompt("2 ** 3")
    assert "8" in result.value[0].content


class StringStringResult(StringResult):
    model_config = ConfigDict(extra="forbid")


async def test_openai_structured_output():
    deployment_name = get_model_deployment("gpt-4.1-nano").name
    credential = DefaultAzureCredential()
    kernel = Kernel()

    kernel.add_service(
        AzureAIInferenceChatCompletion(
            service_id="utility",
            ai_model_id=deployment_name,
            client=ChatCompletionsClient(
                endpoint=f"{os.environ['AZURE_OPENAI_ENDPOINT']}/deployments/{deployment_name}",
                credential=credential,
                credential_scopes=["https://cognitiveservices.azure.com/.default"],
                api_version=os.environ["AZURE_OPENAI_API_VERSION"],
            ),
        )
    )
    chat_history = ChatHistory()
    chat_history.add_user_message("What is 2 ** 3?")
    response: ChatMessageContent = await kernel.get_service(
        "utility"
    ).get_chat_message_content(
        chat_history,
        settings=PromptExecutionSettings(
            response_format=StringStringResult,
            temperature=0.0,
        ),
    )
    print(response)
    assert StringStringResult.model_validate_json(response.content).result == "8"


@pytest.mark.skip(
    reason="Complains about response_format being supported only for API version 2024-08-01-preview or later"
)
async def test_aaii_structured_output():
    deployment_name = get_model_deployment("gpt-4.1-nano").name
    credential = DefaultAzureCredential()
    kernel = Kernel()

    kernel.add_service(
        AzureAIInferenceChatCompletion(
            service_id="utility",
            ai_model_id=deployment_name,
            client=ChatCompletionsClient(
                endpoint=os.environ["AZURE_AI_INFERENCE_ENDPOINT"],
                credential=credential,
                credential_scopes=["https://cognitiveservices.azure.com/.default"],
            ),
        )
    )
    chat_history = ChatHistory()
    chat_history.add_user_message("What is 2 ** 3?")
    response: ChatMessageContent = await kernel.get_service(
        "utility"
    ).get_chat_message_content(
        chat_history,
        settings=PromptExecutionSettings(
            response_format=StringStringResult,
            temperature=0.0,
        ),
    )
    print(response)
    assert StringStringResult.model_validate_json(response.content).result == "8"
