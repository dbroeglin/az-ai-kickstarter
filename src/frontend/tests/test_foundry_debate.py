import logging
import os
from unittest import case

import pytest
from azure.ai.inference.aio import ChatCompletionsClient
from azure.identity.aio import DefaultAzureCredential
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel
from semantic_kernel.agents import (
    AzureAIAgent,
)
from semantic_kernel.contents.text_content import TextContent
from semantic_kernel.contents.function_result_content import FunctionResultContent
from semantic_kernel.contents.function_call_content import FunctionCallContent

from semantic_kernel.connectors.ai.azure_ai_inference import (
    AzureAIInferenceChatCompletion,
)
from semantic_kernel.contents.chat_message_content import ChatMessageContent
from semantic_kernel.core_plugins.time_plugin import TimePlugin
from semantic_kernel.kernel import Kernel


from azure.ai.projects.aio import AIProjectClient

from chainlit_chat_profile import FoundryDebateProfile
from pattern.foundry_debate import FoundryDebateOrchestrator
from utils import get_model_deployment, load_dotenv_from_azd

logging.getLogger("azure.identity").setLevel(logging.INFO)
logging.getLogger("markdown_it").setLevel(logging.WARNING)

# Load settings
load_dotenv_from_azd()

console = Console()


@pytest.fixture()
def credential() -> DefaultAzureCredential:
    return DefaultAzureCredential()


@pytest.fixture()
def project_client(credential) -> AIProjectClient:
    return AzureAIAgent.create_client(credential=credential)


@pytest.fixture()
async def orchestrator(mocker, project_client, credential) -> FoundryDebateOrchestrator:
    mocker.patch(
        "semantic_kernel.core_plugins.time_plugin.TimePlugin.date",
        return_value="Sunday, 12 January, 2031",
    )

    return FoundryDebateProfile.create_orchestrator(
        deployment_name=get_model_deployment("gpt-4.1-mini").name,
        azure_ai_agents=[
            definition async for definition in project_client.agents.list_agents()
        ],
        credential=credential,
        project_client=project_client,
    )


async def agent_response_callback(message: ChatMessageContent) -> None:
    """Callback function that gets intermediary agent responses and
    prints them.
    """

    def extract_content(message: ChatMessageContent) -> str:
        for item in message.items:
            match item:
                case TextContent():
                    return item.text
                case FunctionCallContent():
                    return f"Tool call: {item.plugin_name}.{item.function_name}({item.arguments})"
                case FunctionResultContent():
                    return f"Tool result: {item.result}"
        return ""

    console.print(message)
    console.print(
        Panel(
            Markdown(extract_content(message)),
            title=f"Agent: {message.name} ({message.role.name})",
        )
    )


async def test_blog_generation(orchestrator):
    console.print()  # start an a blank line
    conversation_messages = [
        {
            "role": "user",
            "content": "A blog about cookies",
        }
    ]

    async with AzureAIAgent.create_client(
        credential=DefaultAzureCredential()
    ) as project_client:
        final_message = await orchestrator.process_conversation(
            project_client,
            "test_user",
            conversation_messages,
            agent_response_callback=agent_response_callback,
        )

    assert final_message is not None
    assert "01/12/2031" in final_message.content
    assert "cookies" in final_message.content.lower()

    console.rule()
    console.print(Panel(Markdown(final_message.content), title="Final Response"))
